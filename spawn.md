---
description: Spawn a new independent Claude session in a fresh git worktree (or the current one with --here) — automatically enabled for remote control
argument-hint: [--here] [-t <tmux window title>] [[-p] <task prompt>]
allowed-tools: Bash
---

Spawn a new **independent** Claude Code session (a new tmux window, not a subagent).

Run the script below **exactly** via the Bash tool, substituting the user's arguments for `$ARGUMENTS`. Do not improvise extra steps.

**Loading this skill is not success — running the script is.** The script launches the session, then waits and verifies the tmux pane is still alive before printing `spawned '<window>' (<path>)` — so that line means the claude session actually started, not merely that a window frame was created. Do not report success until the Bash tool returns and its output contains that `spawned` line. Report success only from it, quoting the window name and path it printed, then stop — the spawned session does its own work. If the output instead contains a `spawn failed` line (the script captures and echoes the claude error — e.g. untrusted workspace, worktree conflict) or any `usage:`/precondition error (`not inside tmux`, `not in a git repo`, `fetch failed`), say the spawn failed and relay the reason. Never claim a window was created without the `spawned` line as evidence.

Behavior:

- **Remote Control enabled by default:** all spawned sessions automatically start with `--remote-control`, making them visible and controllable from claude.ai/code and the Claude mobile/desktop app.
- **Default:** open a new tmux window whose Claude session creates its own fresh git worktree via `claude --worktree` (lands under `<repo>/.claude/worktrees/`, branch `worktree-<name>`). `claude --worktree` branches off the repo's current HEAD, so the skill first fetches origin and fast-forwards your local default branch (only when it's checked out and clean) so the worktree starts from the latest default branch.
- **`--here`:** skip the worktree; launch the new session in the current directory.
- **`-t <title>`:** name the tmux window `<title>` (matches the `ctrl+b ,` rename convention). If omitted, the window is named from a slug of the prompt (or `session`) plus a timestamp.
- **`-p <task>` (or bare text):** seed the new session with this task prompt. The `-p` flag is optional — any argument that isn't a recognized flag is taken as prompt text (multiple bare words are joined with spaces), so `/spawn fix the flaky test` == `/spawn -p 'fix the flaky test'`. With no prompt text at all (bare `/spawn`, or `-p` with nothing after it) the session starts **idle** — no prompt is passed to `claude`.

```bash
# --- parse args (iterate "$@" — avoids numbered positionals, which the
#     slash-command renderer substitutes; identical in bash & zsh, spaces-safe) ---
eval "set -- $ARGUMENTS"
here=0
title=""
prompt=""
expect=""
for arg in "$@"; do
	if [ -n "$expect" ]; then
		[ "$expect" = title ] && title="$arg"
		[ "$expect" = prompt ] && prompt="$arg"
		expect=""
		continue
	fi
	case "$arg" in
		--here) here=1 ;;
		-t) expect=title ;;
		-p) expect=prompt ;;
		# unknown flag = typo, not prompt text; anything else is prompt text, so
		# `-p` is optional and bare words are joined into one prompt.
		-*) echo "usage: /spawn [--here] [-t <title>] [[-p] <task>]"; exit 1 ;;
		*) prompt="${prompt:+$prompt }$arg" ;;
	esac
done

# --- preconditions ---
if [ -z "${TMUX:-}" ]; then echo "not inside tmux — open your seed session in a tmux window first"; exit 1; fi
main_root=$(git rev-parse --show-toplevel) || { echo "not in a git repo"; exit 1; }
repo=$(basename "$main_root")

# --- derive names ---
slugsrc="${title:-${prompt:-session}}"
slug=$(printf '%s' "$slugsrc" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//' | cut -c1-40 | sed -E 's/-$//')
[ -z "$slug" ] && slug=session
stamp=$(date +%Y%m%d-%H%M%S)
worktree_name="${slug}-${stamp}"
window_name="${title:-$worktree_name}"

# --- resolve target dir ---
if [ "$here" = 1 ]; then
	launch_dir="$PWD"
	wt_flag=""
	preamble="You are a new independent Claude session running in the CURRENT worktree at $launch_dir."
else
	default=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
	if [ -z "$default" ]; then
		git remote set-head origin -a >/dev/null 2>&1
		default=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
	fi
	if [ -z "$default" ]; then echo "could not determine default branch"; exit 1; fi
	git fetch origin "$default" || { echo "fetch failed"; exit 1; }
	# claude --worktree branches off the current HEAD; fast-forward local $default
	# first so the new worktree starts from latest origin. ff-only — never rewrites
	# local work, and only when $default is the clean, checked-out branch.
	cur=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ "$cur" = "$default" ] && git diff --quiet && git diff --cached --quiet; then
		git merge --ff-only "origin/$default" >/dev/null 2>&1 || echo "note: local $default diverged from origin — worktree bases on local HEAD"
	else
		echo "note: checkout not on a clean $default (on '${cur:-detached HEAD}') — worktree bases on current HEAD, not latest origin/$default"
	fi
	launch_dir="$main_root"
	wt_flag="--worktree $worktree_name"
	wt_path="$main_root/.claude/worktrees/$worktree_name"
	preamble="You are a new independent Claude session in a FRESH git worktree at $wt_path, on branch worktree-$worktree_name.

Worktree setup — installing dependencies, copying any .env from the main checkout at ${main_root}, and whatever else the repo's own docs prescribe (CLAUDE.md's worktree-setup section and/or README) — is NOT an automatic first step. Judge from the task whether it's needed:
- Skip it entirely for read-only work: answering a question, reading or explaining code, research, reviewing a diff, or acting through MCP servers (Teams/Slack messages, Linear, Jira, docs lookups).
- Otherwise do it — only the parts you need — at the moment you first have to install, build, typecheck, lint, run tests, or run the app. Setting up late is fine; a full setup you never use is waste."
fi

# --- build the inner command ---
if [ -n "$prompt" ]; then
	seedfile=$(mktemp)
	cat > "$seedfile" <<SEED
$preamble

Task: $prompt
SEED
	inner_cmd="caffeinate -is claude -n '$window_name' --permission-mode auto --model sonnet --effort medium --remote-control $wt_flag \"\$(cat '$seedfile')\"; rm -f '$seedfile'"
else
	inner_cmd="caffeinate -is claude -n '$window_name' --permission-mode auto --model sonnet --effort medium --remote-control $wt_flag"
fi

# --- launch, then VERIFY the pane survived ---
# tmux new-window returns 0 as soon as the window frame exists — it knows nothing
# about whether the claude process inside started or died. So we keep the pane on
# exit, wait, and check pane_dead: a dead pane means claude failed (untrusted
# workspace, worktree conflict, bad flag) and "spawned" would be a false success.
win_id=$(tmux new-window -P -F '#{window_id}' -c "$launch_dir" -n "$window_name" "$inner_cmd") || { echo "spawn failed — tmux new-window errored"; exit 1; }
tmux set-option -w -t "$win_id" remain-on-exit on
sleep 3
dead=$(tmux list-panes -t "$win_id" -F '#{pane_dead}' 2>/dev/null | head -1)
if [ "$dead" = "1" ]; then
	err=$(tmux capture-pane -p -t "$win_id" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -20)
	tmux kill-window -t "$win_id" 2>/dev/null
	echo "spawn failed — claude exited before the session started:"
	echo "$err"
	exit 1
fi
tmux set-option -w -t "$win_id" remain-on-exit off
echo "spawned '$window_name' (${wt_path:-$launch_dir})"
```

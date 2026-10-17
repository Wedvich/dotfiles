---
name: exclave
description: Add or remove an exclave — a ~/<exclave> workspace with its own Claude Code config dir, git identity and Firefox profile, applied automatically by the shell.
argument-hint: [remove] <exclave>
model: claude-haiku-5-5
disable-model-invocation: true
---

Args: `$ARGUMENTS`. A leading `remove` selects removal; otherwise add.

## 1. Check before changing anything

- No name given: ask for one.
- Name doesn't match `^[a-z0-9][a-z0-9-]*$`: refuse (a leading `-` would reach Firefox as a flag).
- `~/.local/bin/exclave-browser` missing: stop and tell me to run the dotfiles `setup.sh`.
- Add, and no line in `~/.exclaves` is exactly `<exclave>`: refuse if `~/<exclave>` exists or `~/.gitconfig` has an `includeIf` for `gitdir:~/<exclave>/`. That's an existing workspace, and a second `includeIf` would override its git identity.

## 2. Apply

Each piece: check first, skip if already in the target state, report skips. So re-running is safe. Work through every row before stopping; the only questions to ask are the ones this skill names (step 1, (B) step 3, (C) `differs`, step 4).

| Piece | Add | Remove |
|---|---|---|
| Dirs `~/.claude-<exclave>/{skills,agents}`, `~/<exclave>` | `mkdir -p` | Leave alone (step 4) |
| `~/.claude-<exclave>/settings.json` | If missing: `cp ~/.claude/settings.json` there; never overwrite | Leave alone |
| User skill and agent links (B) | Per (B) | Leave alone |
| User-scope MCP servers (C) | Per (C) | Leave alone |
| `~/.gitconfig_<exclave>` | If missing: create with commented `[user]` stub (name/email); never overwrite | Leave alone |
| `~/.gitconfig` block (A) | Append | Delete exactly (A) |
| Firefox profile `<exclave>` | `~/.local/bin/exclave-browser --create-profile <exclave>` (skips an existing one) | Leave alone |
| `~/.exclaves` line exactly `<exclave>` | Append (create the file if missing) | Delete that line only |

(A)
```
[includeIf "gitdir:~/<exclave>/"]
	path = ~/.gitconfig_<exclave>
```

(B) Run the steps below once per kind:

| Kind   | Entries in `~/.claude/<kind>/`                | Skip                         | `src` must pass |
|--------|-----------------------------------------------|------------------------------|-----------------|
| skills | every entry                                   | `synced`, dot-entries        | `[ -d src ]`    |
| agents | every `*.md` file                             | dot-entries                  | `[ -f src ]`    |

`synced` holds the claude.ai account's own skills, and each exclave is a separate account with its own. Agents are needed because skills like `/ship` spawn them by name, and a missing one silently falls back to general-purpose.

For each entry `<name>`, let `src` = `~/.claude/<kind>/<name>`, `dst` = `~/.claude-<exclave>/<kind>/<name>`:

1. `src` fails its check in the table (wrong type or broken link): skip, report.
2. `dst` is a link and `readlink dst` equals `src` with `~` expanded: skip, already done.
3. `dst` is a link to anything else, or a broken link: leave it for now and carry on with the rest of the table. Once everything else is done, list each with its `readlink dst` and ask once whether to replace them with `ln -sfn src dst`.
4. `dst` exists and is not a link: skip, report (exclave-only; never touch it).
5. Otherwise: `ln -s src dst`.

Link to the `~/.claude` path, not its resolved target: a chain still resolves, and follows wherever `setup.sh` points `src` later. Links, not copies, so edits carry over. A skill or agent added later needs `/exclave <exclave>` re-run, unless it lives in the dotfiles repo: `setup.sh` links those into every exclave in `~/.exclaves`.

(C) Copies the user-scope MCP servers (top-level `mcpServers` in `~/.claude.json`) into the exclave. Entries can hold API keys, so never print one; this prints names only. Run it as-is:

```sh
src=~/.claude.json; dst=~/.claude-<exclave>/.claude.json
jq -r '.mcpServers // {} | keys[]' "$src" | while read -r n; do
  a=$(jq -cS --arg n "$n" '.mcpServers[$n]' "$src")
  b=$(jq -cS --arg n "$n" '.mcpServers[$n] // empty' "$dst" 2>/dev/null)
  if [ -z "$b" ]; then CLAUDE_CONFIG_DIR=~/.claude-<exclave> claude mcp add-json --scope user "$n" "$a" >/dev/null 2>&1 && echo "added $n" || echo "FAILED $n"
  elif [ "$a" = "$b" ]; then echo "same $n"; else echo "differs $n"; fi
done
```

For `differs`, ask once (names only) whether to replace; on yes, run `CLAUDE_CONFIG_DIR=~/.claude-<exclave> claude mcp remove --scope user <server>` for each and re-run the script. Never touch servers that exist only in the exclave. OAuth servers need their own `/mcp` sign-in per exclave.

Make the (B) links with `ln` and the (C) entries with its script in Bash; those are the only shell writes allowed. Change files with Edit (Write only to create a missing file), never sed or `>>`. Edit nothing outside the table: the shell hook in `~/.zshenv_dotfile` reads `~/.exclaves` on every `cd`, so never touch `~/.zshenv`, `~/.zshenv_dotfile` or `~/.local/bin/exclave-browser`.

## 3. Verify

Run these and show me the output:
- Add only: `ls -l ~/.claude-<exclave>/{skills,agents}/`, and `find -L ~/.claude-<exclave>/{skills,agents} -maxdepth 1 -type l`, which lists broken links and must print nothing (one you were told not to replace in (B) step 3 is the exception: name it)
- Add only: re-run the (C) script; every line must be `same` (a `differs` you were told not to replace is the exception: name it)
- `cat ~/.exclaves`
- `git config --file ~/.gitconfig --get-regexp includeif`
- `env -u EXCLAVE -u CLAUDE_CONFIG_DIR zsh -c 'cd ~/<exclave> && print -r -- "${CLAUDE_CONFIG_DIR-unset}"'`: must print `~/.claude-<exclave>` expanded after add, and `unset` after remove. (`env -u` drops this session's own values, which would otherwise leak in.)

If a check fails, fix it before reporting done. Then show the lines you added or removed in each file.

## 4. Remove only: offer to delete data

Remove never deletes data on its own. The dirs hold repos and the account's login/history, `~/.gitconfig_<exclave>` holds an identity, and the Firefox profile holds the claude.ai session. List which exist, with sizes, and ask which (if any) to delete. Firefox profiles have no delete CLI: tell me to use `about:profiles`. Delete `~/<exclave>` only if every repo in it has a clean tree and nothing unpushed.

## 5. Finish

- Add: tell me to fill in `~/.gitconfig_<exclave>`, open a new shell, and run `claude` + `/login` inside `~/<exclave>`. The login page opens in the exclave's Firefox profile.
- Remove: tell me to open a new shell. Shells already inside `~/<exclave>` keep the old env vars until they `cd`.

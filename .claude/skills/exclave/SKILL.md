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

Each piece: check first, skip if already in the target state, report skips. So re-running is safe.

| Piece | Add | Remove |
|---|---|---|
| Dirs `~/.claude-<exclave>/skills`, `~/<exclave>` | `mkdir -p` | Leave alone (step 4) |
| `~/.claude-<exclave>/settings.json` | If missing: `cp ~/.claude/settings.json` there; never overwrite | Leave alone |
| User skill links (B) | Per (B) | Leave alone |
| `~/.gitconfig_<exclave>` | If missing: create with commented `[user]` stub (name/email); never overwrite | Leave alone |
| `~/.gitconfig` block (A) | Append | Delete exactly (A) |
| Firefox profile `<exclave>` | `~/.local/bin/exclave-browser --create-profile <exclave>` (skips an existing one) | Leave alone |
| `~/.exclaves` line exactly `<exclave>` | Append (create the file if missing) | Delete that line only |

(A)
```
[includeIf "gitdir:~/<exclave>/"]
	path = ~/.gitconfig_<exclave>
```

(B) For each entry `<name>` in `~/.claude/skills/`, except `synced` and dot-entries (`.trash` etc.). `synced` holds the claude.ai account's own skills, and each exclave is a separate account with its own. Let `src` = `~/.claude/skills/<name>`, `dst` = `~/.claude-<exclave>/skills/<name>`:

1. `src` doesn't resolve to a directory (`[ -d src ]` false: a loose file or broken link): skip, report.
2. `dst` is a link and `readlink dst` equals `src` with `~` expanded: skip, already done.
3. `dst` is a link to anything else, or a broken link: leave it for now and carry on with the rest of the table. Once everything else is done, list each with its `readlink dst` and ask once whether to replace them with `ln -sfn src dst`.
4. `dst` exists and is not a link: skip, report (an exclave-only skill; never touch it).
5. Otherwise: `ln -s src dst`.

Link to the `~/.claude` path, not its resolved target: a chain still resolves, and follows wherever `setup.sh` points `src` later. Links, not copies, so edits carry over; a skill added later needs `/exclave <exclave>` re-run.

Make the (B) links with `ln` in Bash; that's the only shell write allowed. Change files with Edit (Write only to create a missing file), never sed or `>>`. Edit nothing outside the table: the shell hook in `~/.zshenv_dotfile` reads `~/.exclaves` on every `cd`, so never touch `~/.zshenv`, `~/.zshenv_dotfile` or `~/.local/bin/exclave-browser`.

## 3. Verify

Run these and show me the output:
- Add only: `ls -l ~/.claude-<exclave>/skills/`, and `find -L ~/.claude-<exclave>/skills -maxdepth 1 -type l`, which lists broken links and must print nothing (one you were told not to replace in (B) step 3 is the exception: name it)
- `cat ~/.exclaves`
- `git config --file ~/.gitconfig --get-regexp includeif`
- `env -u EXCLAVE -u CLAUDE_CONFIG_DIR zsh -c 'cd ~/<exclave> && print -r -- "${CLAUDE_CONFIG_DIR-unset}"'`: must print `~/.claude-<exclave>` expanded after add, and `unset` after remove. (`env -u` drops this session's own values, which would otherwise leak in.)

If a check fails, fix it before reporting done. Then show the lines you added or removed in each file.

## 4. Remove only: offer to delete data

Remove never deletes data on its own. The dirs hold repos and the account's login/history, `~/.gitconfig_<exclave>` holds an identity, and the Firefox profile holds the claude.ai session. List which exist, with sizes, and ask which (if any) to delete. Firefox profiles have no delete CLI: tell me to use `about:profiles`. Delete `~/<exclave>` only if every repo in it has a clean tree and nothing unpushed.

## 5. Finish

- Add: tell me to fill in `~/.gitconfig_<exclave>`, open a new shell, and run `claude` + `/login` inside `~/<exclave>`. The login page opens in the exclave's Firefox profile.
- Remove: tell me to open a new shell. Shells already inside `~/<exclave>` keep the old env vars until they `cd`.

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
| Dirs `~/.claude-<exclave>`, `~/<exclave>` | `mkdir -p` | Leave alone (step 4) |
| `~/.claude-<exclave>/settings.json` | If missing: `cp ~/.claude/settings.json` there; never overwrite | Leave alone |
| `~/.gitconfig_<exclave>` | If missing: create with commented `[user]` stub (name/email); never overwrite | Leave alone |
| `~/.gitconfig` block (A) | Append | Delete exactly (A) |
| Firefox profile `<exclave>` | `~/.local/bin/exclave-browser --create-profile <exclave>` (skips an existing one) | Leave alone |
| `~/.exclaves` line exactly `<exclave>` | Append (create the file if missing) | Delete that line only |

(A)
```
[includeIf "gitdir:~/<exclave>/"]
	path = ~/.gitconfig_<exclave>
```

Change files with Edit (Write only to create a missing file), never sed or `>>`. Edit nothing outside the table: the shell hook in `~/.zshenv_dotfile` reads `~/.exclaves` on every `cd`, so never touch `~/.zshenv`, `~/.zshenv_dotfile` or `~/.local/bin/exclave-browser`.

## 3. Verify

Run all three and show me the output:
- `cat ~/.exclaves`
- `git config --file ~/.gitconfig --get-regexp includeif`
- `env -u EXCLAVE -u CLAUDE_CONFIG_DIR zsh -c 'cd ~/<exclave> && print -r -- "${CLAUDE_CONFIG_DIR-unset}"'`: must print `~/.claude-<exclave>` expanded after add, and `unset` after remove. (`env -u` drops this session's own values, which would otherwise leak in.)

If a check fails, fix it before reporting done. Then show the lines you added or removed in each file.

## 4. Remove only: offer to delete data

Remove never deletes data on its own. The dirs hold repos and the account's login/history, `~/.gitconfig_<exclave>` holds an identity, and the Firefox profile holds the claude.ai session. List which exist, with sizes, and ask which (if any) to delete. Firefox profiles have no delete CLI: tell me to use `about:profiles`. Delete `~/<exclave>` only if every repo in it has a clean tree and nothing unpushed.

## 5. Finish

- Add: tell me to fill in `~/.gitconfig_<exclave>`, open a new shell, and run `claude` + `/login` inside `~/<exclave>`. The login page opens in the exclave's Firefox profile.
- Remove: tell me to open a new shell. Shells already inside `~/<exclave>` keep the old env vars until they `cd`.

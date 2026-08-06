# dotfiles

Personal dotfiles and machine setup for macOS and WSL2 Ubuntu. `bootstrap.sh` makes sure zsh is installed and set as the default shell, then hands off to `setup.sh`, which symlinks the dotfiles into `$HOME` and installs everything else. Both scripts are idempotent — rerun them anytime to pick up changes or repair a partial install.

### Installing

```bash
curl -fsSL https://raw.githubusercontent.com/Wedvich/dotfiles/main/bootstrap.sh | bash
```

This clones the repo to `~/dotfiles` if it isn't already there.

Appliance-ish hosts (Proxmox VE, LXCs) can pass `--minimal` for shell comfort
without the dev tooling. The script arrives on stdin, so bash needs `-s --` to
forward the flag:

```bash
curl -fsSL https://raw.githubusercontent.com/Wedvich/dotfiles/main/bootstrap.sh | bash -s -- --minimal
```

`--minimal` is sticky: a marker file keeps later runs (including `updot`)
minimal. Pass `--full` to clear it. Minimal hosts skip Starship and fall back to
a plain zsh prompt with the same `❯`. They do get `zoxide` and `eza`, since moving
around a filesystem is the same comfort everywhere — both from the distro's own
repos, so an appliance host doesn't grow a third-party apt source.

On Proxmox VE hosts, setup also strips the "No valid subscription" popup from
the web UI and installs an apt hook that reapplies the patch after upgrades
restore the packaged file. `sudo proxmox-no-nag` runs it on demand,
`sudo proxmox-no-nag --revert` puts the notice back; both are no-ops when
nothing needs changing. A hard reload (Ctrl-Shift-R) is needed to see the
change, since the UI's cache-buster is tied to the package version.

### Testing

```bash
docker run --rm -it -v ~/dotfiles:/work:ro -w /work \
 -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/work \
 ubuntu:24.04 bash bootstrap.sh;
```

Runs the local checkout against a fresh Ubuntu container — nothing is pre-installed, so this also exercises the bootstrap's own `sudo`/`git`/`zsh` provisioning. The read-only mount catches any accidental writes to the repo itself; `safe.directory` is needed because the mounted repo is owned by the host UID, not the container's root, and goes through the environment because git isn't installed yet at that point.

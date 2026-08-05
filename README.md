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
minimal. Pass `--full` to clear it.

### Testing

```bash
docker run --rm -it -v ~/dotfiles:/work:ro -w /work ubuntu:24.04 \
 bash -c "apt update -qy && apt install -qy sudo git curl ca-certificates && git config --global --add safe.directory /work && bash bootstrap.sh";
```

Runs the local checkout against a fresh Ubuntu container. The read-only mount catches any accidental writes to the repo itself; `safe.directory` is needed because the mounted repo is owned by the host UID, not the container's root.

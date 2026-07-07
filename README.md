# dotfiles

Personal dotfiles and machine setup for macOS and WSL2 Ubuntu. `bootstrap.sh` makes sure zsh is installed and set as the default shell, then hands off to `setup.sh`, which symlinks the dotfiles into `$HOME` and installs everything else. Both scripts are idempotent — rerun them anytime to pick up changes or repair a partial install.

### Installing

```bash
curl -fsSL https://raw.githubusercontent.com/Wedvich/dotfiles/main/bootstrap.sh | bash
```

This clones the repo to `~/dotfiles` if it isn't already there.

### Testing

```bash
docker run --rm -it -v ~/dotfiles:/work:ro -w /work ubuntu:24.04 \
 bash -c "apt update -qy && apt install -qy sudo git curl ca-certificates && bash bootstrap.sh";
```

Runs the local checkout against a fresh Ubuntu container. The read-only mount catches any accidental writes to the repo itself.

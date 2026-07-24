#!/bin/sh

# git gpg.ssh.program wrapper (macOS only).
#
# Commit signing goes through Secretive's Secure Enclave agent, while the
# ambient SSH_AUTH_SOCK stays pointed at 1Password for auth. git invokes this
# with ssh-keygen-compatible args (-Y sign ...), so we just pin the socket and
# exec the real ssh-keygen.

SSH_AUTH_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh" \
  exec /usr/bin/ssh-keygen "$@"

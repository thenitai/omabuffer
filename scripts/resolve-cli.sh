#!/bin/sh
# A leftover mise/npm shim is not enough: the CLI must actually start.
cli_path=$(command -v buffer 2>/dev/null) || exit 1
case "$cli_path" in
  /*) ;;
  *) exit 1 ;;
esac

# Probe locally without credentials, and bound broken or stalled launchers.
{ timeout --kill-after=1s 5s "$cli_path" --version; } >/dev/null 2>&1 || exit 1
printf '%s\n' "$cli_path"

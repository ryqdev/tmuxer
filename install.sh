#!/usr/bin/env bash
set -eu

name=${NAME:-tx}
prefix=${PREFIX:-"$HOME/.local"}
case "$name" in
    ''|.|..|*/*) printf 'install: NAME must be a filename (for example tx, tm, rt)\n' >&2; exit 2 ;;
esac

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination=$prefix/bin/$name
if [ ! -f "$source_dir/tx" ]; then
    printf 'install: cannot find %s/tx\n' "$source_dir" >&2
    exit 1
fi
mkdir -p -- "$prefix/bin"
if [ "$source_dir/tx" -ef "$destination" ]; then
    chmod -- 755 "$destination"
else
    cp -- "$source_dir/tx" "$destination"
    chmod -- 755 "$destination"
fi
printf 'Installed: %s\n' "$destination"
printf 'Make sure %s/bin is on PATH.\n' "$prefix"

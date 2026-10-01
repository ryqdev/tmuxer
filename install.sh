#!/usr/bin/env bash
set -eu

name=${NAME:-tr}
prefix=${PREFIX:-"$HOME/.local"}
case "$name" in
    ''|.|..|*/*) printf 'install: NAME must be a filename (for example tr, tx, rt)\n' >&2; exit 2 ;;
esac

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination=$prefix/bin/$name
if [ ! -f "$source_dir/tr" ]; then
    printf 'install: cannot find %s/tr\n' "$source_dir" >&2
    exit 1
fi
mkdir -p -- "$prefix/bin"
if [ "$source_dir/tr" -ef "$destination" ]; then
    chmod -- 755 "$destination"
else
    cp -- "$source_dir/tr" "$destination"
    chmod -- 755 "$destination"
fi
printf 'Installed: %s\n' "$destination"
printf 'Make sure %s/bin is on PATH.\n' "$prefix"

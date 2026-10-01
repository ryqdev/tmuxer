#!/usr/bin/env bash
set -eu

name=${NAME:-tr}
prefix=${PREFIX:-"$HOME/.local"}
case "$name" in
    ''|.|..|*/*) printf 'install: NAME 必须是文件名（例如 tr、tx、rt）\n' >&2; exit 2 ;;
esac

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination=$prefix/bin/$name
if [ ! -f "$source_dir/tr" ]; then
    printf 'install: 找不到 %s/tr\n' "$source_dir" >&2
    exit 1
fi
mkdir -p -- "$prefix/bin"
if [ "$source_dir/tr" -ef "$destination" ]; then
    chmod -- 755 "$destination"
else
    cp -- "$source_dir/tr" "$destination"
    chmod -- 755 "$destination"
fi
printf '已安装：%s\n' "$destination"
printf '请确保 %s/bin 在 PATH 中。\n' "$prefix"

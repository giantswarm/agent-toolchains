#!/bin/sh
set -eu

# Fetch a toolchain's pinned downloads into <prefix>. Each line of <list> is
#
#   <dest> <arch> <sha256> <url> [<member>]
#
# <dest> is the path under the prefix; <arch> is amd64, arm64 or all; the
# download must match <sha256>. Without <member> the download is the file
# itself, installed executable; with one, it is a .tar.gz and <member> the
# file to take from it, or with a trailing / the directory whose contents
# <dest> receives. Nothing a download holds runs here, so the build stage
# runs on the build platform for every target architecture.
#
# Usage: fetch.sh <prefix> <list> <arch>

prefix="$1"
list="$2"
arch="$3"

cache=$(mktemp -d)
grep -v -e '^#' -e '^[[:space:]]*$' "$list" | while read -r dest want sum url member; do
  [ "$want" = "$arch" ] || [ "$want" = all ] || continue
  file="${cache}/${sum}"
  if [ ! -f "$file" ]; then
    curl -fsSL --retry 3 -o "${file}.part" "$url"
    echo "${sum}  ${file}.part" | sha256sum -c -s - || {
      echo "${url}: sha256 is $(sha256sum "${file}.part" | cut -d' ' -f1), want ${sum}" >&2
      exit 1
    }
    mv "${file}.part" "$file"
  fi

  target="${prefix}/${dest}"
  mkdir -p "$(dirname "$target")"
  case "$member" in
    "")
      install -m 0755 "$file" "$target"
      ;;
    */)
      unpacked=$(mktemp -d)
      # Whole: an archive need not list a directory entry of its own.
      tar -xzf "$file" -C "$unpacked"
      mkdir -p "$target"
      cp -R "${unpacked}/${member}." "$target"
      rm -rf "$unpacked"
      ;;
    *)
      unpacked=$(mktemp -d)
      tar -xzf "$file" -C "$unpacked" "$member"
      cp "${unpacked}/${member}" "$target"
      rm -rf "$unpacked"
      ;;
  esac
  echo "${dest}: ${url}${member:+ (${member})}"
done
rm -rf "$cache"

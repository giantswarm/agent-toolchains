#!/bin/sh
set -eu

# Build a toolchain from Alpine's packages under its mount directory, so its
# tools run from there beside any Harness image:
#
#   install  installs the packages for the target architecture under
#            <prefix>, without running their scripts: nothing of the target
#            runs, so the build stage runs on the build platform.
#   finish   makes the prefix self-contained: every executable's ELF
#            interpreter becomes the prefix's own musl loader and its library
#            path the prefix's lib directories, bin/ links each named tool and
#            nothing else, and every shebang naming an interpreter the prefix
#            holds names the prefix's copy, the bin/ one where a tool is. A
#            Harness's own loader and libraries are never used.
#
# Usage: apk-prefix.sh install <prefix> <arch> <package>...
#        apk-prefix.sh finish  <prefix> <arch> <tool>...
# <arch> is the Docker architecture (amd64, arm64); a tool is a name in the
# prefix's usr/bin.

cmd="$1"
prefix="$2"
case "$3" in
  amd64) march=x86_64 ;;
  arm64) march=aarch64 ;;
  *) echo "unsupported architecture: $3" >&2; exit 1 ;;
esac
shift 3

install_packages() {
  mkdir -p "$prefix"
  apk add --no-cache --no-scripts --initdb --root "$prefix" --arch "$march" \
    --keys-dir "/usr/share/apk/keys/${march}" \
    --repositories-file /etc/apk/repositories "$@"
  # apk's lock is root's alone (0600); uid 65532 must read every file.
  rm -f "${prefix}/lib/apk/db/lock"
}

relocate_elf() {
  loader="${prefix}/lib/ld-musl-${march}.so.1"
  [ -e "$loader" ] || { echo "no musl loader at ${loader}" >&2; exit 1; }
  # Executables are the ELF files with an interpreter; libraries keep theirs:
  # musl resolves a library's needs through the executable's library path.
  scanelf --recursive --quiet --interp --format '%i|%F' "$prefix" | while IFS='|' read -r _ file; do
    patchelf --set-interpreter "$loader" --set-rpath "${prefix}/lib:${prefix}/usr/lib" "$file"
  done
}

# The image root's bin/ is the toolchain's PATH, not Alpine's /bin: Alpine's
# /bin and /sbin files move to usr/bin, their symlinks (busybox applets, a
# Harness has its own /bin/sh) go.
clear_root_bin() {
  for dir in bin sbin; do
    [ -d "${prefix}/${dir}" ] || continue
    find "${prefix}/${dir}" -mindepth 1 -maxdepth 1 ! -type l -exec mv -n {} "${prefix}/usr/bin/" \;
    rm -rf "${prefix:?}/${dir}"
  done
}

relocate_shebangs() {
  find "$prefix" -type f -perm -u+x | while read -r file; do
    [ "$(head -c 2 "$file")" = '#!' ] || continue
    line=$(head -n 1 "$file")
    # The interpreter and its arguments, split as the kernel does, unglobbed.
    set -f
    # shellcheck disable=SC2086
    set -- ${line#'#!'}
    set +f
    interp="${1:-}"
    if [ "$interp" = /usr/bin/env ] && [ -n "${2:-}" ]; then
      interp="/usr/bin/$2"
      shift
    fi
    [ -n "$interp" ] && [ -e "${prefix}${interp}" ] || continue
    shift
    tool="${prefix}/bin/${interp##*/}"
    [ -e "$tool" ] || tool="${prefix}${interp}"
    sed -i "1s|.*|#!${tool}${*:+ $*}|" "$file"
  done
}

link_tools() {
  mkdir -p "${prefix}/bin"
  for tool in "$@"; do
    [ -e "${prefix}/usr/bin/${tool}" ] || { echo "no ${tool} in ${prefix}/usr/bin" >&2; exit 1; }
    ln -sf "../usr/bin/${tool}" "${prefix}/bin/${tool}"
  done
}

case "$cmd" in
  install) install_packages "$@" ;;
  finish)
    relocate_elf
    clear_root_bin
    link_tools "$@"
    relocate_shebangs
    chmod -R a+rX "$prefix"
    ;;
  *) echo "usage: $0 install|finish <prefix> <arch> ..." >&2; exit 2 ;;
esac

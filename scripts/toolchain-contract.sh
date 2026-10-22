#!/usr/bin/env bash
set -euo pipefail

# The toolchain contract: a built toolchain image is mounted read-only at
# /opt/kagent/tools/<name> beside an unchanged Harness image, its bin/ on PATH
# after the Harness image's own, and runs as uid 65532. This proves, against
# the built image:
#
#   - it declares its name, the Harnesses it serves and a version command per
#     tool (io.giantswarm.toolchain.* labels, see README.md);
#   - it sets no user and no entrypoint a Harness would see;
#   - every file is readable, every directory searchable and every bin/ tool
#     executable by uid 65532;
#   - it was built at its mount directory: no file names another
#     /opt/kagent/tools/<other> prefix, and no symlink leaves the prefix;
#   - every dynamically linked file finds each library it needs under the
#     prefix;
#   - each tool answers its version command as uid 65532, without a network,
#     with the image mounted beside every Harness image it declares
#     (harnesses: the names and digest-pinned images).
#
# Usage: scripts/toolchain-contract.sh <image> [<harnesses-file>]

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <image> [<harnesses-file>]" >&2
  exit 2
fi
image="$1"
harnesses_file="${2:-$(dirname "$0")/../harnesses}"

uid=65532
tools_root=/opt/kagent/tools
labels=io.giantswarm.toolchain

failed=0
pass() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failed=1; }

inspect() { docker image inspect -f "$1" "$image"; }
# label <key>: the image's label, empty when it is not set.
label() {
  local v
  v=$(inspect "{{index .Config.Labels \"$1\"}}")
  [[ "$v" == "<no value>" ]] || echo "$v"
}

name=$(label "${labels}.name")
if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "FAIL  label ${labels}.name is \"${name}\", want a lower-case name ([a-z0-9-])" >&2
  exit 1
fi
prefix="${tools_root}/${name}"
echo "contract of ${image}: toolchain ${name}, mounted at ${prefix}"

# Image configuration: nothing a Harness would see.
user=$(inspect '{{.Config.User}}')
if [[ -z "$user" ]]; then
  pass "user: none"
else
  fail "user: the image sets ${user}, a toolchain sets none"
fi
entrypoint=$(inspect '{{json .Config.Entrypoint}}')
if [[ "$entrypoint" == "null" || "$entrypoint" == "[]" ]]; then
  pass "entrypoint: none"
else
  fail "entrypoint: the image sets ${entrypoint}, a toolchain sets none"
fi

# The declarations.
mapfile -t harnesses < <(label "${labels}.harnesses" | tr ',' '\n' | tr -d ' ' | sed '/^$/d')
if [[ ${#harnesses[@]} -eq 0 ]]; then
  fail "harnesses: label ${labels}.harnesses declares none"
fi
# shellcheck disable=SC2016 # a Go template, not a shell expansion
mapfile -t tools < <(inspect '{{range $k, $v := .Config.Labels}}{{$k}}{{"\n"}}{{end}}' | sed -n "s/^${labels}\.tool\.//p")
if [[ ${#tools[@]} -eq 0 ]]; then
  fail "tools: no ${labels}.tool.<tool> label declares a version command"
fi

# The files, read from the image's filesystem as a Harness's mount sees it.
work=$(mktemp -d)
cid=""
cleanup() {
  [[ -z "$cid" ]] || docker rm -f "$cid" >/dev/null
  rm -rf "$work"
}
trap cleanup EXIT
cid=$(docker create "$image" contract)
docker export "$cid" >"${work}/rootfs.tar"
if python3 -I "$(dirname "$0")/toolchain-files.py" "${work}/rootfs.tar" "$prefix" "$uid"; then
  :
else
  failed=1
fi

# Each tool beside each declared Harness image.
# Docker before image mounts were stable warns on each one, ahead of the output.
mount_warning='^WARNING: Image mount is an experimental feature'
harness_image() {
  awk -v want="$1" '$1 == want && NF == 2 { print $2 }' "$harnesses_file"
}
for harness in "${harnesses[@]}"; do
  ref=$(harness_image "$harness")
  if [[ -z "$ref" ]]; then
    fail "${harness}: no such Harness in ${harnesses_file}"
    continue
  fi
  docker pull -q "$ref" >/dev/null
  path=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$ref" | sed -n 's/^PATH=//p')
  for tool in "${tools[@]}"; do
    cmd=$(label "${labels}.tool.${tool}")
    if out=$(docker run --rm --network none --user "${uid}:${uid}" \
      --mount "type=image,source=${image},target=${prefix}" \
      -e "PATH=${path:-/usr/local/bin:/usr/bin:/bin}:${prefix}/bin" -e HOME=/tmp \
      --entrypoint /bin/sh "$ref" -c "$cmd" 2>&1 | sed "/${mount_warning}/d"); then
      pass "${harness}: ${tool}: $(echo "$out" | head -1)"
    else
      fail "${harness}: ${tool} (${cmd}): $(echo "$out" | head -3 | tr '\n' ' ')"
    fi
  done
done

if [[ "$failed" -ne 0 ]]; then
  echo "${image} breaks the toolchain contract" >&2
  exit 1
fi
echo "${image} keeps the toolchain contract"

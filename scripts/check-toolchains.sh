#!/usr/bin/env bash
set -euo pipefail

# Build each toolchain under toolchains/ for this machine's platform and run
# the toolchain contract check against it. The image is built locally and
# never pushed: CircleCI publishes (.circleci/custom.yml).
#
# Usage: scripts/check-toolchains.sh [<name>...]   (default: every toolchain)

root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -gt 0 ]]; then
  names=("$@")
else
  mapfile -t names < <(find "${root}/toolchains" -mindepth 2 -maxdepth 2 -name Dockerfile -printf '%h\n' 2>/dev/null | xargs -r -n1 basename | sort)
fi
if [[ ${#names[@]} -eq 0 ]]; then
  echo "no toolchains under toolchains/"
  exit 0
fi

failed=0
for name in "${names[@]}"; do
  dir="${root}/toolchains/${name}"
  image="toolchain-contract/${name}:check"
  echo "::group::toolchain ${name}"
  docker build -t "$image" -f "${dir}/Dockerfile" "${root}/toolchains"
  declared=$(docker image inspect -f '{{index .Config.Labels "io.giantswarm.toolchain.name"}}' "$image")
  if [[ "$declared" != "$name" ]]; then
    echo "FAIL  toolchains/${name}: io.giantswarm.toolchain.name is \"${declared}\", want \"${name}\""
    failed=1
  elif ! "${root}/scripts/toolchain-contract.sh" "$image" "${root}/harnesses"; then
    failed=1
  fi
  echo "::endgroup::"
done

exit "$failed"

#!/usr/bin/env bash
set -euo pipefail

# Prove the toolchain contract check against the fixture toolchains in
# test/fixtures: `good` keeps the contract beside every Harness, and each
# broken fixture fails it for its own reason.
#
# Usage: scripts/toolchain-contract-fixtures.sh

root="$(cd "$(dirname "$0")/.." && pwd)"
check="${root}/scripts/toolchain-contract.sh"

# <fixture target> <the failure the check must report; empty: it passes>
cases=(
  "good|"
  "wrong-prefix|FAIL  built at another prefix: "
  "missing-lib|FAIL  library not under the prefix: "
  "unreadable|FAIL  uid 65532 cannot read "
  "user|FAIL  user: the image sets "
  "entrypoint|FAIL  entrypoint: the image sets "
)

failed=0
for c in "${cases[@]}"; do
  target="${c%%|*}"
  want="${c#*|}"
  image="toolchain-fixture:${target}"
  echo "::group::fixture ${target}"
  docker build -q --target "$target" -t "$image" "${root}/test/fixtures" >/dev/null
  status=0
  out=$("$check" "$image" 2>&1) || status=$?
  echo "$out"
  echo "::endgroup::"
  if [[ -z "$want" && "$status" -eq 0 ]]; then
    echo "ok    fixture ${target} keeps the contract"
  elif [[ -n "$want" && "$status" -ne 0 ]] && grep -qF -- "$want" <<<"$out"; then
    echo "ok    fixture ${target} fails: $(grep -F -- "$want" <<<"$out" | head -1)"
  else
    echo "FAIL  fixture ${target}: exit ${status}, want ${want:-a pass}"
    failed=1
  fi
done

exit "$failed"

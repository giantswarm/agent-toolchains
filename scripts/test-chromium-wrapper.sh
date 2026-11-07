#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
prefix="${temporary_directory}/prefix"
mkdir -p "${prefix}/usr/lib/chromium"
cat > "${prefix}/usr/lib/chromium/chromium" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@"
STUB
chmod 0755 "${prefix}/usr/lib/chromium/chromium"
sed "s|^prefix=/opt/kagent/tools/node$|prefix=${prefix}|" \
  "${root}/toolchains/node/chromium" > "${temporary_directory}/chromium"
chmod 0755 "${temporary_directory}/chromium"

assert_rules() {
  local expected=$1
  shift
  local output
  output=$("${temporary_directory}/chromium" "$@")
  if [[ "${output##*$'\n'}" != "--host-resolver-rules=${expected}" ]]; then
    printf 'Unexpected resolver rules: %s\n' "$output" >&2
    exit 1
  fi
}

protected='MAP muster ^NOTFOUND, MAP muster.* ^NOTFOUND'
offline='MAP * ^NOTFOUND'
assert_rules "$protected"
assert_rules "$protected" '--host-resolver-rules=MAP muster 127.0.0.1'
assert_rules "$protected" '--host-resolver-rules=EXCLUDE *'
assert_rules "$protected" '--host-resolver-rules=MAP * ^NOTFOUND, EXCLUDE muster'
assert_rules "$offline" "--host-resolver-rules=${offline}"
assert_rules "$offline" "--host-resolver-rules=${offline}" '--host-resolver-rules=EXCLUDE *'
output=$("${temporary_directory}/chromium" '--user-data-dir=/tmp/profile with spaces')
[[ "${output%%$'\n'*}" == '--user-data-dir=/tmp/profile with spaces' ]]
printf 'Chromium wrapper resolver checks passed\n'

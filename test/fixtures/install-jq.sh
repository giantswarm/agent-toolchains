#!/bin/sh
set -eu

# Install jq from Alpine's packages under <prefix>, the way a package-built
# toolchain is, and write the bin/ wrapper that runs it through the prefix's
# own loader and libraries.
#
# Usage: install-jq.sh <prefix>

prefix="$1"
mkdir -p "$prefix"
apk add --no-cache --root "$prefix" --initdb \
  --keys-dir /etc/apk/keys --repositories-file /etc/apk/repositories jq
# apk's lock is root's alone (0600); uid 65532 must read every file.
rm -f "${prefix}/lib/apk/db/lock"
mkdir -p "${prefix}/bin"
cat >"${prefix}/bin/jq" <<EOF
#!/bin/sh
exec ${prefix}/lib/ld-musl-$(uname -m).so.1 --library-path ${prefix}/lib:${prefix}/usr/lib ${prefix}/usr/bin/jq "\$@"
EOF
chmod 0755 "${prefix}/bin/jq"

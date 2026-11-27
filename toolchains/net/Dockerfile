# The net toolchain: tools to call services and find out why a connection
# fails. curl (HTTP), dig, host and nslookup (DNS), openssl (TLS: certificate
# chains and handshakes with `openssl s_client`), nc (whether a port answers),
# grpcurl (gRPC, by reflection) and websocat (WebSockets). Alpine's packages
# (toolchains/lib/apk-prefix.sh), but grpcurl: a pinned release binary
# (downloads). No tcpdump: it needs raw sockets, which uid 65532 has not.
# Mounted beside any other toolchain.
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.4@sha256:e2944c2947c8cabdd6b23a2ebcf8094a9f3d53ca9e0340edd065237ab74c18c0

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/net
RUN apk add --no-cache curl patchelf scanelf
COPY lib/apk-prefix.sh lib/fetch.sh /usr/local/bin/
COPY net/downloads /tmp/downloads
RUN apk-prefix.sh install "$PREFIX" "$TARGETARCH" \
      curl bind-tools openssl netcat-openbsd websocat \
 && fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && apk-prefix.sh finish "$PREFIX" "$TARGETARCH" \
      curl dig host nslookup openssl nc grpcurl websocat \
 && rm -rf "${PREFIX}/etc/ssl1.1"

# The tools read the CA bundle at /etc/ssl, the Harness image's: etc/ssl1.1
# only links there, outside the prefix.

# Every version command names the toolchain's copy: a Harness image's own
# tools come first on PATH (all carry busybox's nslookup and nc, the claude
# Harness its own curl), and the check must run the toolchain's.
FROM scratch
COPY --from=build /opt/kagent/tools/net/ /
LABEL io.giantswarm.toolchain.name="net" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,byo" \
      io.giantswarm.toolchain.tool.curl="/opt/kagent/tools/net/bin/curl --version" \
      io.giantswarm.toolchain.tool.dig="/opt/kagent/tools/net/bin/dig -v" \
      io.giantswarm.toolchain.tool.host="/opt/kagent/tools/net/bin/host -V" \
      io.giantswarm.toolchain.tool.nslookup="/opt/kagent/tools/net/bin/nslookup -version" \
      io.giantswarm.toolchain.tool.openssl="/opt/kagent/tools/net/bin/openssl version" \
      io.giantswarm.toolchain.tool.nc="/opt/kagent/tools/net/bin/nc -h 2>&1 | grep -m1 OpenBSD" \
      io.giantswarm.toolchain.tool.grpcurl="/opt/kagent/tools/net/bin/grpcurl --version" \
      io.giantswarm.toolchain.tool.websocat="/opt/kagent/tools/net/bin/websocat --version"

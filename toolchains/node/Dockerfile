# The node toolchain: Node with npm, npx and corepack, from Alpine's packages
# (toolchains/lib/apk-prefix.sh). Alpine packages no corepack: it is the
# pinned npm package of downloads.
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/node
RUN apk add --no-cache curl patchelf scanelf
COPY lib/apk-prefix.sh lib/fetch.sh /usr/local/bin/
COPY node/downloads /tmp/downloads
COPY node/node /tmp/node
# bin/node sets Node's ICU data (node/node); the shebangs of npm, npx and
# corepack name bin/node, so they run through it too.
RUN apk-prefix.sh install "$PREFIX" "$TARGETARCH" nodejs npm \
 && fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && chmod 0755 "${PREFIX}/usr/lib/node_modules/corepack/dist/corepack.js" \
 && ln -s ../lib/node_modules/corepack/dist/corepack.js "${PREFIX}/usr/bin/corepack" \
 && apk-prefix.sh finish "$PREFIX" "$TARGETARCH" node npm npx corepack \
 && rm "${PREFIX}/bin/node" \
 && install -m 0755 /tmp/node "${PREFIX}/bin/node"

FROM scratch
COPY --from=build /opt/kagent/tools/node/ /
LABEL io.giantswarm.toolchain.name="node" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.node="node --version && node -e 'require(\"crypto\").createHash(\"sha256\"); new Intl.DateTimeFormat()'" \
      io.giantswarm.toolchain.tool.npm="npm --version" \
      io.giantswarm.toolchain.tool.npx="npx --version" \
      io.giantswarm.toolchain.tool.corepack="corepack --version"

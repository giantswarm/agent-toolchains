# The data toolchain: tools to query, reshape and convert structured data in a
# shell pipeline. jq (JSON), yq (YAML, and conversion between YAML, JSON, TOML
# and XML), miller `mlr` (CSV and TSV), sqlite3 (SQL over loaded data), gron
# (JSON as greppable lines), jo (JSON from shell arguments) and xmlstarlet (XML
# with XPath). Alpine's packages (toolchains/lib/apk-prefix.sh), but yq: a
# pinned release binary (downloads). Mounted beside any other toolchain.
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.4@sha256:e2944c2947c8cabdd6b23a2ebcf8094a9f3d53ca9e0340edd065237ab74c18c0

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/data
RUN apk add --no-cache curl patchelf scanelf
COPY lib/apk-prefix.sh lib/fetch.sh /usr/local/bin/
COPY data/downloads /tmp/downloads
RUN apk-prefix.sh install "$PREFIX" "$TARGETARCH" \
      jq miller sqlite gron jo xmlstarlet \
 && fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && apk-prefix.sh finish "$PREFIX" "$TARGETARCH" \
      jq yq mlr sqlite3 gron jo xmlstarlet

FROM scratch
COPY --from=build /opt/kagent/tools/data/ /
LABEL io.giantswarm.toolchain.name="data" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,byo" \
      io.giantswarm.toolchain.tool.jq="jq --version" \
      io.giantswarm.toolchain.tool.yq="yq --version" \
      io.giantswarm.toolchain.tool.mlr="mlr --version" \
      io.giantswarm.toolchain.tool.sqlite3="sqlite3 --version" \
      io.giantswarm.toolchain.tool.gron="gron --version" \
      io.giantswarm.toolchain.tool.jo="jo -v" \
      io.giantswarm.toolchain.tool.xmlstarlet="xmlstarlet --version"

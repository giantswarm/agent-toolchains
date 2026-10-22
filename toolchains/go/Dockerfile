# The go toolchain: Go and what a repository made from the giantswarm
# templates (template, mcp-template, template-app) runs locally. No kubectl
# (an agent reaches clusters through mcp-kubernetes), no kind (an actor has no
# container runtime) and no devctl (served by its MCP server).
#
# Built at /opt/kagent/tools/go on the build platform for each target
# architecture: Go's own GOROOT is copied from the target's image, goimports
# is cross-compiled, make is Alpine's, every other tool is a pinned release
# binary (downloads).
ARG GOLANG=gsoci.azurecr.io/giantswarm/golang:1.27.3-alpine3.24@sha256:f2c872bcee949b7be9c490efd02b48a8a2fbf947cdf533f1c58525ec9d8170fd
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6

FROM ${GOLANG} AS goroot

FROM --platform=$BUILDPLATFORM ${GOLANG} AS goimports
ARG TARGETARCH
ARG GOIMPORTS_VERSION=v0.52.0
RUN CGO_ENABLED=0 GOOS=linux GOARCH="$TARGETARCH" go install "golang.org/x/tools/cmd/goimports@${GOIMPORTS_VERSION}" \
 && find "$(go env GOPATH)/bin" -name goimports -type f -exec cp {} /goimports \;

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/go
RUN apk add --no-cache curl patchelf scanelf
COPY lib/apk-prefix.sh lib/fetch.sh /usr/local/bin/
# GNU make from Alpine's packages: the templates' targets are make targets,
# and no Harness image carries make.
RUN apk-prefix.sh install "$PREFIX" "$TARGETARCH" make \
 && apk-prefix.sh finish "$PREFIX" "$TARGETARCH" make
COPY --from=goroot /usr/local/go ${PREFIX}/go
COPY --from=goimports /goimports ${PREFIX}/bin/goimports
COPY go/downloads /tmp/downloads
COPY go/ct ${PREFIX}/bin/ct
# Go's own test suite and test data are for building Go, not with it; some
# test data are foreign binaries whose libraries no prefix holds.
RUN fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && rm -rf "${PREFIX}/go/test" \
 && find "${PREFIX}/go/src" -type d -name testdata -prune -exec rm -rf {} + \
 && ln -s ../go/bin/go "${PREFIX}/bin/go" \
 && ln -s ../go/bin/gofmt "${PREFIX}/bin/gofmt" \
 && chmod 0755 "${PREFIX}/bin/ct" \
 && chmod -R a+rX "$PREFIX"

FROM scratch
COPY --from=build /opt/kagent/tools/go/ /
LABEL io.giantswarm.toolchain.name="go" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.go="go version && go env GOROOT" \
      io.giantswarm.toolchain.tool.make="make --version" \
      io.giantswarm.toolchain.tool.gofmt="echo 'package p' | gofmt" \
      io.giantswarm.toolchain.tool.goimports="echo 'package p' | goimports" \
      io.giantswarm.toolchain.tool.golangci-lint="golangci-lint version" \
      io.giantswarm.toolchain.tool.nancy="nancy --version" \
      io.giantswarm.toolchain.tool.gitsemver="gitsemver --version" \
      io.giantswarm.toolchain.tool.architect="architect version" \
      io.giantswarm.toolchain.tool.helm="helm version --short" \
      io.giantswarm.toolchain.tool.helm-docs="helm-docs --version" \
      io.giantswarm.toolchain.tool.yq="yq --version" \
      io.giantswarm.toolchain.tool.vendir="vendir version" \
      io.giantswarm.toolchain.tool.schemalint="schemalint --version" \
      io.giantswarm.toolchain.tool.helm-values-schema-json="helm-values-schema-json --version" \
      io.giantswarm.toolchain.tool.ct="ct version"

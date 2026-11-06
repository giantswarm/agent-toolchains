# The gitlab toolchain: GitLab's CLI `glab`, a pinned release binary
# (downloads). Apart from `github`, so a Session picks GitHub, GitLab or both.
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.4@sha256:e2944c2947c8cabdd6b23a2ebcf8094a9f3d53ca9e0340edd065237ab74c18c0

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/gitlab
RUN apk add --no-cache curl
COPY lib/fetch.sh /usr/local/bin/
COPY gitlab/downloads /tmp/downloads
RUN fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && chmod -R a+rX "$PREFIX"

# The version command names the toolchain's glab: a Harness image carrying its
# own glab puts that one first on PATH.
FROM scratch
COPY --from=build /opt/kagent/tools/gitlab/ /
LABEL io.giantswarm.toolchain.name="gitlab" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.glab="/opt/kagent/tools/gitlab/bin/glab --version"

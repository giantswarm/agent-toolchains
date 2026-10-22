# Fixture toolchains for scripts/toolchain-contract-fixtures.sh, one target
# each: `good` keeps the toolchain contract, every other target breaks it in
# one way. Each is jq from Alpine's packages, installed under its prefix with
# a bin/ wrapper (install-jq.sh).
ARG ALPINE=docker.io/library/alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6

FROM ${ALPINE} AS build
COPY install-jq.sh /
RUN /install-jq.sh /opt/kagent/tools/jq

# The same toolchain, built at another mount directory.
FROM ${ALPINE} AS build-elsewhere
COPY install-jq.sh /
RUN /install-jq.sh /opt/kagent/tools/elsewhere

# The same toolchain without a library jq needs.
FROM build AS build-missing-lib
RUN rm /opt/kagent/tools/jq/usr/lib/libonig.so.*

FROM scratch AS good
COPY --from=build /opt/kagent/tools/jq/ /
LABEL io.giantswarm.toolchain.name="jq" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.jq="jq --version"

FROM scratch AS wrong-prefix
COPY --from=build-elsewhere /opt/kagent/tools/elsewhere/ /
LABEL io.giantswarm.toolchain.name="jq" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.jq="jq --version"

FROM scratch AS missing-lib
COPY --from=build-missing-lib /opt/kagent/tools/jq/ /
LABEL io.giantswarm.toolchain.name="jq" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.jq="jq --version"

FROM good AS user
USER 65532:65532

FROM good AS entrypoint
ENTRYPOINT ["/opt/kagent/tools/jq/bin/jq"]

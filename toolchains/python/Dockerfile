# The python toolchain: python3 and what the giantswarm templates' pre-commit
# hooks, the app ATS tests and ct's lint run, from Alpine's packages
# (toolchains/lib/apk-prefix.sh): pre-commit, pytest, yamllint and yamale,
# and shellcheck for the shell-lint hook. Alpine packages no yamale: it is the
# hash-pinned wheel of requirements.txt; shellcheck is a pinned download.
# Mounted beside `go` or `node`.
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/python
RUN apk add --no-cache curl patchelf scanelf python3 py3-pip
COPY lib/apk-prefix.sh lib/fetch.sh /usr/local/bin/
COPY python/requirements.txt python/downloads /tmp/
# A virtual environment records bin/ as its Python's home, and Python finds
# its standard library from there as ../lib/python3.X: lib/ links it.
RUN apk-prefix.sh install "$PREFIX" "$TARGETARCH" \
      python3 pre-commit py3-pytest yamllint py3-yaml \
 && pip install --no-deps --require-hashes --no-compile --no-cache-dir \
      --break-system-packages --root-user-action=ignore \
      --prefix "${PREFIX}/usr" -r /tmp/requirements.txt \
 && fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && apk-prefix.sh finish "$PREFIX" "$TARGETARCH" \
      python3 pre-commit pytest yamllint yamale shellcheck \
 && stdlib=$(cd "${PREFIX}/usr/lib" && echo python3.*) \
 && ln -s "../usr/lib/${stdlib}" "${PREFIX}/lib/${stdlib}"

FROM scratch
COPY --from=build /opt/kagent/tools/python/ /
LABEL io.giantswarm.toolchain.name="python" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.python3="python3 --version && python3 -m venv --without-pip /tmp/venv && /tmp/venv/bin/python -c 'import ssl, sqlite3'" \
      io.giantswarm.toolchain.tool.pre-commit="pre-commit --version" \
      io.giantswarm.toolchain.tool.pytest="pytest --version" \
      io.giantswarm.toolchain.tool.yamllint="yamllint --version" \
      io.giantswarm.toolchain.tool.yamale="yamale --help >/dev/null && python3 -c 'import yamale; print(\"yamale\", yamale.__version__)'" \
      io.giantswarm.toolchain.tool.shellcheck="shellcheck --version"

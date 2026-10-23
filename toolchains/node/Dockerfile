# The node toolchain: Node with npm, npx and corepack, and a headless browser:
# Chromium and the Playwright CLI. Node, npm and Chromium come from Alpine's
# packages (toolchains/lib/apk-prefix.sh). Alpine packages no corepack: it is
# the pinned npm package of downloads. The Playwright CLI is the pinned npm
# package of packages/package-lock.json.
ARG ALPINE=gsoci.azurecr.io/giantswarm/alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6

FROM --platform=$BUILDPLATFORM ${ALPINE} AS build
ARG TARGETARCH
ENV PREFIX=/opt/kagent/tools/node
RUN apk add --no-cache curl patchelf scanelf nodejs npm
COPY lib/apk-prefix.sh lib/fetch.sh /usr/local/bin/
COPY node/downloads /tmp/downloads
COPY node/packages /tmp/packages
COPY node/node node/chromium node/playwright-cli /tmp/bin/
# The Playwright CLI is JavaScript only, so the build platform's npm installs
# it for every architecture, from the lockfile and without install scripts.
RUN npm ci --prefix /tmp/packages --omit=dev --ignore-scripts --no-audit --no-fund
# bin/node sets Node's ICU data (node/node); the shebangs of npm, npx and
# corepack name bin/node, so they run through it too. bin/chromium points
# Chromium at the prefix's fonts and ICU data and blocks muster's host
# (node/chromium); bin/playwright-cli configures the CLI (node/playwright-cli).
# Alpine's paths inside the prefix move under it: absolute symlinks,
# fontconfig's font directories, and a library's own run path (libpulse's
# /usr/lib/pulseaudio), which musl searches for that library's needs.
RUN apk-prefix.sh install "$PREFIX" "$TARGETARCH" nodejs npm chromium font-liberation \
 && fetch.sh "$PREFIX" /tmp/downloads "$TARGETARCH" \
 && cp -R /tmp/packages/node_modules/. "${PREFIX}/usr/lib/node_modules/" \
 && chmod 0755 "${PREFIX}/usr/lib/node_modules/corepack/dist/corepack.js" \
 && ln -s ../lib/node_modules/corepack/dist/corepack.js "${PREFIX}/usr/bin/corepack" \
 && sed -i -e "s|/usr/share/fonts|${PREFIX}/usr/share/fonts|g" \
      -e "s|<include ignore_missing=\"yes\">conf.d</include>|<include ignore_missing=\"yes\">${PREFIX}/etc/fonts/conf.d</include>|" \
      -e "s|<cachedir>/var/cache/fontconfig</cachedir>||" \
      "${PREFIX}/etc/fonts/fonts.conf" \
 && find "$PREFIX" -type l | while read -r link; do \
      target=$(readlink "$link"); \
      case "$target" in /*) ln -sfn "${PREFIX}${target}" "$link" ;; esac; \
    done \
 && apk-prefix.sh finish "$PREFIX" "$TARGETARCH" node npm npx corepack \
 && scanelf --recursive --quiet --rpath --format '%r|%F' "$PREFIX" | while IFS='|' read -r rpath file; do \
      moved=$(echo "$rpath" | tr ':' '\n' | sed "\|^${PREFIX}/|!s|^/|${PREFIX}/|" | paste -sd: -); \
      [ "$moved" = "$rpath" ] || patchelf --set-rpath "$moved" "$file"; \
    done \
 && rm "${PREFIX}/bin/node" \
 && install -m 0755 /tmp/bin/node /tmp/bin/chromium /tmp/bin/playwright-cli "${PREFIX}/bin/"

FROM scratch
COPY --from=build /opt/kagent/tools/node/ /
# The launch lines: tool.chromium starts Chromium headless through bin/chromium
# as the check's uid 65532, and tool.playwright-cli loads a page through the
# CLI with the configuration bin/playwright-cli sets.
LABEL io.giantswarm.toolchain.name="node" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.node="node --version && node -e 'require(\"crypto\").createHash(\"sha256\"); new Intl.DateTimeFormat()'" \
      io.giantswarm.toolchain.tool.npm="npm --version" \
      io.giantswarm.toolchain.tool.npx="npx --version" \
      io.giantswarm.toolchain.tool.corepack="corepack --version" \
      io.giantswarm.toolchain.tool.chromium="chromium --version && chromium --headless --no-sandbox --disable-gpu --dump-dom 'data:text/html,<title>ok</title>' | grep -q '<title>ok</title>'" \
      io.giantswarm.toolchain.tool.playwright-cli="playwright-cli --version && cd /tmp && playwright-cli open 'data:text/html,<title>ok</title>' >/dev/null && playwright-cli eval document.title | grep -q ok && playwright-cli close >/dev/null"

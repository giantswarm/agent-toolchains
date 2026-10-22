#!/usr/bin/env bash
set -euo pipefail

# Emit a complete CircleCI continuation config to stdout.
# Called by the setup job in config.yml.
#
# A toolchains/<name>/ directory is image agent-toolchains/<name>, tagged
# <name>/vX.Y.Z (.github/workflows/toolchain-release.yaml), published to
# gsoci.azurecr.io only.
#
# Branch builds: a dev image (amd64) of each changed toolchain, for a proof
#                before merge; it never moves `latest`.
# Tag builds:    the toolchain contract check, then the multi-arch image under
#                its version and `latest`: the push requires the check, so
#                `latest` moves only to a toolchain that keeps the contract.
# No changes:    a no-op config.

ARCHITECT_ORB="giantswarm/architect@10.14.13"
REPOSITORY="https://github.com/giantswarm/agent-toolchains"

# One line, no trailing newline: the orb reads it line by line.
REGISTRIES="public gsoci.azurecr.io ACR_GSOCI_USERNAME ACR_GSOCI_PASSWORD true"

emit_header() {
  cat <<EOF
version: 2.1

orbs:
  architect: ${ARCHITECT_ORB}

jobs:
  toolchain-contract:
    parameters:
      toolchain:
        type: string
    machine:
      image: ubuntu-2404:current
    resource_class: medium
    steps:
      - checkout
      - run:
          name: Toolchain contract of << parameters.toolchain >>
          command: scripts/check-toolchains.sh << parameters.toolchain >>

workflows:
  build:
    jobs:
EOF
}

emit_annotations() {
  local name="$1"
  cat <<EOF
          io.giantswarm.toolchain.name=${name}
          io.giantswarm.toolchain.repository=${REPOSITORY}
          io.giantswarm.toolchain.license=Apache-2.0
EOF
}

emit_branch_job() {
  local name="$1"
  cat <<EOF
    - architect/push-to-registries:
        context: architect
        multiarch: true
        name: push-${name}
        image: giantswarm/agent-toolchains/${name}
        dockerfile: ./toolchains/${name}/Dockerfile
        build-context: ./toolchains/${name}
        platforms: "linux/amd64"
        resource_class: medium
        persist-build-version: false
        registries-data: "${REGISTRIES}"
        annotations: |
$(emit_annotations "$name")
EOF
}

emit_tag_job() {
  local name="$1"
  cat <<EOF
    - toolchain-contract:
        name: contract-${name}
        toolchain: ${name}
        filters:
          tags:
            only: /^${name}\\/v.*/
          branches:
            ignore: /.*/

    - architect/push-to-registries:
        context: architect
        multiarch: true
        name: push-${name}
        image: giantswarm/agent-toolchains/${name}
        dockerfile: ./toolchains/${name}/Dockerfile
        build-context: ./toolchains/${name}
        platforms: "linux/amd64,linux/arm64"
        resource_class: medium
        git-tag-prefix: "${name}"
        registries-data: "${REGISTRIES}"
        annotations: |
$(emit_annotations "$name")
        requires:
          - contract-${name}
        filters:
          tags:
            only: /^${name}\\/v.*/
          branches:
            ignore: /.*/
EOF
}

emit_noop() {
  cat <<EOF
version: 2.1

jobs:
  no-op:
    docker:
      - image: cimg/base:current
    steps:
      - run: echo "No toolchain changed"

workflows:
  noop:
    jobs:
      - no-op
EOF
}

# --- Main ---

if [[ -n "${CIRCLE_TAG:-}" ]]; then
  NAME="${CIRCLE_TAG%%/v*}"
  if [[ ! -f "toolchains/${NAME}/Dockerfile" ]]; then
    echo "ERROR: tag ${CIRCLE_TAG} names no toolchains/<name>/Dockerfile" >&2
    exit 1
  fi
  emit_header
  emit_tag_job "$NAME"
  exit 0
fi

# Branch build: only the changed toolchains.
CHANGED=()
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  mapfile -t CHANGED < <(
    git diff --name-only origin/main...HEAD \
      | sed -n 's|^toolchains/\([^/]*\)/.*|\1|p' \
      | sort -u
  )
fi

BUILD=()
for name in "${CHANGED[@]}"; do
  [[ -f "toolchains/${name}/Dockerfile" ]] && BUILD+=("$name")
done

if [[ ${#BUILD[@]} -eq 0 ]]; then
  emit_noop
  exit 0
fi

emit_header
for name in "${BUILD[@]}"; do
  emit_branch_job "$name"
done

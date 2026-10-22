# agent-toolchains

Toolchains for coding agents: the toolchain contract check and published toolchain images.

A **toolchain** is a named set of tools (`go`, `node`) published as its own OCI image. The platform mounts it read-only at `/opt/kagent/tools/<name>` into a coding agent's Session, beside the unchanged image of the agent's Harness (the kagent ADK, `claude`, `codex` or `omp`), with the toolchain's `bin/` on `PATH` after the Harness image's own. One toolchain serves every Harness it declares.

## Layout

| Path | What it is |
|---|---|
| `toolchains/<name>/Dockerfile` | A toolchain: image `gsoci.azurecr.io/giantswarm/agent-toolchains/<name>`, released as `<name>/vX.Y.Z` |
| `harnesses` | The Harness images the contract check runs beside, digest-pinned, moved by Renovate |
| `scripts/toolchain-contract.sh` | The toolchain contract check of one built image |
| `scripts/check-toolchains.sh` | Builds each toolchain and runs the check on it |
| `test/fixtures/` | Fixture toolchains: one that keeps the contract and one per way to break it |

## Writing a toolchain

The image root is the mount directory: build everything at `/opt/kagent/tools/<name>` in a build stage, then copy that directory to the root of a `scratch` image. Shebangs and library paths embed the build prefix, so a toolchain is not relocatable.

```dockerfile
FROM docker.io/library/alpine:3.22.7@sha256:... AS build
RUN mkdir -p /opt/kagent/tools/jq \
 && apk add --no-cache --root /opt/kagent/tools/jq --initdb \
      --keys-dir /etc/apk/keys --repositories-file /etc/apk/repositories jq \
 && rm -f /opt/kagent/tools/jq/lib/apk/db/lock
# bin/jq: a wrapper that runs usr/bin/jq through the prefix's own loader and libraries

FROM scratch
COPY --from=build /opt/kagent/tools/jq/ /
LABEL io.giantswarm.toolchain.name="jq" \
      io.giantswarm.toolchain.harnesses="kagent,claude,codex,omp" \
      io.giantswarm.toolchain.tool.jq="jq --version"
```

`test/fixtures/Dockerfile` and `test/fixtures/install-jq.sh` are a complete example.

The labels declare the toolchain:

| Label | Value |
|---|---|
| `io.giantswarm.toolchain.name` | The toolchain's name, its directory's name: the mount directory is `/opt/kagent/tools/<name>` |
| `io.giantswarm.toolchain.harnesses` | The Harnesses it serves, comma-separated names from `harnesses` |
| `io.giantswarm.toolchain.tool.<tool>` | One per tool: its version command, run by `/bin/sh -c` |

## The toolchain contract check

`scripts/toolchain-contract.sh <image>` asserts against the built image that:

- it declares its name, its Harnesses and a version command per tool;
- it sets no user and no entrypoint a Harness would see;
- every file is readable, every directory searchable and every `bin/` tool executable by uid 65532;
- it was built at its mount directory: no file names another `/opt/kagent/tools/<other>` prefix and no symlink leaves the prefix;
- every dynamically linked file finds each library it needs under the prefix;
- each tool answers its version command as uid 65532, without a network, with the image mounted read-only beside every Harness image it declares.

It is the required `Toolchain contract` check on every pull request, which first proves itself on the fixture toolchains (`scripts/toolchain-contract-fixtures.sh`): `good` passes, and `wrong-prefix`, `missing-lib`, `unreadable` (apk's root-only lock kept), `user` and `entrypoint` each fail for their own reason. It runs again in the CircleCI tag pipeline, where the push of a release, and so its `latest` tag, requires it.

Run it locally with `make check` (every toolchain) or `make check-fixtures`.

## Releases

Each merge to `main` tags every changed toolchain `<name>/vX.Y.Z` (`.github/workflows/toolchain-release.yaml`), the bump taken from the squash subject: a breaking change the major, a `feat` the minor, anything else the patch. The tag's CircleCI pipeline runs the contract check, then publishes the multi-arch image to `gsoci.azurecr.io` under its version and `latest`. A pull request that changes a toolchain also publishes an amd64 dev image, which never moves `latest`.

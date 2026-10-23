# agent-toolchains

Toolchains for coding agents: the toolchain contract check and published toolchain images.

A **toolchain** is a named set of tools (`go`, `node`) published as its own OCI image. The platform mounts it read-only at `/opt/kagent/tools/<name>` into a coding agent's Session, beside the unchanged image of the agent's Harness (the kagent ADK, `claude`, `codex` or `omp`), with the toolchain's `bin/` on `PATH` after the Harness image's own. One toolchain serves every Harness it declares.

## Layout

| Path | What it is |
|---|---|
| `toolchains/<name>/Dockerfile` | A toolchain: image `gsoci.azurecr.io/giantswarm/agent-toolchains/<name>`, released as `<name>/vX.Y.Z` |
| `toolchains/<name>/downloads` | A toolchain's pinned downloads: per architecture, a URL and its sha256 |
| `toolchains/lib/` | The build scripts every toolchain shares: `fetch.sh` (pinned downloads), `apk-prefix.sh` (Alpine packages) |
| `harnesses` | The Harness images the contract check runs beside, digest-pinned, moved by Renovate |
| `scripts/toolchain-contract.sh` | The toolchain contract check of one built image |
| `scripts/check-toolchains.sh` | Builds each toolchain and runs the check on it |
| `test/fixtures/` | Fixture toolchains: one that keeps the contract and one per way to break it |

## Toolchains

| Toolchain | Tools |
|---|---|
| `go` | Go (with `gofmt`, `go vet`), make, golangci-lint (the version giantswarm/architect lints with), goimports, nancy, gitsemver, architect, helm, helm-docs, yq, vendir, schemalint, helm-values-schema-json, ct: what a repository made from the giantswarm templates runs locally. No kubectl (agents reach clusters through mcp-kubernetes), no kind (an actor has no container runtime), no devctl (served by its MCP server) |
| `node` | Node, npm, npx, corepack |
| `python` | python3, pre-commit, pytest, yamllint, yamale, shellcheck: the templates' pre-commit hooks, the app ATS tests and ct's lint; mounted beside `go` or `node` |
| `github` | `gh` |
| `gitlab` | `glab` |

`github` and `gitlab` are separate, so a Session picks GitHub, GitLab or both. Each declares the Harnesses `kagent`, `claude`, `codex` and `omp`.

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

`test/fixtures/Dockerfile` and `test/fixtures/install-jq.sh` are a complete example. A toolchain builds with `toolchains/` as its context, so its Dockerfile copies the shared scripts from `lib/` and its own files from `<name>/`:

- **A release binary**: a line in `<name>/downloads` (`<dest> <arch> <sha256> <url> [<member>]`), fetched and verified by `lib/fetch.sh` (`github`, `gitlab`, most of `go`).
- **Alpine packages**: `lib/apk-prefix.sh install` installs them for the target architecture under the prefix, and `lib/apk-prefix.sh finish` makes the prefix self-contained: every executable gets the prefix's own musl loader and library path, shebangs name the prefix's interpreters, and `bin/` links the named tools only (`python`, `node`). A binary that does not survive a moved ELF interpreter (a GHC binary such as Alpine's shellcheck) is a pinned download instead.

Nothing of the target architecture runs while building, so the build stage runs on the build platform (`FROM --platform=$BUILDPLATFORM`) and an arm64 image needs no emulation. A tool that reads data from a fixed system path gets a `bin/` wrapper pointing it at the prefix (`go/ct`, `node/node`): a toolchain sets no environment.

The labels declare the toolchain:

| Label | Value |
|---|---|
| `io.giantswarm.toolchain.name` | The toolchain's name, its directory's name: the mount directory is `/opt/kagent/tools/<name>` |
| `io.giantswarm.toolchain.harnesses` | The Harnesses it serves, comma-separated names from `harnesses` |
| `io.giantswarm.toolchain.egress` | Optional: the origins its tools reach, comma-separated `https://host[:port]` (`go`: the module proxy and checksum database). A Session that mounts the toolchain reaches them beside its agent's own; one without it does not |
| `io.giantswarm.toolchain.tool.<tool>` | One per tool: its version command, run by `/bin/sh -c` |

## The toolchain contract check

`scripts/toolchain-contract.sh <image>` asserts against the built image that:

- it declares its name, its Harnesses and a version command per tool, and its egress origins, when it declares any, are `http(s)://host[:port]` origins;
- it sets no user and no entrypoint a Harness would see;
- every file is readable, every directory searchable and every `bin/` tool executable by uid 65532;
- it was built at its mount directory: no file names another `/opt/kagent/tools/<other>` prefix and no symlink leaves the prefix;
- every dynamically linked file finds each library it needs under the prefix;
- each tool answers its version command as uid 65532, without a network, with the image mounted read-only beside every Harness image it declares.

It is the required `Toolchain contract` check on every pull request, which first proves itself on the fixture toolchains (`scripts/toolchain-contract-fixtures.sh`): `good` passes, and `wrong-prefix`, `missing-lib`, `unreadable` (apk's root-only lock kept), `user`, `entrypoint` and `egress` (an origin with a path) each fail for their own reason. It runs again in the CircleCI tag pipeline, where the push of a release, and so its `latest` tag, requires it.

Run it locally with `make check` (every toolchain) or `make check-fixtures`.

## Releases

Each merge to `main` tags every changed toolchain `<name>/vX.Y.Z` (the generated Auto Release, `.github/workflows/zz_generated.auto_release.yaml`), the bump taken from the squash subject: a breaking change the major, a `feat` the minor, anything else the patch. The tag's CircleCI pipeline (devctl-generated) runs the contract check (`check-image` in `.circleci/custom.yml`), then publishes the multi-arch image to `gsoci.azurecr.io` under its version and `latest`. A pull request that changes a toolchain also publishes an amd64 dev image, which never moves `latest`.

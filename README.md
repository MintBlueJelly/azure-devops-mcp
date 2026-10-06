# azure-devops-mcp

A container image for Microsoft's official [Azure DevOps MCP
server](https://github.com/microsoft/azure-devops-mcp), built from source at a pinned upstream
release with the patches in [`patches/`](patches) applied. Upstream ships an npm package and no
image, and its server speaks stdio only.

```
ghcr.io/mintbluejelly/azure-devops-mcp:2.10.0-1
```

**There is no source code here.** Everything this image runs that is not upstream's is in `patches/`,
so reviewing the image means reading those files, and vetting a new upstream release means rebasing
them.

| Path | What it is |
| --- | --- |
| `azure-devops-mcp.dockerfile` | The pins (`UPSTREAM_TAG`, `UPSTREAM_COMMIT`, `PATCH_REVISION`) and the build |
| `patches/` | `git format-patch` output, applied in name order to the pinned commit |
| `.github/workflows/docker-image.yml` | Tests, builds, smoke-tests and releases the image |

## What the patch adds

`0001` adds a second entry point, `dist/http.js`, which serves MCP over stateless Streamable HTTP and
**acts as the caller whose bearer token each request carries.** The server holds no credential of its
own. Every `POST /mcp` needs `Authorization: Bearer <token>`, where the token is a Microsoft Entra
access token for Azure DevOps (resource `499b84ac-1321-427f-aa17-267ca6975798`). Each request gets a
fresh server whose tools use that token and nothing else. A request without one gets `401` before
any tool runs. It is meant to sit behind a gateway that signs each caller in and passes their token
on.

The tools themselves are upstream's, unchanged, and call the Azure DevOps REST API directly.

```sh
docker run --rm -p 8080:8080 ghcr.io/mintbluejelly/azure-devops-mcp:2.10.0-1 <organization>
token=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv)
curl -s http://127.0.0.1:8080/mcp -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"core_list_projects","arguments":{}}}'
```

Arguments after the image name are the server's: the organization, then upstream's `--domains`, and
`--port` (default `8080`) or `--path` (default `/mcp`). `GET /healthz` answers without a token.

- **Stateless.** No session is issued, so a tool that would ask the user for a missing project or
  team fails instead.
- **The image runs the HTTP entry point only.** Upstream's stdio server (`dist/index.js`) is built
  but not supported here: its interactive and `azcli` authentication need `keytar`, which this image
  does not install. Images up to `2.9.0` ran the stdio server.

## Releasing

**The three `ARG`s at the top of `azure-devops-mcp.dockerfile` are the release.** The workflow reads
the version back out of that file as `<upstream version>-<PATCH_REVISION>`, so the two can never
disagree. Push, and the image appears as `:2.10.0-1`, `:latest` and `:<sha>`, with a matching
`v2.10.0-1` GitHub release that names the upstream commit and links each patch.

**Changing a patch means bumping `PATCH_REVISION`.** Otherwise different code would be pushed to a
tag that already exists, and whatever pins that tag would never notice. The workflow refuses a change
under `patches/` that leaves both `UPSTREAM_TAG` and `PATCH_REVISION` alone.

A rebuild with nothing changed finds its release already present and skips it. Run the workflow by
hand to rebuild for a base-image CVE.

The build fails if `UPSTREAM_TAG` no longer points at `UPSTREAM_COMMIT`, if a patch does not apply,
or if upstream's test suite fails against the patched source. That suite runs in the dockerfile's
`test` stage. The workflow builds that stage first, and none of it reaches the image.

## Moving to a new upstream release

```sh
tag=v2.11.0
git ls-remote https://github.com/microsoft/azure-devops-mcp.git "refs/tags/$tag*"   # the commit; for an annotated tag, the ^{} line
git clone --branch "$tag" https://github.com/microsoft/azure-devops-mcp.git upstream && cd upstream
git switch -c patched
git am -3 ../patches/*.patch                      # on a conflict: resolve, git add, git am --continue
npm ci --ignore-scripts && npm rebuild keytar && npm run build && npm test
rm ../patches/*.patch && git format-patch "$tag" --zero-commit --no-signature -o ../patches
```

Then set `UPSTREAM_TAG` and `UPSTREAM_COMMIT`, and reset `PATCH_REVISION` to `1`.

`--zero-commit` and `--no-signature` keep the regenerated files free of a fresh commit hash and the
local git version, so the pull request's diff of `patches/` shows only what actually changed. Each
patch's commit message says why it exists. Drop a patch, or the part of one, once upstream ships the
same change: `0001`'s `jest.config.cjs` hunk is already on upstream `main`.

## `ENTRYPOINT`, not `CMD`

The image declares an `ENTRYPOINT` so that a runner supplying arguments **appends** to it. Against a
`CMD`-only image those arguments replace the command instead, and the container dies with
`exec: … not found`. The entrypoint also carries `--host 0.0.0.0`, because the server's own default,
loopback, cannot be reached from outside the container, so do not pass `--host` again.

The workflow's smoke test starts the image with only an organization and checks that it is reachable,
refuses a request without a token and lists its tools. A broken entrypoint otherwise surfaces as a
container that exits immediately with an empty log.

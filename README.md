# azure-devops-mcp

A container image for Microsoft's official [Azure DevOps MCP
server](https://github.com/microsoft/azure-devops-mcp), which upstream ships as an npm package and
nothing else — no image, no Dockerfile.

There is no source code here. The whole image is `npm install -g @azure-devops/mcp@<version>` over
an Alpine-based Node image, and this repository exists only so that something orchestrating
containers has a pinned image reference to point at.

```
ghcr.io/mintbluejelly/azure-devops-mcp:2.9.0
```

The server itself is stdio-only and takes its configuration from arguments and environment; see
[upstream's documentation](https://github.com/microsoft/azure-devops-mcp) for the organization
argument, the `--domains` toolsets and the authentication modes.

## Releasing

**The npm pin in `azure-devops-mcp.dockerfile` is the release.** The workflow reads the version back
out of that file and tags the image with it, so the two can never disagree — bump the pin, push, and
the image appears as `:2.9.0`, `:latest` and `:<sha>`, with a matching `v2.9.0` GitHub release.

The version is upstream's, not this repository's, so it is not derived from commit history. A
rebuild at an unchanged pin finds its release already present and skips it.

## `ENTRYPOINT`, not `CMD`

The image declares an `ENTRYPOINT` so that a runner supplying arguments **appends** to it. Against a
`CMD`-only image those arguments replace the command instead, and the container dies with
`exec: … not found`. The workflow smoke-tests `--help` against the built image for exactly this
reason: a broken entrypoint otherwise surfaces as a container that exits immediately with an empty
log.

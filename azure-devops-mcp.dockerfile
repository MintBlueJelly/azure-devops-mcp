# ghcr.io/mintbluejelly/azure-devops-mcp
#
# Microsoft's Azure DevOps MCP server, built from source at a pinned upstream release with the
# patches in patches/ applied. Nothing else differs from upstream.
#
# These three ARGs are the release: the workflow reads the image tag back out of this file, as
# <UPSTREAM_TAG without the v>-<PATCH_REVISION>. UPSTREAM_COMMIT is what the tag pointed at when it
# was reviewed, because a tag can move. PATCH_REVISION goes back to 1 whenever UPSTREAM_TAG moves.
ARG UPSTREAM_TAG=v2.10.0
ARG UPSTREAM_COMMIT=43a2b179b02d912399be612e0f7b5121a55eb692
ARG PATCH_REVISION=1

FROM docker.io/node:24-alpine3.24 AS build
ARG UPSTREAM_TAG
ARG UPSTREAM_COMMIT
RUN apk add --no-cache git
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$UPSTREAM_TAG" \
        https://github.com/microsoft/azure-devops-mcp.git . \
 && actual="$(git rev-parse HEAD)" \
 && if [ "$actual" != "$UPSTREAM_COMMIT" ]; then \
        echo "$UPSTREAM_TAG now points at $actual, not the reviewed $UPSTREAM_COMMIT" >&2; exit 1; \
    fi
COPY patches/ /patches/
RUN git apply --verbose /patches/*.patch
# No dependency's install script runs: the HTTP entry point needs none of them.
RUN npm ci --ignore-scripts --no-audit --no-fund
RUN npm run build

# Upstream's own test suite against the patched source. The workflow builds this target before the
# image; a plain build skips it, so none of it reaches the image.
FROM build AS test
# Only upstream's stdio auth tests load keytar. Its install script fetches a prebuilt musl binary,
# which links against libsecret.
RUN apk add --no-cache libsecret && npm rebuild keytar
RUN npm test

FROM build AS prune
RUN npm prune --omit=dev --ignore-scripts --no-audit --no-fund

FROM docker.io/node:24-alpine3.24
ARG UPSTREAM_TAG
ARG UPSTREAM_COMMIT
ARG PATCH_REVISION
LABEL io.github.mintbluejelly.upstream.tag="$UPSTREAM_TAG" \
      io.github.mintbluejelly.upstream.commit="$UPSTREAM_COMMIT" \
      io.github.mintbluejelly.patch-revision="$PATCH_REVISION"
WORKDIR /app
COPY --from=prune /src/package.json ./
COPY --from=prune /src/node_modules ./node_modules/
COPY --from=prune /src/dist ./dist/
USER 1000:1000
EXPOSE 8080
# ENTRYPOINT, not CMD: a runner supplying arguments appends to an entrypoint. Against a CMD-only
# image those arguments replace the command, and the container dies with "exec: ... not found".
# `--host` is here because the server's own default, loopback, is unreachable from outside a container.
ENTRYPOINT ["node", "/app/dist/http.js", "--host", "0.0.0.0"]

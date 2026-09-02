# ghcr.io/mintbluejelly/azure-devops-mcp
#
# Microsoft ships @azure-devops/mcp as an npm package only — no image and no Dockerfile upstream.
# This wrapper exists solely so that a container runtime has something to run.
#
# The npm pin below is the single source of the image tag: the workflow reads it back out of this
# file, so bumping it here is the whole release.
FROM docker.io/node:24-alpine3.24

RUN npm install -g @azure-devops/mcp@2.9.0

# ENTRYPOINT, not CMD: a runner supplying arguments appends to an entrypoint. Against a CMD-only
# image those arguments replace the command, and the container dies with "exec: ... not found".
USER 1000:1000
ENTRYPOINT ["mcp-server-azuredevops"]

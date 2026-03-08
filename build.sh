#!/bin/bash

HASH="${1}"
if [ -z "${HASH}" ]; then
    HASH="$(git ls-remote https://github.com/project-chip/connectedhomeip.git refs/heads/master | awk 'NR==1 {print $1}')"
    if [ -z "${HASH}" ]; then
        echo "Failed to resolve master commit hash from project-chip/connectedhomeip." >&2
        exit 1
    fi
fi
DOCKERFILE_DOWNLOADED=0
if [ ! -f Dockerfile ]; then
    wget "https://raw.githubusercontent.com/project-chip/connectedhomeip/${HASH}/integrations/docker/images/chip-cert-bins/Dockerfile"
    DOCKERFILE_DOWNLOADED=1
fi
docker system prune --all --volumes --force
docker buildx build --load --build-arg COMMITHASH=${HASH} --tag connectedhomeip/chip-cert-bins:${HASH} .
if [ $DOCKERFILE_DOWNLOADED -eq 1 ]; then
    rm Dockerfile
fi
docker save --output chip-cert-bins_${HASH}.tar connectedhomeip/chip-cert-bins:${HASH}

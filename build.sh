#!/bin/bash

PRUNE=0
SAVE=0
GITHUB_USER="project-chip"
POSITIONAL=()
for arg in "$@"; do
    case "$arg" in
        --prune) PRUNE=1 ;;
        --save) SAVE=1 ;;
        --github-user=*) GITHUB_USER="${arg#--github-user=}" ;;
        *) POSITIONAL+=("$arg") ;;
    esac
done
set -- "${POSITIONAL[@]}"

BRANCH_OR_HASH="${1}"
if [ -z "${BRANCH_OR_HASH}" ]; then
    BRANCH_OR_HASH="master"
fi

if echo "${BRANCH_OR_HASH}" | grep -qE '^[0-9a-f]{40}$'; then
    HASH="${BRANCH_OR_HASH}"
else
    HASH="$(git ls-remote https://github.com/${GITHUB_USER}/connectedhomeip.git "refs/heads/${BRANCH_OR_HASH}" | awk 'NR==1 {print $1}')"
    if [ -z "${HASH}" ]; then
        echo "Failed to resolve commit hash for branch '${BRANCH_OR_HASH}' from ${GITHUB_USER}/connectedhomeip." >&2
        exit 1
    fi
fi
DOCKERFILE_DOWNLOADED=0
if [ ! -f Dockerfile ]; then
    wget "https://raw.githubusercontent.com/${GITHUB_USER}/connectedhomeip/${HASH}/integrations/docker/images/chip-cert-bins/Dockerfile"
    DOCKERFILE_DOWNLOADED=1
fi
sed -i '' "s/project-chip/${GITHUB_USER}/g" Dockerfile
if [ $PRUNE -eq 1 ]; then
    docker system prune --all --volumes --force
fi
echo "Building commit ${HASH}"
docker buildx build --load --build-arg COMMITHASH=${HASH} --tag connectedhomeip/chip-cert-bins:${HASH} .
if [ $DOCKERFILE_DOWNLOADED -eq 1 ]; then
    rm Dockerfile
fi
if [ $SAVE -eq 1 ]; then
    docker save --output chip-cert-bins_${HASH}.tar connectedhomeip/chip-cert-bins:${HASH}
fi

#!/bin/bash
# Script to automate building the Matter SDK on Google Cloud Platform
# Based on the instructions in gcp.md

# Exit immediately if a command exits with a non-zero status
set -o pipefail

# Configuration
VM_NAME="matter-vm"
ZONE="us-central1-c"
MACHINE_TYPE="c4a-standard-16"
IMAGE_FAMILY="ubuntu-2204-lts-arm64"
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="200GB"
DISK_TYPE="hyperdisk-balanced"

# Logging
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="build_${TIMESTAMP}.log"

# Usage check
BRANCH_OR_HASH="${1}"
if [ -z "${BRANCH_OR_HASH}" ]; then
    echo "Usage: $0 <COMMIT_HASH_OR_BRANCH>"
    echo "Example: $0 master"
    exit 1
fi

# Resolve commit hash if a branch name is provided
echo "Resolving commit hash for '${BRANCH_OR_HASH}'..."
if echo "${BRANCH_OR_HASH}" | grep -qE '^[0-9a-f]{40}$'; then
    HASH="${BRANCH_OR_HASH}"
else
    # Use git ls-remote to resolve branch to commit hash
    HASH="$(git ls-remote https://github.com/project-chip/connectedhomeip.git "refs/heads/${BRANCH_OR_HASH}" | awk 'NR==1 {print $1}')"
    if [ -z "${HASH}" ]; then
        echo "Error: Failed to resolve commit hash for branch '${BRANCH_OR_HASH}'." >&2
        exit 1
    fi
fi
echo "Resolved to commit: ${HASH}"

# Check if instance already exists
if gcloud compute instances describe "${VM_NAME}" --zone="${ZONE}" >/dev/null 2>&1; then
    echo "Instance '${VM_NAME}' already exists. Reusing it..."
else
    echo "Creating GCP Compute Instance '${VM_NAME}'..."
    gcloud compute instances create "${VM_NAME}" \
        --zone="${ZONE}" \
        --machine-type="${MACHINE_TYPE}" \
        --provisioning-model=SPOT \
        --image-family="${IMAGE_FAMILY}" \
        --image-project="${IMAGE_PROJECT}" \
        --boot-disk-size="${DISK_SIZE}" \
        --boot-disk-type="${DISK_TYPE}"
fi

# Wait for SSH to be ready
echo "Waiting for SSH to become available on '${VM_NAME}'..."
SSH_READY=0
for i in {1..30}; do
    if gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="echo SSH is ready" --quiet >/dev/null 2>&1; then
        echo "SSH is ready!"
        SSH_READY=1
        break
    fi
    echo "Retrying SSH connection in 5 seconds... ($i/30)"
    sleep 5
done

if [ $SSH_READY -ne 1 ]; then
    echo "Error: Timed out waiting for SSH on '${VM_NAME}'." >&2
    exit 1
fi

# Run setup on VM
echo "Starting remote installation and setup..."
gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="
  echo '=== Installing Docker ===' &&
  curl -fsSL https://get.docker.com -o get-docker.sh &&
  sudo sh get-docker.sh &&
  sudo usermod -aG docker \$USER &&
  
  echo '=== Cloning build_matter_sdk_image repo ===' &&
  if [ -d build_matter_sdk_image ]; then
    rm -rf build_matter_sdk_image
  fi &&
  git clone https://github.com/oxesoft/build_matter_sdk_image.git
" 2>&1 | tee "${LOG_FILE}"
SETUP_STATUS=$?

if [ $SETUP_STATUS -eq 0 ]; then
    # Upload Dockerfile if it exists locally
    if [ -f Dockerfile ]; then
        echo "Local Dockerfile found. Uploading to VM..." | tee -a "${LOG_FILE}"
        gcloud compute scp Dockerfile "${VM_NAME}:~/build_matter_sdk_image/" --zone="${ZONE}" 2>&1 | tee -a "${LOG_FILE}"
    fi

    # Start build on VM
    echo "Starting Matter SDK Build..." | tee -a "${LOG_FILE}"
    gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="
      echo '=== Starting Matter SDK Build ===' &&
      cd build_matter_sdk_image && ./build.sh ${HASH} --save
    " 2>&1 | tee -a "${LOG_FILE}"
    BUILD_STATUS=$?
else
    echo "Error: Remote setup failed." >&2 | tee -a "${LOG_FILE}"
    BUILD_STATUS=1
fi

# Download the files back to local machine
echo "Downloading build artifacts..."
gcloud compute scp "${VM_NAME}:~/build_matter_sdk_image/chip-cert-bins_${HASH}.tar" . --zone="${ZONE}" || echo "Warning: Could not download tar file (it may not have been created)."

# Power off VM (clean shutdown)
echo "Shutting down the VM..."
gcloud compute instances stop "${VM_NAME}" --zone="${ZONE}" --quiet

# Delete VM instance
echo "Deleting GCP Compute Instance '${VM_NAME}'..."
gcloud compute instances delete "${VM_NAME}" --zone="${ZONE}" --delete-disks=all --quiet

if [ $BUILD_STATUS -eq 0 ]; then
    echo "Workflow completed successfully!"
else
    echo "Workflow finished, but build failed. Check ${LOG_FILE} for details." >&2
    exit $BUILD_STATUS
fi

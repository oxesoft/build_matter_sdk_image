# Create the instance
gcloud compute instances create matter-vm \
    --zone=us-central1-a \
    --machine-type=c4a-standard-16 \
    --provisioning-model=SPOT \
    --image-family=ubuntu-2204-lts-arm64 \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=200GB \
    --boot-disk-type=hyperdisk-balanced

# Connect via ssh
gcloud compute ssh matter-vm --zone=us-central1-a

# Install basic dependencies and Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Allow your user to run docker without sudo (requires logging out and back in to take effect)
sudo usermod -aG docker $USER

# Download the support scripts
git clone https://github.com/oxesoft/build_matter_sdk_image.git

# Start a tmux session
tmux new -s matter-build

# Send the desired Dockerfile to the instance
gcloud compute scp Dockerfile matter-vm:~/build_matter_sdk_image/ --zone=us-central1-a

# Start the build
./build.sh fb77c3876a0c783db0f975ffb100fb9b119347f5 --save

# Detach from the session without interrupting the build:
# Press Ctrl + B and then the D key (for Detach).

# To come back and check progress later:
tmux attach -t matter-build

# Download the resulting image to the local machine
gcloud compute scp matter-vm:~/chip-cert-bins_fb77c3876a0c783db0f975ffb100fb9b119347f5.tar . --zone=us-central1-a

# To shut down the machine
sudo poweroff

# Delete the instance
gcloud compute instances delete matter-vm --zone=us-central1-a --delete-disks=all

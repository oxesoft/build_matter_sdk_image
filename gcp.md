# Build Matter SDK on Google Cloud Plataform Compute Instance

## Create the instance
### https://cloud.google.com/spot-vms/pricing
```
gcloud compute instances create matter-vm \
    --zone=us-central1-c \
    --machine-type=c4a-standard-16 \
    --provisioning-model=SPOT \
    --image-family=ubuntu-2204-lts-arm64 \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=200GB \
    --boot-disk-type=hyperdisk-balanced
```

## [Optional] Add your public key to the instance to avoid creating a new one every time
```
gcloud compute ssh matter-vm --zone=us-central1-c --ssh-key-file=~/.ssh/id_rsa
```

## Connect via ssh
```
gcloud compute ssh matter-vm --zone=us-central1-c
```

## Install Docker
```
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

## Allow your user to run docker without sudo (requires logging out and back in to take effect)
```
sudo usermod -aG docker $USER
```

## Download the support scripts
```
git clone https://github.com/oxesoft/build_matter_sdk_image.git
```

## [Optional] Send the desired Dockerfile to the instance
```
gcloud compute scp Dockerfile matter-vm:~/build_matter_sdk_image/ --zone=us-central1-c
```

## [Optional] Start a tmux session
```
tmux new -s matter-build
```

# Start the build
```
cd build_matter_sdk_image
./build.sh COMMIT_HASH --save 2>&1 | tee build.log
```

## [Optional] Detach from the session without interrupting the build
### Press Ctrl + B and then the D key (for Detach)

## [Optional] To come back and check progress later
```
tmux attach -t matter-build
```

## Download the resulting files to the local machine
```
gcloud compute scp matter-vm:~/build_matter_sdk_image/chip-cert-bins_COMMIT_HASH.tar . --zone=us-central1-c
gcloud compute scp matter-vm:~/build_matter_sdk_image/build.log . --zone=us-central1-c
```

## Shut down the machine
```
gcloud compute instances stop matter-vm --zone=us-central1-c --quiet
```

## Delete the instance
```
gcloud compute instances delete matter-vm --zone=us-central1-c --delete-disks=all
```

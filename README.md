# Build Matter SDK Image

Simple scripts for building a Matter SDK image.

The build flow resolves the target `connectedhomeip` commit hash (or uses the hash argument), downloads the matching `chip-cert-bins` Dockerfile when needed, builds the Docker image, and exports it as `chip-cert-bins_<hash>.tar`.

There are two scripts that perform this same workflow on different platforms:

- `build.sh` for POSIX shells.
- `build.ps1` for Windows PowerShell.

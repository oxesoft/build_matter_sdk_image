param(
    [Parameter(Position = 0)]
    [string]$Hash
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Hash)) {
    $remoteLine = git ls-remote https://github.com/project-chip/connectedhomeip.git refs/heads/master
    if ([string]::IsNullOrWhiteSpace($remoteLine)) {
        Write-Error "Failed to resolve master commit hash from project-chip/connectedhomeip."
        exit 1
    }

    $Hash = ($remoteLine -split "\s+")[0]
    if ([string]::IsNullOrWhiteSpace($Hash)) {
        Write-Error "Failed to parse master commit hash from git ls-remote output."
        exit 1
    }
}

$dockerfileDownloaded = $false
if (-not (Test-Path -Path "Dockerfile" -PathType Leaf)) {
    $dockerfileUrl = "https://raw.githubusercontent.com/project-chip/connectedhomeip/$Hash/integrations/docker/images/chip-cert-bins/Dockerfile"
    Invoke-WebRequest -Uri $dockerfileUrl -OutFile "Dockerfile"
    $dockerfileDownloaded = $true
}

docker system prune --all --volumes --force
docker buildx build --load --build-arg "COMMITHASH=$Hash" --tag "connectedhomeip/chip-cert-bins:$Hash" .

if ($dockerfileDownloaded) {
    Remove-Item -Path "Dockerfile" -Force
}

docker save --output "chip-cert-bins_${Hash}.tar" "connectedhomeip/chip-cert-bins:$Hash"

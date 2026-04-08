param(
    [Parameter(Position = 0)]
    [string]$BranchOrHash,
    [switch]$Prune,
    [switch]$Save
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BranchOrHash)) {
    $BranchOrHash = "master"
}

if ($BranchOrHash -match '^[0-9a-f]{40}$') {
    $Hash = $BranchOrHash
} else {
    $remoteLine = git ls-remote https://github.com/project-chip/connectedhomeip.git "refs/heads/$BranchOrHash"
    if ([string]::IsNullOrWhiteSpace($remoteLine)) {
        Write-Error "Failed to resolve commit hash for branch '$BranchOrHash' from project-chip/connectedhomeip."
        exit 1
    }

    $Hash = ($remoteLine -split "\s+")[0]
    if ([string]::IsNullOrWhiteSpace($Hash)) {
        Write-Error "Failed to parse commit hash from git ls-remote output."
        exit 1
    }
}

$dockerfileDownloaded = $false
if (-not (Test-Path -Path "Dockerfile" -PathType Leaf)) {
    $dockerfileUrl = "https://raw.githubusercontent.com/project-chip/connectedhomeip/$Hash/integrations/docker/images/chip-cert-bins/Dockerfile"
    Invoke-WebRequest -Uri $dockerfileUrl -OutFile "Dockerfile"
    $dockerfileDownloaded = $true
}

if ($Prune) {
    docker system prune --all --volumes --force
}
Write-Host "Building commit $Hash"
docker buildx build --load --build-arg "COMMITHASH=$Hash" --tag "connectedhomeip/chip-cert-bins:$Hash" .

if ($dockerfileDownloaded) {
    Remove-Item -Path "Dockerfile" -Force
}

if ($Save) {
    docker save --output "chip-cert-bins_${Hash}.tar" "connectedhomeip/chip-cert-bins:$Hash"
}

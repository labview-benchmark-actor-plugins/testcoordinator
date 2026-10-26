<#
.SYNOPSIS
    Uploads a CycloneDX SBOM to Dependency-Track v4.14.2 using native curl, automatically seeding/creating the project if it doesn't exist.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SbomPath,

    [Parameter(Mandatory = $true)]
    [string]$DependencyTrackUrl,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$ProjectVersion,

    [bool]$AutoCreate =$true
)

if (-not (Test-Path -Path $SbomPath -PathType Leaf)) {
    throw "SBOM file not found at '$SbomPath'. Please generate it first using Generate-SBOM.ps1."
}

$resolvedSbomPath = [System.IO.Path]::GetFullPath($SbomPath)
$DependencyTrackUrl =$DependencyTrackUrl.TrimEnd('/')
$uri = "$DependencyTrackUrl/api/v1/bom"

Write-Host "Preparing to upload SBOM to Dependency-Track at $DependencyTrackUrl..." -ForegroundColor Cyan
Write-Host "Target Project: $ProjectName (Version:$ProjectVersion)" -ForegroundColor Cyan

$autoCreateStr =$AutoCreate.ToString().ToLower()

curl.exe -X POST "$uri" `
    -H "X-Api-Key: $ApiKey" `
    -F "autoCreate=$autoCreateStr" `
    -F "projectName=$ProjectName" `
    -F "projectVersion=$ProjectVersion" `
    -F "bom=@$resolvedSbomPath"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload SBOM to Dependency-Track (curl exit code $LASTEXITCODE)."
}

Write-Host "SBOM successfully uploaded and queued in Dependency-Track!" -ForegroundColor Green

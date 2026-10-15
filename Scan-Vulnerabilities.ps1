<#
.SYNOPSIS
    Scans a pre-generated Software Bill of Materials (SBOM) for vulnerabilities using Grype.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SbomPath,

    [string]$OutputJsonPath
)

# 1. Verify SBOM file exists
if (-not (Test-Path -Path $SbomPath -PathType Leaf)) {
    throw "SBOM file not found at '$SbomPath'. Please generate it first using Generate-SBOM.ps1."
}

$resolvedSbomPath = [System.IO.Path]::GetFullPath($SbomPath)
$sbomDir = [System.IO.Path]::GetDirectoryName($resolvedSbomPath)

if (-not $OutputJsonPath) {
    $OutputJsonPath = Join-Path$sbomDir "vulnerabilities.json"
}
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputJsonPath)

# 2. Verify Grype CLI is available locally
if (-not (Get-Command "grype" -ErrorAction SilentlyContinue)) {
    throw "Grype CLI ('grype') is not found in the system PATH. Please install it via: winget install Anchore.Grype"
}

Write-Host "Running Grype vulnerability scan against SBOM: $resolvedSbomPath" -ForegroundColor Cyan

# 3. Execute Grype scan (display human-readable output to console)
grype sbom:$resolvedSbomPath

if ($LASTEXITCODE -ne 0) {
    throw "Grype vulnerability scan failed with exit code $LASTEXITCODE"
}

# 4. Export structured JSON vulnerability report
grype sbom:$resolvedSbomPath -o json >$resolvedOutputPath

Write-Host "Vulnerability JSON report successfully saved to: $resolvedOutputPath" -ForegroundColor Green
<#
.SYNOPSIS
    Master pipeline script to generate an SBOM using VIPM, scan for vulnerabilities using Grype, 
    and upload/seed the results to Dependency-Track v4.14.2.
#>

param(
    # VIPM Generation Parameters
    [Parameter(Mandatory = $true)]
    [string]$LvprojPath,

    [string]$LabViewVersion = '2026q3',

    [Parameter(Mandatory = $true)]
    [string]$LabViewBitness,

    [Parameter(Mandatory = $true)]
    [string]$BuildSpecName,

    [string]$TargetName = 'My Computer',

    [Parameter(Mandatory = $true)]
    [string]$ProductName,

    [Parameter(Mandatory = $true)]
    [string]$ProductVersion,

    [string]$OutputPath = "output/sbom.json",

    [string]$Format = 'cyclonedx',

    [string]$SchemaVersion = '1.5',

    # Vulnerability Scan Parameters
    [switch]$EnableVulnerabilityScan = $true,
    [string]$VulnerabilityOutputPath = "output/vulnerabilities.json",

    # Dependency-Track Parameters
    [switch]$EnableUpload = $true,
    [string]$DependencyTrackUrl = "https://track.vi-tech.nl",
    [string]$ApiKey,
    [string]$ProjectName,
    [string]$ProjectVersion,
    [bool]$AutoCreate = $true
)

# Stop execution immediately if any command fails
$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Starting Complete Local SBOM Pipeline" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# ==========================================
# STEP 1: Generate SBOM via VIPM CLI
# ==========================================
Write-Host "`n[Step 1/3] Validating and Generating SBOM..." -ForegroundColor Yellow

if ($LabViewVersion -match '^(\d{4})q([13])$') {
    $year = [int]$Matches[1]
    $quarter = [int]$Matches[2]
} else {
    throw "Invalid LabVIEW version format: $LabViewVersion. Expected YYYYq1 or YYYYq3 (for example, 2026q3)."
}

$isValid = ($year -gt 2025) -or (($year -eq 2025) -and ($quarter -ge 3))
if (-not $isValid) {
    throw "LabVIEW version $LabViewVersion is below the minimum supported version (2025q3)."
}

Write-Host "Validated LabVIEW Version: Year $year, Version$LabViewVersion" -ForegroundColor Green

if (-not (Get-Command "vipm" -ErrorAction SilentlyContinue)) {
    throw "VIPM CLI ('vipm') is not found in the system PATH. Please ensure VIPM Desktop is installed and the CLI is available."
}

if (-not (Test-Path -Path $LvprojPath -PathType Leaf)) {
    throw "LabVIEW project file not found at '$LvprojPath'."
}

$resolvedLvprojPath = [System.IO.Path]::GetFullPath($LvprojPath)
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)

if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

Write-Host "Generating SBOM using local VIPM CLI..." -ForegroundColor Cyan

vipm sbom $resolvedLvprojPath `
    --format $Format `
    --schema-version $SchemaVersion `
    --labview-version $year `
    --labview-bitness $LabViewBitness `
    --lvproj-build-spec $BuildSpecName `
    --lvproj-target $TargetName `
    --product-name $ProductName `
    --product-version $ProductVersion `
    --output $resolvedOutputPath `
    --allow-missing-files

if ($LASTEXITCODE -ne 0) {
    throw "Local SBOM generation failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -Path $resolvedOutputPath -PathType Leaf)) {
    throw "No SBOM file found at '$resolvedOutputPath'."
}

Write-Host "SBOM generated and verified successfully: $resolvedOutputPath" -ForegroundColor Green


# ==========================================
# STEP 2: Scan for Vulnerabilities via Grype
# ==========================================
if ($EnableVulnerabilityScan) {
    Write-Host "`n[Step 2/3] Scanning SBOM for vulnerabilities using Grype..." -ForegroundColor Yellow

    if (-not (Get-Command "grype" -ErrorAction SilentlyContinue)) {
        throw "Grype CLI ('grype') is not found in the system PATH. Please install it via: winget install Anchore.Grype"
    }

    $resolvedVulnPath = [System.IO.Path]::GetFullPath($VulnerabilityOutputPath)
    $vulnDir = [System.IO.Path]::GetDirectoryName($resolvedVulnPath)
    if (-not (Test-Path -Path $vulnDir)) {
        New-Item -ItemType Directory -Force -Path $vulnDir | Out-Null
    }

    Write-Host "Running Grype scan against SBOM..." -ForegroundColor Cyan
    grype sbom:$resolvedOutputPath

    if ($LASTEXITCODE -ne 0) {
        throw "Grype vulnerability scan failed with exit code $LASTEXITCODE"
    }

    grype sbom:$resolvedOutputPath -o json > $resolvedVulnPath
    Write-Host "Vulnerability JSON report saved to: $resolvedVulnPath" -ForegroundColor Green
} else {
    Write-Host "`n[Step 2/3] Skipping vulnerability scan (disabled by switch)." -ForegroundColor DarkGray
}


# ==========================================
# STEP 3: Upload to Dependency-Track
# ==========================================
if ($EnableUpload) {
    Write-Host "`n[Step 3/3] Uploading SBOM to Dependency-Track..." -ForegroundColor Yellow

    if (-not $ApiKey) {
        throw "ApiKey parameter is required when EnableUpload is true."
    }
    
    if (-not $ProjectName) { $ProjectName = $ProductName }
    if (-not $ProjectVersion) { $ProjectVersion = $ProductVersion }

    $DependencyTrackUrl = $DependencyTrackUrl.TrimEnd('/')
    $uri = "$DependencyTrackUrl/api/v1/bom"

    Write-Host "Target Dependency-Track URL: $DependencyTrackUrl" -ForegroundColor Cyan
    Write-Host "Target Project: $ProjectName (Version: $ProjectVersion)" -ForegroundColor Cyan

    $autoCreateStr = $AutoCreate.ToString().ToLower()

    curl.exe -X POST "$uri" `
        -H "X-Api-Key: $ApiKey" `
        -F "autoCreate=$autoCreateStr" `
        -F "projectName=$ProjectName" `
        -F "projectVersion=$ProjectVersion" `
        -F "bom=@$resolvedOutputPath"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload SBOM to Dependency-Track (curl exit code $LASTEXITCODE)."
    }

    Write-Host "SBOM successfully uploaded and queued in Dependency-Track!" -ForegroundColor Green
} else {
    Write-Host "`n[Step 3/3] Skipping Dependency-Track upload (disabled by switch)." -ForegroundColor DarkGray
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Pipeline Completed Successfully!" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

<#
.SYNOPSIS
    Master pipeline script to generate SBOMs using VIPM and Syft, scan for vulnerabilities using Grype, 
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

    # Syft Generation Parameters
    [switch]$EnableSyft = $true,
    [string]$SyftOutputPath = "output/syft-sbom.json",

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
Write-Host "Starting Complete Local SBOM Pipeline (VIPM + Syft)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# ==========================================
# STEP 1A: Generate LabVIEW SBOM via VIPM CLI
# ==========================================
Write-Host "`n[Step 1A/3] Validating and Generating LabVIEW SBOM via VIPM..." -ForegroundColor Yellow

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

Write-Host "Generating VIPM SBOM..." -ForegroundColor Cyan

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
    throw "Local VIPM SBOM generation failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -Path $resolvedOutputPath -PathType Leaf)) {
    throw "No SBOM file found at '$resolvedOutputPath'."
}

Write-Host "VIPM SBOM generated successfully: $resolvedOutputPath" -ForegroundColor Green


# ==========================================
# STEP 1B: Generate Workspace SBOM via Syft
# ==========================================
if ($EnableSyft) {
    Write-Host "`n[Step 1B/3] Generating Workspace SBOM via Syft..." -ForegroundColor Yellow

    if (-not (Get-Command "syft" -ErrorAction SilentlyContinue)) {
        throw "Syft CLI ('syft') is not found in the system PATH. Please install it via: winget install Anchore.Syft"
    }

    $resolvedSyftPath = [System.IO.Path]::GetFullPath($SyftOutputPath)
    $syftDir = [System.IO.Path]::GetDirectoryName($resolvedSyftPath)
    if (-not (Test-Path -Path $syftDir)) {
        New-Item -ItemType Directory -Force -Path $syftDir | Out-Null
    }

    Write-Host "Scanning local directory with Syft..." -ForegroundColor Cyan
    syft dir:. -o cyclonedx-json > $resolvedSyftPath

    if ($LASTEXITCODE -ne 0) {
        throw "Syft SBOM generation failed with exit code $LASTEXITCODE"
    }

    Write-Host "Syft Workspace SBOM generated successfully: $resolvedSyftPath" -ForegroundColor Green
} else {
    Write-Host "`n[Step 1B/3] Skipping Syft SBOM generation (disabled by switch)." -ForegroundColor DarkGray
}


# ==========================================
# STEP 2: Scan for Vulnerabilities via Grype
# ==========================================
if ($EnableVulnerabilityScan) {
    Write-Host "`n[Step 2/3] Scanning VIPM SBOM for vulnerabilities using Grype..." -ForegroundColor Yellow

    if (-not (Get-Command "grype" -ErrorAction SilentlyContinue)) {
        throw "Grype CLI ('grype') is not found in the system PATH. Please install it via: winget install Anchore.Grype"
    }

    $resolvedVulnPath = [System.IO.Path]::GetFullPath($VulnerabilityOutputPath)
    $vulnDir = [System.IO.Path]::GetDirectoryName($resolvedVulnPath)
    if (-not (Test-Path -Path $vulnDir)) {
        New-Item -ItemType Directory -Force -Path $vulnDir | Out-Null
    }

    Write-Host "Running Grype scan against VIPM SBOM..." -ForegroundColor Cyan
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
    Write-Host "`n[Step 3/3] Uploading VIPM SBOM to Dependency-Track..." -ForegroundColor Yellow

    # Fallback to environment variable if -ApiKey parameter wasn't supplied
    if (-not $ApiKey) {
        $ApiKey = $env:DEPENDENCY_TRACK_API_KEY
    }

    if (-not $ApiKey) {
        throw "Dependency-Track API Key is missing. Provide it via the -ApiKey parameter or set the DEPENDENCY_TRACK_API_KEY environment variable."
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

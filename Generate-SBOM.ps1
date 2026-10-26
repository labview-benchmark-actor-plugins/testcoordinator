<#
.SYNOPSIS
    Generates a Software Bill of Materials (SBOM) locally on Windows using the native VIPM CLI.
#>

param(
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

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$Format = 'cyclonedx',

    [string]$SchemaVersion = '1.5'
)

# 1. Validate LabVIEW Version format and minimum supported version (2025q3+)
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

Write-Host "Validated LabVIEW Version: Year $year, Version $LabViewVersion" -ForegroundColor Green

# 2. Verify VIPM CLI is available locally
if (-not (Get-Command "vipm" -ErrorAction SilentlyContinue)) {
    throw "VIPM CLI ('vipm') is not found in the system PATH. Please ensure VIPM Desktop is installed and the CLI is available."
}

# Verify input project file exists
if (-not (Test-Path -Path $LvprojPath -PathType Leaf)) {
    throw "LabVIEW project file not found at '$LvprojPath'."
}

# Resolve absolute paths safely using .NET
$resolvedLvprojPath = [System.IO.Path]::GetFullPath($LvprojPath)
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)

if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

Write-Host "Generating SBOM using local VIPM CLI..." -ForegroundColor Cyan

# 3. Execute VIPM CLI sbom command natively
vipm sbom $resolvedLvprojPath `
    --format $Format `
    --schema-version $SchemaVersion `
    --labview-version $year `
    --labview-bitness $LabViewBitness `
    --lvproj-build-spec $BuildSpecName `
    --lvproj-target $TargetName `
    --product-name $ProductName `
    --product-version $ProductVersion `
    --output $resolvedOutputPath

if ($LASTEXITCODE -ne 0) {
    throw "Local SBOM generation failed with exit code $LASTEXITCODE"
}

# 4. Verify SBOM Exists
if (-not (Test-Path -Path $resolvedOutputPath -PathType Leaf)) {
    throw "No SBOM file found at '$resolvedOutputPath'."
}

Write-Host "SBOM verified successfully: $resolvedOutputPath" -ForegroundColor Green
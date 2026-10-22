<#
.SYNOPSIS
    Apply the patches of a build definition to the checked-out PHP source tree.
.PARAMETER Definition
    Path to the build definition directory (builds/<version>).
.PARAMETER SourceDirectory
    PHP source tree (defaults to the current directory).
#>
param(
    [Parameter(Mandatory = $true)] [string] $Definition,
    [string] $SourceDirectory = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'

$source = Get-Content (Join-Path $Definition 'source.json') -Raw | ConvertFrom-Json
Push-Location $SourceDirectory
try {
    $head = (git rev-parse HEAD).Trim()
    if ($head -ne $source.source.commit) {
        throw "Source checkout is at $head, build definition expects $($source.source.commit) ($($source.source.ref))"
    }
    Write-Host "Source: $($source.source.repository)@$head ($($source.source.ref))"

    $patchDir = Join-Path $Definition 'patches'
    $patches = @(Get-ChildItem -Path $patchDir -Filter '*.patch' -File | Sort-Object Name)
    if ($patches.Count -eq 0) {
        Write-Host 'No patches to apply.'
    }
    foreach ($patch in $patches) {
        $hash = (Get-FileHash -Algorithm SHA256 $patch.FullName).Hash.ToLower()
        Write-Host "Applying $($patch.Name) (sha256 $hash)"
        git apply --check --verbose --whitespace=nowarn $patch.FullName
        if ($LASTEXITCODE -ne 0) { throw "Patch $($patch.Name) does not apply" }
        git apply --verbose --whitespace=nowarn $patch.FullName
        if ($LASTEXITCODE -ne 0) { throw "Applying $($patch.Name) failed" }
    }

    $versionHeader = Get-Content -Path 'main/php_version.h' -Raw
    $version = [regex]::Match($versionHeader, 'PHP_VERSION\s+"([^"]+)"').Groups[1].Value
    if ($version -ne $source.php_version) {
        throw "Source reports PHP $version, build definition expects $($source.php_version)"
    }
    Write-Host "PHP version in source: $version"
    Write-Host '--- working tree changes ---'
    git --no-pager diff --stat
    if ($patches.Count -gt 0 -and -not (git status --porcelain)) {
        throw 'Patches were listed but the working tree is unchanged'
    }
} finally {
    Pop-Location
}

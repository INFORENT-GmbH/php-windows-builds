<#
.SYNOPSIS
    Assemble the release directory: original archives (with BUILD-INFO.txt added),
    product-specific bundles from bundles.json, and SHA256SUMS.txt.
#>
param(
    [Parameter(Mandatory = $true)] [string] $ArtifactsDirectory,
    [Parameter(Mandatory = $true)] [string] $Definition,
    [Parameter(Mandatory = $true)] [string] $OutputDirectory,
    [Parameter(Mandatory = $true)] [string] $BuildInfoFile
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$bundlesFile = Join-Path $Definition 'bundles.json'
$bundles = if (Test-Path $bundlesFile) { Get-Content $bundlesFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }

$allZips = @(Get-ChildItem -Path $ArtifactsDirectory -Filter '*.zip' -File)
if ($allZips.Count -eq 0) { throw "No archives in $ArtifactsDirectory" }

foreach ($zip in $allZips) {
    $target = Join-Path $OutputDirectory $zip.Name
    Copy-Item -Path $zip.FullName -Destination $target -Force
    if ($zip.Name -match '^php-[^-]+-(nts-)?Win32-v[cs]\d+-(x64|x86)\.zip$') {
        Compress-Archive -Path $BuildInfoFile -DestinationPath $target -Update
    }
    Write-Host "Added $($zip.Name)"
}

$binaryZips = @($allZips | Where-Object { $_.Name -match '^php-(?<ver>[^-]+)-(?<nts>nts-)?Win32-(?<vs>v[cs]\d+)-(?<arch>x64|x86)\.zip$' })
foreach ($zip in $binaryZips) {
    $null = $zip.Name -match '^php-(?<ver>[^-]+)-(?<nts>nts-)?Win32-(?<vs>v[cs]\d+)-(?<arch>x64|x86)\.zip$'
    $ver = $Matches.ver; $arch = $Matches.arch
    $ts = if ($Matches.nts) { 'nts' } else { 'ts' }
    foreach ($bundle in $bundles.PSObject.Properties) {
        $name = "php-$ver-$($bundle.Name)-$ts-$arch.zip"
        $work = Join-Path $tempRoot ("bundle-" + [System.IO.Path]::GetFileNameWithoutExtension($name))
        if (Test-Path $work) { Remove-Item -Recurse -Force $work }
        Expand-Archive -Path $zip.FullName -DestinationPath $work -Force

        # Two-phase rename so that swaps (php.exe -> php-cli.exe, php-cgi.exe -> php.exe) work.
        $renames = $bundle.Value.rename.PSObject.Properties
        foreach ($r in $renames) {
            $from = Join-Path $work $r.Name
            if (-not (Test-Path $from)) { throw "$($r.Name) not found in $($zip.Name) for bundle $($bundle.Name)" }
            Move-Item -Path $from -Destination "$from.__bundle" -Force
        }
        foreach ($r in $renames) {
            Move-Item -Path (Join-Path $work "$($r.Name).__bundle") -Destination (Join-Path $work $r.Value) -Force
        }

        Copy-Item -Path $BuildInfoFile -Destination (Join-Path $work 'BUILD-INFO.txt') -Force
        $mapping = ($renames | ForEach-Object { "  $($_.Name)  ->  $($_.Value)" }) -join "`r`n"
        Set-Content -Path (Join-Path $work 'BUNDLE.txt') -Value @"
Bundle:  $($bundle.Name)
Source:  $($zip.Name)
$($bundle.Value.description)

Files renamed relative to the standard PHP archive:
$mapping
"@ -Encoding utf8

        $out = Join-Path $OutputDirectory $name
        if (Test-Path $out) { Remove-Item -Force $out }
        Compress-Archive -Path (Join-Path $work '*') -DestinationPath $out
        Write-Host "Bundle $name created from $($zip.Name)"
    }
}

$sums = Get-ChildItem -Path $OutputDirectory -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' -and $_.Name -ne 'release-notes.md' } | Sort-Object Name | ForEach-Object {
    "$((Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower())  $($_.Name)"
}
Set-Content -Path (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value ($sums -join "`n") -Encoding ascii
Write-Host '--- release files ---'
Get-ChildItem -Path $OutputDirectory -File | ForEach-Object { '{0,12:n0}  {1}' -f $_.Length, $_.Name } | Write-Host

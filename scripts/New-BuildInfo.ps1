<#
.SYNOPSIS
    Write BUILD-INFO.txt (goes into every archive) and release-notes.md for a build definition.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Definition,
    [Parameter(Mandatory = $true)] [string] $OutputDirectory,
    [Parameter(Mandatory = $true)] [string] $Repository,
    [Parameter(Mandatory = $true)] [string] $RepositorySha,
    [Parameter(Mandatory = $true)] [string] $RunUrl,
    [string] $ReleaseTag = '',
    [string] $RunnerImage = ''
)
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $Definition 'source.json') -Raw | ConvertFrom-Json
$patches = @(Get-ChildItem -Path (Join-Path $Definition 'patches') -Filter '*.patch' -File | Sort-Object Name)
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$lines = @(
    "PHP $($source.php_version) for Windows - built by $Repository",
    "",
    "Built:            $now",
    "Build repository: https://github.com/$Repository @ $RepositorySha",
    "Build run:        $RunUrl",
    "Builder:          https://github.com/$($source.builder.repository) @ $($source.builder.commit) ($($source.builder.ref))",
    "Runner image:     $RunnerImage",
    "",
    "PHP source:       https://github.com/$($source.source.repository) @ $($source.source.commit) (tag $($source.source.ref))",
    "Patches applied (in order):"
)
foreach ($p in $patches) {
    $hash = (Get-FileHash -Algorithm SHA256 $p.FullName).Hash.ToLower()
    $lines += "  - $($p.Name)"
    $lines += "    sha256 $hash"
}
if ($patches.Count -eq 0) { $lines += '  (none)' }
$lines += ''
$lines += "Notes: $($source.notes)"
$lines += ''
$lines += 'PHP is licensed under the PHP License 3.01 (see license.txt in this archive).'
Set-Content -Path (Join-Path $OutputDirectory 'BUILD-INFO.txt') -Value ($lines -join "`r`n") -Encoding utf8

$patchTable = ($patches | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
    "| ``$($_.Name)`` | ``$hash`` |"
}) -join "`n"
if (-not $patchTable) { $patchTable = '| (none) | |' }
$notes = @"
PHP **$($source.php_version)** for Windows, built from [$($source.source.repository)@$($source.source.commit.Substring(0,9))](https://github.com/$($source.source.repository)/commit/$($source.source.commit)) (tag ``$($source.source.ref)``) with the patches below, using [$($source.builder.repository)@$($source.builder.commit.Substring(0,9))](https://github.com/$($source.builder.repository)/commit/$($source.builder.commit)) on GitHub-hosted ``$RunnerImage`` runners.

$($source.notes)

| Patch | SHA-256 |
|---|---|
$patchTable

**Archives**

- ``php-<version>-[nts-]Win32-<toolset>-<arch>.zip`` - standard PHP layout (``php.exe`` = CLI, ``php-cgi.exe`` = CGI/FastCGI).
- ``php-<version>-icewarp-<nts|ts>-<arch>.zip`` - IceWarp layout: ``php.exe`` = CGI/FastCGI binary, ``php-cli.exe`` = CLI binary.
- ``php-debug-pack-*`` / ``php-devel-pack-*`` - debug symbols and headers, ``php-test-pack-*`` - test suite.
- ``SHA256SUMS.txt`` - checksums of all files; ``BUILD-INFO.txt`` is also inside every archive.

Provenance: [build run]($RunUrl), repository ``$Repository`` @ ``$RepositorySha``. The patched source is reproducible from the tag and the patch files in ``builds/$($source.php_version)/``.
"@
Set-Content -Path (Join-Path $OutputDirectory 'release-notes.md') -Value $notes -Encoding utf8
Write-Host (Get-Content (Join-Path $OutputDirectory 'BUILD-INFO.txt') -Raw)

<#
.SYNOPSIS
    Verify that an installed PHP (e.g. in an IceWarp folder) carries the php2shell
    mitigations (CVE-2026-109618, CVE-2026-109619).

.DESCRIPTION
    This is a POSITIVE test: it does not attack anything. The fix makes PHP's memory
    manager terminate the process immediately (exit code 1) when an allocation fails,
    instead of unwinding through the old "bailout" path that was exploitable. An
    unpatched PHP ends the same out-of-memory condition with exit code 255.

    The engine code lives in php7ts.dll (TS) or php7.dll (NTS), NOT in php.exe. The
    probe runs the real binaries from the target folder, so it tests the DLL that is
    actually loaded, not the launcher .exe or its compiled-in banner.

.PARAMETER PhpDir
    Folder containing php.exe / php-cli.exe. Defaults to the current directory.

.PARAMETER ExpectBuildDate
    Expected engine "Build Date" (default 'Oct 22 2026'); only a warning if it differs.
.EXAMPLE
    .\Verify-Fix.ps1 -PhpDir 'C:\Program Files (x86)\IceWarp\php'
#>
[CmdletBinding()]
param(
    [string] $PhpDir = (Get-Location).Path,
    [string] $ExpectBuildDate = 'Oct 22 2026'
)
$ErrorActionPreference = 'Stop'

function Find-Cli([string] $dir) {
    foreach ($n in @('php-cli.exe', 'php.exe')) {
        $p = Join-Path $dir $n
        if (Test-Path $p) {
            $v = (& $p -n -v 2>&1 | Out-String)
            if ($v -match '\(cli\)') { return $p }
        }
    }
    return $null
}

function Invoke-OomProbe([string] $exe, [bool] $isCgi) {
    # Ask for 64 MB with a 2 MB limit: a guaranteed, harmless allocation failure.
    $script = Join-Path $env:TEMP ("php2shell-verify-" + [guid]::NewGuid().ToString('N') + '.php')
    Set-Content -Path $script -Value '<?php $a = str_repeat("x", 64 * 1024 * 1024); echo "NO";' -NoNewline
    try {
        if ($isCgi) {
            $out = (& $exe -n -d memory_limit=2M $script 2>&1 | Out-String)
        } else {
            $out = (& $exe -n -d memory_limit=2M $script 2>&1 | Out-String)
        }
        return @{ ExitCode = $LASTEXITCODE; Output = $out.Trim() }
    } finally {
        Remove-Item $script -ErrorAction SilentlyContinue
    }
}

Write-Host "php2shell fix verification (CVE-2026-109618, CVE-2026-109619)" -ForegroundColor Cyan
Write-Host "Folder: $PhpDir`n"

$results = @()

$cli = Find-Cli $PhpDir
if (-not $cli) { throw "No PHP CLI binary (php-cli.exe or php.exe reporting '(cli)') found in $PhpDir" }

# --- Identify the engine (these fields come from the DLL, not the launcher) ---
$info = (& $cli -n -i 2>&1 | Out-String)
$banner = (& $cli -n -v 2>&1 | Out-String).Trim()
$buildDate = ([regex]::Match($info, 'Build Date\s*=>\s*(.+)')).Groups[1].Value.Trim()
$extBuild  = ([regex]::Match($info, 'PHP Extension Build\s*=>\s*(.+)')).Groups[1].Value.Trim()
$version   = ([regex]::Match($banner, 'PHP (\S+)')).Groups[1].Value

Write-Host ($banner.Split("`n")[0])
Write-Host "Engine Build Date:   $buildDate"
Write-Host "Extension Build:     $extBuild`n"

if ($buildDate -ne $ExpectBuildDate) {
    Write-Host "WARNING: engine Build Date is '$buildDate', expected '$ExpectBuildDate'." -ForegroundColor Yellow
    Write-Host "         The loaded php7ts.dll/php7.dll may be the OLD one. If php.exe was replaced" -ForegroundColor Yellow
    Write-Host "         but the DLL was not, you are still unpatched.`n" -ForegroundColor Yellow
}

# --- Behavioral proof of the mitigation on every runnable binary ---
$targets = @([pscustomobject]@{ Path = $cli; Cgi = $false; Label = 'CLI (' + (Split-Path $cli -Leaf) + ')' })
foreach ($n in @('php.exe', 'php-cgi.exe')) {
    $p = Join-Path $PhpDir $n
    if ((Test-Path $p) -and $p -ne $cli) {
        $vb = (& $p -n -v 2>&1 | Out-String)
        if ($vb -match '\(cgi-fcgi\)') { $targets += [pscustomobject]@{ Path = $p; Cgi = $true; Label = 'CGI/FastCGI (' + $n + ')' } }
    }
}

foreach ($t in $targets) {
    $r = Invoke-OomProbe -exe $t.Path -isCgi $t.Cgi
    $hasFatal = $r.Output -match 'Allowed memory size'
    $patched  = ($r.ExitCode -eq 1) -and $hasFatal
    $unpatched = ($r.ExitCode -eq 255)
    $status = if ($patched) { 'PATCHED' } elseif ($unpatched) { 'NOT PATCHED' } else { 'UNEXPECTED' }
    $color = if ($patched) { 'Green' } else { 'Red' }
    Write-Host ("{0,-26} exit={1,-4} -> {2}" -f $t.Label, $r.ExitCode, $status) -ForegroundColor $color
    if (-not $patched -and -not $hasFatal) { Write-Host "    output: $($r.Output)" -ForegroundColor DarkGray }
    $results += $patched
}

Write-Host ''
if ($results -contains $false -or $results.Count -eq 0) {
    Write-Host "RESULT: NOT fixed. At least one binary uses an unpatched engine." -ForegroundColor Red
    Write-Host "Replace php7ts.dll (TS) or php7.dll (NTS) as well, then restart IceWarp services and re-run." -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: php2shell mitigation is ACTIVE on all PHP binaries in this folder." -ForegroundColor Green
    Write-Host "Reminder: restart IceWarp services so running php.exe instances reload the patched DLL." -ForegroundColor Green
    Write-Host "Note: this confirms CVE-2026-109618/-109619 only. PHP 7.3 is EOL; keep the admin/WebClient surface restricted." -ForegroundColor Green
    exit 0
}

<#
.SYNOPSIS
    Smoke-test the PHP binary archives produced by php-windows-builder.
.DESCRIPTION
    For every php-<version>-[nts-]Win32-<toolset>-<arch>.zip: extract, check the
    version banner, thread safety, loaded modules, the CGI binary, clean handling
    of an out-of-memory condition and a multipart/form-data request through php-cgi
    (the code paths touched by the php2shell mitigations).
#>
param(
    [Parameter(Mandatory = $true)] [string] $ArtifactsDirectory,
    [Parameter(Mandatory = $true)] [string] $ExpectedVersion
)
$ErrorActionPreference = 'Stop'

function Get-BinaryArchives([string] $Directory) {
    Get-ChildItem -Path $Directory -Filter 'php-*.zip' -File |
        Where-Object { $_.Name -match '^php-[^-]+-(nts-)?Win32-v[cs]\d+-(x64|x86)\.zip$' }
}

function Invoke-Cgi {
    param([string] $Exe, [string] $Script, [byte[]] $Body, [string] $ContentType)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = '-n'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['REDIRECT_STATUS'] = '200'
    $psi.Environment['REQUEST_METHOD'] = 'POST'
    $psi.Environment['SCRIPT_FILENAME'] = $Script
    $psi.Environment['CONTENT_TYPE'] = $ContentType
    $psi.Environment['CONTENT_LENGTH'] = "$($Body.Length)"
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.BaseStream.Write($Body, 0, $Body.Length)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; Output = $out }
}

$archives = @(Get-BinaryArchives $ArtifactsDirectory)
if ($archives.Count -eq 0) { throw "No PHP binary archives found in $ArtifactsDirectory" }

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$failures = @()

foreach ($zip in $archives) {
    Write-Host "::group::$($zip.Name)"
    try {
        $dir = Join-Path $tempRoot ('smoke-' + [System.IO.Path]::GetFileNameWithoutExtension($zip.Name))
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
        Expand-Archive -Path $zip.FullName -DestinationPath $dir -Force

        $php = Join-Path $dir 'php.exe'
        $cgi = Join-Path $dir 'php-cgi.exe'
        foreach ($exe in @($php, $cgi)) {
            if (-not (Test-Path $exe)) { throw "$([System.IO.Path]::GetFileName($exe)) missing" }
        }

        $banner = (& $php -n -v 2>&1 | Out-String)
        Write-Host $banner.Trim()
        if ($banner -notmatch ('PHP ' + [regex]::Escape($ExpectedVersion) + ' ')) { throw "Version banner does not report PHP $ExpectedVersion" }
        $expectNts = $zip.Name -match '-nts-'
        if ($expectNts -and $banner -notmatch '\(NTS') { throw 'Expected an NTS build' }
        if (-not $expectNts -and $banner -notmatch '\(ZTS') { throw 'Expected a TS (ZTS) build' }

        $cgiBanner = (& $cgi -n -v 2>&1 | Out-String)
        if ($cgiBanner -notmatch 'cgi-fcgi') { throw "php-cgi.exe banner unexpected: $cgiBanner" }

        $modules = (& $php -n -m 2>&1 | Out-String)
        foreach ($m in @('Core', 'date', 'json', 'pcre', 'standard', 'SPL')) {
            if ($modules -notmatch "(?m)^$m\s*$") { throw "Module $m not loaded" }
        }
        Write-Host ("Modules: " + (($modules -split "[\r\n]+" | Where-Object { $_ -and $_ -notmatch '^\[' }) -join ', '))

        $echo = (& $php -n -r "echo 'ok';" 2>&1 | Out-String).Trim()
        if ($echo -ne 'ok') { throw "php -r failed: $echo" }

        # Out-of-memory must end in a clean fatal error (exit 255), not a crash.
        $oom = (& $php -n -d memory_limit=2M -r '$a = str_repeat("x", 64 * 1024 * 1024);' 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 255 -or $oom -notmatch 'Allowed memory size') {
            throw "OOM handling unexpected (exit $LASTEXITCODE): $oom"
        }
        Write-Host 'OOM handling: clean fatal error'

        # multipart/form-data through php-cgi exercises main/rfc1867.c and main/php_variables.c.
        $script = Join-Path $dir 'smoke-multipart.php'
        Set-Content -Path $script -Value '<?php echo "field=", $_POST["f"], " files=", count($_FILES), " size=", $_FILES["u"]["size"], " err=", $_FILES["u"]["error"];' -NoNewline
        $boundary = 'smokeBoundary1234'
        $bodyText = "--$boundary`r`nContent-Disposition: form-data; name=`"f`"`r`n`r`nhello`r`n" +
                    "--$boundary`r`nContent-Disposition: form-data; name=`"u`"; filename=`"a.txt`"`r`nContent-Type: text/plain`r`n`r`n0123456789`r`n" +
                    "--$boundary--`r`n"
        $body = [System.Text.Encoding]::ASCII.GetBytes($bodyText)
        $res = Invoke-Cgi -Exe $cgi -Script $script -Body $body -ContentType "multipart/form-data; boundary=$boundary"
        if ($res.ExitCode -ne 0 -or $res.Output -notmatch 'field=hello files=1 size=10 err=0') {
            throw "multipart request unexpected (exit $($res.ExitCode)): $($res.Output)"
        }
        Write-Host 'multipart/form-data via php-cgi: ok'

        $info = (& $php -n -i 2>&1 | Select-String -Pattern '^(Architecture|Compiler|Thread Safety|Zend Memory Manager|Build Date)' | Out-String)
        Write-Host $info.Trim()
        Write-Host "PASS $($zip.Name)"
    } catch {
        Write-Host "::error::$($zip.Name): $($_.Exception.Message)"
        $failures += "$($zip.Name): $($_.Exception.Message)"
    } finally {
        Write-Host '::endgroup::'
    }
}

if ($failures.Count -gt 0) {
    throw ("Smoke tests failed:`n" + ($failures -join "`n"))
}
Write-Host "All $($archives.Count) archives passed."

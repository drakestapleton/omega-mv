# One command for the UXL checks. Thin Windows entry.
# If a WSL distro is installed, hand off to ./uxl-run.sh there (same script, same flags).
# Otherwise run the Python checks here. omc stages are NOT_RUN, with the WSL2 hint.
# If execution policy blocks this file:
#   powershell -ExecutionPolicy Bypass -File .\uxl-run.ps1
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Get-WslDistro {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return $null
    }
    $raw = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        return $null
    }
    foreach ($item in @($raw)) {
        $name = (($item -replace "`0", '')).Trim()
        if ($name) {
            return $name
        }
    }
    return $null
}

$distro = Get-WslDistro
if ($distro) {
    $dir = (Get-Location).Path.Replace("'", "''")
    $quoted = @()
    foreach ($arg in $args) {
        $quoted += "'" + ($arg -replace "'", "'\''") + "'"
    }
    $tail = $quoted -join ' '
    & wsl.exe -d $distro -- bash -lc "cd `$(wslpath -u '$dir') && ./uxl-run.sh $tail"
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$python = $null
foreach ($name in @('py', 'python', 'python3')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source; break }
}
if (-not $python) {
    Write-Error 'Python 3.8+ not found (tried py, python, python3). On Windows, install WSL2 Ubuntu or Python, then rerun .\uxl-run.ps1'
    exit 1
}
& $python 'tools/uxl/run_all.py' @args
exit $LASTEXITCODE

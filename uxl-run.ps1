# One command for the UXL checks. The work is in Python.
# If execution policy blocks this file:
#   powershell -ExecutionPolicy Bypass -File .\uxl-run.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ($env:OS -eq 'Windows_NT' -and -not $env:WSL_DISTRO_NAME -and -not $env:WSL_INTEROP) {
    $dir = (Get-Location).Path.Replace("'", "''")
    Write-Host "native Windows: seed/out/omc is an AArch64 Linux binary and cannot exec here. omc-dependent stages need WSL2 (Ubuntu + qemu-user-static). Rerun there: wsl -d Ubuntu -- bash -lc `"sudo apt-get install -y qemu-user-static binfmt-support && cd `$(wslpath -u '$dir') && ./uxl-run.sh`""
}
$python = $null
foreach ($name in @('py', 'python', 'python3')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source; break }
}
if (-not $python) {
    Write-Error 'Python 3.8+ not found (tried py, python, python3)'
    exit 1
}
& $python 'tools/uxl/run_all.py' @args
exit $LASTEXITCODE

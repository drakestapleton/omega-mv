# One command for the UXL checks. The work is in Python.
# If execution policy blocks this file:
#   powershell -ExecutionPolicy Bypass -File .\uxl-run.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
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

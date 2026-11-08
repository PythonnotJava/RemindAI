param(
    [string]$OutDir = "dist",
    [switch]$OneDir,
    [switch]$NoInstall,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$pyArgs = @("build.py", "--outdir", $OutDir)
if ($OneDir) { $pyArgs += "--onedir" }
if ($NoInstall) { $pyArgs += "--no-install" }
if ($SkipSmoke) { $pyArgs += "--skip-smoke" }

python @pyArgs

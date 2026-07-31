param(
    [string]$DelphiVersion = ''
)

$ErrorActionPreference = 'Stop'
$DextRoot = Split-Path -Parent $PSScriptRoot
$env:DEXT_PROJECT_TYPE = 'Tests'
. (Join-Path $PSScriptRoot 'set_env.ps1') `
    -Platform Win32 -Config Release -DelphiVersion $DelphiVersion

$ProjectDir = Join-Path $DextRoot 'Tests\Core\UnitTests'
$OutputDir = Join-Path $DextRoot 'Tests\Output'
$SearchRoots = @(
    $ProjectDir,
    (Join-Path $env:BDS 'lib\Win32\release'),
    (Join-Path $DextRoot 'Sources')
)
$SearchRoots += Get-ChildItem `
    (Join-Path $DextRoot 'Sources'), `
    (Join-Path $DextRoot 'External'), `
    (Join-Path $DextRoot 'Apps\CLI\Commands') `
    -Directory -Recurse | Select-Object -ExpandProperty FullName
$SearchPath = ($SearchRoots | Sort-Object -Unique) -join ';'

Push-Location $ProjectDir
try {
    $BuildExitCode = 1
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        & dcc32 -B -Q `
            "-E$OutputDir" `
            "-N0$env:OUTPUT_PATH" `
            "-U$SearchPath" `
            "-I$SearchPath" `
            '-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl' `
            'Dext.Core.UnitTests.dpr'
        $BuildExitCode = $LASTEXITCODE
        if ($BuildExitCode -eq 0) {
            break
        }
        if ($Attempt -lt 5) {
            Start-Sleep -Seconds (2 * $Attempt)
        }
    }
    if ($BuildExitCode -ne 0) {
        exit $BuildExitCode
    }
} finally {
    Pop-Location
}

& (Join-Path $OutputDir 'Dext.Core.UnitTests.exe') -no-wait
exit $LASTEXITCODE

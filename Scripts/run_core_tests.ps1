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
    & dcc32 -B -Q `
        "-E$OutputDir" `
        "-N0$env:OUTPUT_PATH" `
        "-U$SearchPath" `
        "-I$SearchPath" `
        '-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl' `
        'Dext.Core.UnitTests.dpr'
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}

& (Join-Path $OutputDir 'Dext.Core.UnitTests.exe') -no-wait
exit $LASTEXITCODE

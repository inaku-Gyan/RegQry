[CmdletBinding()]
param(
    [ValidateSet('all', 'format', 'lint', 'test', 'package')]
    [string]$Check = 'all',
    [string]$ExpectedHost,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$previousWarnings = $env:CARGO_BUILD_WARNINGS
Push-Location -LiteralPath $projectRoot
try {
    $env:CARGO_BUILD_WARNINGS = 'deny'
    Write-Output ('PowerShell ' + $PSVersionTable.PSVersion.ToString())
    $compiler = & rustc -Vv
    if ($LASTEXITCODE -ne 0) { throw 'rustc version check failed' }
    if ($compiler -notcontains 'release: 1.100.0') { throw 'Rust 1.100.0 is required' }
    if ($ExpectedHost -and $compiler -notcontains ('host: ' + $ExpectedHost)) {
        throw ('Expected a native ' + $ExpectedHost + ' compiler')
    }
    $compiler | Write-Output
    if ($Check -in @('all', 'format')) {
        & cargo fmt --all -- --check
        if ($LASTEXITCODE -ne 0) { throw 'Formatting check failed' }
    }
    if ($Check -in @('all', 'lint')) {
        & cargo clippy --locked --all-targets
        if ($LASTEXITCODE -ne 0) { throw 'Clippy failed' }
    }
    if ($Check -in @('all', 'test')) {
        & cargo test --locked
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
    }
    if ($Check -in @('all', 'package')) {
        & (Join-Path $PSScriptRoot 'check-package.ps1') -AllowDirty:$AllowDirty
    }
}
finally {
    $env:CARGO_BUILD_WARNINGS = $previousWarnings
    Pop-Location
}

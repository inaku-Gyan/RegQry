[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Executable,
    [Parameter(Mandatory)][ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')][string]$Target,
    [Parameter(Mandatory)][string]$ReportDirectory,
    [string]$Dumpbin
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bundle/support.ps1')
if (-not $Dumpbin) {
    $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($command) { $Dumpbin = $command.Source }
    else {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $hostFolder = if ((Get-BundleEnvironment).nativeTarget -eq 'aarch64-pc-windows-msvc') { 'Hostarm64\arm64' } else { 'Hostx64\x64' }
        $found = @(& $vswhere -latest -products '*' -find ('VC\Tools\MSVC\**\bin\' + $hostFolder + '\dumpbin.exe'))
        if ($LASTEXITCODE -ne 0) { throw 'Visual Studio discovery failed' }
        if ($found.Count -eq 0) { throw 'MSVC dumpbin is required; use a native Developer PowerShell or -Dumpbin' }
        $Dumpbin = $found[0]
    }
}
$Dumpbin = (Get-Item -LiteralPath $Dumpbin).FullName
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
if (Test-Path -LiteralPath $reportRoot) { throw 'PE ReportDirectory must not exist' }
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$expectedMachine = if ($Target -eq 'aarch64-pc-windows-msvc') { 'AA64' } else { '8664' }
# Reviewed Windows system imports. New names require review; being installed on
# the build machine is not evidence that a DLL is available on clean clients.
$systemDlls = @('kernel32.dll', 'advapi32.dll', 'ntdll.dll', 'bcrypt.dll', 'bcryptprimitives.dll', 'userenv.dll', 'ws2_32.dll', 'api-ms-win-core-synch-l1-2-0.dll')
$result = [ordered]@{
    schemaVersion = 1
    status = 'fail'
    target = $Target
    scope = 'direct and delay-load PE imports; actual execution environments are recorded separately'
    dumpbinVersion = (Get-Item -LiteralPath $Dumpbin).VersionInfo.FileVersion
    dumpbinSha256 = (Get-FileHash -LiteralPath $Dumpbin -Algorithm SHA256).Hash.ToLowerInvariant()
    executables = @()
    error = $null
}
$savedLanguage = $env:VSLANG
try {
    $env:VSLANG = '1033'
    $index = 0
    foreach ($path in $Executable) {
        $path = (Get-Item -LiteralPath $path).FullName
        $imports = @(& $Dumpbin /nologo /imports $path)
        if ($LASTEXITCODE -ne 0) { throw ('dumpbin imports failed: ' + $path) }
        $headers = @(& $Dumpbin /nologo /headers $path)
        if ($LASTEXITCODE -ne 0) { throw ('dumpbin headers failed: ' + $path) }
        $importsLog = ('{0:D2}-imports.txt' -f $index)
        $headersLog = ('{0:D2}-headers.txt' -f $index)
        [IO.File]::WriteAllLines((Join-Path $reportRoot $importsLog), [string[]]$imports, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllLines((Join-Path $reportRoot $headersLog), [string[]]$headers, [Text.UTF8Encoding]::new($false))
        $dlls = @($imports | ForEach-Object { if ($_ -match '^\s+([a-zA-Z0-9_.-]+\.dll)\s*$') { $Matches[1].ToLowerInvariant() } } | Sort-Object -Unique)
        $entry = [ordered]@{
            file = [IO.Path]::GetFileName($path)
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            imports = $dlls
            importsLog = 'pe/' + $importsLog
            headersLog = 'pe/' + $headersLog
        }
        $result.executables += $entry
        if (($headers -join "`n") -notmatch ('(?im)^\s+' + $expectedMachine + '\s+machine\s+\(')) { throw ('PE machine mismatch: ' + $path) }
        if ($dlls.Count -eq 0) { throw ('No DLL imports parsed: ' + $path) }
        foreach ($dll in $dlls) {
            if ($dll -notin $systemDlls) { throw ('Unapproved DLL or dynamic CRT import: ' + $dll + ' in ' + $entry.file) }
        }
        $index++
    }
    if ($index -eq 0) { throw 'No executables inspected' }
    $result.status = 'pass'
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    try { Write-BundleJson -Value $result -Path (Join-Path $reportRoot 'result.json') }
    finally { $env:VSLANG = $savedLanguage }
}

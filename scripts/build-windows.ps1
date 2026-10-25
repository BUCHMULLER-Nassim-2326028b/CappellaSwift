param(
    [ValidateSet('debug','release')][string]$Configuration = 'release',
    [switch]$SkipPrepare,
    [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
    [string]$Version
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot/lib/WindowsBuild.ps1"
$Version = Get-CappellaDistributionVersion -RepositoryRoot $repo -Version $Version
$triple = if ($Architecture -eq 'arm64') { 'aarch64-unknown-windows-msvc' } else { 'x86_64-unknown-windows-msvc' }
Push-Location $repo
try {
    # Resolve once in PowerShell. cmd can inherit a different PATH resolution
    # on GitHub runners; never ask it to locate the compiler by its bare name.
    $swiftExe = (Get-Command swift.exe -CommandType Application -ErrorAction Stop).Source
    # Skip preparation only when the generated bindings match the configuration.
    # An unstamped cache is regenerated once.
    $configurationHash = (Get-FileHash -LiteralPath "$repo/windows/projections.json" -Algorithm SHA256).Hash
    $projectionStamp = Join-Path $repo '.windows/projections.config.sha256'
    $bindingsCurrent = (Test-Path -LiteralPath '.windows/Projections/Package.swift') -and
        (Test-Path -LiteralPath $projectionStamp) -and
        ([IO.File]::ReadAllText($projectionStamp).Trim() -eq $configurationHash)
    if (!$SkipPrepare -or !$bindingsCurrent) { & "$PSScriptRoot/prepare-windows.ps1" }
    if (!(Test-Path '.windows/Projections/Package.swift')) { throw 'Exécuter scripts/prepare-windows.ps1 avant de compiler.' }
    # Refresh handwritten runtime support even when generated bindings are cached.
    Sync-WindowsRuntimeSupport -RepositoryRoot $repo -ProjectionRoot "$repo/.windows/Projections"
    # Windows PowerShell 5.1 turns redirected native stderr (including compiler
    # warnings) into error records. Judge the compiler by its exit code.
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.build') | Out-Null
    $buildLog = Join-Path $repo ".build/windows-build-$Architecture-$Configuration.log"
    $ErrorActionPreference = 'Continue'
    try {
        # Merge inside cmd so PowerShell 5 does not turn each Swift diagnostic
        # line into a RemoteException. Configuration is restricted by ValidateSet.
        # /s strips the outer quote pair, preserving the quoted executable path.
        $buildCommand = '""{0}" build -c {1} --triple {2} --product CappellaWindows -j 4 2>&1"' -f $swiftExe, $Configuration, $triple
        & $env:ComSpec /d /s /c $buildCommand | Tee-Object -FilePath $buildLog | ForEach-Object { Write-Host $_ }
        $compileExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    if ($compileExitCode -ne 0) {
        Select-String -LiteralPath $buildLog -Pattern "error:" | Select-Object -First 12 | ForEach-Object { Write-Host $_.Line }
        throw "Compilation Windows échouée ($compileExitCode). Journal : $buildLog"
    }
    $binOutput = & $swiftExe build -c $Configuration --triple $triple --show-bin-path
    if ($LASTEXITCODE -ne 0 -or !$binOutput) { throw 'Répertoire Swift introuvable.' }
    $bin = ($binOutput | Select-Object -Last 1).Trim()
    $app = Join-Path $repo "dist/Cappella-Windows-$Architecture"
    New-Item -ItemType Directory -Force -Path "$app/Resources", "$app/Licenses" | Out-Null
    Copy-Item -LiteralPath (Join-Path $bin 'CappellaWindows.exe') -Destination "$app/Cappella.exe"
    if ($Configuration -eq 'release') {
        Remove-WindowsDistributionDebugInfo -Executable "$app/Cappella.exe" -SwiftExecutable $swiftExe
    }
    Copy-Item -Path "$repo/packaging/Resources/*" -Destination "$app/Resources"
    [IO.File]::WriteAllText("$app/Resources/Version.txt", $Version, (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath "$repo/.windows/microsoft.windowsappsdk.1.7.250909003/runtimes/win-$Architecture/native/Microsoft.WindowsAppRuntime.Bootstrap.dll" -Destination $app
    # Swift DLLs must travel with the app; do not rely on the developer's PATH.
    $swiftRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path $swiftExe -Parent) '../../../..'))
    $runtime = Get-ChildItem -LiteralPath (Join-Path $swiftRoot 'Runtimes') -Recurse -Filter 'swiftCore.dll' |
        Where-Object { (Get-WindowsPEArchitecture -Path $_.FullName) -eq $Architecture } |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ((Get-WindowsPEArchitecture -Path "$app/Cappella.exe") -ne $Architecture) {
        throw "Le binaire compilé ne correspond pas à $Architecture."
    }
    if (!$runtime) { throw "Runtime Swift introuvable sous $swiftRoot/Runtimes." }
    if ($Configuration -eq 'release') {
        Copy-WindowsRuntimeDependencies -RuntimeDirectory $runtime.DirectoryName -ApplicationDirectory $app -SwiftExecutable $swiftExe
    } else {
        Copy-Item -Path (Join-Path $runtime.DirectoryName '*.dll') -Destination $app
    }
    Copy-Item -Path "$repo/windows/*LICENSE*", "$repo/windows/THIRD-PARTY-NOTICES.md" -Destination "$app/Licenses"
    foreach ($package in @('microsoft.windowsappsdk.1.7.250909003','microsoft.windows.sdk.contracts.10.0.22621.3233','microsoft.web.webview2.1.0.2903.40')) {
        Get-ChildItem -LiteralPath "$repo/.windows/$package" -File | Where-Object Name -Match 'license|notice' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$app/Licenses/$package-$($_.Name)" }
    }
    & "$PSScriptRoot/build-windows-icons.ps1" -OutputDirectory "$app/Resources"
    & "$PSScriptRoot/embed-windows-resources.ps1" -Executable "$app/Cappella.exe" -Icon "$app/Resources/AppIcon.ico" -Architecture $Architecture -Version $Version
    # Remove helpers left by earlier builds before creating the distribution archive.
    foreach ($helper in @('Installer-runtime.ps1', 'LIRE-MOI.md')) {
        $helperPath = Join-Path $app $helper
        if (Test-Path -LiteralPath $helperPath -PathType Leaf) {
            Remove-Item -LiteralPath $helperPath
        }
    }
    New-WindowsPortableArchive -ApplicationDirectory $app -Destination "$repo/dist/Cappella-$Version-Windows-$Architecture-Portable.zip"
    $distributionBytes = (Get-ChildItem -LiteralPath $app -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Host ('Distribution décompressée : {0:N1} Mio.' -f ($distributionBytes / 1MB))
    Write-Host "Application : $app/Cappella.exe"
    Write-Host "Archive : $repo/dist/Cappella-$Version-Windows-$Architecture-Portable.zip"
} finally { Pop-Location }

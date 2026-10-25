param(
    [string]$Version,
    [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
    [string]$Compiler
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot/lib/WindowsBuild.ps1"
$Version = Get-CappellaDistributionVersion -RepositoryRoot $repo -Version $Version
$app = Join-Path $repo "dist/Cappella-Windows-$Architecture"
if (!(Test-Path -LiteralPath "$app/Cappella.exe" -PathType Leaf)) {
    throw 'Compiler le programme avec scripts/build-windows.ps1 avant de créer le Setup.'
}
$stamp = Join-Path $app 'Resources/Version.txt'
if (!(Test-Path -LiteralPath $stamp) -or [IO.File]::ReadAllText($stamp).Trim() -ne $Version) {
    throw "La version du programme ne correspond pas au Setup $Version. Recompiler avec la même version."
}
if ((Get-WindowsPEArchitecture -Path "$app/Cappella.exe") -ne $Architecture) {
    throw "Le binaire à installer ne correspond pas à $Architecture."
}
if (!$Compiler) {
    $command = Get-Command ISCC.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { $Compiler = $command.Source }
    else {
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if ($base) {
                $candidate = Join-Path $base 'Inno Setup 6/ISCC.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $Compiler = $candidate; break }
            }
        }
    }
}
if (!$Compiler -or !(Test-Path -LiteralPath $Compiler -PathType Leaf)) {
    throw 'Installer Inno Setup 6 (https://jrsoftware.org/isinfo.php), ou préciser -Compiler avec le chemin de ISCC.exe.'
}
$cache = Join-Path $repo '.windows/installer'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$runtime = Join-Path $cache "WindowsAppRuntimeInstall-$Architecture.exe"
if (!(Test-Path -LiteralPath $runtime -PathType Leaf)) {
    $partial = $runtime + '.download.exe'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/windowsappsdk/1.7/1.7.250909003/windowsappruntimeinstall-$Architecture.exe" -OutFile $partial
        $signature = Get-AuthenticodeSignature -LiteralPath $partial
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw 'Signature Microsoft du runtime invalide.'
        }
        Move-Item -LiteralPath $partial -Destination $runtime
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial }
    }
}
$signature = Get-AuthenticodeSignature -LiteralPath $runtime
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw "Runtime en cache invalide : supprimer $runtime puis relancer."
}
$numericVersion = ($Version -split '[-+]')[0]
& $Compiler "/DAppVersion=$Version" "/DNumericVersion=$numericVersion" "/DRepositoryRoot=$repo" "/DAppArchitecture=$Architecture" (Join-Path $repo 'windows/Cappella.iss')
if ($LASTEXITCODE -ne 0) { throw "Création du Setup échouée ($LASTEXITCODE)." }
$setup = Join-Path $repo "dist/Cappella-$Version-Windows-$Architecture-Setup.exe"
if (!(Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Setup introuvable : $setup" }
Write-Host "Installateur : $setup"

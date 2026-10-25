function Sync-WindowsRuntimeSupport {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ProjectionRoot
    )
    foreach ($module in @('WinUI', 'WinAppSDK')) {
        $moduleRoot = Join-Path $ProjectionRoot "Sources/$module"
        $supportRoot = Join-Path $moduleRoot 'Support'
        New-Item -ItemType Directory -Force -Path $supportRoot | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot "windows/Support/$module") -Filter '*.swift' -File | ForEach-Object {
            $target = Join-Path $supportRoot $_.Name
            $legacyTarget = Join-Path $moduleRoot $_.Name
            if (!(Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $legacyTarget)) { $target = $legacyTarget }
            if (!(Test-Path -LiteralPath $target) -or [IO.File]::ReadAllText($_.FullName) -ne [IO.File]::ReadAllText($target)) {
                Copy-Item -LiteralPath $_.FullName -Destination $target
            }
        }
    }
}

function Get-WindowsLLVMTool {
    param(
        [Parameter(Mandatory = $true)][string]$SwiftExecutable,
        [Parameter(Mandatory = $true)][ValidateSet('llvm-objcopy', 'llvm-readobj')][string]$Name
    )
    # Use LLVM from the same toolchain as Swift rather than an arbitrary PATH entry.
    $tool = Join-Path (Split-Path $SwiftExecutable -Parent) ($Name + '.exe')
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Outil LLVM introuvable : $tool" }
    return $tool
}

function Remove-WindowsDistributionDebugInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$SwiftExecutable
    )
    $objcopy = Get-WindowsLLVMTool -SwiftExecutable $SwiftExecutable -Name llvm-objcopy
    $before = (Get-Item -LiteralPath $Executable).Length
    # Only debugger data: preserve Swift reflection, unwind tables, imports and code.
    # Run before embedding PE resources, which can discard the COFF string table.
    & $objcopy --strip-debug --remove-section=swiftast --remove-section=.swift_ast $Executable
    if ($LASTEXITCODE -ne 0) { throw "Suppression des informations de débogage échouée ($LASTEXITCODE)." }
    $after = (Get-Item -LiteralPath $Executable).Length
    Write-Host ('Exécutable distribué : {0:N1} -> {1:N1} Mio (débogage conservé dans .build).' -f ($before / 1MB), ($after / 1MB))
}

function Copy-WindowsRuntimeDependencies {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeDirectory,
        [Parameter(Mandatory = $true)][string]$ApplicationDirectory,
        [Parameter(Mandatory = $true)][string]$SwiftExecutable
    )
    $readobj = Get-WindowsLLVMTool -SwiftExecutable $SwiftExecutable -Name llvm-readobj
    $libraries = @{}
    foreach ($file in Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' -File) {
        $libraries[$file.Name] = $file
    }
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue((Join-Path $ApplicationDirectory 'Cappella.exe'))
    $pending.Enqueue((Join-Path $ApplicationDirectory 'Microsoft.WindowsAppRuntime.Bootstrap.dll'))
    $selected = @{}
    # Some Foundation modules, runtime diagnostics and VC++ helpers can be loaded
    # dynamically. Keep these even when absent from static/delay import tables.
    foreach ($name in $libraries.Keys) {
        if ($name -like '*Foundation*.dll' -or
            $name -in @('swiftRuntime.dll', 'swiftRemoteMirror.dll') -or
            $name -match '^(msvcp|vcruntime|vccorlib|concrt)') {
            $selected[$name] = $true
            $pending.Enqueue($libraries[$name].FullName)
        }
    }
    while ($pending.Count -gt 0) {
        $binary = $pending.Dequeue()
        # LLVM lists both regular and delay-loaded imports for COFF.
        $imports = @(& $readobj --coff-imports $binary)
        if ($LASTEXITCODE -ne 0) { throw "Dépendances illisibles : $binary" }
        foreach ($line in $imports) {
            if ($line -match '^\s+Name:\s+([^\s]+\.dll)\s*$') {
                $name = $Matches[1]
                if ($libraries.ContainsKey($name) -and !$selected.ContainsKey($name)) {
                    $selected[$name] = $true
                    $pending.Enqueue($libraries[$name].FullName)
                }
            }
        }
    }
    # Remove only obsolete runtime DLLs known to this toolchain in our generated
    # output; leave application resources, user files and shared system DLLs alone.
    foreach ($name in $libraries.Keys) {
        $destination = Join-Path $ApplicationDirectory $name
        if ($selected.ContainsKey($name)) {
            Copy-Item -LiteralPath $libraries[$name].FullName -Destination $destination
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination
        }
    }
    Write-Host ('DLL Swift et VC++ distribuées : {0}/{1} (dépendances transitives et modules dynamiques conservés).' -f $selected.Count, $libraries.Count)
}

function Get-CappellaDistributionVersion {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [string]$Version)
    if (!$Version) {
        if ($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME -match '^v(.+)$') {
            $Version = $Matches[1]
        } else {
            $source = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'Sources/CappellaCore/AppVersion.swift'))
            if ($source -notmatch 'public static let development = "([^"]+)"') { throw 'Version centrale introuvable dans AppVersion.swift.' }
            $Version = $Matches[1]
        }
    }
    if ($Version -notmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') {
        throw 'Version invalide : utiliser par exemple 1.0.1 ou 1.0.1-beta.1.'
    }
    return $Version
}

function Get-WindowsPEArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Signature DOS invalide : $Path" }
        $stream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 0x40 -or $offset -gt $stream.Length - 6) { throw "Offset PE invalide : $Path" }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Signature PE invalide : $Path" }
        switch ($reader.ReadUInt16()) {
            0x8664 { return 'x64' }
            0xAA64 { return 'arm64' }
            0x014C { return 'x86' }
            default { throw "Architecture PE inconnue : $Path" }
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

function New-WindowsPortableArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ApplicationDirectory,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Add-Type -AssemblyName System.IO.Compression
    $directory = (Get-Item -LiteralPath $ApplicationDirectory).FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    if ($destinationPath.StartsWith($directory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Le ZIP doit être créé en dehors du dossier de l''application.'
    }
    $suffix = [guid]::NewGuid().ToString('N')
    $partial = $destinationPath + '.partial-' + $suffix
    $backup = $destinationPath + '.previous-' + $suffix
    $published = $false
    try {
        $output = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $archive = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $true)
            try {
                foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Force | Sort-Object FullName) {
                    $sourceStream = $null
                    # Compress-Archive in PowerShell 5 uses exclusive reads.
                    # Permit readers (loaded DLLs/scanners), but reject writers.
                    for ($attempt = 0; $attempt -lt 4; $attempt++) {
                        try {
                            $sourceStream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                            break
                        } catch [IO.IOException] {
                            if ($attempt -eq 3) {
                                throw "Archive impossible : $($file.FullName) est inaccessible. Fermer l'application ou le processus qui verrouille ce fichier, puis relancer. $($_.Exception.Message)"
                            }
                            Start-Sleep -Milliseconds 150
                        }
                    }
                    try {
                        $relative = $file.FullName.Substring($directory.Length + 1).Replace('\', '/')
                        $entry = $archive.CreateEntry((Split-Path $directory -Leaf) + '/' + $relative, [IO.Compression.CompressionLevel]::Optimal)
                        $entryOutput = $entry.Open()
                        try { $sourceStream.CopyTo($entryOutput) } finally { $entryOutput.Dispose() }
                    } finally { $sourceStream.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $output.Dispose() }
        # Publish only a complete archive; keep the previous ZIP if anything fails.
        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            [IO.File]::Replace($partial, $destinationPath, $backup)
        } else { [IO.File]::Move($partial, $destinationPath) }
        $published = $true
    } finally {
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial }
        if ($published -and (Test-Path -LiteralPath $backup -PathType Leaf)) { Remove-Item -LiteralPath $backup }
    }
}

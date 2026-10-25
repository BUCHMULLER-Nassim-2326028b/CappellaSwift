param([Parameter(Mandatory=$true)][string]$Executable, [Parameter(Mandatory=$true)][string]$Icon, [ValidateSet('x64','arm64')][string]$Architecture = 'x64', [string]$Version)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/lib/WindowsBuild.ps1"
$Version = Get-CappellaDistributionVersion -RepositoryRoot (Split-Path $PSScriptRoot -Parent) -Version $Version
$numericVersion = ($Version -split '[-+]')[0] + '.0'
# PE resources only: the application UI is implemented with WinUI controls.
$nativeSource = @'
using System;
using System.IO;
using System.Text;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class CappellaPEResources {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr BeginUpdateResourceW(string path, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool UpdateResourceW(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint length);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool EndUpdateResourceW(IntPtr update, bool discard);
    static void Write(IntPtr handle, int type, int id, byte[] bytes) {
        if (!UpdateResourceW(handle, (IntPtr)type, (IntPtr)id, 0, bytes, (uint)bytes.Length)) throw new Win32Exception();
    }
    public static void UseWindowsSubsystem(string executable, ushort expectedMachine) {
        // Equivalent to editbin /SUBSYSTEM:WINDOWS. Keep the Swift CRT entry
        // point intact; avoid making linker flags invalidate every projection.
        using (var file = new FileStream(executable, FileMode.Open, FileAccess.ReadWrite))
        using (var reader = new BinaryReader(file, Encoding.UTF8, true))
        using (var writer = new BinaryWriter(file, Encoding.UTF8, true)) {
            if (reader.ReadUInt16()!=0x5A4D) throw new InvalidDataException("Missing DOS signature.");
            file.Position=0x3C; int pe=reader.ReadInt32();
            if (pe<0x40 || pe>file.Length-96) throw new InvalidDataException("Invalid PE offset.");
            file.Position=pe;
            if (reader.ReadUInt32()!=0x4550 || reader.ReadUInt16()!=expectedMachine) throw new InvalidDataException("Unexpected PE architecture.");
            file.Position=pe+24;
            if (reader.ReadUInt16()!=0x20B) throw new InvalidDataException("Expected PE32+ image.");
            file.Position=pe+24+64; writer.Write((uint)0); // Checksum is optional for user applications.
            file.Position=pe+24+68; writer.Write((ushort)2);
        }
    }
    static void Align(BinaryWriter writer) {
        while (writer.BaseStream.Position % 4 != 0) writer.Write((byte)0);
    }
    static byte[] VersionBlock(string key, ushort type, ushort valueLength, byte[] value, params byte[][] children) {
        using (var stream = new MemoryStream()) using (var writer = new BinaryWriter(stream, Encoding.Unicode)) {
            writer.Write((ushort)0); writer.Write(valueLength); writer.Write(type);
            writer.Write(Encoding.Unicode.GetBytes(key + "\0")); Align(writer);
            writer.Write(value);
            foreach (byte[] child in children) { Align(writer); writer.Write(child); }
            long length = stream.Length;
            stream.Position = 0; writer.Write(checked((ushort)length)); writer.Flush();
            return stream.ToArray();
        }
    }
    static byte[] VersionString(string key, string value) {
        return VersionBlock(key, 1, checked((ushort)(value.Length + 1)), Encoding.Unicode.GetBytes(value + "\0"));
    }
    static byte[] VersionInfo(string text) {
        Version version = Version.Parse(text.Split('-', '+')[0]);
        uint ms = checked((uint)(version.Major << 16) | (uint)version.Minor);
        uint ls = checked((uint)(version.Build << 16));
        byte[] fixedInfo;
        using (var stream = new MemoryStream()) using (var writer = new BinaryWriter(stream)) {
            writer.Write(0xFEEF04BDu); writer.Write(0x10000u);
            writer.Write(ms); writer.Write(ls); writer.Write(ms); writer.Write(ls);
            writer.Write(0x3Fu); writer.Write(0u); writer.Write(0x40004u);
            writer.Write(1u); writer.Write(0u); writer.Write(0u); writer.Write(0u);
            fixedInfo = stream.ToArray();
        }
        byte[] table = VersionBlock("040904B0", 1, 0, new byte[0],
            VersionString("FileDescription", "Cappella"), VersionString("FileVersion", text),
            VersionString("ProductName", "Cappella"), VersionString("ProductVersion", text),
            VersionString("OriginalFilename", "Cappella.exe"));
        byte[] strings = VersionBlock("StringFileInfo", 1, 0, new byte[0], table);
        byte[] translation = VersionBlock("Translation", 0, 4, new byte[] { 9, 4, 176, 4 });
        byte[] variables = VersionBlock("VarFileInfo", 1, 0, new byte[0], translation);
        return VersionBlock("VS_VERSION_INFO", 0, 52, fixedInfo, strings, variables);
    }
    public static void Embed(string executable, string icon, string manifest, string version) {
        byte[] ico = File.ReadAllBytes(icon);
        ushort count = BitConverter.ToUInt16(ico, 4);
        if (ico.Length < 6 || BitConverter.ToUInt16(ico,2)!=1 || count==0) throw new InvalidDataException("ICO invalide.");
        IntPtr handle = BeginUpdateResourceW(executable, false);
        if (handle == IntPtr.Zero) throw new Win32Exception();
        bool committed = false;
        try {
            using (var group = new MemoryStream()) using (var writer = new BinaryWriter(group)) {
                writer.Write((ushort)0); writer.Write((ushort)1); writer.Write(count);
                for (int i=0; i<count; i++) {
                    int entry=6+i*16, length=checked((int)BitConverter.ToUInt32(ico,entry+8)), offset=checked((int)BitConverter.ToUInt32(ico,entry+12));
                    byte[] image=new byte[length]; Array.Copy(ico,offset,image,0,length);
                    Write(handle,3,i+1,image);
                    writer.Write(ico,entry,12); writer.Write((ushort)(i+1));
                }
                Write(handle,14,1,group.ToArray());
            }
            Write(handle,24,1,Encoding.UTF8.GetBytes(manifest));
            Write(handle,16,1,VersionInfo(version));
            if (!EndUpdateResourceW(handle,false)) throw new Win32Exception();
            committed=true;
        } finally { if (!committed) EndUpdateResourceW(handle,true); }
    }
}

'@
# Add-Type definitions live for the entire PowerShell process. Key the type by
# its source so a script update never reuses an older, incompatible helper.
$hasher = [Security.Cryptography.SHA256]::Create()
try { $digest = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($nativeSource)) }
finally { $hasher.Dispose() }
$typeName = 'CappellaPEResources_' + [BitConverter]::ToString($digest).Replace('-', '')
$resourceType = $typeName -as [type]
if (!$resourceType) {
    $resourceType = Add-Type -TypeDefinition $nativeSource.Replace('CappellaPEResources', $typeName) -PassThru
}
$manifest = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="__CAPPELLA_NUMERIC_VERSION__" processorArchitecture="amd64" name="Cappella.Windows" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security></trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/></application></compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>
    <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
    <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
  </windowsSettings></application>
</assembly>
'@
$manifest = $manifest.Replace('__CAPPELLA_NUMERIC_VERSION__', $numericVersion)
$manifestArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'amd64' }
$manifest = $manifest.Replace('processorArchitecture="amd64"', ('processorArchitecture="' + $manifestArchitecture + '"'))
$resourceType::Embed((Resolve-Path -LiteralPath $Executable).Path, (Resolve-Path -LiteralPath $Icon).Path, $manifest, $Version)

$machine = if ($Architecture -eq 'arm64') { [uint16]0xAA64 } else { [uint16]0x8664 }
$resourceType::UseWindowsSubsystem((Resolve-Path -LiteralPath $Executable).Path, $machine)

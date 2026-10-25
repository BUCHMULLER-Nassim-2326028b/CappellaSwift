#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Cette compilation exige macOS et les outils de développement Apple." >&2
  exit 1
fi
version="${1:-}"
if [[ -z "$version" ]]; then
  if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    version="${GITHUB_REF_NAME#v}"
  else
    version="$(sed -nE 's/^[[:space:]]*public static let development = "([^"]+)".*/\1/p' Sources/CappellaCore/AppVersion.swift)"
  fi
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]]; then
  echo "Version invalide : $version" >&2
  exit 1
fi
swift build -c release --arch arm64
bin_path="$(swift build -c release --arch arm64 --show-bin-path)"
app_path="$PWD/dist/Cappella.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/CappellaMac" "$app_path/Contents/MacOS/CappellaMac"
# Only the distributed copy loses debugger data; preserve the original build.
xcrun strip -S "$app_path/Contents/MacOS/CappellaMac"
cp packaging/Info.plist "$app_path/Contents/Info.plist"
numeric_version="${version%%[-+]*}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $numeric_version" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $numeric_version" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CappellaVersion $version" "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources"
cp packaging/Resources/Mire.jpg "$app_path/Contents/Resources/Mire.jpg"
cp packaging/Resources/PreludeFLF*.ttf "$app_path/Contents/Resources/"
cp packaging/Resources/CappellaLogo.png packaging/Resources/CappellaLogo_dark.png "$app_path/Contents/Resources/"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/cappella-icons.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
xcrun swiftc -parse-as-library scripts/build-icons.swift -o "$icon_work/build-icons"
"$icon_work/build-icons" packaging/Resources/CappellaLogo.png packaging/Resources/CappellaLogo_dark.png "$icon_work"
for icon_name in AppIcon AppIconDark; do
  iconutil --convert icns "$icon_work/$icon_name.iconset" --output "$app_path/Contents/Resources/$icon_name.icns"
  test -s "$app_path/Contents/Resources/$icon_name.icns"
done

chmod +x "$app_path/Contents/MacOS/CappellaMac"
plutil -lint "$app_path/Contents/Info.plist"
[[ "$(lipo -archs "$app_path/Contents/MacOS/CappellaMac")" == "arm64" ]]
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"

archive="$PWD/dist/Cappella-$version-macOS-arm64-Portable.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"

echo "Application ARM64 : $app_path"
echo "Archive : $archive"

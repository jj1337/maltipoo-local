#!/bin/zsh
# Builds MaltipooLocal.app (ad-hoc signed) into ./build
set -e
cd "$(dirname "$0")"
A=build/MaltipooLocal.app
rm -rf build; mkdir -p $A/Contents/MacOS $A/Contents/Resources
swiftc -O -target arm64-apple-macos12.0 dog.swift -o $A/Contents/MacOS/Maltipoo
cp -R gifs gifs_orig dur.json $A/Contents/Resources/
# icon from the first frame of a GIF
I=build/icon.iconset; mkdir -p $I
sips -s format png gifs/Bark.gif --out build/icon.png >/dev/null
for s in 16 32 64 128 256 512; do
  sips -z $s $s build/icon.png --out $I/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out $I/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $I -o $A/Contents/Resources/AppIcon.icns
cat > $A/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Maltipoo Local</string>
<key>CFBundleDisplayName</key><string>Maltipoo Local</string>
<key>CFBundleIdentifier</key><string>local.maltipoo.ollama</string>
<key>CFBundleExecutable</key><string>Maltipoo</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
codesign --force --deep --sign - $A
echo "Built $A"

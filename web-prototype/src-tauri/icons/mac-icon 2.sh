#!/bin/sh
# Builds the Mac app icon from Halftime.icon (an Icon Composer document: white in light mode, black in dark) into
# Assets.car, which macOS picks the right appearance from. Run after editing Halftime.icon; needs Xcode 26.
# Halftime.icon/glyph.svg is the source of Assets/glyph.png: sips -s format png glyph.svg --out Assets/glyph.png
set -e
cd "$(dirname "$0")"
out=$(mktemp -d)
xcrun actool Halftime.icon --compile "$out" --platform macosx --minimum-deployment-target 11.0 --app-icon Halftime \
	--output-partial-info-plist "$out/partial.plist" >/dev/null
cp "$out/Assets.car" Assets.car
rm -rf "$out"

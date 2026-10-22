#!/usr/bin/env python3
"""Builds ByteCache's app icons from App/Resources/AppIcon.icon's layers (braces + arrow).

- Gives AppIcon.icon its dark look: black background, white glyphs.
- Writes the alternate icons (Settings → Appearance → App Icon) as App/Resources/AppIcon-<Name>.icon,
  each with its own light and dark look.
- Renders a preview of each for the picker into the ByteCacheFeatures asset catalog (app-icon-<name>),
  using Icon Composer's ictool, once for iPhone/iPad and once for the Mac's shape. On the Mac the
  preview is also what the Dock shows while ByteCache runs (macOS has no alternate app icons).

Usage: design/AppIcon/make-app-icons.py      (needs Icon Composer in /Applications)
"""
import copy, json, os, shutil, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESOURCES = os.path.join(ROOT, "App/Resources")
PREVIEWS = os.path.join(ROOT, "Packages/ByteCacheKit/Sources/ByteCacheFeatures/Resources/Icons.xcassets/AppIcons")
ICTOOL = "/Applications/Icon Composer.app/Contents/Executables/ictool"


def colour(r, g, b):
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


WHITE = colour(1, 1, 1)
BLUE = colour(0, 0.53333, 1)

# name: (light background, light glyphs or None for white, dark background, dark glyphs)
# A background is one colour (an automatic gradient from it) or two (a linear gradient).
ICONS = {
    "Default": (BLUE, None, colour(0.10, 0.10, 0.11), WHITE),
    "Black": (colour(0.10, 0.10, 0.11), None, colour(0.10, 0.10, 0.11), WHITE),
    "Midnight": (colour(0.07, 0.10, 0.26), colour(0.45, 0.75, 1.00), colour(0.03, 0.04, 0.09), colour(0.45, 0.75, 1.00)),
    "Mint": (colour(0.00, 0.70, 0.52), None, colour(0.05, 0.13, 0.11), colour(0.20, 0.85, 0.65)),
    "Grape": (colour(0.55, 0.30, 0.95), None, colour(0.11, 0.08, 0.18), colour(0.72, 0.56, 1.00)),
    "Sunset": ([colour(1.00, 0.58, 0.15), colour(0.94, 0.24, 0.55)], None, colour(0.16, 0.08, 0.09), colour(1.00, 0.55, 0.42)),
    "Graphite": (colour(0.44, 0.46, 0.50), None, colour(0.10, 0.10, 0.11), colour(0.78, 0.79, 0.82)),
    "Light": (colour(1, 1, 1), BLUE, colour(0.11, 0.11, 0.12), colour(0.20, 0.60, 1.00)),
}


def fill(background):
    return {"linear-gradient": background} if isinstance(background, list) else {"automatic-gradient": background}


def build(name, base):
    light_bg, light_glyph, dark_bg, dark_glyph = ICONS[name]
    doc = copy.deepcopy(base)
    doc.pop("fill", None)
    doc["fill-specializations"] = [{"value": fill(light_bg)}, {"appearance": "dark", "value": fill(dark_bg)}]
    for layer in doc["groups"][0]["layers"]:
        specs = [{"appearance": "dark", "value": {"automatic-gradient": dark_glyph}}]
        if light_glyph:
            specs.insert(0, {"value": {"automatic-gradient": light_glyph}})
        layer["fill-specializations"] = specs
    folder = os.path.join(RESOURCES, "AppIcon.icon" if name == "Default" else f"AppIcon-{name}.icon")
    if name != "Default":
        shutil.rmtree(folder, ignore_errors=True)
        shutil.copytree(os.path.join(RESOURCES, "AppIcon.icon", "Assets"), os.path.join(folder, "Assets"))
    json.dump(doc, open(os.path.join(folder, "icon.json"), "w"), indent=2)
    return folder


def preview(name, icon):
    folder = os.path.join(PREVIEWS, f"app-icon-{name.lower()}.imageset")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    images = []
    # The Mac one is also the Dock icon while the app runs, so it's large.
    for platform, idiom, file, size in (("iOS", "universal", "ios.png", 180), ("macOS", "mac", "mac.png", 512)):
        subprocess.run([ICTOOL, icon, "--export-image", "--output-file", os.path.join(folder, file),
                        "--platform", platform, "--rendition", "Default",
                        "--width", str(size), "--height", str(size), "--scale", "1"], check=True, capture_output=True)
        images.append({"filename": file, "idiom": idiom})
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
              open(os.path.join(folder, "Contents.json"), "w"), indent=2)


if __name__ == "__main__":
    base = json.load(open(os.path.join(RESOURCES, "AppIcon.icon/icon.json")))
    os.makedirs(PREVIEWS, exist_ok=True)
    json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
              open(os.path.join(PREVIEWS, "Contents.json"), "w"), indent=2)
    for name in ICONS:
        preview(name, build(name, base))
    print(f"{len(ICONS)} icons")

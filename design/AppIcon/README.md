# ByteCatch app icon (Icon Composer)

Layers drawn to Apple's App Icon Template (iOS/iPadOS/macOS/watchOS 27): 1024×1024 square canvas,
no rounded corners (the system applies the mask and Liquid Glass), foreground inside the safe area.

| File | Layer |
|---|---|
| `1-background.png` | Full-bleed blue gradient (or use Icon Composer's own background fill) |
| `2-braces.png` | White `{ }` |
| `3-arrow.png` | White "catch" arrow |
| `preview.png` | Flat composite with the iOS mask — reference only, don't import |

Regenerate with `xcrun swift design/AppIcon/make-layers.swift design/AppIcon`.

## Build the icon
1. Open **Icon Composer** (Xcode → Open Developer Tool → Icon Composer) → New.
2. Drag `2-braces.png` and `3-arrow.png` into the layer list (each as its own group).
3. Background: drag in `1-background.png`, or pick a blue gradient fill in the document inspector.
4. Check Default / Dark / Clear / Tinted and iPhone, iPad, Mac previews; tune glass, shadow and translucency.
5. Save as `App/Resources/AppIcon.icon` (name must be `AppIcon`).

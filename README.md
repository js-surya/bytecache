# ByteCatch

An unofficial native client for [ByteStash](https://github.com/jordan-dalby/ByteStash), the self-hosted code snippet manager, for iPhone, iPad and Mac.

- **Catch code from anywhere:** select code in Safari or any app → Share → ByteCatch. The language is detected on-device.
- **Browse and copy:** search, filter by language/category, pinned, favorites, recycle bin, syntax highlighting, copy per file.
- **Edit:** multi-file snippets, categories, public flag.
- **Native everywhere:** three-column layout on iPad and Mac, keyboard shortcuts, drag and drop, multiple windows, Shortcuts/Siri/Spotlight, offline reading.

ByteCatch is not affiliated with the ByteStash project. It talks to ByteStash's HTTP API and contains no ByteStash code.

## Build
Requirements: Xcode 27+, XcodeGen (`brew install xcodegen`).

```sh
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # set your Team ID
open ByteCatch.xcodeproj
scripts/test.sh                                            # package tests + iOS and macOS builds
```

Try it against the public demo (don't store real code there): tap **Try the demo server**.

## Layout
- `Packages/ByteCatchKit` — `ByteCatchCore` (API, auth, cache), `ByteCatchLanguage` (detection), `ByteCatchFeatures` (view models, shared SwiftUI).
- `App/`, `ShareExtension-iOS/`, `ShareExtension-macOS/` — thin targets.
- `Tools/LanguageModelTrainer` — reproducible training of the language model (sources and licenses in `Packages/ByteCatchKit/Sources/ByteCatchLanguage/DATA.md`).
- `docs/` — design, plan, privacy policy, App Store notes, parity checklist.

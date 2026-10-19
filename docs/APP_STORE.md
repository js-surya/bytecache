# App Store submission notes

**Name:** ByteCache — Snippets for ByteStash
**Subtitle:** Save code from anywhere
**Category:** Developer Tools
**Platforms:** iOS / iPadOS 17+, macOS 14+ (two builds, one App Store record each or universal purchase)

## Positioning
ByteCache is an unofficial client for ByteStash (github.com/jordan-dalby/ByteStash). It is not affiliated with or endorsed by the ByteStash project. It does not use the ByteStash logo. Say this in the description and in review notes.

## Review notes (paste into App Store Connect)
> ByteCache connects to a self-hosted ByteStash server. To review, tap "Try the demo server" on the first screen; it signs in to the public demo at https://bytestash-demo.pikapod.net (username `demo`, password `demodemo`). The demo is maintained by the ByteStash community and is public, so its content is user-generated test data.
> To test sharing: select text in Safari → Share → ByteCache → Save.

## Privacy
- Privacy policy: docs/PRIVACY.md (host it, e.g. GitHub Pages, and link it in App Store Connect).
- App Privacy questionnaire: "Data Not Collected".
- Privacy manifests ship in the app and both extensions (`PrivacyInfo.xcprivacy`).

## Before uploading
1. Paid Apple Developer Program membership; set your Team in `Config/Signing.xcconfig`.
2. Register the App Group (`group.app.bytecache` for iOS) and enable Keychain Sharing; Xcode's automatic signing does this when the Team is set.
3. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` (or in Xcode).
4. Product → Archive for "Any iOS Device" and for "My Mac", then Distribute App.
5. Screenshots: iPhone 6.9", iPad 13", Mac — use the demo server (`-BCDemoLogin` launch argument in Debug signs in automatically).

## License note
ByteCache is written from scratch against ByteStash's HTTP API; it contains no ByteStash (GPL-3.0) code. Third-party: HighlightSwift (MIT) bundling highlight.js (BSD-3-Clause) — both credited in Settings → Acknowledgements.

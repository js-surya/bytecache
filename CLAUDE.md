# ByteCache

ByteCache ("Cache the bytes"; renamed from ByteCatch in CP-18 because of a name clash): unofficial native ByteStash client for iPhone, iPad and Mac (SwiftUI, one codebase, native macOS — not Catalyst).

- Design: `docs/superpowers/specs/2026-10-18-bytecache-design.md`
- Plan (work task by task, TDD, commit per task): `docs/superpowers/plans/2026-10-18-bytecache.md`
- Batch 2 plan: `docs/superpowers/plans/2026-10-19-batch2.md` (all done).
- GitHub: js-surya/bytecache. Branching: see "Branches and releases" below. All 15 plan tasks are done; progress ledger in `.superpowers/sdd/2026-10-18-bytecatch/progress.md`. Remaining: manual parity pass (`docs/PARITY_CHECKLIST.md`).

## Layout
- `Packages/ByteCacheKit` — all logic. `ByteCacheCore` (API, auth, cache), `ByteCacheLanguage` (detection), `ByteCacheFeatures` (view models + shared SwiftUI views). New files here need no project changes.
- `App/Sources` — thin app target (iOS + macOS). `ShareExtension-iOS`, `ShareExtension-macOS` — share extensions.
- `project.yml` — XcodeGen spec that generated `ByteCache.xcodeproj`. If you change targets/settings in project.yml, run `xcodegen generate` (overwrites edits made in Xcode's project editor). Pick one: edit project.yml + regenerate, or edit in Xcode and stop regenerating.

## Language model
- Retrain: `Tools/LanguageModelTrainer/fetch-sources.sh` then `swift run -c release --package-path Tools/LanguageModelTrainer train` (~15 min). Any change to `CodeTokenizer.features` needs a retrain. Acceptance tests: `LanguageEvalTests`, `RegressionTests`.

## Debug launch arguments
- `-BCDemoLogin` signs in to the demo server; `-BCKeyLogin` signs in to env `BC_DEBUG_SERVER` with env `BC_DEBUG_API_KEY`; `-BCSelectFirst` selects the first snippet; `-BCShowSettings` opens Settings once (iPhone/iPad; Mac Settings is a sidebar window) (env `BC_SETTINGS_PAGE=about|acknowledgements|account|haptics|servers|report|mcp` then opens that page); `-BCNewSnippet` opens the editor; `-BCTab search|library|pinned|favorites` opens an iPhone tab; `-BCOpenSnippet <id>` opens a snippet; env `BC_DEBUG_API_KEY` pre-fills the API key field; env `BC_DEBUG_CODE` pre-fills the `-BCNewSnippet` editor; env `BC_DEBUG_PRETEND_VERSION=1.0.0` makes the update check think the app is that version; `-BCLoadingPreview` shows only the loading animation; `-BCCopyToast` shows the "Copied" toast every 3 s; `-BCSearch <text>` starts the iPhone Search tab with that search; `-BCSuggestTitlePreview` offers Suggest Title on any snippet; `-BCSmartGroupDemo` adds and selects a sample Smart Group; `-BCNewSmartGroup` opens the Smart Group editor; `-BCExpireSession` swaps the login for an expired session token (shows the sign-in path); `-BCShareImage` opens Share as Image for the first file of an opened snippet; `-BCExpiryDemo` makes snippets 9 and 10 expire in 50 minutes and 2 days; `-BCAccessibilityGuide` opens the Mac Accessibility drag-in guide; `-BCScanPreview` opens the camera screen over a black placeholder (simulator) (Debug builds only).
- After each build, install it on the main iPhone simulator (iPhone 18 Pro) without debug flags; use the spare iPhone 17e for screenshots.

## Branches and releases
- Feature/fix branches (one per Linear issue, e.g. `cp-14-report-a-bug`) → PR into **`develop`** (no GitHub CI; run tests locally first, then merge).
- Release: ask the user for the version, `scripts/set-version.sh X.Y.Z` on `develop`, PR `develop` → `main` (CI tests it), then **merge commit, not squash**; the merge publishes GitHub release `vX.Y.Z` (`.github/workflows/release.yml`) with notes from the commit log.
- Since 1.3.0 the apps ship only through TestFlight (public link https://testflight.apple.com/join/rpmeVJW6) and the App Store: GitHub releases have notes and source, no app files. Archive in Xcode, Organizer → App Store Connect.

## Commands
- Package tests: `swift test --package-path Packages/ByteCacheKit`
- Everything: `scripts/test.sh`

## Rules
- Every feature must work on iPhone, iPad and Mac before it's done.
- Never copy code from the GPL-3.0 ByteStash repo; talk to its HTTP API only.
- Auth header `bytestashauth: Bearer <jwt>`. Snippet PUT replaces everything — always send all fields incl. `is_public`.
- Test server `https://bytestash-demo.pikapod.net` (`demo`/`demodemo`) is public: no real code.
- Signing: copy `Config/Signing.xcconfig.example` → `Config/Signing.xcconfig` and set your Team ID.
- No tip or donation links in the app (removed in 1.3.0; outside payment links break App Store guideline 3.1.1).

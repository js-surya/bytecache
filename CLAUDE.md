# ByteCatch

Unofficial native ByteStash client for iPhone, iPad and Mac (SwiftUI, one codebase, native macOS — not Catalyst).

- Design: `docs/superpowers/specs/2026-10-18-bytecatch-design.md`
- Plan (work task by task, TDD, commit per task): `docs/superpowers/plans/2026-10-18-bytecatch.md`
- All 15 plan tasks are implemented on branch `feature/bytecatch-v1`; progress ledger in `.superpowers/sdd/2026-10-18-bytecatch/progress.md`. Remaining: manual parity pass (`docs/PARITY_CHECKLIST.md`).

## Layout
- `Packages/ByteCatchKit` — all logic. `ByteCatchCore` (API, auth, cache), `ByteCatchLanguage` (detection), `ByteCatchFeatures` (view models + shared SwiftUI views). New files here need no project changes.
- `App/Sources` — thin app target (iOS + macOS). `ShareExtension-iOS`, `ShareExtension-macOS` — share extensions.
- `project.yml` — XcodeGen spec that generated `ByteCatch.xcodeproj`. If you change targets/settings in project.yml, run `xcodegen generate` (overwrites edits made in Xcode's project editor). Pick one: edit project.yml + regenerate, or edit in Xcode and stop regenerating.

## Language model
- Retrain: `Tools/LanguageModelTrainer/fetch-sources.sh` then `swift run -c release --package-path Tools/LanguageModelTrainer train` (~15 min). Any change to `CodeTokenizer.features` needs a retrain. Acceptance tests: `LanguageEvalTests`, `RegressionTests`.

## Debug launch arguments
- `-BCDemoLogin` signs in to the demo server; `-BCSelectFirst` selects the first snippet (Debug builds only).

## Commands
- Package tests: `swift test --package-path Packages/ByteCatchKit`
- Everything: `scripts/test.sh`

## Rules
- Every feature must work on iPhone, iPad and Mac before it's done.
- Never copy code from the GPL-3.0 ByteStash repo; talk to its HTTP API only.
- Auth header `bytestashauth: Bearer <jwt>`. Snippet PUT replaces everything — always send all fields incl. `is_public`.
- Test server `https://bytestash-demo.pikapod.net` (`demo`/`demodemo`) is public: no real code.
- Signing: copy `Config/Signing.xcconfig.example` → `Config/Signing.xcconfig` and set your Team ID.

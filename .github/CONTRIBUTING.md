# Contributing to ByteCatch

Thanks for helping! A few things keep the project healthy.

## Before you start
- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Every feature must work on iPhone, iPad **and** Mac.
- ByteStash is GPL-3.0. Never copy its code; ByteCatch only talks to its HTTP API.

## Setting up
1. Install Xcode 27+ and XcodeGen (`brew install xcodegen`).
2. `cp Config/Signing.xcconfig.example Config/Signing.xcconfig` and set your Team ID.
3. Open `ByteCatch.xcodeproj`. If you change `project.yml`, run `xcodegen generate`.

## Code
- Logic goes in `Packages/ByteCatchKit` with tests; the app targets stay thin.
- Write the test first, watch it fail, then make it pass.
- Run `scripts/test.sh` before opening a pull request.
- Use the public demo server (`https://bytestash-demo.pikapod.net`, `demo`/`demodemo`) for manual testing. It's public, so never put real code there.

## Commits
Short, conventional messages such as `fix(scan): …` or `feat(editor): …`, with the issue number when there is one.

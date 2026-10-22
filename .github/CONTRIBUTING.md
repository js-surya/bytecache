# Contributing to ByteCache

Thanks for helping! A few things keep the project healthy.

## Before you start
- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Every feature must work on iPhone, iPad **and** Mac.
- ByteStash is GPL-3.0. Never copy its code; ByteCache only talks to its HTTP API.

## Setting up
1. Install Xcode 27+ and XcodeGen (`brew install xcodegen`).
2. `cp Config/Signing.xcconfig.example Config/Signing.xcconfig` and set your Team ID.
3. Open `ByteCache.xcodeproj`. If you change `project.yml`, run `xcodegen generate`.

## Code
- Logic goes in `Packages/ByteCacheKit` with tests; the app targets stay thin.
- Write the test first, watch it fail, then make it pass.
- Run `scripts/test.sh` before opening a pull request.
- Use the public demo server (`https://bytestash-demo.pikapod.net`, `demo`/`demodemo`) for manual testing. It's public, so never put real code there.

## Commits
Short, conventional messages such as `fix(scan): …` or `feat(editor): …`, with the issue number when there is one.

## Branches and releases
- `main` holds released code. `develop` collects work for the next release.
- Every change goes on its own branch and into **`develop`** through a pull request (several small fixes can share one branch). Run `scripts/test.sh` first; pull requests into `develop` don't use GitHub's build machines.
- **To release:** on `develop`, set the version and build with `scripts/set-version.sh X.Y.Z BUILD` and commit, then open a pull request from `develop` into `main`. GitHub runs the tests and checks that the iPhone/iPad and Mac apps compile. **Merge it with a regular merge, not squash**: GitHub then publishes "ByteCache X.Y.Z (BUILD)" (tag `vX.Y.Z`, or `vX.Y.Z-BUILD` for a later build of the same version) with the source code and notes listing every change since the previous release. The apps are distributed only through TestFlight and the App Store.
- Docs-only changes don't start a build.

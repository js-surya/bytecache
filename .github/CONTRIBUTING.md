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
- Every change goes on its own branch and into `main` through a pull request. Several small fixes can share one branch.
- Each pull request is tested and built automatically; the iPhone/iPad and Mac builds can be downloaded from the run.
- **To release:** set the new version on the branch with `scripts/set-version.sh X.Y.Z` (commit the result). When that pull request is merged, GitHub publishes release `vX.Y.Z` with the builds, the source code and release notes. Merges that don't change the version don't create a release.
- Label pull requests `feature`, `bug` or `improvement` so they land in the right section of the release notes (`skip-changelog` leaves one out).
- Build the release files locally with `scripts/package-release.sh`.

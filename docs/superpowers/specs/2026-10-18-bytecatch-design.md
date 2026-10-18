# ByteCatch — Design

Date: 2026-10-18
Status: Draft, awaiting approval

## Intent

ByteCatch is a native Apple client (iPhone, iPad, Mac) for [ByteStash](https://github.com/jordan-dalby/ByteStash),
a self-hosted code-snippet manager. The owner's real moment: browsing other sites on
an iPhone, finding code worth keeping, and having no quick way to get it into ByteStash.
The web UI on a phone is too clumsy for that.

So ByteCatch is **capture-first**: saving code from any app must be near-instant. Browsing
and copying saved snippets on the phone is the second job.

## Goals

1. **Catch from anywhere** — iOS Share Extension. Select code in Safari (or any app that
   shares text / URLs) → Share → ByteCatch → sheet with code prefilled, language auto-guessed,
   title field focused → Save. Target: under ~5 seconds, never leave the source app.
2. **Clipboard catch** — when the main app opens and the clipboard holds text, offer a
   "Save copied code" banner (uses iOS paste permission flow; never reads silently).
3. **Browse** — snippet list with search, filters (language, category, favorites, pinned),
   sort, infinite scroll. Detail view with syntax-highlighted code per fragment and a
   one-tap Copy button per fragment.
4. **Light editing** — edit title, description, categories, fragment code/language;
   pin / favorite; move to recycle bin.
5. **Any server** — user enters their own ByteStash server URL (incl. sub-path / `BASE_PATH`).
6. **App Store-ready** — owner may publish.
7. **iPad and Mac layouts** — real adaptive layouts, not a stretched phone UI (see Platforms).
8. **Production-grade language detection** — on-device, accurate, measured (see Language detection).

## Non-goals (v1)

- SSO / OIDC login (server's flow is cookie + web redirect only; revisit later).
- Admin screens, API-key management, user settings, public snippet browsing, share links.
- Full IDE-grade editor.
- Multiple accounts / servers at once.

## Anti-goals

- Capture that takes many taps or forces opening the main app.
- Copying code from the GPL-3.0 ByteStash web client. ByteCatch is written from scratch
  against the HTTP API only, so its license stays the owner's choice.
- Implying it is official: no ByteStash logo; describe as "an unofficial client for ByteStash".
- Reading the clipboard without the user's action.
- Collecting any analytics / data.

## Constraints

- Xcode 27.1, iOS 27 SDK available on the owner's Mac. Deployment targets: iOS / iPadOS 17,
  macOS 14 (SwiftData, modern SwiftUI APIs; broad device reach).
- Test server: public demo `https://bytestash-demo.pikapod.net`, user `demo` / `demodemo`.
  It is shared and public — never store real code there.
- Share Extension + app must share login token and server URL → App Group + shared
  Keychain access group. Free Apple account is enough for on-device testing; shipping
  needs the paid program.
- Project location: the repository root.

## ByteStash API (verified against source and live demo)

All paths are prefixed with the server base URL (which may include a sub-path).

- Auth header: `bytestashauth: Bearer <jwt>` (server reads `req.headers['bytestashauth']`).
- `GET /api/auth/config` → `{ authRequired, allowNewAccounts, hasUsers, disableAccounts,
  disableInternalAccounts, allowPasswordChanges }`. Used on server-setup screen to validate
  the URL and decide if password login is available. If `authRequired == false` the server
  is single-user with no login; support via `POST /api/auth/anonymous` (returns a token).
- `POST /api/auth/login` `{username, password}` → `{ token, user }`. 401 = bad creds,
  403 = disabled/deactivated.
- `GET /api/auth/verify` → session check on launch.
- `GET /api/snippets?limit&offset&search&searchCode&language&category(csv)&favorites&pinned&recycled&sort`
  → `{ data: [Snippet], pagination: { total, offset, limit, hasMore } }`. limit max 100.
- `GET /api/snippets/metadata` → `{ categories: [String], languages: [String] }`.
- `GET /api/snippets/:id`, `POST /api/snippets` (201), `PUT /api/snippets/:id`.
- `PATCH /api/snippets/:id/pin`, `/favorite`, `/recycle`, `/restore`; `DELETE /api/snippets/:id`.

Snippet JSON (live sample):

```json
{ "id": 1796, "title": "asdf", "description": "", "updated_at": "2026-10-18 00:45:14Z",
  "expiry_date": null, "user_id": 2, "is_public": 0, "is_pinned": 0, "is_favorite": 0,
  "username": "demo", "categories": [], "share_count": 0,
  "fragments": [ { "id": 3421, "file_name": "main", "code": "...", "language": "plaintext", "position": 0 } ] }
```

Note booleans arrive as `0/1` ints; decode tolerantly (Int or Bool).

POST / PUT body (from `snippetRepository.create/update`):
`{ title, description, categories: [String], fragments: [{ file_name, code, language }], is_public: 0|1 }`.
Fragment order = array order. **PUT replaces everything**: all categories and fragments are
rewritten, and omitting `is_public` resets it to 0 — so edits must always send the full
snippet including the current `is_public`.

## Decided how

- **SwiftUI multiplatform**, one codebase. Native macOS target (not Mac Catalyst, not
  "Designed for iPad"), so menus, windows, keyboard shortcuts feel like a Mac app. (My call.)
- **SwiftUI**, Swift concurrency, `URLSession`. No third-party networking.
- **Targets:** `ByteCatch` (iOS/iPadOS app), `ByteCatchMac` (macOS app — or one multiplatform
  target, builder's choice), `ByteCatchShare` (iOS Share Extension), `ByteCatchShareMac` (macOS
  Share Extension), shared Swift package `ByteCatchKit` (API client, models, auth store,
  language detection) used by all.
- **Token + server URL** stored in Keychain with shared access group; non-secret prefs in
  App Group `UserDefaults`.
- **Syntax highlighting:** a maintained Swift package (Highlightr or similar), read-only views.
  Editing uses a plain monospaced `TextEditor`. (My call — keeps v1 simple.)
- **Offline:** cache last-fetched snippet list + details with SwiftData so recent snippets
  open without network; writes require network (no offline queue in v1). (My call.)
- **Token expiry:** on 401, clear token and route to login (server default expiry 24h).

## Platforms

Navigation is a `NavigationSplitView` everywhere; it collapses to a stack on iPhone.

- **iPhone:** stack — list → detail. Share sheet is compact.
- **iPad:** three columns — sidebar (All, Pinned, Favorites, Recycle Bin, Languages,
  Categories) | snippet list | detail. Supports Split View / Slide Over / Stage Manager,
  hardware-keyboard shortcuts (⌘N new, ⌘F search, ⌘C copy focused fragment, ⌘E edit),
  drag & drop: drop text onto the window to create a snippet, drag a fragment out as text.
- **Mac:** same three columns, native toolbar with search field, menu bar commands with the
  same shortcuts, multiple windows (open a snippet in its own window), Settings via the
  standard Settings scene, Share Extension in the macOS Share menu, drag & drop as on iPad.
  "Services" menu entry ("Save to ByteCatch") is nice-to-have, not v1-required.
- Sidebar filters map to the existing API query params (`pinned`, `favorites`, `recycled`,
  `language`, `category`).

## Language detection

Must be production-grade: on-device (code never leaves the device for detection), fast,
and measured. Lives in `ByteCatchKit`, used by the share extensions, clipboard catch, and
new-snippet editor.

**Pipeline** (modelled on GitHub Linguist's strategy chain; first confident answer wins):

1. **Explicit hints** — file name / extension when available (shared file, URL path like
   `.../foo.py`, GitHub/Gist raw URLs), editor modelines (`vim: ft=`, `-*- mode: -*-`).
2. **Shebang** — `#!/usr/bin/env python3`, `#!/bin/bash`, etc.
3. **Strong structural signals** — valid JSON parse, XML/HTML prolog, YAML document markers,
   Markdown structure, `<?php`, `package main`, SQL statement grammar, Dockerfile directives.
4. **ML classifier** — a Core ML text classifier (trained with Create ML, character + token
   n-gram features) over the top ~40 languages ByteStash supports. Returns ranked
   languages with probabilities.
5. **Disambiguation rules** for known confusable pairs (C / C++ / Objective-C, JS / TS / JSX,
   Kotlin / Swift / Scala, Bash / Zsh / PowerShell, CSS / SCSS / Less) — Linguist-style
   heuristics applied on top of the classifier's top candidates.
6. **Fallback** — if top confidence < threshold, return `plaintext` and show the user the
   top 3 candidates as quick picks instead of silently guessing wrong.

**Output:** `[(languageId, confidence)]`, ids exactly matching ByteStash's language ids
(the set in ByteStash's client `languageUtils.tsx` — use the id list as data; do not copy
code). The save sheet preselects #1 and shows #2–3 as one-tap alternatives.

**Training data:** permissively licensed only (e.g. GitHub Linguist `samples/`, MIT-licensed
repos). Record sources + licenses in `ByteCatchKit/LanguageModel/DATA.md`. Training script
(Create ML / Python) is checked into the repo so the model is reproducible.

**Acceptance bar (measured by an automated eval on a held-out set, run in CI/tests):**
- ≥ 92% top-1 and ≥ 98% top-3 accuracy on held-out snippets of 5–200 lines.
- ≥ 85% top-1 on very short snippets (1–4 lines), where it may also correctly abstain.
- Detection < 30 ms for a 200-line snippet on a recent iPhone; model ≤ 5 MB.
- Regression test fixture of real-world snippets (incl. confusable pairs) must stay green.

## Screens

1. **Server setup** — URL field, "Try demo server" button, validates via `/api/auth/config`.
2. **Login** — username/password. Shows clear error for SSO-only servers.
3. **Snippet list** — search bar, filter chips, pull-to-refresh, infinite scroll,
   swipe actions (pin, favorite, recycle). Clipboard banner on open.
4. **Snippet detail** — title, categories, fragments with highlighted code + Copy each,
   Edit, Share text.
5. **Edit / New** — title, description, categories (tokens with suggestions from metadata),
   fragments (file name, language picker, code).
6. **Settings** — server, signed-in user, sign out, about/privacy, "unofficial client" note.
7. **Share sheet (extension)** — compact: code preview, language, title, categories, Save.
   If not signed in: message telling the user to open ByteCatch first.

## Left to the builder

- Exact folder / file layout, view models, test structure.
- Choice of highlighting package after quick evaluation (must support iOS + macOS).
- Exact ML feature set / model type, provided the acceptance bar is met.
- App icon placeholder and accent colour.
- Unit tests for API decoding, query building, language detection; UI flow tested manually
  on the iOS 27 simulator against the demo server.

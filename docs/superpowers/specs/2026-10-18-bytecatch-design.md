# ByteCatch — Design

Date: 2026-10-18
Status: Draft, awaiting approval

## Intent

ByteCatch is a native iOS client for [ByteStash](https://github.com/jordan-dalby/ByteStash),
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

## Non-goals (v1)

- SSO / OIDC login (server's flow is cookie + web redirect only; revisit later).
- Admin screens, API-key management, user settings, public snippet browsing, share links.
- Full IDE-grade editor.
- iPad-specific layout (should work, not tuned).
- Multiple accounts / servers at once.

## Anti-goals

- Capture that takes many taps or forces opening the main app.
- Copying code from the GPL-3.0 ByteStash web client. ByteCatch is written from scratch
  against the HTTP API only, so its license stays the owner's choice.
- Implying it is official: no ByteStash logo; describe as "an unofficial client for ByteStash".
- Reading the clipboard without the user's action.
- Collecting any analytics / data.

## Constraints

- Xcode 27.1, iOS 27 SDK available on the owner's Mac. Deployment target: iOS 17
  (SwiftData, modern SwiftUI APIs; broad device reach).
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

- **SwiftUI**, Swift concurrency, `URLSession`. No third-party networking.
- **Targets:** `ByteCatch` (app), `ByteCatchShare` (Share Extension), shared Swift package
  `ByteCatchKit` (API client, models, auth store, language detection) used by both.
- **Token + server URL** stored in Keychain with shared access group; non-secret prefs in
  App Group `UserDefaults`.
- **Syntax highlighting:** a maintained Swift package (Highlightr or similar), read-only views.
  Editing uses a plain monospaced `TextEditor`. (My call — keeps v1 simple.)
- **Offline:** cache last-fetched snippet list + details with SwiftData so recent snippets
  open without network; writes require network (no offline queue in v1). (My call.)
- **Language guess:** lightweight heuristics (shebangs, keywords, braces/indent patterns)
  mapping to ByteStash language ids; user can override in the save sheet. (My call.)
- **Token expiry:** on 401, clear token and route to login (server default expiry 24h).

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
- Choice of highlighting package after quick evaluation.
- App icon placeholder and accent colour.
- Unit tests for API decoding, query building, language detection; UI flow tested manually
  on the iOS 27 simulator against the demo server.

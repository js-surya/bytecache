# Parity checklist

Tick each cell after trying it on that platform. "Auto" = covered by automated tests (`scripts/test.sh`) and build-verified; still worth a manual pass.

| Feature | iPhone | iPad | Mac |
|---|---|---|---|
| Server setup, demo button, login, sign out, change server | ☐ | ☐ | ☐ |
| Sign in with API key (Password / API Key switch) | ☐ | ☐ | ☐ |
| Several servers: add, switch (Settings → Servers and sidebar menu), remove, Cancel while adding | ☐ | ☐ | ☐ |
| Share extension: Safari selection → Save | ☐ | ☐ | ☐ (Share menu) |
| Share extension: text file from Files / Finder | ☐ | ☐ | ☐ |
| Share extension when signed out shows message + Copy | ☐ | ☐ | ☐ |
| Clipboard banner → Paste → capture sheet | ☐ | ☐ | ☐ |
| Language detection preselects + 3 quick picks | ☐ | ☐ | ☐ |
| Sidebar: All / Pinned / Favorites / Recycle Bin / Languages / Categories | ☐ | ☐ | ☐ |
| Search (debounced), Search Code toggle, sort menu | ☐ | ☐ | ☐ |
| Infinite scroll on demo (1,300+ snippets) | ☐ | ☐ | ☐ |
| Highlighted code, line numbers, Copy per file | ☐ | ☐ | ☐ |
| New / edit / multi-file / categories / public toggle | ☐ | ☐ | ☐ |
| Pin / favorite / recycle / restore / delete forever | ☐ | ☐ | ☐ |
| Context menu (long-press / right-click), swipe actions (iOS) | ☐ | ☐ | ☐ |
| Offline: airplane mode shows cached list + banner | ☐ | ☐ | ☐ |
| Keyboard: ⌘N ⌘F ⌘R ⌘E ⌘⇧C ⌘⌫ ⌘S | ☐ (hw keyboard) | ☐ | ☐ |
| Drag text in → capture; drag a code card out | ☐ | ☐ | ☐ |
| Open snippet in new window | n/a (iOS limit) | ☐ | ☐ |
| Shortcuts: Save to ByteCatch, Search Snippets, Open Snippet | ☐ | ☐ | ☐ |
| Spotlight finds a viewed snippet; tapping opens it | ☐ | ☐ | ☐ |
| Settings (iOS Settings style, icon rows) | ☐ (sheet) | ☐ (sheet) | ☐ (Settings window) |
| Appearance: Automatic / Light / Dark, accent colour | ☐ | ☐ | ☐ |
| Markdown preview (Preview / Source) | ☐ | ☐ | ☐ |
| Save snippet to Files (title.ext; folder for multi-file; per-card Save File…) | ☐ | ☐ | ☐ |
| App Lock: Face ID / Touch ID / passcode, timeout, privacy cover | ☐ | ☐ | ☐ |
| API keys: list, create (shown once), delete; change password | ☐ | ☐ | ☐ |
| Widgets: Pinned / Recent, copy button, tap to open, Locked state | ☐ (+ Lock Screen) | ☐ | ☐ |
| Save Clipboard: Control Center / Lock Screen control (iOS 18+), Action Button & Siri shortcut | ☐ | ☐ | ☐ (shortcut) |
| Scan code: camera (device only) / photo; Mac: image file / paste image | ☐ | ☐ | ☐ |
| Smart suggestions (Apple Intelligence, iOS/macOS 26) | ☐ | ☐ | ☐ |
| iCloud sync of settings + server list (needs signed build + iCloud); switch off works | ☐ | ☐ | ☐ |
| Handoff: view snippet on one device → continue on another; web fallback; switch off works | ☐ | ☐ | ☐ |
| Code theme (22 themes), font size, line numbers — viewer, editor, share sheet | ☐ | ☐ | ☐ |
| **Batch 3** | | | |
| Secret warning in capture + editor; Replace with {{SECRET}} | ☐ | ☐ | ☐ |
| Most Used list (copies from list, detail, widget) | ☐ | ☐ | ☐ |
| Public toggle; Public snippets browse (read-only, copy/save) | ☐ | ☐ | ☐ |
| Share links: create (expiry, sign-in), copy, QR, revoke (password logins) | ☐ | ☐ | ☐ |
| Bulk select: pin, favorite, add/remove category, recycle, restore, delete forever | ☐ | ☐ | ☐ |
| Explain snippet (Apple Intelligence; hidden when unavailable) | ☐ | ☐ | ☐ |
| Backup: export ZIP of files + JSON; import JSON | ☐ | ☐ | ☐ |
| Import: GitHub Gist URL, VS Code snippets file, code files/folder → preview → create | ☐ | ☐ | ☐ |
| Offline save queue: capture/share/Shortcut offline → "waiting to upload" row → uploads when online; Retry / Discard | ☐ | ☐ | ☐ |
| Code editor: live colouring, line numbers, auto-indent, auto-close, bracket match, find & replace (key bar on iPhone/iPad, ⌘F on Mac) | ☐ | ☐ | ☐ |

## Review focus (from the plan)
| Case | Expected | Auto | Manual |
|---|---|---|---|
| Loosely typed server URL (`nas.local/`, `/bytestash`, `…/api`, `…/login`) | normalised, no double slashes | ✅ ServerURLTests | ☐ |
| Token expires mid-use (app, share extension, intents) | clean sign-out to login; share keeps code | ✅ SessionManager/Capture/Intent tests | ☐ |
| Editing a public snippet | stays public, nothing dropped | ✅ SnippetEditorModelTests | ☐ |
| 5,000-line paste, empty selection, URL-only share, CRLF | fast; Save disabled when empty; CRLF → LF | ✅ Detector/Capture/Loader tests | ☐ |
| No network | cached list + Offline banner; edits kept with retryable error | ✅ List/Editor tests | ☐ |

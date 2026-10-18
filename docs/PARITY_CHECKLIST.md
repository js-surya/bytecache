# Parity checklist

Tick each cell after trying it on that platform. "Auto" = covered by automated tests (`scripts/test.sh`) and build-verified; still worth a manual pass.

| Feature | iPhone | iPad | Mac |
|---|---|---|---|
| Server setup, demo button, login, sign out, change server | ☐ | ☐ | ☐ |
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
| Code theme (22 themes), font size, line numbers — viewer, editor, share sheet | ☐ | ☐ | ☐ |

## Review focus (from the plan)
| Case | Expected | Auto | Manual |
|---|---|---|---|
| Loosely typed server URL (`nas.local/`, `/bytestash`, `…/api`, `…/login`) | normalised, no double slashes | ✅ ServerURLTests | ☐ |
| Token expires mid-use (app, share extension, intents) | clean sign-out to login; share keeps code | ✅ SessionManager/Capture/Intent tests | ☐ |
| Editing a public snippet | stays public, nothing dropped | ✅ SnippetEditorModelTests | ☐ |
| 5,000-line paste, empty selection, URL-only share, CRLF | fast; Save disabled when empty; CRLF → LF | ✅ Detector/Capture/Loader tests | ☐ |
| No network | cached list + Offline banner; edits kept with retryable error | ✅ List/Editor tests | ☐ |

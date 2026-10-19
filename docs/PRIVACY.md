# ByteCache Privacy Policy

_Last updated: 2026-10-19_

ByteCache is an unofficial client for ByteStash, the self-hosted code snippet manager.

**ByteCache collects no data.** There is no analytics, tracking, advertising or crash reporting, and no ByteCache server.

- **Your snippets** go only to the ByteStash server address you enter, over the connection you configure (use HTTPS).
- **Your logins** (each server's address, username and session token or API key) are stored in the Apple Keychain on your device and shared only with ByteCache's own share extension. Your password is never stored. Removing a server in Settings → Servers deletes its login from the device.
- **Recently viewed snippets** are cached on your device so you can read them offline. Signing out or changing server stops using them; deleting the app removes them.
- **Clipboard:** ByteCache only checks whether the clipboard contains text. It reads the text only when you tap Paste.
- **Language detection** runs entirely on your device.
- **Scanning code** (camera, photos, images) uses Apple's on-device text recognition. Pictures are not stored or sent anywhere; only the text you choose to save goes to your server.
- **Smart suggestions** (optional) use Apple Intelligence on your device to propose a title, description and categories. Your code is not sent anywhere.
- **App Lock** uses Face ID / Touch ID / Optic ID or your passcode through iOS/macOS; ByteCache never sees biometric data.
- **Widgets** show pinned and recent snippets from a small file stored only on your device (hidden while App Lock is on).
- **iCloud sync** (optional, on by default; Settings → iCloud Sync): your display settings and the list of server addresses are stored in your private iCloud key-value storage so your other devices match. Logins, API keys, user names and snippets are never put in iCloud.
- **Handoff** (optional, on by default; Settings → Handoff): while you view a snippet, your other devices on the same Apple Account are offered the server address and snippet number so they can open it.
- **Share links** are created on your ByteStash server only when you ask; anyone with a link (or, if you chose so, any signed-in user of that server) can view that snippet until it expires or you revoke it.
- **Importing a GitHub Gist** fetches it from `api.github.com` without signing in; nothing else is sent to GitHub.
- **Offline saves:** snippets you save while offline are kept in a file on your device (shared with ByteCache's extensions) until they upload to your server or you discard them.
- **Most Used** counts how often you copy each snippet, on your device only.
- **Backups** you export are files you choose where to put; ByteCache keeps no copy.
- **Update check** (optional, on by default; Settings → About → Updates): once a day ByteCache asks GitHub's public API (`api.github.com`) for the latest ByteCache release, to tell you about new versions. The request carries nothing about you or your snippets; GitHub sees your IP address, as with any web request.
- **Spotlight:** titles and the first lines of recently viewed snippets are indexed on your device so Spotlight can find them. Signing out removes them from the index.

Questions: open an issue in the ByteCache repository.

# ByteCatch Privacy Policy

_Last updated: 2026-10-19_

ByteCatch is an unofficial client for ByteStash, the self-hosted code snippet manager.

**ByteCatch collects no data.** There is no analytics, tracking, advertising or crash reporting, and no ByteCatch server.

- **Your snippets** go only to the ByteStash server address you enter, over the connection you configure (use HTTPS).
- **Your logins** (each server's address, username and session token or API key) are stored in the Apple Keychain on your device and shared only with ByteCatch's own share extension. Your password is never stored. Removing a server in Settings → Servers deletes its login from the device.
- **Recently viewed snippets** are cached on your device so you can read them offline. Signing out or changing server stops using them; deleting the app removes them.
- **Clipboard:** ByteCatch only checks whether the clipboard contains text. It reads the text only when you tap Paste.
- **Language detection** runs entirely on your device.
- **iCloud sync** (optional, on by default; Settings → iCloud Sync): your display settings and the list of server addresses are stored in your private iCloud key-value storage so your other devices match. Logins, API keys, user names and snippets are never put in iCloud.
- **Handoff** (optional, on by default; Settings → Handoff): while you view a snippet, your other devices on the same Apple Account are offered the server address and snippet number so they can open it.
- **Spotlight:** titles and the first lines of recently viewed snippets are indexed on your device so Spotlight can find them. Signing out removes them from the index.

Questions: open an issue in the ByteCatch repository.

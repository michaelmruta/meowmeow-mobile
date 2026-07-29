# App Review Notes

Meow Music Player is a player for audio files supplied by the user. It does not provide a music catalog, streaming subscription, purchases, or downloadable copyrighted content.

No account or sign-in is required.

## How to test

1. Open the **Sync** tab.
2. Under **Local Storage**, tap **Choose…**
3. Select a folder in Files containing supported audio files.
4. Tap **Sync Now**.
5. Open **Browse** and select an artist, album, or song.

Alternatively, use Finder file sharing to place audio inside Meow Music Player’s `Downloads` folder, then reopen the app or refresh the library.

WebDAV is optional. If tested, enter an HTTPS WebDAV URL (or a private/local-network HTTP URL), credentials, and the optional remote folder. Credentials are stored in the system Keychain.

Artwork and lyrics lookups are optional user-initiated actions in the metadata editor. The app contacts Apple’s iTunes Search service for artwork and LRCLIB for lyrics.

The app uses only system-provided encryption through HTTPS and the Apple Keychain. It does not implement proprietary encryption.

## Review contact

- First name: `[REQUIRED]`
- Last name: `[REQUIRED]`
- Phone: `[REQUIRED]`
- Email: `[REQUIRED]`

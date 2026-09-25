# Security Policy

## Reporting a vulnerability

Please don't open a public issue for security problems. Instead, report them
privately using GitHub's **Report a vulnerability** button on the repository's
Security tab.

Include steps to reproduce and the potential impact. You'll get an
acknowledgement, and a fix will be prioritized based on severity.

## Scope

Of particular interest:

- Exposure of Plex access tokens (for example in logs, URLs or caches)
- Ways a media server or plex.tv response could compromise the app
- Weaknesses in how credentials are stored on the device

## How RetroGuide.TV handles credentials

- Plex tokens are stored in the Apple TV keychain and are never written to
  preferences or caches.
- The app only talks to plex.tv and to the media servers you connect.
- Debug-only developer conveniences are compiled out of release builds.

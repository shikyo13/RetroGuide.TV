# Contributing to RetroGuide.TV

Thanks for your interest in improving RetroGuide.TV!

## Reporting bugs

Open an issue with:

- What you did, what you expected and what happened instead
- Your Apple TV model and tvOS version
- Your media server and version (for example Plex Media Server 1.43)
- For playback problems, the file's container and codecs (Plex shows these under
  *Get Info*) and whether the server is on your home network

Please don't include server addresses, tokens or screenshots containing account
details.

## Suggesting features

Open an issue describing the problem you'd like solved. Ideas for new built-in
channels are especially welcome; see "Adding a built-in channel" in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep changes focused; one feature or fix per pull request.
3. Follow the existing structure and conventions (see
   [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):
   - Pure logic goes in `Packages/RetroGuideKit`, with tests.
   - UI uses the design system (tokens, theme, shared components), not literal values.
   - Swift 6 strict concurrency must stay warning-free.
4. Run the tests and build the app:
   ```bash
   swift test --package-path Packages/RetroGuideKit
   xcodebuild -project RetroGuide.xcodeproj -scheme RetroGuide \
     -destination 'generic/platform=tvOS Simulator' build
   ```
5. For UI changes, include a screenshot or short description of what you
   verified in the Apple TV simulator.
6. Use [Conventional Commits](https://www.conventionalcommits.org) for commit
   messages (for example `feat(guide): …`, `fix(playback): …`).

If you change `project.yml`, run `xcodegen generate` and commit the regenerated
project.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By participating
you agree to uphold it.

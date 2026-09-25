# Third-party notices

RetroGuide.TV is licensed under the MIT License (see `LICENSE`). The app bundles
the following third-party software.

## MPVKit (libmpv, FFmpeg and bundled dependencies)

- Source: https://github.com/mpvkit/MPVKit (version pinned in `project.yml`)
- License: GNU Lesser General Public License v3.0 (`LICENSES/LGPL-3.0.txt`)
- Upstream projects: mpv (https://mpv.io), FFmpeg (https://ffmpeg.org)

RetroGuide.TV links the LGPL build of MPVKit (the `MPVKit` product, not
`MPVKit-GPL`). Because RetroGuide.TV is open source, you can rebuild it against a
modified version of these libraries: replace the MPVKit package version or path in
`project.yml`, run `xcodegen generate`, and build.

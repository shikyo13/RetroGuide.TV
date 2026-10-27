#!/bin/bash
# Refreshes App/Resources/cacert.pem, the certificate authorities the video
# player (mpv/FFmpeg over GnuTLS, which can't use Apple's trust store) checks
# server certificates against. Source: curl's extract of Mozilla's root store,
# checked against its published SHA-256.
#
# Roots listed in DISTRUSTED are left out. The player can't check revocation,
# so a root whose intermediates are compromised has to go entirely:
#   emSign (eMudhra): eight intermediate keys compromised, October 2026.
#
# Usage (from the repository root): Tools/CABundle/update-ca-bundle.sh
set -euo pipefail
SOURCE="https://curl.se/ca/cacert.pem"
OUTPUT="App/Resources/cacert.pem"
DISTRUSTED='^emSign'
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -fsSL "$SOURCE" -o "$WORK/cacert.pem"
curl -fsSL "$SOURCE.sha256" -o "$WORK/cacert.pem.sha256"
(cd "$WORK" && shasum -a 256 -c cacert.pem.sha256 >/dev/null) || { echo "checksum mismatch" >&2; exit 1; }
# Each certificate is a blank line, its name, a rule, then the PEM block.
awk -v distrusted="$DISTRUSTED" '
  BEGIN { RS = ""; ORS = "\n\n" }
  { split($0, lines, "\n"); if (lines[1] !~ distrusted) print }
' "$WORK/cacert.pem" > "$OUTPUT"
removed=$(( $(grep -c "BEGIN CERTIFICATE" "$WORK/cacert.pem") - $(grep -c "BEGIN CERTIFICATE" "$OUTPUT") ))
echo "$(grep -c "BEGIN CERTIFICATE" "$OUTPUT") certificates written to $OUTPUT ($removed distrusted left out)"
grep -m1 "as of:" "$OUTPUT"

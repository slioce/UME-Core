#!/bin/sh
# Prints the Sparkle appcast OpenEmu's core updater reads: one item, the latest release.
# Usage: make-appcast.sh <version> <owner/repo> <zip> <minimum macOS>
set -e
VERSION=$1 REPO=$2 ZIP=$3 MINOS=$4
URL="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")"
LENGTH=$(stat -f %z "$ZIP")
DATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MAME</title>
    <link>https://raw.githubusercontent.com/$REPO/master/appcast.xml</link>
    <description>MAME core for OpenEmu: most recent version.</description>
    <language>en</language>
    <item>
      <title>MAME Version $VERSION</title>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <pubDate>$DATE</pubDate>
      <enclosure url="$URL" sparkle:version="$VERSION" type="application/octet-stream" length="$LENGTH"/>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
XML

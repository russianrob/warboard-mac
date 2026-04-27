#!/usr/bin/env python3
"""Generate / update appcast.xml for Sparkle 2.x.

Runs in CI on tag pushes after the DMG is signed. Reads the existing
appcast.xml (if any), prepends a fresh <item> for the new release, and
writes the file back. Sparkle clients fetch this from the SUFeedURL in
Info.plist (raw.githubusercontent.com/.../main/appcast.xml) and pick
the highest sparkle:version they haven't installed yet.

Inputs (env vars):
  VERSION         — semver string, e.g. "0.5.0"
  DMG_URL         — public download URL for the signed DMG
  DMG_LENGTH      — byte size of the DMG (Sparkle uses for progress)
  ED_SIGNATURE    — base64 Ed25519 signature from sign_dmg.py
  RELEASE_NOTES   — plain-text body (becomes <description>)

Output: appcast.xml in cwd.
"""
import datetime
import html
import os
import re
import sys
from pathlib import Path


def must(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        sys.exit(f"missing env: {name}")
    return v


def main() -> int:
    version = must("VERSION")
    dmg_url = must("DMG_URL")
    length = must("DMG_LENGTH")
    sig = must("ED_SIGNATURE")
    notes = os.environ.get("RELEASE_NOTES", "").strip()

    pub_date = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )

    # Sparkle treats sparkle:version as the build number / monotonic
    # version; sparkle:shortVersionString is the user-facing string.
    # We use the same value for both — we don't have a separate build
    # counter and CFBundleVersion is "1" in the project.
    new_item = (
        "    <item>\n"
        f"      <title>Warboard {html.escape(version)}</title>\n"
        f"      <pubDate>{pub_date}</pubDate>\n"
        f"      <sparkle:version>{html.escape(version)}</sparkle:version>\n"
        f"      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>\n"
        f"      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"      <description><![CDATA[{notes}]]></description>\n"
        f"      <enclosure url=\"{html.escape(dmg_url)}\"\n"
        f"                 length=\"{html.escape(length)}\"\n"
        f"                 type=\"application/octet-stream\"\n"
        f"                 sparkle:edSignature=\"{html.escape(sig)}\"/>\n"
        "    </item>\n"
    )

    appcast = Path("appcast.xml")
    if appcast.is_file():
        existing = appcast.read_text(encoding="utf-8")
        # Drop any prior item with the same sparkle:version so
        # re-running the workflow on an existing tag doesn't duplicate.
        pattern = re.compile(
            r"    <item>\s*?<title>Warboard "
            + re.escape(version)
            + r"</title>.*?</item>\s*",
            re.DOTALL,
        )
        existing = pattern.sub("", existing)
        # Insert the new item right after <channel>'s opening tag so
        # Sparkle sees newest-first ordering (it doesn't actually sort,
        # but humans reading the file appreciate it).
        new_appcast = existing.replace(
            "<channel>",
            "<channel>\n" + new_item.rstrip() + "\n",
            1,
        )
    else:
        new_appcast = (
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            "<rss version=\"2.0\""
            " xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\""
            " xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
            "  <channel>\n"
            "    <title>Warboard</title>\n"
            "    <link>https://github.com/russianrob/warboard-mac</link>\n"
            "    <description>Warboard for Mac — auto-update feed.</description>\n"
            "    <language>en</language>\n"
            + new_item
            + "  </channel>\n"
            "</rss>\n"
        )
    appcast.write_text(new_appcast, encoding="utf-8")
    print(f"Wrote appcast.xml with version {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Генерує appcast.xml для Sparkle (одна, остання версія).

    make-appcast.py --version 1.2.0 --url <zip-url> --signature "sparkle:edSignature=... length=..." \
                    --notes notes.md --page <release-page-url> > appcast.xml

Опис змін (markdown з повідомлення тегу) перетворюється на простий HTML,
який Sparkle показує у вікні оновлення.
"""
import argparse
import html
import re
from email.utils import formatdate


def markdown_to_html(text: str) -> str:
    """Мінімальний markdown: заголовки, списки, **жирний**, `код`, абзаци."""
    out, in_list = [], False

    def inline(s: str) -> str:
        s = html.escape(s)
        s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
        s = re.sub(r"`(.+?)`", r"<code>\1</code>", s)
        return s

    for raw in text.splitlines():
        line = raw.rstrip()
        item = re.match(r"^\s*[-*]\s+(.*)", line)
        if item:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(item.group(1))}</li>")
            continue
        if in_list and line.startswith("  ") and line.strip():
            # Продовження пункту списку (наприклад, переклад на другому рядку).
            out[-1] = out[-1][:-5] + "<br>" + inline(line.strip()) + "</li>"
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        heading = re.match(r"^(#{1,6})\s+(.*)", line)
        if heading:
            level = min(len(heading.group(1)) + 1, 6)
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        elif line.strip():
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--signature", required=True, help='output of sign_update: sparkle:edSignature="…" length="…"')
    p.add_argument("--notes", required=True)
    p.add_argument("--page", required=True)
    p.add_argument("--min-system", default="14.0")
    args = p.parse_args()

    if not re.fullmatch(r'\s*sparkle:edSignature="[^"]+"\s+length="\d+"\s*', args.signature):
        raise SystemExit(f"Unexpected signature format: {args.signature!r}")

    with open(args.notes, encoding="utf-8") as f:
        notes_html = markdown_to_html(f.read())
    style = ("<style>body{font:13px -apple-system,sans-serif} h2,h3{margin:.6em 0 .3em} "
             "ul{padding-left:1.2em} code{font:12px ui-monospace,monospace}</style>")

    v = html.escape(args.version)
    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Easy CamSorter</title>
    <link>{html.escape(args.page)}</link>
    <item>
      <title>Easy CamSorter {v}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{v}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(args.min_system)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{html.escape(args.page)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{style}
{notes_html}]]></description>
      <enclosure url="{html.escape(args.url)}" type="application/octet-stream" {args.signature.strip()}/>
    </item>
  </channel>
</rss>""")


if __name__ == "__main__":
    main()

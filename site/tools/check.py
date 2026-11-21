#!/usr/bin/env python3
"""Static checks for the landing site. No browser or dependencies.

Run from the repository root:
    python3 site/tools/check.py
"""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re
import sys

SITE = Path(__file__).resolve().parent.parent
INDEX = SITE / "index.html"
REQUIRED_META = [
    'name="viewport"',
    'name="description"',
    'rel="canonical"',
    'property="og:image"',
    'name="twitter:card"',
]


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.anchors = []
        self.assets = []
        self.images = []
        self.meta = []
        self.scripts = []
        self.text = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "id" in values:
            self.ids.add(values["id"])
        if tag == "a" and values.get("href"):
            self.anchors.append(values["href"])
        if tag in {"img", "source"}:
            if values.get("src"):
                self.assets.append(values["src"])
            for candidate in (values.get("srcset") or "").split(","):
                candidate = candidate.strip().split(" ")[0]
                if candidate:
                    self.assets.append(candidate)
            if tag == "img":
                self.images.append(values)
        if tag == "link" and values.get("href"):
            self.assets.append(values["href"])
            self.meta.append(str(attrs))
        if tag == "meta":
            self.meta.append(str(attrs))
        if tag == "script" and values.get("type") == "application/ld+json":
            self.scripts.append(values)
        if tag in {"script", "style"}:
            self._skip += 1

    def handle_endtag(self, tag):
        if tag in {"script", "style"} and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip:
            self.text.append(data)


def is_external(url):
    return url.startswith(("http://", "https://", "mailto:", "data:"))


def main():
    failures = []
    html = INDEX.read_text(encoding="utf-8")
    page = Page()
    page.feed(html)

    for needle in REQUIRED_META:
        if needle not in html:
            failures.append(f"missing head metadata: {needle}")

    for href in page.anchors:
        if href.startswith("#") and len(href) > 1 and href[1:] not in page.ids:
            failures.append(f"unresolved anchor: {href}")

    for raw in page.assets:
        if not raw or raw.startswith(("#", "data:", "mailto:")):
            continue
        if is_external(raw):
            if raw.startswith("http://"):
                failures.append(f"insecure asset URL: {raw}")
            continue
        path = unquote(urlsplit(raw).path)
        if not (SITE / path.lstrip("./")).exists():
            failures.append(f"missing local asset: {raw}")

    for image in page.images:
        for attribute in ("width", "height", "alt"):
            if attribute not in image:
                failures.append(f"image without {attribute}: {image.get('src', '?')}")

    visible = " ".join(page.text)
    if re.search(r"[\u2013\u2014]", visible):
        failures.append("visible text contains an em dash or en dash")

    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.S):
        try:
            json.loads(block)
        except json.JSONDecodeError as error:
            failures.append(f"invalid JSON-LD: {error}")

    for name in ("styles.css", "main.js", "robots.txt", "sitemap.xml", "404.html"):
        if not (SITE / name).exists():
            failures.append(f"missing site file: {name}")

    for extra in ("assets/brand/og-image-1200x630.png", "assets/brand/favicon.ico",
                  "assets/shots/checkup.webp", "assets/shots/results.webp"):
        if not (SITE / extra).exists():
            failures.append(f"missing brand/screenshot asset: {extra}")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1

    print(f"Site checks passed: {len(page.ids)} ids, {len(page.anchors)} links, "
          f"{len(page.images)} images, {len(page.assets)} assets.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

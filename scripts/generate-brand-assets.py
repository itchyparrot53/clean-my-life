#!/usr/bin/env python3
"""Generate the repo's brand images from the app icon and wordmark.

Run after a brand change:
    python3 scripts/generate-brand-assets.py

Needs Pillow (pip install pillow). Outputs:
    docs/brand/readme-hero.png              README banner
    site/assets/brand/og-image-1200x630.png social card
    site/assets/brand/app-icon-1024.png     site icon
    site/assets/brand/wordmark-white.png    site wordmark
    site/assets/brand/apple-touch-icon-180x180.png
    site/assets/brand/favicon.ico
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "assets" / "app_icon.png"
WORDMARK = ROOT / "Sources" / "MacClean" / "BrandAssets" / "Wordmark_White.png"
FONT = "/System/Library/Fonts/Avenir Next.ttc"

INK = (26, 20, 38)
LAVENDER = (201, 167, 245)
PINK = (243, 163, 199)
CYAN = (92, 200, 240)
WHITE = (255, 255, 255)


def font(size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size, index=index)


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        row = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(width):
            pixels[x, y] = row
    return image


def glow(image: Image.Image, centre: tuple[int, int], radius: int, colour: tuple[int, int, int], strength: int) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse(
        (centre[0] - radius, centre[1] - radius, centre[0] + radius, centre[1] + radius),
        fill=(*colour, strength),
    )
    layer = layer.filter(ImageFilter.GaussianBlur(radius // 2))
    image.alpha_composite(layer)


def rounded_pill(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, face: ImageFont.FreeTypeFont, pad: int = 18) -> int:
    left, top = xy
    box = draw.textbbox((0, 0), text, font=face)
    width = box[2] - box[0] + pad * 2
    height = box[3] - box[1] + pad
    draw.rounded_rectangle((left, top, left + width, top + height), radius=height // 2,
                           fill=(18, 13, 28, 150), outline=(255, 255, 255, 70), width=1)
    draw.text((left + pad, top + pad // 2 - 2), text, font=face, fill=(242, 236, 252, 245))
    return width


def wordmark(size: int) -> Image.Image:
    mark = Image.open(WORDMARK).convert("RGBA")
    ratio = size / mark.height
    return mark.resize((round(mark.width * ratio), size), Image.LANCZOS)


def make_hero() -> None:
    image = gradient((1600, 540), (24, 18, 36), (52, 30, 66)).convert("RGBA")
    glow(image, (250, 460), 420, PINK, 46)
    glow(image, (1330, 90), 460, CYAN, 30)
    glow(image, (1040, 470), 380, LAVENDER, 40)

    mark = wordmark(196)
    image.alpha_composite(mark, (86, 96))

    draw = ImageDraw.Draw(image)
    draw.text((92, 318), "The open-source Mac cleaner, optimizer,",
              font=font(38, 2), fill=(244, 238, 252, 245))
    draw.text((92, 368), "and malware scanner.",
              font=font(38, 2), fill=(244, 238, 252, 245))

    face = font(22, 2)
    x = 94
    for label in ["macOS 14+", "Swift 6", "BSD-3", "No telemetry"]:
        x += rounded_pill(draw, (x, 444), label, face) + 12

    image.convert("RGB").save(ROOT / "docs" / "brand" / "readme-hero.png", optimize=True)


def make_og() -> None:
    image = gradient((1200, 630), (24, 18, 36), (52, 30, 66)).convert("RGBA")
    glow(image, (170, 520), 360, PINK, 42)
    glow(image, (1080, 90), 420, CYAN, 28)
    glow(image, (900, 560), 340, LAVENDER, 34)

    icon = Image.open(ICON).convert("RGBA").resize((248, 248), Image.LANCZOS)
    image.alpha_composite(icon, (84, 188))

    draw = ImageDraw.Draw(image)
    draw.text((382, 178), "Clean My Life", font=font(76, 0), fill=WHITE)
    draw.text((386, 288), "Your Mac, clean. For life.", font=font(30, 2), fill=(214, 198, 236))
    draw.text((386, 334), "25 tools. A deeper malware scan. Zero telemetry.",
              font=font(23, 2), fill=(176, 160, 202))

    face = font(19, 2)
    x = 386
    for label in ["macOS 14+", "Swift 6", "BSD-3", "Open source"]:
        x += rounded_pill(draw, (x, 408), label, face) + 10

    draw.text((86, 548), "github.com/itchyparrot53/clean-my-life",
              font=font(19, 2), fill=(201, 184, 226))

    image.convert("RGB").save(ROOT / "site" / "assets" / "brand" / "og-image-1200x630.png", optimize=True)


def make_icons() -> None:
    icon = Image.open(ICON).convert("RGBA")
    target = ROOT / "site" / "assets" / "brand"
    icon.resize((1024, 1024), Image.LANCZOS).save(target / "app-icon-1024.png", optimize=True)
    icon.resize((512, 512), Image.LANCZOS).save(target / "app-icon-512.png", optimize=True)
    icon.resize((180, 180), Image.LANCZOS).save(target / "apple-touch-icon-180x180.png", optimize=True)
    icon.resize((32, 32), Image.LANCZOS).save(target / "favicon-32.png", optimize=True)
    icon.save(target / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

    mark = Image.open(WORDMARK).convert("RGBA")
    mark.save(target / "wordmark-white.png", optimize=True)


def main() -> None:
    (ROOT / "docs" / "brand").mkdir(parents=True, exist_ok=True)
    (ROOT / "site" / "assets" / "brand").mkdir(parents=True, exist_ok=True)
    make_hero()
    make_og()
    make_icons()
    for path in [
        ROOT / "docs" / "brand" / "readme-hero.png",
        ROOT / "site" / "assets" / "brand" / "og-image-1200x630.png",
        ROOT / "site" / "assets" / "brand" / "app-icon-1024.png",
        ROOT / "site" / "assets" / "brand" / "apple-touch-icon-180x180.png",
        ROOT / "site" / "assets" / "brand" / "favicon.ico",
    ]:
        print(f"{path.relative_to(ROOT)}  {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()

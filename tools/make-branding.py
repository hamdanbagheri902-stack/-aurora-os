#!/usr/bin/env python3
"""make-branding.py — draw the original installer artwork (no third-party assets).

Creates in --out: logo.png (256x256), welcome.png (640x300) and
slide1.png..slide3.png (800x440). Needs python3-pil and fonts-dejavu-core.
The look: a deep-night gradient with soft "aurora" light ribbons.
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

NIGHT_TOP = (10, 16, 40)
NIGHT_BOTTOM = (18, 52, 86)
RIBBONS = [(64, 224, 180), (90, 160, 255), (170, 120, 255)]
FONT_DIRS = ["/usr/share/fonts/truetype/dejavu"]


def font(size: int, bold: bool = False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for d in FONT_DIRS:
        path = os.path.join(d, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def gradient(w: int, h: int) -> Image.Image:
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(a + (b - a) * t) for a, b in zip(NIGHT_TOP, NIGHT_BOTTOM))
        draw.line([(0, y), (w, y)], fill=c)
    return img


def ribbons(w: int, h: int, seed: float = 0.0, strength: int = 120) -> Image.Image:
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for i, color in enumerate(RIBBONS):
        base = h * (0.35 + 0.12 * i)
        amp = h * (0.10 + 0.03 * i)
        phase = seed + i * 1.7
        for k in range(18):
            off = k * 2.2
            pts = [(x, base + off + amp * math.sin(x / w * 2.4 * math.pi + phase)
                    + amp * 0.35 * math.sin(x / w * 5.1 * math.pi + phase * 2))
                   for x in range(0, w + 8, 8)]
            alpha = max(0, strength - k * 6)
            draw.line(pts, fill=color + (alpha,), width=3)
    return layer.filter(ImageFilter.GaussianBlur(radius=max(4, w // 90)))


def compose(w: int, h: int, seed: float) -> Image.Image:
    base = gradient(w, h).convert("RGBA")
    return Image.alpha_composite(base, ribbons(w, h, seed))


def logo(size: int = 256) -> Image.Image:
    scale = 4  # draw big, shrink = smooth edges
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, s - 1, s - 1], fill=255)
    disc = compose(s, s, seed=0.8)
    img.paste(disc, (0, 0), mask)
    draw = ImageDraw.Draw(img)
    # three arcs rising like light over a horizon
    for i, color in enumerate(RIBBONS):
        r = s * (0.36 - i * 0.08)
        cx, cy = s / 2, s * 0.70
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=200, end=340,
                 fill=color + (255,), width=int(s * 0.045))
    draw.line([(s * 0.18, s * 0.70), (s * 0.82, s * 0.70)],
              fill=(235, 245, 255, 255), width=int(s * 0.03))
    return img.resize((size, size), Image.LANCZOS)


def centered_text(img, text, y, size, bold=False, fill=(240, 246, 255)):
    draw = ImageDraw.Draw(img)
    f = font(size, bold)
    box = draw.textbbox((0, 0), text, font=f)
    draw.text(((img.width - (box[2] - box[0])) / 2, y), text, font=f, fill=fill)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    logo().save(os.path.join(a.out, "logo.png"))

    welcome = compose(640, 300, seed=0.3)
    welcome.alpha_composite(logo(120), (260, 40))
    centered_text(welcome, f"{a.name} {a.version}", 180, 34, bold=True)
    centered_text(welcome, "Welcome", 228, 20, fill=(200, 220, 240))
    welcome.convert("RGB").save(os.path.join(a.out, "welcome.png"))

    slides = [
        (f"Welcome to {a.name}", "A clean, familiar desktop, built on Debian."),
        ("Installing...", "This usually takes 5–15 minutes. Sit back."),
        ("Almost there", "After the restart, remove the USB stick or ISO."),
    ]
    for i, (title, sub) in enumerate(slides, start=1):
        img = compose(800, 440, seed=i * 1.3)
        img.alpha_composite(logo(110), (345, 70))
        centered_text(img, title, 215, 36, bold=True)
        centered_text(img, sub, 275, 20, fill=(205, 222, 240))
        img.convert("RGB").save(os.path.join(a.out, f"slide{i}.png"))

    print(f"make-branding.py: wrote artwork to {a.out}")


if __name__ == "__main__":
    main()

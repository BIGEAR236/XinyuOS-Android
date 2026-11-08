#!/usr/bin/env python3
"""Generate Android launcher icon assets from tools/icon_source.png.

Outputs to android_icons/ (committed to the repo); tools/prepare_platforms.py
copies them over the flutter-create template res/ during builds. Re-run this
after replacing icon_source.png (square, >=512px works best).

Usage: python -X utf8 tools/make_launcher_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'tools' / 'icon_source.png'
OUT = ROOT / 'android_icons'
DENSITIES = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}
# The adaptive background must match the icon's border tone (white here) so
# launcher masks cut seamlessly into it.
BACKGROUND_COLOR = '#FFFFFF'


def main() -> None:
    img = Image.open(SRC).convert('RGB')
    side = min(img.size)
    img = img.crop(((img.width - side) // 2, (img.height - side) // 2,
                    (img.width + side) // 2, (img.height + side) // 2))
    for name, mult in DENSITIES.items():
        folder = OUT / f'mipmap-{name}'
        folder.mkdir(parents=True, exist_ok=True)
        size = round(48 * mult)
        square = img.resize((size, size), Image.LANCZOS)
        square.save(folder / 'ic_launcher.png')
        # Round variant for launchers that request a circular icon.
        big = size * 4
        mask = Image.new('L', (big, big), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
        alpha = mask.resize((size, size), Image.LANCZOS)
        circular = square.convert('RGBA')
        circular.putalpha(alpha)
        circular.save(folder / 'ic_launcher_round.png')
        # Adaptive foreground: 108dp full-bleed; launchers crop to the safe
        # zone, which only trims the image's white border.
        fg = round(108 * mult)
        img.resize((fg, fg), Image.LANCZOS).save(folder / 'ic_launcher_foreground.png')
    values = OUT / 'values'
    values.mkdir(parents=True, exist_ok=True)
    (values / 'ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<resources><color name="ic_launcher_background">{BACKGROUND_COLOR}'
        '</color></resources>\n', encoding='utf-8')
    total = sum(1 for _ in OUT.rglob('*.png'))
    print(f'OK: {total} icon PNGs + background color written to {OUT}')


if __name__ == '__main__':
    main()

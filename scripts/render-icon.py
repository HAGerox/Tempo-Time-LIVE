#!/usr/bin/env python3
"""Rasterize the existing Android vector mark (assets/AppIcon.svg) at macOS icon sizes.
Developer-only Pillow dependency; generated PNG/ICNS assets are committed.
"""
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1]
scale = 4096 / 48
image = Image.new('RGBA', (4096, 4096))
draw = ImageDraw.Draw(image)
def box(values):
    return tuple(round(value * scale) for value in values)
draw.rounded_rectangle(box((4, 4, 44, 44)), radius=round(9 * scale), fill='#FFFFFF')
draw.ellipse(box((10, 10, 38, 38)), fill='#FF5E42')
draw.rectangle(box((21.5, 16, 26.5, 32)), fill='#FFF8EE')
image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
image.save(root / 'assets/AppIcon.png')
image.save(root / 'assets/AppIcon.icns', format='ICNS')
image.save(root / 'src-tauri/icons/icon.png')
image.save(root / 'src-tauri/icons/icon.icns', format='ICNS')
image.save(root / 'src-tauri/icons/icon.ico', format='ICO')

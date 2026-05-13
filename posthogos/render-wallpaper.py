#!/usr/bin/env python3
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "archiso/airootfs/usr/share/wallpapers/PostHogOS/contents/images"
ASSETS = IMAGES / "source-assets"
OUT = IMAGES / "3840x2160.png"

WIDTH = 3840
HEIGHT = 2160
BACKGROUND_COLOR = "#e1d7c2ff"
# The website renders the texture at 100 CSS px. This wallpaper is generated at
# 3840px wide and normally displayed at 1920px in the VM, so use a 2x source tile
# to keep the visible repeat scale aligned with the homepage screenshot.
BACKGROUND_TILE_SIZE = 200
GARDEN_SIZE = 1240


def tile_background(canvas: Image.Image) -> None:
    tile = Image.open(ASSETS / "keyboard_garden_bg_light.png").convert("RGBA").resize(
        (BACKGROUND_TILE_SIZE, BACKGROUND_TILE_SIZE), Image.Resampling.LANCZOS
    )
    for y in range(0, HEIGHT, tile.height):
        for x in range(0, WIDTH, tile.width):
            canvas.alpha_composite(tile, (x, y))


def place_garden(canvas: Image.Image) -> None:
    garden = Image.open(ASSETS / "keyboard_garden_light.png").convert("RGBA")
    garden = garden.resize((GARDEN_SIZE, GARDEN_SIZE), Image.Resampling.LANCZOS)
    canvas.alpha_composite(garden, (2440, 760))


def main() -> None:
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), BACKGROUND_COLOR)
    tile_background(canvas)
    place_garden(canvas)
    canvas.convert("RGB").save(OUT, "PNG", optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()

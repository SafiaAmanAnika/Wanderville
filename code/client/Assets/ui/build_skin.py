"""Build the in-game UI skin from the supplied pack in images/.

The pack is drawn at 1000-2000 px, but a StyleBoxTexture draws its nine-patch
corners at texture size, so each piece is cropped to its visible pixels and
scaled until its frame is a sensible on-screen thickness. The margins that
Scripts/components/ui_skin.gd uses are measured on these outputs.

    python3 Assets/ui/build_skin.py   (needs Pillow; run from code/client)
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / "skin"

# source, output name, scale (or exact output size)
PIECES = [
    ("shared/panel_background", "panel", 0.30),
    ("shared/button_normal", "button_normal", 0.09),
    ("shared/button_hover", "button_hover", 0.09),
    ("shared/button_pressed", "button_pressed", 0.09),
    ("shared/button_disabled", "button_disabled", 0.09),
    ("shared/text_input", "input", 0.07),
    ("shared/text_input", "message_strip", 0.10),
    ("shared/list_slot_background", "card", 0.15),
    ("shared/progress_track", "progress_track", 0.04),
    ("shared/progress_fill", "progress_fill", 0.04),
    ("fixed/inventory_slot", "slot", 0.104),
    ("fixed/shop_card", "shop_card", 0.15),
    ("fixed/world_card_frame", "world_card", 0.18),
    ("fixed/floor_swatch", "floor_swatch", 0.075),
    ("fixed/buy_sell_button", "buy_sell", 0.0876),
    ("fixed/settings_icon", "settings_icon", (112, 104)),
    ("fixed/quantity_minus", "quantity_minus", (72, 72)),
    ("fixed/quantity_plus", "quantity_plus", (72, 72)),
]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for source, name, scale in PIECES:
        image = Image.open(HERE / "images" / f"{source}.webp").convert("RGBA")
        alpha = image.getchannel("A").point(lambda v: 255 if v > 16 else 0)
        image = image.crop(alpha.getbbox())
        if isinstance(scale, tuple):
            size = scale
        else:
            size = (round(image.width * scale), round(image.height * scale))
        image.resize(size, Image.LANCZOS).save(OUT / f"{name}.png", optimize=True)
        print(f"{name}: {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the Dark Matter Detector application icon.

The icon is drawn procedurally so the app has no runtime image dependency.
The design is a dark, rounded macOS app tile containing a stylised liquid-xenon
TPC cross-section, gold sensor ring, S1 flash, upward electron drift and an S2
flash at the liquid-gas interface.

Usage:
    python3 tools/generate_app_icon.py

The generated file is written to DarkMatterDetector/AppIcon.icns. Pass
--preview-dir to also write PNG previews at useful sizes.
"""

from __future__ import annotations

import argparse
import math
import random
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BASE = 1024
SS = 3  # supersampling factor
CANVAS = BASE * SS

CENTER = (512.0, 520.0)
CARD_BOX = (100, 100, 924, 924)
CARD_RADIUS = 185

NAVY_TOP = (10, 27, 43)
NAVY_BOTTOM = (2, 6, 12)
CYAN = (104, 236, 255)
PALE_CYAN = (190, 249, 255)
GOLD = (255, 197, 90)
PALE_GOLD = (255, 228, 152)
STEEL = (137, 164, 176)
GREEN = (78, 224, 161)
ORANGE = (255, 158, 72)
WHITE = (245, 254, 255)


def rgba(color: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], max(0, min(255, alpha))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(round(lerp(a[0], b[0], t))),
        int(round(lerp(a[1], b[1], t))),
        int(round(lerp(a[2], b[2], t))),
    )


def p(value: float) -> int:
    return int(round(value * SS))


def box(cx: float, cy: float, radius: float) -> tuple[int, int, int, int]:
    return (p(cx - radius), p(cy - radius), p(cx + radius), p(cy + radius))


def new_layer() -> Image.Image:
    return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))


def blur_layer(layer: Image.Image, radius: float) -> Image.Image:
    return layer.filter(ImageFilter.GaussianBlur(max(0.01, radius * SS)))


def add_glow(
    base: Image.Image,
    cx: float,
    cy: float,
    radius: float,
    color: tuple[int, int, int],
    alpha: int,
    blur: float,
) -> None:
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box(cx, cy, radius), fill=rgba(color, alpha))
    base.alpha_composite(blur_layer(layer, blur))


def card_mask() -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (p(CARD_BOX[0]), p(CARD_BOX[1]), p(CARD_BOX[2]), p(CARD_BOX[3])),
        radius=p(CARD_RADIUS),
        fill=255,
    )
    return mask


def make_background(mask: Image.Image) -> Image.Image:
    # Use a lower-resolution gradient and upscale it; this keeps the generator
    # fast while still giving the card a silky, continuous finish.
    y, x = np.mgrid[0:BASE, 0:BASE]
    t = np.clip(0.54 * (x / (BASE - 1)) + 0.46 * (y / (BASE - 1)), 0.0, 1.0)
    top = np.array(NAVY_TOP, dtype=np.float32)
    bottom = np.array(NAVY_BOTTOM, dtype=np.float32)
    rgb = top[None, None, :] * (1.0 - t[..., None]) + bottom[None, None, :] * t[..., None]

    # A soft blue aura lifts the detector off the background.
    distance = np.sqrt((x - 512.0) ** 2 + (y - 500.0) ** 2)
    aura = np.clip(1.0 - distance / 500.0, 0.0, 1.0) ** 2.1
    rgb = rgb + (np.array((16, 79, 108), dtype=np.float32) - rgb) * (aura[..., None] * 0.58)

    # A restrained top-left sheen catches the light like a physical app tile.
    sheen = np.clip((x + y) / (2.0 * (BASE - 1)), 0.0, 1.0)
    rgb = rgb * (0.94 + 0.08 * (1.0 - sheen[..., None]))

    image = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8),
                                       np.full((BASE, BASE), 255, dtype=np.uint8)]))
    image = image.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
    card = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    card.paste(image, (0, 0), mask)
    return card


def draw_card(canvas: Image.Image) -> None:
    mask = card_mask()

    # Ground shadow. Keeping it inside the transparent icon margin leaves the
    # icon reading cleanly at Dock sizes.
    shadow = new_layer()
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (p(CARD_BOX[0] + 2), p(CARD_BOX[1] + 18), p(CARD_BOX[2] + 2), p(CARD_BOX[3] + 18)),
        radius=p(CARD_RADIUS),
        fill=(0, 0, 0, 150),
    )
    canvas.alpha_composite(blur_layer(shadow, 30))

    card = make_background(mask)
    canvas.alpha_composite(card)


def draw_stars(canvas: Image.Image, mask: Image.Image) -> None:
    rng = random.Random(17)
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    placed = 0
    while placed < 16:
        x = rng.uniform(130, 894)
        y = rng.uniform(130, 894)
        if math.hypot(x - 512, y - 520) < 395:
            continue
        if not (mask.getpixel((p(x), p(y))) > 0):
            continue
        radius = rng.uniform(0.8, 2.0)
        alpha = rng.randint(22, 62)
        color = CYAN if rng.random() < 0.55 else WHITE
        draw.ellipse(box(x, y, radius), fill=rgba(color, alpha))
        placed += 1
    canvas.alpha_composite(layer)


def draw_annulus(
    canvas: Image.Image,
    cx: float,
    cy: float,
    radius_inner: float,
    radius_outer: float,
    color_inner: tuple[int, int, int],
    color_outer: tuple[int, int, int],
    alpha: int = 255,
) -> None:
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    step = 1
    while step <= radius_outer - radius_inner:
        radius = radius_inner + step
        t = step / max(1.0, radius_outer - radius_inner)
        color = lerp_color(color_inner, color_outer, t)
        draw.ellipse(box(cx, cy, radius), outline=rgba(color, alpha), width=max(1, SS * 2))
        step += 1
    canvas.alpha_composite(layer)


def draw_detector(canvas: Image.Image) -> None:
    cx, cy = CENTER

    # Soft halo around the nested shield so the detector separates from the
    # dark card even at small Dock sizes.
    add_glow(canvas, cx, cy, 378, (20, 108, 139), 30, 28)

    # Outer water-shield band.
    draw_annulus(canvas, cx, cy, 332, 366, (8, 39, 55), (14, 76, 99), 245)
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box(cx, cy, 366), outline=rgba(CYAN, 205), width=p(2.2))
    draw.ellipse(box(cx, cy, 332), outline=rgba((35, 118, 143), 220), width=p(1.4))
    draw.arc(box(cx, cy, 366), 188, 273, fill=rgba(PALE_CYAN, 185), width=p(2.8))
    draw.arc(box(cx, cy, 366), 52, 128, fill=rgba((8, 30, 43), 155), width=p(3.2))
    canvas.alpha_composite(layer)

    # Gd-loaded veto ring: short dashes evoke the segmented scintillator panels.
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    for index in range(32):
        start = index * (360.0 / 32.0) + 1.8
        end = start + (360.0 / 32.0) - 4.2
        draw.arc(box(cx, cy, 321), start, end, fill=rgba(GREEN, 168), width=p(4.2))
    canvas.alpha_composite(layer)

    # Titanium cryostat band with a metallic edge.
    draw_annulus(canvas, cx, cy, 296, 315, (65, 90, 101), (168, 194, 205), 255)
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box(cx, cy, 315), outline=rgba((216, 238, 245), 210), width=p(1.5))
    draw.ellipse(box(cx, cy, 296), outline=rgba((38, 58, 67), 240), width=p(2.0))
    draw.arc(box(cx, cy, 315), 188, 270, fill=rgba((239, 252, 255), 160), width=p(1.7))
    canvas.alpha_composite(layer)

    # Active liquid-xenon volume: deep blue edge, luminous cyan core.
    tpc = new_layer()
    draw = ImageDraw.Draw(tpc)
    radius = 294
    while radius > 0:
        t = 1.0 - (radius / 294.0)
        color = lerp_color((8, 34, 62), (30, 149, 200), min(1.0, t ** 0.62))
        draw.ellipse(box(cx, cy, radius), fill=rgba(color, 255))
        radius -= 2
    canvas.alpha_composite(tpc)

    add_glow(canvas, cx, cy, 260, (30, 146, 198), 82, 30)
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box(cx, cy, 294), outline=rgba((83, 226, 248), 220), width=p(2.1))
    draw.arc(box(cx, cy, 294), 190, 274, fill=rgba((190, 250, 255), 160), width=p(1.8))
    canvas.alpha_composite(layer)

    # Field-cage rings.
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    for radius in (58, 112, 166, 220, 268):
        draw.ellipse(box(cx, cy, radius), outline=rgba((92, 222, 240), 38), width=p(1.0))
    for angle in range(0, 360, 30):
        radians = math.radians(angle)
        inner = (cx + 84 * math.cos(radians), cy + 84 * math.sin(radians))
        outer = (cx + 288 * math.cos(radians), cy + 288 * math.sin(radians))
        draw.line([(p(inner[0]), p(inner[1])), (p(outer[0]), p(outer[1]))],
                  fill=rgba((95, 220, 238), 20), width=p(0.9))
    canvas.alpha_composite(layer)

    # The top/bottom PMT planes become one clean ring of gold sensor nodes in
    # this cross-section icon. The ring stays legible even at 16 px.
    add_glow(canvas, cx, cy, 263, GOLD, 70, 16)
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box(cx, cy, 263), outline=rgba(GOLD, 58), width=p(1.4))
    for index in range(40):
        angle = math.radians(index * 9.0 - 90.0)
        x = cx + 263 * math.cos(angle)
        y = cy + 263 * math.sin(angle)
        draw.ellipse(box(x + 0.7, y + 1.1, 7.0), fill=rgba((39, 24, 8), 245))
        draw.ellipse(box(x, y, 5.7), fill=rgba(GOLD, 255))
        draw.ellipse(box(x - 1.1, y - 1.2, 1.7), fill=rgba((255, 247, 204), 230))
    canvas.alpha_composite(layer)

    # A warm arc shows the liquid-gas interface responding to the S2 flash.
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.arc(box(cx, cy, 292), 246, 294, fill=rgba((255, 182, 88), 155), width=p(2.2))
    canvas.alpha_composite(blur_layer(layer, 2.2))


def line_with_glow(
    canvas: Image.Image,
    start: tuple[float, float],
    end: tuple[float, float],
    color: tuple[int, int, int],
    core_alpha: int,
    glow_alpha: int,
    core_width: float,
    glow_width: float,
    glow_blur: float,
) -> None:
    glow = new_layer()
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.line([(p(start[0]), p(start[1])), (p(end[0]), p(end[1]))],
                   fill=rgba(color, glow_alpha), width=max(1, p(glow_width)))
    for point in (start, end):
        glow_draw.ellipse(box(point[0], point[1], glow_width / 2), fill=rgba(color, glow_alpha))
    canvas.alpha_composite(blur_layer(glow, glow_blur))

    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.line([(p(start[0]), p(start[1])), (p(end[0]), p(end[1]))],
              fill=rgba(color, core_alpha), width=max(1, p(core_width)))
    for point in (start, end):
        draw.ellipse(box(point[0], point[1], core_width / 2), fill=rgba(color, core_alpha))
    canvas.alpha_composite(layer)


def draw_events(canvas: Image.Image) -> None:
    cx, cy = CENTER

    # Incoming particle. It ends at the S1 interaction point.
    start = (199, 814)
    end = (cx, cy)
    line_with_glow(canvas, start, end, (172, 241, 255), 235, 52, 2.5, 9.0, 10.0)
    line_with_glow(canvas, start, end, WHITE, 210, 0, 1.0, 0.0, 0.0)
    add_glow(canvas, start[0], start[1], 7, PALE_CYAN, 110, 5)

    # The drift column. A narrow luminous beam plus a few rising charge dots.
    drift_top = (512, 245)
    line_with_glow(canvas, (cx, cy - 8), drift_top, PALE_GOLD, 220, 78, 2.4, 13.0, 10.0)
    for index, y in enumerate((466, 424, 382, 340, 300)):
        offset = (4.0 if index % 2 == 0 else -3.0)
        add_glow(canvas, cx + offset, y, 5.2, GOLD, 110, 4.0)
        layer = new_layer()
        draw = ImageDraw.Draw(layer)
        draw.ellipse(box(cx + offset, y, 2.3), fill=rgba((255, 238, 172), 235))
        canvas.alpha_composite(layer)

    # S1: compact, cold, and very bright.
    add_glow(canvas, cx, cy, 145, (48, 201, 255), 48, 32)
    add_glow(canvas, cx, cy, 78, (105, 234, 255), 84, 19)
    add_glow(canvas, cx, cy, 34, (225, 252, 255), 230, 9)
    add_glow(canvas, cx, cy, 14, WHITE, 255, 4)

    # Four subtle diffraction spikes keep the flash from looking like a plain dot.
    rays = new_layer()
    draw = ImageDraw.Draw(rays)
    for angle in (0, 45, 90, 135):
        radians = math.radians(angle)
        inner = (cx + 34 * math.cos(radians), cy + 34 * math.sin(radians))
        outer = (cx + 111 * math.cos(radians), cy + 111 * math.sin(radians))
        draw.line([(p(inner[0]), p(inner[1])), (p(outer[0]), p(outer[1]))],
                  fill=rgba((208, 249, 255), 88), width=max(1, p(1.2)))
    canvas.alpha_composite(blur_layer(rays, 2.0))

    # S2: a warm electroluminescence burst at the liquid-gas interface.
    add_glow(canvas, drift_top[0], drift_top[1], 86, ORANGE, 55, 22)
    add_glow(canvas, drift_top[0], drift_top[1], 32, (255, 200, 111), 145, 10)
    add_glow(canvas, drift_top[0], drift_top[1], 13, (255, 247, 214), 255, 4)

    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box(drift_top[0], drift_top[1], 34), outline=rgba((255, 184, 91), 178), width=p(2.2))
    draw.ellipse(box(drift_top[0], drift_top[1], 53), outline=rgba((255, 190, 103), 90), width=p(1.2))
    canvas.alpha_composite(layer)

    for angle, radius in ((-40, 61), (24, 58), (73, 45), (146, 50)):
        radians = math.radians(angle)
        x = drift_top[0] + radius * math.cos(radians)
        y = drift_top[1] + radius * math.sin(radians)
        layer = new_layer()
        draw = ImageDraw.Draw(layer)
        draw.ellipse(box(x, y, 2.1), fill=rgba((255, 211, 142), 170))
        canvas.alpha_composite(layer)


def draw_finish(canvas: Image.Image) -> None:
    layer = new_layer()
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        (p(CARD_BOX[0]), p(CARD_BOX[1]), p(CARD_BOX[2]), p(CARD_BOX[3])),
        radius=p(CARD_RADIUS),
        outline=rgba((66, 124, 145), 210),
        width=p(2.4),
    )
    draw.rounded_rectangle(
        (p(CARD_BOX[0] + 3), p(CARD_BOX[1] + 3), p(CARD_BOX[2] - 3), p(CARD_BOX[3] - 3)),
        radius=p(CARD_RADIUS - 3),
        outline=rgba((195, 248, 255), 32),
        width=p(1.0),
    )
    canvas.alpha_composite(layer)


def build_master() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw_card(canvas)
    draw_stars(canvas, card_mask())
    draw_detector(canvas)
    draw_events(canvas)
    draw_finish(canvas)
    return canvas.resize((BASE, BASE), Image.Resampling.LANCZOS)


def write_icns(master: Image.Image, output: Path) -> None:
    entries = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    with tempfile.TemporaryDirectory(prefix="dmd-iconset-") as temporary:
        iconset = Path(temporary) / "AppIcon.iconset"
        iconset.mkdir()
        for size, name in entries:
            resized = master.resize((size, size), Image.Resampling.LANCZOS)
            resized.save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(output)],
            check=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "DarkMatterDetector" / "AppIcon.icns",
        help="Destination .icns file (default: DarkMatterDetector/AppIcon.icns)",
    )
    parser.add_argument(
        "--preview-dir",
        type=Path,
        help="Optional directory for 1024, 128 and 32 px PNG previews.",
    )
    args = parser.parse_args()

    master = build_master()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_icns(master, args.output)
    print(f"Wrote {args.output} ({args.output.stat().st_size} bytes)")

    if args.preview_dir:
        args.preview_dir.mkdir(parents=True, exist_ok=True)
        for size in (1024, 128, 32, 16):
            preview = master.resize((size, size), Image.Resampling.LANCZOS)
            preview.save(args.preview_dir / f"AppIcon-{size}.png")
        print(f"Wrote previews to {args.preview_dir}")


if __name__ == "__main__":
    main()

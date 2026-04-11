"""Generate a premium app icon for VoxScribe.

Creates a sleek microphone icon with a dark gradient background,
subtle glow effects, and modern design. Outputs all required sizes
for macOS app icon assets.
"""

import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def create_icon(size: int) -> Image.Image:
    """Create the VoxScribe app icon at the given size.

    Args:
        size: The icon dimension in pixels (square).

    Returns:
        A PIL Image with the rendered icon.
    """
    scale = size / 1024.0
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background: rounded square with dark gradient
    margin = int(size * 0.02)
    corner_radius = int(size * 0.22)

    # Draw gradient background
    for y in range(margin, size - margin):
        progress = (y - margin) / (size - 2 * margin)
        r = int(15 + progress * 10)
        g = int(15 + progress * 5)
        b = int(30 + progress * 15)
        draw.line([(margin, y), (size - margin, y)], fill=(r, g, b, 255))

    # Apply rounded corners by masking
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [margin, margin, size - margin - 1, size - margin - 1],
        radius=corner_radius,
        fill=255,
    )
    img.putalpha(mask)

    # Subtle radial glow at center-top
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    center_x = size // 2
    center_y = int(size * 0.35)
    glow_radius = int(size * 0.35)
    for r_offset in range(glow_radius, 0, -1):
        alpha = int(25 * (1 - r_offset / glow_radius))
        glow_draw.ellipse(
            [
                center_x - r_offset,
                center_y - r_offset,
                center_x + r_offset,
                center_y + r_offset,
            ],
            fill=(80, 120, 220, alpha),
        )
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # Microphone body
    mic_width = int(size * 0.18)
    mic_height = int(size * 0.30)
    mic_x = center_x - mic_width // 2
    mic_y = int(size * 0.20)
    mic_radius = mic_width // 2

    # Mic body gradient (lighter at top, darker at bottom)
    for y_pos in range(mic_y + mic_radius, mic_y + mic_height):
        progress = (y_pos - mic_y) / mic_height
        r = int(220 - progress * 40)
        g = int(225 - progress * 45)
        b = int(240 - progress * 30)
        draw.line(
            [(mic_x, y_pos), (mic_x + mic_width, y_pos)], fill=(r, g, b, 255)
        )

    # Mic top rounded cap
    draw.ellipse(
        [mic_x, mic_y, mic_x + mic_width, mic_y + mic_width],
        fill=(230, 235, 245, 255),
    )

    # Mic bottom rounded cap
    draw.ellipse(
        [
            mic_x,
            mic_y + mic_height - mic_radius,
            mic_x + mic_width,
            mic_y + mic_height + mic_radius,
        ],
        fill=(180, 185, 210, 255),
    )

    # Mic grille lines
    grille_spacing = max(3, int(size * 0.025))
    line_width = max(1, int(size * 0.004))
    for gy in range(
        mic_y + mic_radius + grille_spacing,
        mic_y + mic_height - grille_spacing,
        grille_spacing,
    ):
        draw.line(
            [(mic_x + int(mic_width * 0.2), gy), (mic_x + int(mic_width * 0.8), gy)],
            fill=(150, 155, 180, 120),
            width=line_width,
        )

    # Mic arc (the U-shaped holder)
    arc_width = int(size * 0.30)
    arc_height = int(size * 0.18)
    arc_x = center_x - arc_width // 2
    arc_y = mic_y + mic_height - int(size * 0.02)
    arc_thickness = max(2, int(size * 0.02))

    draw.arc(
        [arc_x, arc_y, arc_x + arc_width, arc_y + arc_height * 2],
        start=0,
        end=180,
        fill=(160, 170, 200, 200),
        width=arc_thickness,
    )

    # Mic stand (vertical line)
    stand_x = center_x
    stand_top = arc_y + arc_height
    stand_bottom = stand_top + int(size * 0.10)
    stand_width = max(2, int(size * 0.02))
    draw.line(
        [(stand_x, stand_top), (stand_x, stand_bottom)],
        fill=(160, 170, 200, 200),
        width=stand_width,
    )

    # Mic base (horizontal line)
    base_width = int(size * 0.14)
    draw.line(
        [
            (center_x - base_width // 2, stand_bottom),
            (center_x + base_width // 2, stand_bottom),
        ],
        fill=(160, 170, 200, 200),
        width=stand_width,
    )

    # Sound waves (right side)
    wave_center_y = mic_y + mic_height // 2
    wave_x_start = mic_x + mic_width + int(size * 0.04)
    wave_thickness = max(2, int(size * 0.015))

    for i, wave_size in enumerate([0.06, 0.10, 0.14]):
        wave_w = int(size * wave_size)
        wave_h = int(size * wave_size * 1.5)
        alpha = 200 - i * 50
        color = (100, 160, 255, alpha)
        draw.arc(
            [
                wave_x_start + int(i * size * 0.02),
                wave_center_y - wave_h // 2,
                wave_x_start + wave_w + int(i * size * 0.02),
                wave_center_y + wave_h // 2,
            ],
            start=-60,
            end=60,
            fill=color,
            width=wave_thickness,
        )

    # Sound waves (left side - mirrored)
    wave_x_end = mic_x - int(size * 0.04)
    for i, wave_size in enumerate([0.06, 0.10, 0.14]):
        wave_w = int(size * wave_size)
        wave_h = int(size * wave_size * 1.5)
        alpha = 200 - i * 50
        color = (100, 160, 255, alpha)
        draw.arc(
            [
                wave_x_end - wave_w - int(i * size * 0.02),
                wave_center_y - wave_h // 2,
                wave_x_end - int(i * size * 0.02),
                wave_center_y + wave_h // 2,
            ],
            start=120,
            end=240,
            fill=color,
            width=wave_thickness,
        )


    return img


def main():
    """Generate all macOS app icon sizes and save to the asset catalog."""
    icon_sizes = [16, 32, 64, 128, 256, 512, 1024]
    output_dir = "/Users/marc/Projects/voxscribe/VoxScribe/Resources/Assets.xcassets/AppIcon.appiconset"

    import os
    os.makedirs(output_dir, exist_ok=True)

    for icon_size in icon_sizes:
        icon = create_icon(icon_size)
        filename = f"icon_{icon_size}x{icon_size}.png"
        icon.save(os.path.join(output_dir, filename))
        print(f"Generated {filename}")

    # Generate Contents.json
    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_64x64.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_1024x1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
        ],
        "info": {"author": "xcode", "version": 1},
    }

    import json
    with open(os.path.join(output_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    print(f"\nAll icons saved to {output_dir}")


if __name__ == "__main__":
    main()

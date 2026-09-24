#!/usr/bin/env python3
"""Store artwork for OmAnnotate: preview.png, the marketplace card image.

Everything is drawn here except two images it places: the logo (icon.png) and
the settings window's own content (docs/settings.png, from
`omarchy-shell omannotate-settings capture`). Lines use the plugin's own look:
smoothed through midpoints, a faint dark edge, 80% opacity. Colors are the
Matte Black theme's (accent #E68E0D) so the picture matches a real desktop.

Run: python3 scripts/make-art.py
"""
import math
from pathlib import Path

import cairo

ROOT = Path(__file__).resolve().parents[1]
FONT = "JetBrainsMono Nerd Font"


def rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))


ACCENT = rgb("#E68E0D")
BACKGROUND = rgb("#121212")
DARKER = rgb("#0B0B0B")
FOREGROUND = rgb("#BEBEBE")
MUTED = rgb("#8A8A8D")
DIM = rgb("#3A3A3A")
EDGE_ALPHA = 0.35  # Ink.js OUTLINE_ALPHA
OPACITY = 0.8


def trace(cr, points):
    """Quadratic curves through midpoints, as Ink.svgPath draws them."""
    cr.move_to(*points[0])
    if len(points) < 3:
        cr.line_to(*points[-1])
        return
    current = points[0]
    for control, following in zip(points[1:-1], points[2:]):
        end = ((control[0] + following[0]) / 2, (control[1] + following[1]) / 2)
        cr.curve_to(current[0] + 2 / 3 * (control[0] - current[0]), current[1] + 2 / 3 * (control[1] - current[1]),
                    end[0] + 2 / 3 * (control[0] - end[0]), end[1] + 2 / 3 * (control[1] - end[1]), *end)
        current = end
    cr.line_to(*points[-1])


def line(cr, points, width, color=ACCENT, alpha=OPACITY):
    """One drawn line: grouped so the dark edge never shows through the color."""
    cr.push_group()
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    trace(cr, points)
    cr.set_source_rgba(0, 0, 0, EDGE_ALPHA)
    cr.set_line_width(width + max(2.5, width * 0.45))
    cr.stroke_preserve()
    cr.set_source_rgb(*color)
    cr.set_line_width(width)
    cr.stroke()
    cr.pop_group_to_source()
    cr.paint_with_alpha(alpha)


def loop(cx, cy, rx, ry, start=200, turn=395, wobble=0.04, steps=60):
    """A hand-drawn ellipse that overshoots its start, like a quick circle."""
    points = []
    for i in range(steps + 1):
        angle = math.radians(start + turn * i / steps)
        grow = 1 + wobble * math.sin(i / steps * math.pi * 3) + 0.06 * i / steps
        points.append((cx + rx * grow * math.cos(angle), cy + ry * grow * math.sin(angle)))
    return points


def curve(p0, p1, bend, steps=24):
    """A gently bent stroke from p0 to p1; bend is the sideways offset of its middle."""
    (x0, y0), (x1, y1) = p0, p1
    nx, ny = -(y1 - y0), x1 - x0
    length = math.hypot(nx, ny) or 1
    nx, ny = nx / length, ny / length
    return [(x0 + (x1 - x0) * t + nx * bend * 4 * t * (1 - t), y0 + (y1 - y0) * t + ny * bend * 4 * t * (1 - t))
            for t in (i / steps for i in range(steps + 1))]


def arrow(tail, tip, bend, head):
    """Shaft plus two short head strokes, drawn as separate lines like a real arrow."""
    shaft = curve(tail, tip, bend)
    (px, py), (tx, ty) = shaft[-3], tip
    angle = math.atan2(ty - py, tx - px)
    wings = [[(tx - head * math.cos(angle + side), ty - head * math.sin(angle + side)), (tx, ty)]
             for side in (math.radians(32), math.radians(-32))]
    return [shaft] + wings


def text(cr, x, y, value, size, color, bold=False):
    cr.select_font_face(FONT, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(size)
    cr.set_source_rgb(*color)
    cr.move_to(x, y)
    cr.show_text(value)


def pointer(cr, x, y, size):
    """The standard arrow cursor, white with a dark outline."""
    shape = [(0, 0), (0, 16), (4.2, 12.2), (7, 18.5), (9.6, 17.4), (6.9, 11.2), (12.4, 11.2)]
    cr.save()
    cr.translate(x, y)
    cr.scale(size / 18.5, size / 18.5)
    cr.move_to(*shape[0])
    for point in shape[1:]:
        cr.line_to(*point)
    cr.close_path()
    cr.set_source_rgb(1, 1, 1)
    cr.fill_preserve()
    cr.set_source_rgb(0, 0, 0)
    cr.set_line_width(1.2)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    cr.stroke()
    cr.restore()


def place(cr, png, x, y, height):
    """Paint a PNG scaled to a height, smoothly."""
    image = cairo.ImageSurface.create_from_png(str(png))
    scale = height / image.get_height()
    cr.save()
    cr.translate(x, y)
    cr.scale(scale, scale)
    cr.set_source_surface(image, 0, 0)
    cr.get_source().set_filter(cairo.FILTER_BEST)
    cr.paint()
    cr.restore()
    return image.get_width() * scale


def preview(path, settings_png, logo_png):
    width, height = 2400, 1200
    surface = cairo.ImageSurface(cairo.FORMAT_RGB24, width, height)
    cr = cairo.Context(surface)
    cr.set_source_rgb(*DARKER)
    cr.paint()
    cr.set_source_rgba(*FOREGROUND, 0.035)
    cr.set_line_width(1)
    for x in range(0, width, 48):
        cr.move_to(x + 0.5, 0)
        cr.line_to(x + 0.5, height)
    for y in range(0, height, 48):
        cr.move_to(0, y + 0.5)
        cr.line_to(width, y + 0.5)
    cr.stroke()

    logo = place(cr, logo_png, 96, 64, 140)
    text(cr, 96 + logo + 36, 146, "OmAnnotate", 76, FOREGROUND, bold=True)
    text(cr, 96 + logo + 36, 204, "Hold Super + Ctrl and drag to draw on any screen", 32, MUTED)

    # A shared screen: one window with a slide, in Omarchy's focused-window border.
    wx, wy, ww, wh = 96, 268, 1390, 836
    cr.set_source_rgb(*BACKGROUND)
    cr.rectangle(wx, wy, ww, wh)
    cr.fill()
    cr.set_source_rgb(*ACCENT)
    cr.set_line_width(3)
    cr.rectangle(wx + 1.5, wy + 1.5, ww - 3, wh - 3)
    cr.stroke()

    text(cr, wx + 64, wy + 110, "Launch plan", 50, FOREGROUND, bold=True)
    for i, item in enumerate(["Beta opens to 200 teams", "Pricing page ships Friday", "Support rota starts Monday"]):
        text(cr, wx + 64, wy + 210 + i * 64, "- " + item, 29, MUTED)

    base = wy + wh - 110
    heights = [170, 250, 205, 430, 300]
    bar, gap, left = 84, 40, wx + 760
    for i, value in enumerate(heights):
        x = left + i * (bar + gap)
        cr.set_source_rgb(*(FOREGROUND if i == 3 else DIM))
        cr.rectangle(x, base - value, bar, value)
        cr.fill()
        text(cr, x + 22, base + 44, f"W{i + 1}", 24, MUTED)
    cr.set_source_rgb(*DIM)
    cr.rectangle(left - 20, base, 5 * (bar + gap), 2)
    cr.fill()

    # The annotations: underline the title, circle the tallest bar, point at it.
    width_px = 11
    line(cr, curve((wx + 60, wy + 136), (wx + 402, wy + 128), -5), width_px)
    tallest_x = left + 3 * (bar + gap) + bar / 2
    line(cr, loop(tallest_x, base - 250, 96, 262), width_px)
    for part in arrow((wx + 560, wy + 300), (tallest_x - 118, base - 330), -70, 42):
        line(cr, part, width_px)
    pointer(cr, tallest_x - 112, base - 336, 46)

    # The real settings window, captured by the plugin, framed like a
    # Hyprland window border.
    card = cairo.ImageSurface.create_from_png(str(settings_png))
    scale = 1000 / card.get_height()
    cw = card.get_width() * scale
    cx, cy = width - 96 - cw, (height - 1000) / 2 + 30
    cr.set_source_rgba(0, 0, 0, 0.45)
    cr.rectangle(cx + 14, cy + 18, cw, 1000)
    cr.fill()
    cr.save()
    cr.translate(cx, cy)
    cr.scale(scale, scale)
    cr.set_source_surface(card, 0, 0)
    cr.get_source().set_filter(cairo.FILTER_BEST)
    cr.paint()
    cr.restore()
    cr.set_source_rgb(*FOREGROUND)
    cr.set_line_width(3)
    cr.rectangle(cx - 1.5, cy - 1.5, cw + 3, 1003)
    cr.stroke()
    surface.write_to_png(str(path))


if __name__ == "__main__":
    preview(ROOT / "preview.png", ROOT / "docs/settings.png", ROOT / "icon.png")
    print("Wrote preview.png")

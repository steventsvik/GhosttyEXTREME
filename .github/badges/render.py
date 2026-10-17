#!/usr/bin/env python3
"""Render a README badge as a flat SVG, so the badges never depend on a badge service.

    render.py OUT.svg LABEL MESSAGE [--color HEX] [--label-color HEX] [--logo apple]

The look matches a flat-square shields badge: 20px tall, Verdana 11px, five pixels of
padding each side. Text widths come from a small Verdana metrics table and every run
of text carries textLength, so a missing font only changes the glyphs, not the layout.
"""
import argparse
import html
import sys

# Verdana at 11px, advance widths in pixels. Anything not listed is treated as 7px.
WIDTHS = {
    " ": 3.9, ".": 3.9, ",": 4.0, ":": 4.4, "+": 9.0, "-": 5.0, "/": 5.0, "(": 4.6, ")": 4.6,
    "0": 7.0, "1": 7.0, "2": 7.0, "3": 7.0, "4": 7.0, "5": 7.0, "6": 7.0, "7": 7.0, "8": 7.0, "9": 7.0,
    "a": 6.6, "b": 6.9, "c": 5.9, "d": 6.9, "e": 6.6, "f": 3.9, "g": 6.9, "h": 6.9, "i": 3.0, "j": 3.7,
    "k": 6.4, "l": 3.0, "m": 10.6, "n": 6.9, "o": 6.7, "p": 6.9, "q": 6.9, "r": 4.7, "s": 5.8, "t": 4.3,
    "u": 6.9, "v": 6.5, "w": 9.0, "x": 6.5, "y": 6.5, "z": 5.8,
    "A": 7.5, "B": 7.6, "C": 7.7, "D": 8.4, "E": 6.9, "F": 6.3, "G": 8.5, "H": 8.3, "I": 4.6, "J": 5.0,
    "K": 7.6, "L": 6.1, "M": 9.3, "N": 8.3, "O": 8.6, "P": 6.6, "Q": 8.6, "R": 7.7, "S": 7.5, "T": 6.7,
    "U": 8.1, "V": 7.5, "W": 10.8, "X": 7.5, "Y": 6.7, "Z": 7.5,
}

LOGOS = {
    # simple-icons "apple" (CC0), 24x24 viewBox
    "apple": "M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675"
             "-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987"
             " 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662"
             "-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623"
             "-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83"
             "-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701",
}

PAD = 5
HEIGHT = 20
LOGO = 14


def width(text):
    return round(sum(WIDTHS.get(c, 7.0) for c in text), 1)


def text_on(fill, shadow):
    # Light text gets a dark shadow, dark text none: same rule as shields.
    return fill, shadow


def luminance(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.299 * r + 0.587 * g + 0.114 * b


def run(label, message, color, label_color, logo):
    label_w = width(label)
    msg_w = width(message)
    logo_w = LOGO + 3 if logo else 0
    left = PAD + logo_w + label_w + PAD
    right = PAD + msg_w + PAD
    total = left + right
    label_fill = "#fff" if luminance(label_color) < 0.6 else "#333"
    msg_fill = "#fff" if luminance(color) < 0.6 else "#333"
    title = html.escape(f"{label}: {message}")
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{total:g}" height="{HEIGHT}" '
        f'role="img" aria-label="{title}">',
        f"<title>{title}</title>",
        f'<rect width="{left:g}" height="{HEIGHT}" fill="#{label_color}"/>',
        f'<rect x="{left:g}" width="{right:g}" height="{HEIGHT}" fill="#{color}"/>',
    ]
    if logo:
        parts.append(
            f'<svg x="{PAD}" y="{(HEIGHT - LOGO) / 2:g}" width="{LOGO}" height="{LOGO}" viewBox="0 0 24 24">'
            f'<path fill="#{color}" d="{LOGOS[logo]}"/></svg>'
        )
    parts.append(
        '<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" '
        'font-size="110" text-rendering="geometricPrecision">'
    )
    lx = PAD + logo_w + label_w / 2
    mx = left + right / 2
    for x, w, text, fill in ((lx, label_w, label, label_fill), (mx, msg_w, message, msg_fill)):
        t = html.escape(text)
        parts.append(
            f'<text x="{x * 10:g}" y="140" transform="scale(.1)" fill="{fill}" '
            f'textLength="{w * 10:g}">{t}</text>'
        )
    parts.append("</g></svg>")
    return "".join(parts) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("label")
    ap.add_argument("message")
    ap.add_argument("--color", default="deb86e")
    ap.add_argument("--label-color", default="17140f")
    ap.add_argument("--logo", choices=sorted(LOGOS))
    a = ap.parse_args()
    for c in (a.color, a.label_color):
        if len(c) != 6 or any(ch not in "0123456789abcdefABCDEF" for ch in c):
            sys.exit(f"bad color {c!r}; give six hex digits")
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(run(a.label, a.message, a.color, a.label_color, a.logo))


if __name__ == "__main__":
    main()

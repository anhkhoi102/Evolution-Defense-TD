"""One colour grade for every source pack, so Kenney's teal/pink-leaning
palettes and Quaternius' colours land in the same natural, Bad North-like
range. Used on texture pixels (PIL) and material base colours (Blender).
Input/output: sRGB floats 0…1."""
import colorsys


def grade(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    deg = h * 360
    if s < 0.08:                                   # greys: slightly warm, keep value
        return tuple(min(1, max(0, c)) for c in colorsys.hsv_to_rgb(40 / 360, s * 0.5 + 0.03, v * 0.97))
    if 140 <= deg <= 195:                          # teal "greens" → leafy green
        nd = 95 + (deg - 140) * 0.35
        s, v = min(1, s * 0.95), v * 0.82
    elif 195 < deg <= 235 and s < 0.45:            # pale blue rock/stone → cool grey stone
        nd, s, v = 215, s * 0.25, v * 0.9
    elif 0 <= deg <= 30 and v > 0.6 and s < 0.7:   # salmon/pink wood → warm brown wood
        nd, s, v = 26, min(1, s * 1.05 + 0.15), v * 0.72
    elif 330 <= deg <= 360 and v > 0.6 and s < 0.6:
        nd, s, v = 22, s + 0.15, v * 0.7
    else:
        nd = deg
    return colorsys.hsv_to_rgb((nd % 360) / 360, min(1, s), min(1, v))


def grade_srgb8(px):
    r, g, b = (c / 255 for c in px[:3])
    out = grade(r, g, b)
    return tuple(int(round(c * 255)) for c in out) + tuple(px[3:])

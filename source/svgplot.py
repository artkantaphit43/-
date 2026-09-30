"""Minimal SVG plotting helpers for the pump-selection handbook.

Text is emitted as real <text> elements so Chromium shapes Thai correctly.
Colors follow a validated categorical palette; gridlines are hairline and solid.
"""
from html import escape

INK = "#1f2328"
INK2 = "#52514e"
MUTED = "#898781"
GRID = "#e6e5df"
AXIS = "#c3c2b7"
SURFACE = "#ffffff"

BLUE = "#2a78d6"
ORANGE = "#eb6834"
AQUA = "#1baf7a"
VIOLET = "#4a3aa7"
RED = "#e34948"
GREEN = "#008300"
YELLOW = "#eda100"
BLUE_L = "#86b6ef"
BLUE_D = "#104281"
BLUE_M = "#5598e7"
ORANGE_L = "#f4a582"

FONT = "'Sarabun', 'Liberation Sans', 'DejaVu Sans', sans-serif"


def fmt(v, nd=None):
    if nd is None:
        if abs(v - round(v)) < 1e-9:
            nd = 0
        else:
            nd = 1
    s = f"{v:,.{nd}f}"
    return s


def t(x, y, s, size=12, anchor="start", color=INK2, weight=400, baseline="auto",
      italic=False, extra=""):
    st = ' font-style="italic"' if italic else ""
    bl = f' dominant-baseline="{baseline}"' if baseline != "auto" else ""
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" text-anchor="{anchor}" '
            f'fill="{color}" font-weight="{weight}"{st}{bl} {extra}>{s}</text>')


def text_w(s, size=11.5):
    """Rough rendered width (px) of a Sarabun string; Thai combining marks take no width."""
    w = 0.0
    for ch in s:
        o = ord(ch)
        if o in (0x0E31,) or 0x0E34 <= o <= 0x0E3A or 0x0E47 <= o <= 0x0E4E:
            continue
        if 0x0E00 <= o <= 0x0E7F:
            w += 0.62
        elif ch == " ":
            w += 0.26
        elif ch in "il.,:;|!'()[]":
            w += 0.28
        elif ch.isupper() or ch in "mwMW%":
            w += 0.66
        else:
            w += 0.52
    return w * size


class Chart:
    _n = 0

    def __init__(self, w=680, h=360, xlim=(0, 1), ylim=(0, 1), xlabel="", ylabel="",
                 xticks=None, yticks=None, ml=64, mr=24, mt=18, mb=50,
                 xfmt=None, yfmt=None, grid=True, show_xaxis=True, ox=0, oy=0):
        self.w, self.h = w, h
        self.xlim, self.ylim = xlim, ylim
        self.ml, self.mr, self.mt, self.mb = ml, mr, mt, mb
        self.ox, self.oy = ox, oy
        self.pw = w - ml - mr
        self.ph = h - mt - mb
        self.parts = []
        self.over = []
        self.xlabel, self.ylabel = xlabel, ylabel
        self.xticks = xticks
        self.yticks = yticks
        self.xfmt = xfmt or (lambda v: fmt(v))
        self.yfmt = yfmt or (lambda v: fmt(v))
        self.grid = grid
        self.show_xaxis = show_xaxis
        self.defs = []
        Chart._n += 1
        self.uid = f"clip{Chart._n}"

    # coordinate transforms
    def X(self, x):
        a, b = self.xlim
        return self.ox + self.ml + (x - a) / (b - a) * self.pw

    def Y(self, y):
        a, b = self.ylim
        return self.oy + self.mt + self.ph - (y - a) / (b - a) * self.ph

    def _axes(self):
        out = []
        x0, x1 = self.X(self.xlim[0]), self.X(self.xlim[1])
        y0, y1 = self.Y(self.ylim[0]), self.Y(self.ylim[1])
        if self.grid:
            for v in self.yticks or []:
                y = self.Y(v)
                out.append(f'<line x1="{x0:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{y:.1f}" stroke="{GRID}" stroke-width="1"/>')
            for v in self.xticks or []:
                x = self.X(v)
                out.append(f'<line x1="{x:.1f}" y1="{y0:.1f}" x2="{x:.1f}" y2="{y1:.1f}" stroke="{GRID}" stroke-width="1"/>')
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y0:.1f}" stroke="{AXIS}" stroke-width="1.2"/>')
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x0:.1f}" y2="{y1:.1f}" stroke="{AXIS}" stroke-width="1.2"/>')
        for v in self.yticks or []:
            out.append(t(x0 - 7, self.Y(v) + 4, self.yfmt(v), 11.5, "end", MUTED,
                         extra='style="font-variant-numeric:tabular-nums"'))
        if self.show_xaxis:
            for v in self.xticks or []:
                out.append(t(self.X(v), y0 + 17, self.xfmt(v), 11.5, "middle", MUTED,
                             extra='style="font-variant-numeric:tabular-nums"'))
            if self.xlabel:
                out.append(t((x0 + x1) / 2, y0 + 38, self.xlabel, 12.5, "middle", INK2, 500))
        if self.ylabel:
            cy = (y0 + y1) / 2
            cx = self.ox + 16
            out.append(f'<text transform="translate({cx:.1f},{cy:.1f}) rotate(-90)" font-size="12.5" '
                       f'text-anchor="middle" fill="{INK2}" font-weight="500">{self.ylabel}</text>')
        return out

    # marks
    def line(self, xs, ys, color=BLUE, width=2, dash=None, opacity=1, clip=True):
        pts = []
        for x, y in zip(xs, ys):
            if y is None:
                continue
            pts.append(f"{self.X(x):.1f},{self.Y(y):.1f}")
        d = f' stroke-dasharray="{dash}"' if dash else ""
        cp = f' clip-path="url(#{self.uid})"' if clip else ""
        self.parts.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{color}" stroke-width="{width}" '
                          f'stroke-linejoin="round" stroke-linecap="round" opacity="{opacity}"{d}{cp}/>')

    def fn(self, f, x0, x1, n=120, **kw):
        xs = [x0 + (x1 - x0) * i / n for i in range(n + 1)]
        ys = [f(x) for x in xs]
        self.line(xs, ys, **kw)

    def area(self, xs, ylo, yhi, color=BLUE, opacity=0.1):
        top = [f"{self.X(x):.1f},{self.Y(y):.1f}" for x, y in zip(xs, yhi)]
        bot = [f"{self.X(x):.1f},{self.Y(y):.1f}" for x, y in zip(reversed(xs), reversed(ylo))]
        self.parts.append(f'<polygon points="{" ".join(top + bot)}" fill="{color}" opacity="{opacity}" '
                          f'clip-path="url(#{self.uid})"/>')

    def vband(self, x0, x1, color=AQUA, opacity=0.1, label=None, label_y=None, label_color=INK2, size=11.5):
        X0, X1 = self.X(x0), self.X(x1)
        yt, yb = self.Y(self.ylim[1]), self.Y(self.ylim[0])
        self.parts.insert(0, f'<rect x="{X0:.1f}" y="{yt:.1f}" width="{X1 - X0:.1f}" height="{yb - yt:.1f}" '
                             f'fill="{color}" opacity="{opacity}"/>')
        if label:
            ly = self.Y(label_y) if label_y is not None else yt + 14
            self.over.append(t((X0 + X1) / 2, ly, label, size, "middle", label_color, 500))

    def vline(self, x, color=MUTED, width=1, dash="4 3", y0=None, y1=None):
        ya = self.Y(self.ylim[0] if y0 is None else y0)
        yb = self.Y(self.ylim[1] if y1 is None else y1)
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.parts.append(f'<line x1="{self.X(x):.1f}" y1="{ya:.1f}" x2="{self.X(x):.1f}" y2="{yb:.1f}" '
                          f'stroke="{color}" stroke-width="{width}"{d}/>')

    def hline(self, y, color=MUTED, width=1, dash="4 3", x0=None, x1=None):
        xa = self.X(self.xlim[0] if x0 is None else x0)
        xb = self.X(self.xlim[1] if x1 is None else x1)
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.parts.append(f'<line x1="{xa:.1f}" y1="{self.Y(y):.1f}" x2="{xb:.1f}" y2="{self.Y(y):.1f}" '
                          f'stroke="{color}" stroke-width="{width}"{d}/>')

    def point(self, x, y, color=INK, r=5):
        self.over.append(f'<circle cx="{self.X(x):.1f}" cy="{self.Y(y):.1f}" r="{r}" fill="{color}" '
                         f'stroke="{SURFACE}" stroke-width="2"/>')

    def label(self, x, y, s, dx=0, dy=0, anchor="start", size=12, color=INK, weight=500, halo=True):
        X, Y = self.X(x) + dx, self.Y(y) + dy
        if halo:
            self.over.append(t(X, Y, s, size, anchor, SURFACE, weight,
                               extra='stroke="#fff" stroke-width="4" stroke-linejoin="round"'))
        self.over.append(t(X, Y, s, size, anchor, color, weight))

    def leader(self, x, y, lx, ly, s, anchor="start", size=12, color=INK, weight=500):
        """Label at data coords (lx,ly) with a thin connector to (x,y)."""
        X, Y = self.X(x), self.Y(y)
        LX, LY = self.X(lx), self.Y(ly)
        self.over.append(f'<line x1="{X:.1f}" y1="{Y:.1f}" x2="{LX:.1f}" y2="{LY:.1f}" stroke="{MUTED}" stroke-width="1"/>')
        off = 4 if anchor == "start" else (-4 if anchor == "end" else 0)
        self.over.append(t(LX + off, LY + 4, s, size, anchor, SURFACE, weight,
                           extra='stroke="#fff" stroke-width="4" stroke-linejoin="round"'))
        self.over.append(t(LX + off, LY + 4, s, size, anchor, color, weight))

    def arrow(self, x0, y0, x1, y1, color=INK2, width=1.3, both=False):
        self.over.append(arrow_px(self.X(x0), self.Y(y0), self.X(x1), self.Y(y1), color, width, both))

    def legend(self, items, x=None, y=None, cols=None):
        """items: list of (label, color, kind) kind in line/dash/area/dot. Wraps onto extra rows."""
        X = self.ox + self.ml + 4 if x is None else x
        Y = self.oy + 12 if y is None else y
        right = self.ox + self.w - 6
        out = []
        cx, cy = X, Y
        for lab, col, kind in items:
            wlab = 26 + text_w(lab) + 18
            if cx + wlab > right and cx > X:
                cx = X
                cy += 18
            if kind == "line":
                out.append(f'<line x1="{cx:.1f}" y1="{cy - 4:.1f}" x2="{cx + 20:.1f}" y2="{cy - 4:.1f}" stroke="{col}" stroke-width="2.4" stroke-linecap="round"/>')
            elif kind == "dash":
                out.append(f'<line x1="{cx:.1f}" y1="{cy - 4:.1f}" x2="{cx + 20:.1f}" y2="{cy - 4:.1f}" stroke="{col}" stroke-width="2.4" stroke-dasharray="5 3"/>')
            elif kind == "area":
                out.append(f'<rect x="{cx:.1f}" y="{cy - 10:.1f}" width="20" height="11" rx="2" fill="{col}" opacity="0.25"/>')
            elif kind == "dot":
                out.append(f'<circle cx="{cx + 10:.1f}" cy="{cy - 4:.1f}" r="5" fill="{col}"/>')
            out.append(t(cx + 26, cy, lab, 11.5, "start", INK2))
            cx += wlab
        self.over.append("".join(out))
        return cy

    def raw(self, s, over=True):
        (self.over if over else self.parts).append(s)

    def body(self):
        x0, y1 = self.X(self.xlim[0]), self.Y(self.ylim[1])
        clip = (f'<clipPath id="{self.uid}"><rect x="{x0:.1f}" y="{y1 - 2:.1f}" width="{self.pw:.1f}" '
                f'height="{self.ph + 4:.1f}"/></clipPath>')
        return "".join([clip] + self._axes() + self.parts + self.over)

    def svg(self):
        return wrap(self.w, self.h, self.body())


def arrow_px(X0, Y0, X1, Y1, color=INK2, width=1.3, both=False, head=7):
    import math
    ang = math.atan2(Y1 - Y0, X1 - X0)

    def headp(X, Y, a):
        p1 = (X - head * math.cos(a - 0.4), Y - head * math.sin(a - 0.4))
        p2 = (X - head * math.cos(a + 0.4), Y - head * math.sin(a + 0.4))
        return f'<polygon points="{X:.1f},{Y:.1f} {p1[0]:.1f},{p1[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}" fill="{color}"/>'
    s = f'<line x1="{X0:.1f}" y1="{Y0:.1f}" x2="{X1:.1f}" y2="{Y1:.1f}" stroke="{color}" stroke-width="{width}"/>'
    s += headp(X1, Y1, ang)
    if both:
        s += headp(X0, Y0, ang + math.pi)
    return s


def wrap(w, h, body, extra_style=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" '
            f'style="font-family:{FONT};{extra_style}" role="img">{body}</svg>')


def ticks(a, b, step):
    out = []
    v = a
    while v <= b + 1e-9:
        out.append(round(v, 10))
        v += step
    return out

"""Report pages where ink appears in the last 3 pt of the content area with no text line there."""
import sys
import pymupdf

path = sys.argv[1] if len(sys.argv) > 1 else "../pump-selection-handbook.pdf"
d = pymupdf.open(path)
bottom = 842 - 17 / 25.4 * 72
strip = pymupdf.Rect(40, bottom - 3.2, 560, bottom)
hits = []
for i, p in enumerate(d):
    if i == 0:
        continue
    covered = False
    for b in p.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            r = pymupdf.Rect(l["bbox"])
            if r.intersects(strip) and r.y1 < bottom + 3 and r.y0 < strip.y0 - 4:
                covered = True
    for dr in p.get_drawings():
        f = dr.get("fill")
        if dr["rect"].intersects(strip) and dr["rect"].height < 400 and not (f and min(f) > 0.97):
            covered = True
    if covered:
        continue
    pix = p.get_pixmap(dpi=150, clip=strip)
    s = pix.samples
    n = sum(1 for k in range(0, len(s), pix.n) if min(s[k:k + 3]) < 215)
    if n:
        hits.append((i + 1, n))
print(len(hits), hits)

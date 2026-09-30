"""Build the pump-selection handbook PDF.

    python3 build.py            -> ../pump-selection-handbook.pdf

Pipeline: calculations -> SVG figures -> HTML chapters (placeholders filled,
figures/tables numbered) -> Chromium PDF (pass 1) -> page numbers read from the
PDF outline -> table of contents filled -> Chromium PDF (pass 2).
"""
import glob
import html
import os
import re
import subprocess
import sys

import calc
import figs_charts
import figs_diagrams

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PDF = os.path.join(HERE, "..", "pump-selection-handbook.pdf")
THAI_LETTERS = ["ก", "ข", "ค", "ง", "จ", "ฉ", "ช", "ซ"]


def load_figures():
    figs = {}
    for k, f in figs_charts.CHARTS.items():
        figs[k] = f()
    for k, f in figs_diagrams.DIAGRAMS.items():
        figs[k] = f()
    return figs


def fill(text, V, FIG):
    def rep_fig(m):
        name = m.group(1)
        if name not in FIG:
            raise KeyError(f"missing figure {name}")
        return FIG[name]
    text = re.sub(r"\{\{fig:([a-z0-9_]+)\}\}", rep_fig, text)

    def rep_val(m):
        k = m.group(1)
        if k not in V:
            raise KeyError(f"missing value {k}")
        return str(V[k])
    return re.sub(r"\{\{([a-zA-Z0-9_]+)\}\}", rep_val, text)


def number_items(chapters):
    """chapters: list of (label, html). Numbers figures/tables per chapter, resolves [[ref]]."""
    refs = {}
    out = []
    for label, body in chapters:
        nf = [0]
        nt = [0]
        nx = [0]

        def fig(m):
            nf[0] += 1
            num = f"{label}.{nf[0]}" if label else f"{nf[0]}"
            fm = re.search(r'id="([^"]+)"', m.group(1))
            fid = fm.group(1) if fm else None
            if fid:
                refs[fid] = f"รูปที่ {num}"
            return m.group(0).replace("<figcaption>", f'<figcaption><b>รูปที่ {num}</b> ', 1)
        body = re.sub(r'<figure([^>]*)>.*?<figcaption>', fig, body, flags=re.S)

        def tab(m):
            nt[0] += 1
            num = f"{label}.{nt[0]}" if label else f"{nt[0]}"
            tm = re.search(r'id="([^"]+)"', m.group(1))
            tid = tm.group(1) if tm else None
            if tid:
                refs[tid] = f"ตารางที่ {num}"
            return m.group(0).replace("<caption>", f'<caption><b>ตารางที่ {num}</b> ', 1)
        body = re.sub(r'<table([^>]*)>\s*<caption>', tab, body, flags=re.S)

        nq = [0]

        def ex(m):
            if 'data-kind="q"' in (m.group(1) or ""):
                nq[0] += 1
                return m.group(0).replace('<div class="ex-title">', f'<div class="ex-title"><b>ข้อที่ {nq[0]}</b> ', 1)
            nx[0] += 1
            num = f"{label}.{nx[0]}" if label else f"{nx[0]}"
            xm = re.search(r'id="([^"]+)"', m.group(1) or "")
            xid = xm.group(1) if xm else None
            if xid:
                refs[xid] = f"ตัวอย่าง {num}"
            return m.group(0).replace('<div class="ex-title">', f'<div class="ex-title"><b>ตัวอย่าง {num}</b> ', 1)
        body = re.sub(r'<div class="box ex"([^>]*)>\s*<div class="ex-title">', ex, body, flags=re.S)

        m = re.search(r'<h1[^>]*id="([^"]+)"', body)
        if m and label:
            refs[m.group(1)] = f"บทที่ {label}" if label.isdigit() else f"ภาคผนวก {label}"
        out.append(body)

    def rep(m):
        k = m.group(1)
        if k not in refs:
            raise KeyError(f"unresolved reference {k}")
        return refs[k]
    return [re.sub(r"\[\[([a-z0-9\-_]+)\]\]", rep, b) for b in out]


def strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def add_heading_ids(doc):
    n = [0]

    def rep(m):
        tag, attrs = m.group(1), m.group(2)
        if 'id="' in attrs:
            return m.group(0)
        n[0] += 1
        return f'<{tag}{attrs} id="hd-{n[0]}">'
    return re.sub(r'<(h[12])([^>]*)>', rep, doc)


def collect_headings(doc):
    heads = []
    for m in re.finditer(r'<h([12])([^>]*)>(.*?)</h\1>', doc, flags=re.S):
        lvl = int(m.group(1))
        attrs = m.group(2)
        if "notoc" in attrs:
            continue
        inner = re.sub(r'(<span class="chno">.*?</span>)', r'\1 ', m.group(3))
        hid = re.search(r'id="([^"]+)"', attrs).group(1)
        heads.append((lvl, strip_tags(inner), attrs, hid))
    return heads


def toc_html(heads, pages):
    rows = []
    for i, (lvl, title, attrs, hid) in enumerate(heads):
        pg = pages[i] if pages and i < len(pages) else "00"
        cls = "toc-part" if "part" in attrs else ("toc-h1" if lvl == 1 else "toc-h2")
        if cls == "toc-part":
            rows.append(f'<a class="{cls}" href="#{hid}"><span class="t">{html.escape(title)}</span></a>')
        else:
            rows.append(f'<a class="{cls}" href="#{hid}"><span class="t">{html.escape(title)}</span><span class="dots"></span><span class="p">{pg}</span></a>')
    return "\n".join(rows)


def render(html_path, pdf_path):
    subprocess.run(["node", os.path.join(HERE, "render.js"), html_path, pdf_path], check=True)


def link_pages(pdf_path, heads):
    """Page numbers of headings, read from the TOC's internal link targets."""
    import pymupdf
    doc = pymupdf.open(pdf_path)
    links = []
    for pno in range(doc.page_count):
        pl = [l for l in doc[pno].get_links() if l.get("kind") in (pymupdf.LINK_GOTO, pymupdf.LINK_NAMED) and l.get("page", -1) >= 0]
        pl.sort(key=lambda l: (round(l["from"].y0, 1), l["from"].x0))
        links.extend(pl)
    pages = [str(l["page"] + 1) for l in links[:len(heads)]]
    if len(links) < len(heads):
        pages += ["?"] * (len(heads) - len(links))
    return pages, doc.page_count


def fix_outline(pdf_path, heads, pages):
    """Replace Chromium's outline (which duplicates some titles) with a clean nested one."""
    import pymupdf
    doc = pymupdf.open(pdf_path)
    toc = []
    in_part = False
    h1_level = 1
    for (lvl, title, attrs, hid), pg in zip(heads, pages):
        if not pg.isdigit():
            continue
        p = int(pg)
        if "part" in attrs:
            in_part = True
            h1_level = 1
            toc.append([1, title, p])
        elif lvl == 1:
            if "appendix" in attrs or "front" in attrs:
                in_part = False
            h1_level = 2 if in_part else 1
            toc.append([h1_level, title, p])
        else:
            toc.append([h1_level + 1, title, p])
    doc.set_toc(toc)
    doc.set_metadata({"title": "คู่มือการเลือกปั๊มสำหรับระบบผลิตน้ำประปาและระบบน้ำเสีย",
                      "subject": "สื่อการสอนการเลือกปั๊มสำหรับวิศวกร งานประปาและน้ำเสีย",
                      "keywords": "pump selection, NPSH, system curve, wastewater, water supply",
                      "creator": "build.py (HTML + Chromium)", "producer": doc.metadata.get("producer", "")})
    tmp = pdf_path + ".tmp"
    doc.save(tmp, garbage=3, deflate=True)
    doc.close()
    os.replace(tmp, pdf_path)


def main():
    V = calc.run_all()
    FIG = load_figures()
    files = sorted(glob.glob(os.path.join(HERE, "content", "*.html")))
    chapters = []
    ch_no = 0
    app_no = 0
    for f in files:
        body = open(f, encoding="utf-8").read()
        body = fill(body, V, FIG)
        label = ""
        if re.search(r'<h1[^>]*class="[^"]*chapter', body):
            ch_no += 1
            label = str(ch_no)
            body = body.replace("{{CH}}", label)
            body = re.sub(r'(<h1[^>]*class="[^"]*chapter[^"]*"[^>]*>)', r'\1<span class="chno">บทที่ ' + label + '</span>', body, count=1)
        elif re.search(r'<h1[^>]*class="[^"]*appendix', body):
            label = THAI_LETTERS[app_no]
            app_no += 1
            body = re.sub(r'(<h1[^>]*class="[^"]*appendix[^"]*"[^>]*>)', r'\1<span class="chno">ภาคผนวก ' + label + '</span>', body, count=1)
        if re.search(r'<h1[^>]*class="[^"]*(chapter|appendix|front)', body):
            body = f'<section class="pagewrap">{body}</section>'
        chapters.append((label, body))
    bodies = number_items(chapters)
    doc = add_heading_ids("\n".join(bodies))
    css = open(os.path.join(HERE, "style.css"), encoding="utf-8").read()
    heads = collect_headings(doc)

    def assemble(pages):
        d = doc.replace("<!--TOC-->", toc_html(heads, pages))
        return ('<!doctype html><html lang="th"><head><meta charset="utf-8">'
                '<title>คู่มือการเลือกปั๊มสำหรับระบบผลิตน้ำประปาและระบบน้ำเสีย</title>'
                '<link rel="stylesheet" href="fonts.css">'
                f'<style>{css}</style></head><body>{d}</body></html>')

    tmp_html = os.path.join(HERE, "_book.html")
    tmp_pdf = os.path.join(HERE, "_pass1.pdf")
    open(tmp_html, "w", encoding="utf-8").write(assemble(None))
    render(tmp_html, tmp_pdf)
    pages, n1 = link_pages(tmp_pdf, heads)
    open(tmp_html, "w", encoding="utf-8").write(assemble(pages))
    render(tmp_html, OUT_PDF)
    pages2, n2 = link_pages(OUT_PDF, heads)
    if pages2 != pages:
        print("warning: TOC page numbers shifted between passes", file=sys.stderr)
        open(tmp_html, "w", encoding="utf-8").write(assemble(pages2))
        render(tmp_html, OUT_PDF)
    os.remove(tmp_pdf)
    fix_outline(OUT_PDF, heads, pages2)
    missing = [h[1] for h, p in zip(heads, pages2) if p == "?"]
    if missing:
        print("warning: headings not found in outline:", missing, file=sys.stderr)
    print(f"built {OUT_PDF}: {n2} pages, {len(heads)} TOC entries")


if __name__ == "__main__":
    main()

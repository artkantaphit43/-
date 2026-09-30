import sys, calc
calc.run_all()
import figs_charts
mods = [figs_charts.CHARTS]
try:
    import figs_diagrams; mods.append(figs_diagrams.DIAGRAMS)
except ImportError as e:
    print("no diagrams", e)
names = sys.argv[1:]
html = ['<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="fonts.css"><style>body{font-family:Sarabun;width:174mm;margin:10mm} .f{border:1px solid #ddd;margin:0 0 8mm;break-inside:avoid} h4{margin:2mm 0}</style></head><body>']
for m in mods:
    for k, f in m.items():
        if names and k not in names: continue
        html.append(f'<h4>{k}</h4><div class="f">{f()}</div>')
html.append('</body></html>')
open('preview.html','w').write("".join(html))

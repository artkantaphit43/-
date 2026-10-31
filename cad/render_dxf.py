#!/usr/bin/env python3
"""Render cad/weir_tank.dxf เป็น PNG (แปลน / รูปตัด A-A / รูปตัด B-B) ใช้ฟอนต์ไทย Loma

ใช้งาน: python3 cad/render_dxf.py cad/weir_tank.dxf cad
"""
import sys, ezdxf
from ezdxf.addons.drawing import RenderContext, Frontend
from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
from ezdxf.addons.drawing.config import Configuration, BackgroundPolicy, ColorPolicy
from ezdxf.fonts import fonts
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
doc = ezdxf.readfile(sys.argv[1])
doc.styles.get("THAI").dxf.font = "Loma.otf"
msp = doc.modelspace()
def render(out, bbox=None, dpi=170):
    fig = plt.figure(); ax = fig.add_axes([0, 0, 1, 1])
    ctx = RenderContext(doc)
    Frontend(ctx, MatplotlibBackend(ax), config=Configuration(background_policy=BackgroundPolicy.WHITE, color_policy=ColorPolicy.BLACK)).draw_layout(msp, finalize=True)
    if bbox:
        ax.set_xlim(bbox[0], bbox[2]); ax.set_ylim(bbox[1], bbox[3])
    w, h = (bbox[2]-bbox[0], bbox[3]-bbox[1]) if bbox else (20000, 12000)
    fig.set_size_inches(14, 14*h/w)
    fig.savefig(out, dpi=dpi, facecolor="white"); plt.close(fig)
for name, bb in [("plan", (-2000, -2800, 7600, 4700)), ("section", (-1500, -8700, 8800, -3900)), ("bb", (8300, -9700, 13800, -3900))]:
    render(f"{sys.argv[2]}/cad_{name}.png", bb)
print("ok")

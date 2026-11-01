#!/usr/bin/env python3
"""สร้างโมเดล 3D ของบ่อ (หน่วย mm) สำหรับ SketchUp จากขนาดชุดเดียวกับ make_dxf.py

ได้ 3 ไฟล์:
  cad/weir_tank.dae              — SketchUp: File > Import > COLLADA (.dae)
  cad/weir_tank_sketchup.rb      — SketchUp: Window/Extensions > Ruby Console > load "…/weir_tank_sketchup.rb"

ใช้งาน: python3 cad/make_3d.py
"""
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = open(os.path.join(HERE, "..", "make_dxf.py"), encoding="utf-8").read()
exec(SRC[SRC.index("T = 200"):SRC.index("LEVELS =")])   # ใช้ค่าขนาดจาก make_dxf.py ชุดเดียวกัน

# วัสดุ: ชื่อ -> (R, G, B, ความทึบ)
MAT = {"คอนกรีต": (190, 190, 185, 1.0), "สแตนเลส": (120, 140, 170, 1.0), "ท่อ": (235, 150, 60, 1.0),
       "อุปกรณ์": (230, 160, 40, 1.0), "เครื่องวัด": (240, 240, 245, 1.0), "น้ำ": (90, 160, 220, 0.45)}
TAGS = ["คอนกรีต", "แผ่นสแตนเลส", "ท่อ", "ปั๊มและเครื่องวัด", "น้ำ"]
yc = B / 2
solids = []   # (ชื่อ, tag, วัสดุ, ชนิด, ข้อมูล)


def box(name, tag, mat, x1, x2, y1, y2, z1, z2):
    if x2 - x1 < 1 or y2 - y1 < 1 or z2 - z1 < 1:
        return
    solids.append((name, tag, mat, "box", (x1, x2, y1, y2, z1, z2)))


def prism_x(name, tag, mat, profile, x1, x2):
    """รูปตัดใน (y, z) ยื่นตามแกน x จาก x1 ถึง x2"""
    solids.append((name, tag, mat, "prism", (profile, x1, x2)))


def cyl(name, tag, mat, axis, c1, c2, r, s1, s2):
    """ทรงกระบอกตามแกน axis ('x' หรือ 'z') กึ่งกลาง (c1, c2) รัศมี r จาก s1 ถึง s2"""
    solids.append((name, tag, mat, "cyl", (axis, c1, c2, r, s1, s2)))


C, S, P, E, W = "คอนกรีต", "แผ่นสแตนเลส", "ท่อ", "ปั๊มและเครื่องวัด", "น้ำ"
yA, yB = -OFF1 - T, B + OFF1 + T
# ---- คอนกรีต ----
box("พื้นช่อง 1", C, "คอนกรีต", -T, L1, yA, yB, ZF1 - T, ZF1)
box("ผนังหัวบ่อ", C, "คอนกรีต", -T, 0, yA, yB, ZF1, ZTOP)
box("ผนังข้างช่อง 1 (ซ้าย)", C, "คอนกรีต", 0, L1 + T, yA, -OFF1, ZF1 - T, ZTOP)
box("ผนังข้างช่อง 1 (ขวา)", C, "คอนกรีต", 0, L1 + T, B + OFF1, yB, ZF1 - T, ZTOP)
box("ผนังปลายช่อง 1 (ซ้าย)", C, "คอนกรีต", L1, L1 + T, -OFF1, 0, ZF1 - T, ZTOP)
box("ผนังปลายช่อง 1 (ขวา)", C, "คอนกรีต", L1, L1 + T, B, B + OFF1, ZF1 - T, ZTOP)
box("ผนังกันน้ำกระแทก", C, "คอนกรีต", XB1, XB1 + TB1, -OFF1, B + OFF1, ZF1 + GAP1, ZTOP)
box("ช่อง 2 ขอบม่านน้ำ (ผนังปลายช่อง 1 ช่วงกลาง)", C, "คอนกรีต", L1, X2, 0, B, ZF1 - T, ZR)
box("ผนังข้างช่อง 2 (ซ้าย)", C, "คอนกรีต", L1 + T, X2, -T, 0, ZF1 - T, ZTOP)
box("ผนังข้างช่อง 2 (ขวา)", C, "คอนกรีต", L1 + T, X2, B, B + T, ZF1 - T, ZTOP)
box("พื้นช่อง 3", C, "คอนกรีต", X2, XE + T, -T, B + T, -T, 0)
box("ผนังข้างช่อง 3 (ซ้าย)", C, "คอนกรีต", X2, XE + T, -T, 0, 0, ZTOP)
box("ผนังข้างช่อง 3 (ขวา)", C, "คอนกรีต", X2, XE + T, B, B + T, 0, ZTOP)
box("ผนังท้ายบ่อ", C, "คอนกรีต", XE, XE + T, 0, B, 0, ZTOP)
box("ผนัง ① ลอดใต้", C, "คอนกรีต", XB3, XB3 + TB3, 0, B, ZB3, ZTOP)
box("ผนัง ② ล้นข้าม", C, "คอนกรีต", XS3, XS3 + TB3, 0, B, 0, ZS3)
box("กำแพงใต้แผ่นเวียร์", C, "คอนกรีต", XW, XW + TWW, 0, B, 0, ZWW)
# ---- สแตนเลส ----
w = ZN - ZV
hp = B / 2 + 100
plate = [(yc - hp, ZPB), (yc + hp, ZPB), (yc + hp, ZPT), (yc + w, ZPT), (yc + w, ZN), (yc, ZV),
         (yc - w, ZN), (yc - w, ZPT), (yc - hp, ZPT)]
prism_x("แผ่นเวียร์ V-notch 90° SS304 หนา 6", S, "สแตนเลส", plate, XW - 6, XW)
box("คาน Flow meter", S, "สแตนเลส", XT - 50, XT + 50, -T, B + T, ZTOP, ZTOP + 50)
# ---- ท่อ ----
cyl("ท่อน้ำเข้า 6\"", P, "ท่อ", "x", yc, ZIN, DPO / 2, -T - 600, 100)
cyl("ท่อน้ำออก 8\"", P, "ท่อ", "x", yc, DOUT / 2 + 20, 109, XE - 20, XE + T + 600)
# ---- ปั๊มและเครื่องวัด ----
box("ปั๊มจุ่ม 10 m³/ชม.", E, "อุปกรณ์", XP - PW / 2, XP + PW / 2, yc + 500 - PW / 2, yc + 500 + PW / 2, ZF1, ZF1 + PH)
cyl("ท่อปั๊ม recycle", E, "อุปกรณ์", "z", XP + 120, yc + 500, 30, ZF1 + PH, ZTOP + 300)
cyl("Flow meter (DL10)", E, "เครื่องวัด", "z", XT, yc, 26, ZDL, ZDL + 81)
cyl("หัววัด BOD", E, "เครื่องวัด", "z", XBOD, YBOD + 40, 30, ZBOD, ZBOD + 774)
# ---- น้ำ (ที่น้ำออกแบบ 65 m³/ชม.) ----
box("น้ำช่อง 1 (หน้าผนังกันน้ำกระแทก)", W, "น้ำ", 0, XB1, -OFF1, B + OFF1, ZF1, 958)
box("น้ำช่อง 1 (โซนปั๊ม)", W, "น้ำ", XB1 + TB1, L1, -OFF1, B + OFF1, ZF1, 958)
box("น้ำช่อง 2", W, "น้ำ", L1, X2, 0, B, ZR, ZR + 60)
box("น้ำช่อง 3", W, "น้ำ", X2, XW - 6, 0, B, 0, Z3D)
box("น้ำหลังเวียร์", W, "น้ำ", XW + TWW, XE, 0, B, 0, ZTAIL)


# ================= mesh (สำหรับ .dae และรูปตัวอย่าง) =================
def ear_clip(poly):
    pts = list(range(len(poly)))
    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in pts)
    if area < 0:
        pts.reverse()
    tris = []
    def inside(p, a, b, c):
        d = lambda u, v, w_: (u[0] - w_[0]) * (v[1] - w_[1]) - (v[0] - w_[0]) * (u[1] - w_[1])
        s1, s2, s3 = d(p, a, b), d(p, b, c), d(p, c, a)
        return not ((s1 < 0 or s2 < 0 or s3 < 0) and (s1 > 0 or s2 > 0 or s3 > 0))
    while len(pts) > 3:
        for k in range(len(pts)):
            i, j, l = pts[k - 1], pts[k], pts[(k + 1) % len(pts)]
            a, b, c = poly[i], poly[j], poly[l]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 0:
                continue
            if any(inside(poly[m], a, b, c) for m in pts if m not in (i, j, l)):
                continue
            tris.append((i, j, l)); pts.pop(k); break
    tris.append(tuple(pts))
    return tris


def mesh(kind, d):
    """คืน (จุด, หน้า polygon ที่หมุนออกด้านนอก)"""
    if kind == "box":
        x1, x2, y1, y2, z1, z2 = d
        v = [(x1, y1, z1), (x2, y1, z1), (x2, y2, z1), (x1, y2, z1), (x1, y1, z2), (x2, y1, z2), (x2, y2, z2), (x1, y2, z2)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return v, f
    if kind == "prism":
        prof, x1, x2 = d
        n = len(prof)
        v = [(x1, y, z) for y, z in prof] + [(x2, y, z) for y, z in prof]
        cap = ear_clip(prof)          # ทวนเข็ม (มองจาก +x)
        f = [tuple(reversed(t)) for t in cap] + [tuple(i + n for i in t) for t in cap]
        f += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        return v, f
    axis, c1, c2, r, s1, s2 = d
    n = 24
    ring = [(c1 + r * math.cos(2 * math.pi * k / n), c2 + r * math.sin(2 * math.pi * k / n)) for k in range(n)]
    if axis == "z":
        v = [(a, b, s1) for a, b in ring] + [(a, b, s2) for a, b in ring]
    else:
        v = [(s1, a, b) for a, b in ring] + [(s2, a, b) for a, b in ring]
    f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, (k + 1) % n + n, k + n) for k in range(n)]
    if axis == "x":   # วงแหวนในระนาบ y-z ทวนเข็มเมื่อมองจาก +x → หน้า s1 หันไป -x ถูกแล้ว
        pass
    return v, f


def tri(face):
    return [(face[0], face[k], face[k + 1]) for k in range(1, len(face) - 1)]


# ================= COLLADA (.dae) =================
def write_dae(path):
    fx, mats, geos, nodes = [], [], [], []
    for m, (r, g, b, a) in MAT.items():
        mid = f"m{list(MAT).index(m)}"
        tr = f"<transparent opaque='A_ONE'><color>1 1 1 1</color></transparent><transparency><float>{a}</float></transparency>" if a < 1 else ""
        fx.append(f"<effect id='{mid}-fx'><profile_COMMON><technique sid='c'><lambert><diffuse><color>{r/255:.3f} {g/255:.3f} {b/255:.3f} 1</color></diffuse>{tr}</lambert></technique></profile_COMMON></effect>")
        mats.append(f"<material id='{mid}' name='{m}'><instance_effect url='#{mid}-fx'/></material>")
    for i, (name, tag, mat, kind, d) in enumerate(solids):
        v, f = mesh(kind, d)
        tris = [t for face in f for t in tri(face)]
        mid = f"m{list(MAT).index(mat)}"
        pos = " ".join(f"{x:.1f} {y:.1f} {z:.1f}" for x, y, z in v)
        nrm = []
        for a_, b_, c_ in tris:
            u = [v[b_][k] - v[a_][k] for k in range(3)]; w_ = [v[c_][k] - v[a_][k] for k in range(3)]
            n_ = (u[1]*w_[2]-u[2]*w_[1], u[2]*w_[0]-u[0]*w_[2], u[0]*w_[1]-u[1]*w_[0]); L_ = math.sqrt(sum(q*q for q in n_)) or 1
            nrm.append(tuple(q / L_ for q in n_))
        nstr = " ".join(f"{x:.4f} {y:.4f} {z:.4f}" for x, y, z in nrm)
        idx = " ".join(f"{a} {t} {b} {t} {c} {t}" for t, (a, b, c) in enumerate(tris))
        geos.append(f"<geometry id='g{i}' name='{name}'><mesh><source id='g{i}-p'><float_array id='g{i}-a' count='{3*len(v)}'>{pos}</float_array>"
                    f"<technique_common><accessor source='#g{i}-a' count='{len(v)}' stride='3'><param name='X' type='float'/><param name='Y' type='float'/><param name='Z' type='float'/></accessor></technique_common></source>"
                    f"<source id='g{i}-n'><float_array id='g{i}-na' count='{3*len(nrm)}'>{nstr}</float_array>"
                    f"<technique_common><accessor source='#g{i}-na' count='{len(nrm)}' stride='3'><param name='X' type='float'/><param name='Y' type='float'/><param name='Z' type='float'/></accessor></technique_common></source>"
                    f"<vertices id='g{i}-v'><input semantic='POSITION' source='#g{i}-p'/></vertices>"
                    f"<triangles material='mat' count='{len(tris)}'><input semantic='VERTEX' source='#g{i}-v' offset='0'/>"
                    f"<input semantic='NORMAL' source='#g{i}-n' offset='1'/><p>{idx}</p></triangles></mesh></geometry>")
        nodes.append(f"<node id='n{i}' name='{tag} - {name}'><instance_geometry url='#g{i}'><bind_material><technique_common>"
                     f"<instance_material symbol='mat' target='#{mid}'/></technique_common></bind_material></instance_geometry></node>")
    doc = ("<?xml version='1.0' encoding='utf-8'?>"
           "<COLLADA xmlns='http://www.collada.org/2005/11/COLLADASchema' version='1.4.1'>"
           "<asset><unit name='millimeter' meter='0.001'/><up_axis>Z_UP</up_axis></asset>"
           f"<library_effects>{''.join(fx)}</library_effects><library_materials>{''.join(mats)}</library_materials>"
           f"<library_geometries>{''.join(geos)}</library_geometries>"
           f"<library_visual_scenes><visual_scene id='s' name='บ่อวัดน้ำ'><node id='root' name='บ่อวัดน้ำ 3 ช่อง'>{''.join(nodes)}</node></visual_scene></library_visual_scenes>"
           "<scene><instance_visual_scene url='#s'/></scene></COLLADA>")
    open(path, "w", encoding="utf-8").write(doc)


# ================= Ruby สำหรับ SketchUp =================
def write_rb(path):
    L = ["# encoding: UTF-8",
         "# วาดบ่อวัดน้ำ 3 ช่อง (ปั๊มจุ่ม | ม่านน้ำ | เวียร์ V-notch 90°) หน่วย mm — สร้างจาก cad/make_3d.py",
         "# ใช้งาน: SketchUp > Extensions > Developer > Ruby Console แล้วพิมพ์  load 'C:/path/weir_tank_sketchup.rb'",
         "# ระดับ ±0 = ผิวพื้นช่อง 2–3 / x = 0 ที่ผิวในผนังหัวบ่อ (น้ำไหลตามแกน x)",
         "model = Sketchup.active_model",
         "model.start_operation('บ่อวัดน้ำ', true)",
         "def pt(x, y, z) Geom::Point3d.new(x.mm, y.mm, z.mm) end",
         "mats = {}"]
    for m, (r, g, b, a) in MAT.items():
        L.append(f"mats['{m}'] = model.materials['{m}'] || model.materials.add('{m}'); mats['{m}'].color = Sketchup::Color.new({r}, {g}, {b}); mats['{m}'].alpha = {a}")
    L.append("tags = {}")
    for t in TAGS:
        L.append(f"tags['{t}'] = model.layers['{t}'] || model.layers.add('{t}')")
    L += ["root = model.active_entities.add_group", "root.name = 'บ่อวัดน้ำ 3 ช่อง'",
          "def solid(root, name, tag, mat)",
          "  g = root.entities.add_group; g.name = name; g.layer = tag; g.material = mat",
          "  yield g.entities",
          "  g",
          "end"]
    for name, tag, mat, kind, d in solids:
        head = f"solid(root, '{name}', tags['{tag}'], mats['{mat}']) do |e|"
        if kind == "box":
            x1, x2, y1, y2, z1, z2 = d
            body = (f"  f = e.add_face(pt({x1},{y1},{z1}), pt({x2},{y1},{z1}), pt({x2},{y2},{z1}), pt({x1},{y2},{z1}))\n"
                    f"  f.reverse! if f.normal.z < 0\n  f.pushpull({z2 - z1}.mm)")
        elif kind == "prism":
            prof, x1, x2 = d
            ps = ", ".join(f"pt({x1},{y},{z})" for y, z in prof)
            body = f"  f = e.add_face({ps})\n  f.reverse! if f.normal.x < 0\n  f.pushpull({x2 - x1}.mm)"
        else:
            axis, c1, c2, r, s1, s2 = d
            c = f"pt({c1},{c2},{s1})" if axis == "z" else f"pt({s1},{c1},{c2})"
            ax = "Z_AXIS" if axis == "z" else "X_AXIS"
            comp = "z" if axis == "z" else "x"
            body = (f"  f = e.add_face(e.add_circle({c}, {ax}, {r}.mm, 24))\n"
                    f"  f.reverse! if f.normal.{comp} < 0\n  f.pushpull({s2 - s1}.mm)")
        L += [head, body, "end"]
    L += ["model.commit_operation", "Sketchup.active_model.active_view.zoom_extents",
          "puts 'วาดบ่อวัดน้ำเสร็จแล้ว'"]
    open(path, "w", encoding="utf-8").write("\n".join(L) + "\n")


if __name__ == "__main__":
    write_dae(os.path.join(HERE, "weir_tank.dae"))
    write_rb(os.path.join(HERE, "weir_tank_sketchup.rb"))
    print("saved", len(solids), "ชิ้น -> cad/weir_tank.dae, cad/weir_tank_sketchup.rb")

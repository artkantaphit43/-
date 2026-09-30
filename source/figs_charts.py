"""Data charts (pump curves, system curves, operating points)."""
import math
from svgplot import (Chart, wrap, t, ticks, arrow_px, fmt, INK, INK2, MUTED, GRID, AXIS,
                     BLUE, ORANGE, AQUA, VIOLET, RED, GREEN, YELLOW, BLUE_L, BLUE_D, BLUE_M, ORANGE_L)
import calc
from calc import P1, P2, P3, V


def rng(a, b, n=160):
    return [a + (b - a) * i / n for i in range(n + 1)]


# ---------------------------------------------------------------------------
def fig_syscurve():
    """System curve = static + friction, with min / max static band."""
    c = Chart(680, 370, (0, 2000), (0, 70), "อัตราการไหลรวม Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 2000, 250), ticks(0, 70, 10), mt=46)
    qs = rng(0, 2000)
    hi = [calc.ex1_sys(q, 38.0) + calc.ex1_branch(q / 3) for q in qs]
    lo = [calc.ex1_sys(q, 34.0) + calc.ex1_branch(q / 3) for q in qs]
    c.area(qs, lo, hi, ORANGE, 0.12)
    c.line(qs, hi, ORANGE, 2)
    c.line(qs, lo, ORANGE, 2, dash="6 4")
    c.hline(38, MUTED, 1, "3 3")
    c.hline(34, MUTED, 1, "3 3")
    c.label(1990, 38, "เฮดสถิตสูงสุด 38 ม. (น้ำต้นทางต่ำสุด)", dy=-6, anchor="end", size=11, color=INK2, weight=400)
    c.label(1990, 34, "เฮดสถิตต่ำสุด 34 ม. (น้ำต้นทางสูงสุด)", dy=15, anchor="end", size=11, color=INK2, weight=400)
    q = 1500
    h = calc.ex1_sys(q, 38.0) + calc.ex1_branch(q / 3)
    c.arrow(q, 38, q, h - 0.3, INK2, 1.2, both=True)
    c.leader(q, 41, 1100, 24, "ความสูญเสียรวม ≈ " + V["e1_loss"] + " ม.", anchor="end", size=11.5)
    c.point(q, h, BLUE_D)
    c.leader(q, h, 1180, 58, "จุดออกแบบ 1,500 ลบ.ม./ชม. @ " + V["e1_tdh_max"] + " ม.", anchor="end", size=11.5)
    c.legend([("กราฟระบบ – ระดับน้ำต้นทางต่ำสุด", ORANGE, "line"),
              ("กราฟระบบ – ระดับน้ำต้นทางสูงสุด", ORANGE, "dash"),
              ("ช่วงที่กราฟระบบเปลี่ยนแปลงได้", ORANGE, "area")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_pumpcurve():
    """Stacked panels: H, eta, P, NPSH3 for pump P1 (no dual axes)."""
    W = 680
    panels = [
        ("เฮด H (ม.)", (0, 70), ticks(0, 70, 10), lambda q: P1.H(q), BLUE, 150),
        ("ประสิทธิภาพ η (%)", (0, 100), ticks(0, 100, 20), lambda q: P1.eta(q) * 100, AQUA, 120),
        ("กำลังที่เพลา P (kW)", (0, 125), ticks(0, 125, 25), lambda q: P1.P(q), VIOLET, 120),
        ("NPSH3 (ม.)", (0, 10), ticks(0, 10, 2), lambda q: P1.NPSH3(q), RED, 110),
    ]
    body = []
    y = 0
    qb = P1.Qb
    for i, (lab, yl, yt, f, col, h) in enumerate(panels):
        last = i == len(panels) - 1
        c = Chart(W, h + (46 if last else 10), (0, 800), yl, "อัตราการไหล Q (ลบ.ม./ชม.)" if last else "", lab,
                  ticks(0, 800, 100), yt, mt=8, mb=46 if last else 2, ml=70, show_xaxis=last, oy=y)
        c.vband(qb * 0.7, qb * 1.2, AQUA, 0.08)
        c.vline(qb, MUTED, 1, "4 3")
        q0 = 0 if i != 3 else 100
        c.fn(f, q0, 780, color=col, width=2)
        if i == 0:
            c.point(qb, P1.H(qb), BLUE_D)
            c.label(qb, P1.H(qb), "BEP", dx=8, dy=-8, size=12)
            c.label(qb * 0.95, 8, "ช่วงแนะนำ (POR) 70–120% ของ Q", anchor="middle", size=11, color=INK2, weight=400)
            c.label(10, P1.H0, "เฮดที่วาล์วปิด (shut-off) " + V["p1_H0"] + " ม.", dx=4, dy=-6, size=11, color=INK2, weight=400)
        if i == 1:
            c.point(qb, P1.eta(qb) * 100, BLUE_D)
            c.label(qb, P1.eta(qb) * 100, "η สูงสุด " + V["p1_emax"] + "%", dx=8, dy=-8, size=12)
        if i == 2:
            c.label(760, P1.P(760), "กำลังยังเพิ่มขึ้นเมื่อ Q มากขึ้น", dx=-4, dy=-10, anchor="end", size=11, color=INK2, weight=400)
        if i == 3:
            c.label(760, P1.NPSH3(760), "NPSH3 เพิ่มขึ้นเร็วทางขวา", dx=-4, dy=-10, anchor="end", size=11, color=INK2, weight=400)
        body.append(c.body())
        y += h + (46 if last else 10)
    return wrap(W, y, "".join(body))


# ---------------------------------------------------------------------------
def fig_opoint():
    c = Chart(680, 380, (0, 800), (0, 70), "อัตราการไหล Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 800, 100), ticks(0, 70, 10), mt=34)
    qs = rng(0, 800)
    c.line(qs, [P1.H(q) for q in qs], BLUE, 2)
    s1 = lambda q: 30 + 30 * (q / 600) ** 2
    s2 = lambda q: 30 + 48 * (q / 600) ** 2
    c.line(qs, [s1(q) for q in qs], ORANGE, 2)
    c.line(qs, [s2(q) for q in qs], ORANGE, 2, dash="6 4")
    q1 = calc.bisect(lambda q: P1.H(q) - s1(q), 1, 800)
    q2 = calc.bisect(lambda q: P1.H(q) - s2(q), 1, 800)
    c.point(q1, s1(q1), BLUE_D)
    c.point(q2, s2(q2), BLUE_D)
    c.leader(q1, s1(q1), 790, 26, f"จุดทำงาน A ({q1:,.0f} ลบ.ม./ชม.)", anchor="end", size=11.5)
    c.leader(q2, s2(q2), 250, 62, f"จุดทำงาน B เมื่อหรี่วาล์ว/ท่อเก่า ({q2:,.0f})", anchor="end", size=11.5)
    c.arrow(q1 - 10, 18, q2 + 10, 18, INK2, 1.3)
    c.label((q1 + q2) / 2, 18, "Q ลดลง", dy=-8, anchor="middle", size=11.5, color=INK2, weight=400)
    c.hline(30, MUTED, 1, "3 3")
    c.label(15, 30, "เฮดสถิต", dy=-6, size=11, color=INK2, weight=400)
    c.legend([("กราฟปั๊ม (H–Q)", BLUE, "line"), ("กราฟระบบ – ปกติ", ORANGE, "line"),
              ("กราฟระบบ – ความต้านทานสูงขึ้น", ORANGE, "dash")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_por():
    c = Chart(680, 360, (0, 800), (0, 70), "อัตราการไหล Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 800, 100), ticks(0, 70, 10), mt=20)
    qb = P1.Qb
    c.vband(qb * 0.4, qb * 1.3, YELLOW, 0.10)
    c.vband(qb * 0.7, qb * 1.2, AQUA, 0.16)
    c.vband(qb * 0.8, qb * 1.1, GREEN, 0.14)
    c.fn(lambda q: P1.H(q), 0, 780, color=BLUE, width=2)
    c.point(qb, P1.H(qb), BLUE_D)
    c.label(qb, P1.H(qb), "BEP", dx=8, dy=-10, size=12)
    y = 14
    c.label(qb * 0.95, 21, "เหมาะที่สุด 80–110%", anchor="middle", size=11.5, color=INK)
    c.label(qb * 0.95, 13, "POR 70–120%", anchor="middle", size=11.5, color=INK)
    c.label(qb * 0.95, 5, "AOR (ตามผู้ผลิต) เช่น 40–130%", anchor="middle", size=11.5, color=INK)
    c.label(qb * 0.2, 40, "ไหลน้อยเกินไป:", size=11.5, anchor="middle", color=INK)
    c.label(qb * 0.2, 35, "หมุนวนย้อนกลับ", size=11, anchor="middle", color=INK2, weight=400)
    c.label(qb * 0.2, 30.5, "สั่น ร้อน แรงรัศมีสูง", size=11, anchor="middle", color=INK2, weight=400)
    c.label(qb * 1.42, 58, "ไหลมากเกินไป:", size=11.5, anchor="middle", color=INK)
    c.label(qb * 1.42, 53, "เสี่ยงคาวิเทชัน", size=11, anchor="middle", color=INK2, weight=400)
    c.label(qb * 1.42, 48.5, "มอเตอร์เกินกำลัง", size=11, anchor="middle", color=INK2, weight=400)
    return c.svg()


# ---------------------------------------------------------------------------
def fig_affinity():
    """Two panels: (a) no static head; (b) high static head."""
    W = 680
    body = []
    speeds = [(1.0, BLUE_D, "100%"), (0.9, BLUE, "90%"), (0.8, BLUE_M, "80%"), (0.7, BLUE_L, "70%")]
    for k, (static, title) in enumerate(((0.0, "(ก) ระบบที่ไม่มีเฮดสถิต (เช่น ระบบหมุนเวียน)"),
                                         (34.0, "(ข) ระบบที่มีเฮดสถิตสูง (เช่น ส่งน้ำขึ้นถังสูง)"))):
        ox = k * 340
        c = Chart(340, 330, (0, 800), (0, 70), "Q (ลบ.ม./ชม.)", "H (ม.)" if k == 0 else "",
                  ticks(0, 800, 200), ticks(0, 70, 10), ml=46, mr=10, mt=40, mb=46, ox=ox)
        c.raw(t(ox + 46, 16, title, 11.5, "start", INK, 600))
        if static == 0:
            kk = P1.H(510) / 510 ** 2
            sysf = lambda q: kk * q * q
        else:
            kk = (47.0 - 34.0) / 510 ** 2
            sysf = lambda q: 34.0 + kk * q * q
        for r, col, lab in speeds:
            c.fn(lambda q, r=r: P1.H(q, r), 0, 790 * r, color=col, width=2)
            c.label(8, P1.H(0, r), lab, dx=0, dy=-4, size=10.5, color=INK2, weight=500)
        c.fn(sysf, 0, 800, color=ORANGE, width=2)
        # BEP parabola
        kb = P1.Hbep() / P1.Qb ** 2
        c.fn(lambda q: kb * q * q, 0, 700, color=MUTED, width=1.2, dash="4 3")
        for r, col, lab in speeds:
            try:
                q = calc.bisect(lambda q: P1.H(q, r) - sysf(q), 1, 790 * r)
                if P1.H(q, r) - sysf(q) > 1 or q < 5:
                    raise ValueError
                pct = q / (P1.Qb * r) * 100
                c.point(q, sysf(q), BLUE_D, r=4.5)
                c.label(q, sysf(q), f"{pct:.0f}%", dx=7, dy=12 if static else -6, size=10.5, color=INK, weight=600)
            except ValueError:
                pass
        if static:
            c.label(790, 34, "เฮดสถิต", dx=-2, dy=14, anchor="end", size=10.5, color=INK2, weight=400)
            c.hline(34, MUTED, 1, "3 3")
        body.append(c.body())
    foot = t(46, 344, "ตัวเลขที่จุด = ตำแหน่งจุดทำงานเทียบ Q ที่ BEP ของความเร็วนั้น ๆ · เส้นประเทา = เส้นพาราโบลา BEP (H ∝ Q²)", 10.5, "start", INK2)
    return wrap(W, 352, "".join(body) + foot)


# ---------------------------------------------------------------------------
def fig_trim():
    c = Chart(680, 340, (0, 800), (0, 70), "อัตราการไหล Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 800, 100), ticks(0, 70, 10), mt=20)
    for d, col in ((400, BLUE_D), (385, BLUE), (370, BLUE_M), (355, BLUE_L)):
        r = d / 400
        c.fn(lambda q, r=r: P1.H(q, r), 0, 780 * r, color=col, width=2)
        c.label(12, P1.H(0, r), f"Ø {d} มม.", dx=0, dy=-4, size=10.5, color=INK, weight=500)
    c.label(20, 10, "เส้นโค้งตามกฎการตัดใบพัดโดยประมาณ (Q ∝ D, H ∝ D²) – ให้ใช้กราฟจริงจากผู้ผลิตเสมอ", size=11, color=INK2, weight=400)
    return c.svg()


# ---------------------------------------------------------------------------
def fig_parallel():
    """Example 1: 1, 2, 3 pumps in parallel with min / max static system curves."""
    c = Chart(680, 410, (0, 2200), (0, 70), "อัตราการไหลรวม Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 2200, 200), ticks(0, 70, 10), mt=48)
    # modified pump curve = H - branch loss
    def mod(q):
        return P1.H(q) - calc.ex1_branch(q)
    qs = rng(0, 800)
    cols = {1: BLUE_L, 2: BLUE, 3: BLUE_D}
    for n in (1, 2, 3):
        c.line([n * q for q in qs if n * q <= 2200], [mod(q) for q in qs if n * q <= 2200], cols[n], 2)
        qe = min(760, 2150 / n)
        c.label(n * qe, mod(qe), f"{n} เครื่อง", dx=-4 if n == 3 else 6, dy=16 if n == 3 else 4,
                anchor="end" if n == 3 else "start", size=11.5, color=INK)
    Q = rng(0, 2200)
    c.line(Q, [calc.ex1_sys(x, 38.0) for x in Q], ORANGE, 2)
    c.line(Q, [calc.ex1_sys(x, 34.0) for x in Q], ORANGE, 2, dash="6 4")
    for r in V["e1_rows"]:
        c.point(r["Q"], calc.ex1_sys(r["Q"], r["static"]), INK, 4.5)
    r = V["e1_rows"]
    c.leader(r[0]["Q"], calc.ex1_sys(r[0]["Q"], 38), 1900, 60,
             f"3 เครื่อง @LWL: {r[0]['Q']:,.0f} ลบ.ม./ชม.", anchor="end", size=11)
    c.leader(r[5]["Q"], calc.ex1_sys(r[5]["Q"], 34), 820, 22,
             f"1 เครื่อง @HWL: {r[5]['q']:,.0f} ลบ.ม./ชม. = {r[5]['pct']:.0f}% BEP", anchor="start", size=11)
    c.legend([("กราฟปั๊มขนาน (หักความสูญเสียในท่อแยกแล้ว)", BLUE, "line"), ("กราฟระบบ LWL (เฮดสถิต 38 ม.)", ORANGE, "line"),
              ("กราฟระบบ HWL (34 ม.)", ORANGE, "dash")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_parallel_generic():
    """Generic: parallel pumps on flat vs steep system curve."""
    c = Chart(680, 360, (0, 1600), (0, 70), "อัตราการไหลรวม Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 1600, 200), ticks(0, 70, 10), mt=36)
    qs = rng(0, 790)
    c.line(qs, [P1.H(q) for q in qs], BLUE_L, 2)
    c.line([2 * q for q in qs], [P1.H(q) for q in qs], BLUE_D, 2)
    c.label(790, P1.H(790), "1 เครื่อง", dx=6, dy=4, size=11.5)
    c.label(1560, P1.H(780), "2 เครื่อง", dx=-4, dy=16, anchor="end", size=11.5)
    flat = lambda Q: 38 + 9 * (Q / 1000) ** 2
    steep = lambda Q: 5 + 58 * (Q / 1000) ** 2
    Q = rng(0, 1600)
    c.line(Q, [flat(x) for x in Q], ORANGE, 2)
    c.line(Q, [steep(x) for x in Q], ORANGE, 2, dash="6 4")
    for sysf, nm in ((flat, "ระบบ A"), (steep, "ระบบ B")):
        q1 = calc.bisect(lambda q: P1.H(q) - sysf(q), 1, 790)
        q2 = calc.bisect(lambda q: P1.H(q / 2) - sysf(q), 1, 1580)
        c.point(q1, sysf(q1), INK, 4.5)
        c.point(q2, sysf(q2), INK, 4.5)
        gain = (q2 / q1 - 1) * 100
        if nm == "ระบบ A":
            c.leader(q2, sysf(q2), 1590, 66, f"{nm}: 1→2 เครื่อง Q เพิ่ม {gain:.0f}%", anchor="end", size=11)
        else:
            c.leader(q2, sysf(q2), 1590, 12, f"{nm}: 1→2 เครื่อง Q เพิ่มเพียง {gain:.0f}%", anchor="end", size=11)
        V["par_gain_" + ("a" if nm == "ระบบ A" else "b")] = f"{gain:.0f}"
    c.legend([("กราฟปั๊ม", BLUE, "line"), ("ระบบ A – เฮดสถิตสูง (โค้งแบน)", ORANGE, "line"),
              ("ระบบ B – แรงเสียดทานสูง (โค้งชัน)", ORANGE, "dash")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_series():
    c = Chart(680, 340, (0, 800), (0, 130), "อัตราการไหล Q (ลบ.ม./ชม.)", "เฮด H (ม.)",
              ticks(0, 800, 100), ticks(0, 130, 20), mt=36)
    qs = rng(0, 790)
    c.line(qs, [P1.H(q) for q in qs], BLUE_L, 2)
    c.line(qs, [2 * P1.H(q) for q in qs], BLUE_D, 2)
    c.label(150, P1.H(150), "1 เครื่อง", dy=-8, anchor="middle", size=11.5)
    c.label(150, 2 * P1.H(150), "2 เครื่องต่ออนุกรม", dy=-8, anchor="middle", size=11.5)
    sysf = lambda q: 70 + 30 * (q / 600) ** 2
    c.fn(sysf, 0, 800, color=ORANGE, width=2)
    q2 = calc.bisect(lambda q: 2 * P1.H(q) - sysf(q), 1, 790)
    c.point(q2, sysf(q2), INK, 4.5)
    c.leader(q2, sysf(q2), 700, 120, f"จุดทำงาน {q2:,.0f} ลบ.ม./ชม. @ {sysf(q2):.0f} ม.", anchor="end", size=11)
    c.label(40, 63, "เครื่องเดียวส่งไม่ถึง (เฮดสถิต 70 ม. > shut-off 58 ม.)", dy=0, size=11, color=INK2, weight=400)
    c.legend([("กราฟปั๊ม", BLUE, "line"), ("กราฟระบบ", ORANGE, "line")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_npsh_budget():
    """Horizontal stacked bars: NPSHa components vs NPSH3 + margin (suction lift example)."""
    Ha = float(V["np_ha"])
    Hv = float(V["np_hv"])
    W, H = 680, 250
    ml, mr = 150, 30
    scale = (W - ml - mr) / 11.0
    out = []

    def X(v):
        return ml + v * scale
    for v in range(0, 12):
        out.append(f'<line x1="{X(v):.1f}" y1="30" x2="{X(v):.1f}" y2="200" stroke="{GRID}"/>')
        out.append(t(X(v), 216, str(v), 11.5, "middle", MUTED))
    out.append(t((ml + W - mr) / 2, 240, "เฮด (ม.)", 12.5, "middle", INK2, 500))
    # bar 1: atmospheric head, then subtract segments
    y1 = 44
    out.append(t(ml - 10, y1 + 16, "ความดันบรรยากาศ", 12, "end", INK))
    out.append(f'<rect x="{X(0):.1f}" y="{y1}" width="{Ha * scale:.1f}" height="24" rx="3" fill="{BLUE}"/>')
    out.append(t(X(Ha) + 6, y1 + 17, f"{Ha:.2f} ม.", 11.5, "start", INK))
    y2 = 88
    out.append(t(ml - 10, y2 + 16, "หักออก", 12, "end", INK))
    out.append(t(ml - 10, y2 + 32, "(จากขวาไปซ้าย)", 10.5, "end", MUTED))
    segs = [(4.5, ORANGE, "ระยะยกดูด 4.5 ม."), (0.8, VIOLET, "สูญเสียท่อดูด 0.8 ม."), (Hv, RED, f"ความดันไอ {Hv:.2f} ม.")]
    x = Ha
    for i, (val, col, lab) in enumerate(segs):
        out.append(f'<rect x="{X(x - val) + 1:.1f}" y="{y2}" width="{val * scale - 2:.1f}" height="24" fill="{col}" opacity="0.9"/>')
        if i == 2:
            out.append(t(X(x - val) - 6, y2 + 17, lab, 11, "end", INK2))
        else:
            out.append(t(X(x - val / 2), y2 + 40, lab, 11, "middle", INK2))
        x -= val
    y3 = 150
    npsha = float(V["np_a"])
    out.append(t(ml - 10, y3 + 16, "NPSHa เทียบ NPSH3", 12, "end", INK))
    out.append(f'<rect x="{X(0):.1f}" y="{y3}" width="{npsha * scale:.1f}" height="24" rx="3" fill="{AQUA}"/>')
    out.append(t(X(npsha) + 6, y3 + 17, f"NPSHa = {npsha:.2f} ม.", 11.5, "start", INK, 600))
    out.append(f'<line x1="{X(3.5):.1f}" y1="{y3 - 6}" x2="{X(3.5):.1f}" y2="{y3 + 30}" stroke="{INK}" stroke-width="2"/>')
    out.append(t(X(3.5), y3 - 10, "NPSH3 = 3.5", 11, "middle", INK))
    out.append(f'<line x1="{X(3.5 * 1.3):.1f}" y1="{y3 - 6}" x2="{X(3.5 * 1.3):.1f}" y2="{y3 + 30}" stroke="{INK}" stroke-width="1.2" stroke-dasharray="3 2"/>')
    out.append(t(X(3.5 * 1.3) + 4, y3 + 42, "1.3 × NPSH3", 11, "middle", INK2))
    return wrap(W, H, "".join(out))


# ---------------------------------------------------------------------------
def fig_npsh_curve():
    c = Chart(680, 340, (0, 800), (0, 14), "อัตราการไหล Q (ลบ.ม./ชม.)", "NPSH (ม.)",
              ticks(0, 800, 100), ticks(0, 14, 2), mt=36)
    qs = rng(80, 790)
    c.line(qs, [P1.NPSH3(q) for q in qs], RED, 2)
    c.line(qs, [1.3 * P1.NPSH3(q) for q in qs], RED, 1.6, dash="5 4")
    # NPSHa for a suction-lift arrangement with DN300 suction
    rho, pv, _ = calc.WATER[30]
    Ha = calc.p_atm_kpa(50) * 1000 / (rho * 9.81)
    Hv = pv * 1000 / (rho * 9.81)

    def npsha(q):
        v = q / 3600 / calc.area(0.30)
        return Ha - Hv - 3.0 - calc.hw_loss(12, q / 3600, 120, 0.30) - 2.5 * calc.vh(v)
    qa = rng(0, 790)
    c.line(qa, [npsha(q) for q in qa], AQUA, 2)
    qx = calc.bisect(lambda q: npsha(q) - 1.3 * P1.NPSH3(q), 100, 790)
    c.point(qx, npsha(qx), INK, 4.5)
    c.leader(qx, npsha(qx), 420, 11.5, f"ขีดจำกัดใช้งาน ≈ {qx:,.0f} ลบ.ม./ชม.", anchor="end", size=11)
    c.vband(qx, 800, RED, 0.07)
    c.label(qx + 10, 1.0, "ห้ามใช้งาน: NPSH ไม่พอ", size=11, color=INK)
    c.legend([("NPSHa (ระบบ)", AQUA, "line"), ("NPSH3 (ปั๊ม)", RED, "line"), ("1.3 × NPSH3", RED, "dash")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_cycle():
    """Cycle time vs inflow ratio for constant-speed pump."""
    c = Chart(680, 320, (0, 1), (0, 14), "อัตราน้ำเข้า / อัตราสูบ (q/Q)", "รอบเวลา T ÷ (V/Q)",
              [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], ticks(0, 14, 2),
              xfmt=lambda v: f"{v:.1f}", mt=20)
    xs = rng(0.075, 0.925, 200)
    c.line(xs, [1 / x + 1 / (1 - x) for x in xs], BLUE, 2)
    c.point(0.5, 4, BLUE_D)
    c.leader(0.5, 4, 0.5, 9, "ต่ำสุดที่ q = Q/2 → T_min = 4V/Q", anchor="middle", size=11.5)
    c.label(0.13, 11.5, "← น้ำเข้าน้อย: ใช้เวลาเติมนาน", size=11, color=INK2, weight=400)
    c.label(0.87, 11.5, "น้ำเข้ามาก: ใช้เวลาสูบนาน →", size=11, color=INK2, weight=400, anchor="end")
    return c.svg()


# ---------------------------------------------------------------------------
def fig_ex2():
    c = Chart(680, 400, (0, 250), (0, 40), "อัตราการไหลรวม Q (ลิตร/วินาที)", "เฮด H (ม.)",
              ticks(0, 250, 25), ticks(0, 40, 5), mt=36)
    mod = lambda q: P2.H(q) - calc.ex2_branch(q)
    qs = rng(0, 165)
    for n, col in ((1, BLUE_L), (2, BLUE_D)):
        c.line([n * q for q in qs if n * q <= 250 and mod(q) > 0], [mod(q) for q in qs if n * q <= 250 and mod(q) > 0], col, 2)
    c.label(148, 4, "1 เครื่อง", dx=10, dy=0, anchor="start", size=11.5)
    c.label(248, mod(124), "2 เครื่อง", dx=0, dy=16, anchor="end", size=11.5)
    rr = V["e2_vfd_rr"]
    modr = lambda q: P2.H(q, rr) - calc.ex2_branch(q)
    c.line([q for q in rng(0, 150)], [modr(q) for q in rng(0, 150)], BLUE_M, 1.6, dash="5 4")
    Q = rng(0, 250)
    c.line(Q, [calc.ex2_sys(x, float(V["e2_s_max"])) for x in Q], ORANGE, 2)
    c.vband(0, float(V["e2_qmin_v06"]), RED, 0.06)
    c.label(float(V["e2_qmin_v06"]) / 2, 2, "v ในท่อส่ง < 0.6 ม./วินาที", anchor="middle", size=11, color=INK)
    r = V["e2_rows"]
    c.point(r[0]["Q"], calc.ex2_sys(r[0]["Q"], r[0]["static"]), INK, 4.5)
    c.point(r[2]["Q"], calc.ex2_sys(r[2]["Q"], r[2]["static"]), INK, 4.5)
    c.leader(r[0]["Q"], calc.ex2_sys(r[0]["Q"], r[0]["static"]), 245, 34, f"2 เครื่อง: {r[0]['Q']:.0f} ลิตร/วินาที", anchor="end", size=11)
    c.leader(r[2]["Q"], calc.ex2_sys(r[2]["Q"], r[2]["static"]), 150, 10, f"1 เครื่อง: {r[2]['Q']:.0f} ลิตร/วินาที", anchor="start", size=11)
    qv = float(V["e2_qmin_v06"])
    c.point(qv, calc.ex2_sys(qv, float(V["e2_s_max"])), INK, 4)
    c.leader(qv, calc.ex2_sys(qv, float(V["e2_s_max"])), 48, 9, f"VFD {V['e2_vfd_hz']} Hz (ต่ำสุดที่ยอมได้)", anchor="middle", size=11)
    c.legend([("ปั๊ม 100% (หักท่อแยกแล้ว)", BLUE, "line"), (f"ปั๊ม {V['e2_vfd_r']}% ความเร็ว", BLUE_M, "dash"),
              ("กราฟระบบ (ระดับหยุด)", ORANGE, "line")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_ex3():
    c = Chart(680, 380, (0, 1.6), (0, 35), "อัตราการไหลรวม 2 เครื่อง Q (ลบ.ม./วินาที)", "เฮด H (ม.)",
              ticks(0, 1.6, 0.2), ticks(0, 35, 5), xfmt=lambda v: f"{v:.1f}", mt=36)
    mod = lambda q, r=1.0: P3.H(q, r) - calc.ex3_col(q)
    qs = rng(0, 0.8)
    c.line([2 * q for q in qs], [mod(q) for q in qs], BLUE_D, 2)
    rr = V["e3_vfd_rr"]
    c.line([2 * q for q in rng(0, 0.8 * rr)], [mod(q, rr) for q in rng(0, 0.8 * rr)], BLUE_M, 1.8, dash="5 4")
    Q = rng(0, 1.6)
    c.line(Q, [calc.ex3_sys(x, float(V["e3_s_low"])) for x in Q], ORANGE, 2)
    c.line(Q, [calc.ex3_sys(x, float(V["e3_s_fl"])) for x in Q], ORANGE, 2, dash="6 4")
    r = V["e3_rows"]
    for row in r:
        Qo = 2 * row["q"]
        c.point(Qo, calc.ex3_sys(Qo, row["static"]), INK, 4.5)
    c.leader(2 * r[0]["q"], calc.ex3_sys(2 * r[0]["q"], r[0]["static"]), 1.58, 28,
             f"น้ำต่ำสุด: {r[0]['pct']:.0f}% BEP", anchor="end", size=11)
    c.leader(2 * r[1]["q"], calc.ex3_sys(2 * r[1]["q"], r[1]["static"]), 1.58, 5,
             f"น้ำหลาก: {r[1]['pct']:.0f}% BEP (เกินช่วง)", anchor="end", size=11)
    c.point(1.0, calc.ex3_sys(1.0, float(V["e3_s_fl"])), INK, 4)
    c.leader(1.0, calc.ex3_sys(1.0, float(V["e3_s_fl"])), 0.55, 4, f"น้ำหลาก + VFD {V['e3_vfd_r']}%: {V['e3_vfd_pct']}% BEP", anchor="middle", size=11)
    c.legend([("2 เครื่อง 100%", BLUE_D, "line"), (f"2 เครื่อง {V['e3_vfd_r']}%", BLUE_M, "dash"),
              ("ระบบ – น้ำต่ำสุด", ORANGE, "line"), ("ระบบ – น้ำหลาก", ORANGE, "dash")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_lcc():
    """Horizontal stacked bar of 15-year LCC (present value) for one duty pump of example 1."""
    pvf = float(V["lcc_pvf"])
    energy = float(V["e1_pin"].replace(",", "")) * 7300 * 4.5 * pvf / 1e6
    items = [("ซื้อปั๊ม+มอเตอร์", 1.6, BLUE), ("ติดตั้ง/ทดสอบ", 0.6, VIOLET),
             ("พลังงาน (15 ปี)", energy, ORANGE), ("บำรุงรักษา (15 ปี)", 0.12 * pvf, AQUA),
             ("หยุดเดินเครื่อง/อื่น ๆ", 0.3, YELLOW)]
    total = sum(v for _, v, _ in items)
    W, H = 680, 170
    ml, mr = 20, 20
    sc = (W - ml - mr) / total
    out = []
    x = ml
    y = 40
    for lab, v, col in items:
        w = v * sc
        out.append(f'<rect x="{x + 1:.1f}" y="{y}" width="{max(w - 2, 1):.1f}" height="30" fill="{col}"/>')
        x += w
    # legend under
    lx, ly = ml, 100
    for i, (lab, v, col) in enumerate(items):
        cx = lx + (i % 3) * 215
        cy = ly + (i // 3) * 26
        out.append(f'<rect x="{cx}" y="{cy - 10}" width="12" height="12" rx="2" fill="{col}"/>')
        out.append(t(cx + 18, cy, f"{lab} {v:,.1f} ล้านบาท ({v / total * 100:.0f}%)", 11.5, "start", INK2))
    out.append(t(ml, 26, f"รวมมูลค่าปัจจุบันตลอดอายุ 15 ปี ≈ {total:,.1f} ล้านบาท ต่อปั๊มหนึ่งชุด", 12, "start", INK, 600))
    V["lcc_total"] = f"{total:,.1f}"
    V["lcc_energy"] = f"{energy:,.1f}"
    V["lcc_energy_pct"] = f"{energy / total * 100:.0f}"
    return wrap(W, H, "".join(out))


# ---------------------------------------------------------------------------
def fig_hammer():
    """Illustrative HGL envelopes after pump trip along a rising main."""
    L = 4500
    c = Chart(680, 370, (0, L), (60, 220), "ระยะทางจากสถานีสูบ (ม.)", "ระดับ (ม. รทก.)",
              ticks(0, L, 500), ticks(60, 220, 20), mt=46)
    xs = rng(0, L, 90)
    ground = lambda x: 97 + 25 * math.sin(x / L * math.pi * 1.05) * (1 - x / L) + 36 * (x / L) ** 1.6
    pipe = lambda x: ground(x) - 1.5
    hgl = lambda x: 146.5 - 8.5 * x / L
    dh = float(V["wh_dh"])
    hmax = lambda x: hgl(x) + dh * 0.55 * (1 - x / L) ** 0.8
    hmin = lambda x: hgl(x) - dh * 0.55 * (1 - x / L) ** 0.8
    c.area(xs, [60] * len(xs), [ground(x) for x in xs], "#8a6d3b", 0.12)
    c.line(xs, [pipe(x) for x in xs], INK2, 2.2)
    c.line(xs, [hgl(x) for x in xs], BLUE, 2)
    c.line(xs, [hmax(x) for x in xs], RED, 1.8, dash="6 4")
    c.line(xs, [hmin(x) for x in xs], VIOLET, 1.8, dash="6 4")
    xv = calc.bisect(lambda x: hmin(x) - pipe(x), 10, L - 10)
    c.vband(0, xv, VIOLET, 0.07)
    c.label(xv / 2, 66, "ช่วงที่ความดันต่ำกว่าบรรยากาศ → เสี่ยงน้ำแยกตัว", anchor="middle", size=11, color=INK)
    c.legend([("แนวท่อ", INK2, "line"), ("HGL ขณะเดินปกติ", BLUE, "line"), ("ขอบเขตความดันสูงสุด", RED, "dash"),
              ("ขอบเขตความดันต่ำสุด", VIOLET, "dash")])
    return c.svg()


# ---------------------------------------------------------------------------
def fig_coverage():
    """Approximate application map of pump types (log-log)."""
    W, H = 680, 420
    ml, mr, mt, mb = 70, 20, 20, 50
    pw, ph = W - ml - mr, H - mt - mb
    qmin, qmax = 1, 100000
    hmin, hmax = 1, 1000
    X = lambda q: ml + (math.log10(q) - math.log10(qmin)) / (math.log10(qmax) - math.log10(qmin)) * pw
    Y = lambda h: mt + ph - (math.log10(h) - math.log10(hmin)) / (math.log10(hmax) - math.log10(hmin)) * ph
    out = []
    for e in range(0, 6):
        for m in (1, 2, 5):
            q = m * 10 ** e
            if q > qmax:
                continue
            out.append(f'<line x1="{X(q):.1f}" y1="{mt}" x2="{X(q):.1f}" y2="{mt + ph}" stroke="{GRID}"/>')
            if m == 1:
                out.append(t(X(q), mt + ph + 17, f"{q:,}", 11.5, "middle", MUTED))
    for e in range(0, 4):
        for m in (1, 2, 5):
            h = m * 10 ** e
            if h > hmax:
                continue
            out.append(f'<line x1="{ml}" y1="{Y(h):.1f}" x2="{ml + pw}" y2="{Y(h):.1f}" stroke="{GRID}"/>')
            if m == 1:
                out.append(t(ml - 7, Y(h) + 4, f"{h:,}", 11.5, "end", MUTED))
    out.append(f'<rect x="{ml}" y="{mt}" width="{pw}" height="{ph}" fill="none" stroke="{AXIS}"/>')
    out.append(t(ml + pw / 2, H - 10, "อัตราการไหล Q (ลบ.ม./ชม.) – สเกลลอการิทึม", 12.5, "middle", INK2, 500))
    out.append(f'<text transform="translate(16,{mt + ph / 2}) rotate(-90)" font-size="12.5" text-anchor="middle" fill="{INK2}" font-weight="500">เฮด H (ม.) – สเกลลอการิทึม</text>')
    regions = [
        ("ปั๊มหอยโข่งดูดปลาย (end-suction)", 2, 1500, 5, 150, BLUE),
        ("ปั๊มหลายใบพัด (multistage)", 1, 800, 30, 800, VIOLET),
        ("ปั๊มเรือนแยก (split case)", 150, 20000, 10, 250, AQUA),
        ("ปั๊มเทอร์ไบน์แนวตั้ง (VTP)", 20, 25000, 5, 400, YELLOW),
        ("ปั๊มแบบไหลผสม/ไหลตามแกน", 1500, 100000, 1.5, 30, ORANGE),
        ("ปั๊มจุ่มน้ำเสีย (submersible)", 5, 30000, 2, 80, RED),
    ]
    for lab, q0, q1, h0, h1, col in regions:
        out.append(f'<rect x="{X(q0):.1f}" y="{Y(h1):.1f}" width="{X(q1) - X(q0):.1f}" height="{Y(h0) - Y(h1):.1f}" '
                   f'fill="{col}" fill-opacity="0.07" stroke="{col}" stroke-width="1.6" rx="6"/>')
    labs = [("ปั๊มหลายใบพัด (multistage)", 1.3, 600), ("ปั๊มดูดปลาย (end-suction)", 2.4, 120),
            ("ปั๊มจุ่มน้ำเสีย (submersible)", 5.5, 2.4), ("ปั๊มเทอร์ไบน์แนวตั้ง (VTP)", 1800, 330),
            ("ปั๊มเรือนแยก (split case)", 700, 200), ("ปั๊มไหลผสม/ไหลตามแกน", 5000, 2.0)]
    for lab, q, h in labs:
        out.append(t(X(q), Y(h), lab, 11.5, "start", INK, 600,
                     extra='stroke="#fff" stroke-width="3.5" paint-order="stroke"'))
    return wrap(W, H, "".join(out))


# ---------------------------------------------------------------------------
def fig_vapor():
    c = Chart(680, 300, (0, 100), (0, 11), "อุณหภูมิน้ำ (°C)", "เฮดความดันไอ (ม.)",
              ticks(0, 100, 10), ticks(0, 11, 1), mt=20)
    xs, ys = [], []
    for T, (rho, pv, nu) in sorted(calc.WATER.items()):
        xs.append(T)
        ys.append(pv * 1000 / (rho * 9.81))
    c.line(xs, ys, RED, 2)
    for T in (30, 60, 80):
        rho, pv, _ = calc.WATER[T]
        h = pv * 1000 / (rho * 9.81)
        c.point(T, h, INK, 4)
        c.label(T, h, f"{T}°C → {h:.2f} ม.", dx=-8, dy=-8, anchor="end", size=11)
    c.vband(25, 35, AQUA, 0.12, "น้ำประปา/น้ำเสียในไทย", label_y=10, size=11)
    return c.svg()


CHARTS = dict(
    fig_syscurve=fig_syscurve, fig_pumpcurve=fig_pumpcurve, fig_opoint=fig_opoint, fig_por=fig_por,
    fig_affinity=fig_affinity, fig_trim=fig_trim, fig_parallel=fig_parallel,
    fig_parallel_generic=fig_parallel_generic, fig_series=fig_series, fig_npsh_budget=fig_npsh_budget,
    fig_npsh_curve=fig_npsh_curve, fig_cycle=fig_cycle, fig_ex2=fig_ex2, fig_ex3=fig_ex3, fig_lcc=fig_lcc,
    fig_hammer=fig_hammer, fig_coverage=fig_coverage, fig_vapor=fig_vapor,
)

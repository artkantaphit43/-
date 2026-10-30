#!/usr/bin/env python3
"""
ออกแบบบ่อ 3 ช่อง: ช่องรับน้ำ/ปั๊มจุ่ม -> ช่องโชว์น้ำใส (ยกพื้น น้ำไหลบาง) -> ช่องเวียร์ V-notch 90°

    ช่อง 1  ท่อ 6" (ท่อจุ่ม) -> ผนังกั้นลอดใต้ -> โซนปั๊มจุ่ม (สูบไป Water recycle)
            น้ำที่เหลือล้นข้ามขั้นขึ้นพื้นยกของช่อง 2
    ช่อง 2  พื้นยกสูง ปลายมีสันเตี้ย (end sill) คุมให้ชั้นน้ำบางและนิ่ง (Froude < 0.5)
            น้ำตกข้ามสันลงช่อง 3 แบบอิสระ
    ช่อง 3  โซนรับน้ำตก -> แผ่นกันคลื่นรูพรุน -> ช่วงตรง -> V-notch 90° -> ท่อออก 8"

สมการเวียร์ Kindsvater-Shen (ISO 1438), θ = 90°: Q [m³/s] = 1.365·(h + 0.00085)^2.5
สันปลายช่อง 2 (sharp-crested, ไม่มีการบีบด้านข้าง):    Q = 1.84·B·H^1.5   (Francis)

ใช้งาน:
    python3 weir_design.py
    python3 weir_design.py --qmin 50 --qmax 100 --q-recycle 10 --sill 0.03
    python3 weir_design.py --csv rating_table.csv
"""
import argparse
import math

G = 9.81
CE_90 = 0.578
KH_90 = 0.00085  # m


def q_from_h(h):
    """อัตราการไหลผ่าน V-notch 90° [m³/s] จากความสูงน้ำเหนือยอด V [m]"""
    return CE_90 * (8 / 15) * math.sqrt(2 * G) * (h + KH_90) ** 2.5


def h_from_q(q):
    """ความสูงน้ำเหนือยอด V [m] สำหรับอัตราการไหล q [m³/s]"""
    return (q / (CE_90 * (8 / 15) * math.sqrt(2 * G))) ** 0.4 - KH_90


def thin_layer(q, b, sill):
    """ความลึกน้ำบนพื้นยกช่อง 2, ความเร็ว, Froude, ความหนาม่านน้ำบนสัน"""
    head = (q / (1.84 * b)) ** (2 / 3)
    depth = sill + head
    v = q / (b * depth)
    return depth, v, v / math.sqrt(G * depth), head


def design(a):
    B = a.b
    q_weir = [(a.qmin - a.q_recycle), (a.qmax - a.q_recycle), a.qmax]  # m³/h
    hmax = h_from_q(a.qmax / 3600)
    hmin = h_from_q(q_weir[0] / 3600)
    P = a.p

    # ---- ช่อง 3: เวียร์ (พื้นบ่อ = ±0.000) ----
    el_vertex = P
    el_w_max = P + hmax
    el_notch_top = P + a.notch_depth
    v_approach = a.qmax / 3600 / (B * el_w_max)
    a_out = math.pi * a.d_out ** 2 / 4
    el_tail = a.d_out / 2 + (a.qmax / 3600 / (0.6 * a_out)) ** 2 / (2 * G)

    # ---- ช่อง 2: พื้นยก ----
    el_raised = a.raised
    rows2 = [(qh, *thin_layer(qh / 3600, B, a.sill)) for qh in
             sorted({a.qmin - a.q_recycle, a.qmin, 62.0, a.qmax - a.q_recycle, a.qmax})]
    d_max = rows2[-1][1]
    v_max = rows2[-1][2]
    # ระดับช่อง 1 = พื้นยก + ความลึก + การสูญเสียทางเข้า (0.5·v²/2g) + v²/2g
    el_c1_max = el_raised + d_max + 1.5 * v_max ** 2 / (2 * G)
    el_wall = el_c1_max + a.freeboard
    fall = el_raised + a.sill - el_w_max

    print("=" * 70)
    print(" บ่อ 3 ช่อง: ปั๊มจุ่ม | โชว์น้ำใส | V-notch 90°")
    print("=" * 70)
    print(f" น้ำเข้า {a.qmin:.0f}–{a.qmax:.0f} m³/h, สูบ recycle {a.q_recycle:.0f} m³/h, กว้างภายใน B = {B:.2f} m")
    print("-" * 70)
    print(" ช่อง 2 — ชั้นน้ำบนพื้นยก (สันปลายสูง {:.0f} cm)".format(a.sill * 100))
    print("   Q [m³/h]   ลึก [cm]   v [m/s]   Froude   ม่านน้ำบนสัน [cm]")
    for qh, d, v, fr, head in rows2:
        print(f"   {qh:7.0f}   {d*100:7.1f}   {v:7.2f}   {fr:6.2f}   {head*100:10.1f}")
    print("-" * 70)
    print(" ช่อง 3 — เวียร์ V-notch 90°")
    for name, qh in [("ต่ำสุด (ปั๊มเดิน)", q_weir[0]), ("สูงสุด (ปั๊มเดิน)", q_weir[1]), ("สูงสุด (ปั๊มหยุด)", q_weir[2])]:
        print(f"   {name:<20} {qh:5.0f} m³/h -> h = {h_from_q(qh/3600)*100:5.1f} cm")
    print(f"   P = {P:.2f} m, ร่อง V ลึก {a.notch_depth:.2f} m (ปาก {2*a.notch_depth:.2f} m)")
    print(f"   ช่วงตรงหน้าเวียร์ {a.l_approach:.2f} m (≥ 10·hmax = {10*hmax:.2f}), "
          f"จุดวัด h ห่างแผ่น {a.x_tap:.2f} m (4–5·hmax = {4*hmax:.2f}–{5*hmax:.2f})")
    print("-" * 70)
    print(" ระดับ (พื้นบ่อ = ±0.000 m)")
    for name, el in [
        ("สันกำแพง", el_wall),
        ("น้ำช่อง 1 สูงสุด", el_c1_max),
        ("สันปลายพื้นยก (ช่อง 2)", el_raised + a.sill),
        ("ผิวพื้นยก (ช่อง 2)", el_raised),
        ("ขอบบนร่อง V", el_notch_top),
        ("น้ำช่อง 3 สูงสุด", el_w_max),
        ("ยอด V", el_vertex),
        ("น้ำท้ายเวียร์ (Qmax)", el_tail),
        ("ปั๊ม START (ช่อง 1)", a.start),
        ("ปั๊ม STOP (ช่อง 1)", a.stop),
    ]:
        print(f"   {name:<26}: {el:+6.3f} m")
    print("-" * 70)

    checks = [
        ("0.05 ≤ h ≤ 0.38 m ตลอดช่วง", 0.05 <= hmin and hmax <= 0.38),
        ("h/P ≤ 0.4", hmax / P <= 0.4),
        ("h/B ≤ 0.2", hmax / B <= 0.2),
        ("P ≥ 0.45 m, B ≥ 0.90 m", P >= 0.45 and B >= 0.90),
        ("ร่อง V ลึก ≥ hmax + 80 mm", a.notch_depth >= hmax + 0.08 - 1e-9),
        ("ช่วงตรงหน้าเวียร์ ≥ 10·hmax", a.l_approach >= 10 * hmax - 1e-9),
        ("จุดวัด h อยู่ใน 4–5·hmax", 4 * hmax - 1e-9 <= a.x_tap <= 5 * hmax + 1e-9),
        ("ความเร็วหน้าเวียร์ < 0.15 m/s", v_approach < 0.15),
        ("น้ำท้ายต่ำกว่ายอด V ≥ 60 mm", el_tail <= el_vertex - 0.06),
        ("ช่อง 2 น้ำนิ่ง (Froude < 0.5 ทุกอัตราไหล)", all(r[3] < 0.5 for r in rows2)),
        ("สันช่อง 2 สูงกว่าน้ำช่อง 3 ≥ 10 cm (น้ำตกอิสระ)", fall >= 0.10 - 1e-9),
        ("ปั๊ม START ต่ำกว่าผิวพื้นยก", a.start < el_raised),
    ]
    print(" ตรวจสอบเกณฑ์")
    for text, ok in checks:
        print(f"   [{'OK' if ok else 'NG'}] {text}")
    print("=" * 70)

    rows = [(h / 100, q_from_h(h / 100)) for h in range(5, int(round(a.notch_depth * 100)) - 4)]
    if a.csv:
        with open(a.csv, "w", encoding="utf-8") as f:
            f.write("h_cm,Q_m3_per_h,Q_L_per_s\n")
            for h, q in rows:
                f.write(f"{h*100:.0f},{q*3600:.2f},{q*1000:.3f}\n")
        print(f" บันทึกตาราง rating curve -> {a.csv}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--qmin", type=float, default=50.0, help="น้ำเข้าต่ำสุด [m³/h]")
    p.add_argument("--qmax", type=float, default=100.0, help="น้ำเข้าสูงสุด [m³/h]")
    p.add_argument("--q-recycle", type=float, default=10.0, help="สูบไป Water recycle [m³/h]")
    p.add_argument("--b", type=float, default=1.05, help="ความกว้างภายในบ่อ [m]")
    p.add_argument("--p", type=float, default=0.60, help="ความสูงยอด V จากพื้นบ่อ [m]")
    p.add_argument("--notch-depth", type=float, default=0.30, help="ความลึกร่อง V [m]")
    p.add_argument("--l-approach", type=float, default=2.10, help="ช่วงตรงหน้าเวียร์ [m]")
    p.add_argument("--x-tap", type=float, default=0.95, help="ระยะจุดวัด h เหนือแผ่นเวียร์ [m]")
    p.add_argument("--raised", type=float, default=0.90, help="ระดับผิวพื้นยกช่อง 2 [m]")
    p.add_argument("--sill", type=float, default=0.02, help="ความสูงสันปลายพื้นยก [m]")
    p.add_argument("--start", type=float, default=0.80, help="ระดับปั๊ม START [m]")
    p.add_argument("--stop", type=float, default=0.40, help="ระดับปั๊ม STOP [m]")
    p.add_argument("--freeboard", type=float, default=0.20, help="ระยะเผื่อเหนือน้ำช่อง 1 สูงสุด [m]")
    p.add_argument("--d-out", type=float, default=0.200, help="ท่อออก [m] (8\" ≈ 0.200)")
    p.add_argument("--csv", help="บันทึก rating table เป็นไฟล์ CSV")
    design(p.parse_args())

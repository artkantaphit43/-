#!/usr/bin/env python3
"""
ออกแบบ/ตรวจสอบ Weir V-notch 90° (fully contracted) + บ่อปั๊มจุ่มสำหรับ Water recycle

สมการ Kindsvater-Shen (ISO 1438 / USBR Water Measurement Manual):
    Q = Ce * (8/15) * sqrt(2g) * tan(θ/2) * he^2.5
    he = h + kh
    สำหรับ θ = 90°:  Ce = 0.578,  kh = 0.00085 m
    => Q [m³/s] ≈ 1.365 * (h + 0.00085)^2.5

ใช้งาน:
    python3 weir_design.py                 # ใช้ค่าออกแบบตั้งต้น (Qmax = 10 L/s)
    python3 weir_design.py --qmax 15       # ออกแบบใหม่ที่ Qmax = 15 L/s
    python3 weir_design.py --csv rating.csv
"""
import argparse
import math

G = 9.81
CE_90 = 0.578
KH_90 = 0.00085  # m


def q_from_h(h):
    """อัตราการไหล [m³/s] จากความสูงน้ำเหนือยอด V [m]"""
    he = h + KH_90
    return CE_90 * (8 / 15) * math.sqrt(2 * G) * math.tan(math.radians(45)) * he ** 2.5


def h_from_q(q):
    """ความสูงน้ำ [m] ที่ต้องการสำหรับอัตราการไหล q [m³/s]"""
    k = CE_90 * (8 / 15) * math.sqrt(2 * G)
    return (q / k) ** 0.4 - KH_90


def design(args):
    qmax = args.qmax / 1000  # L/s -> m³/s
    hmax = h_from_q(qmax)

    # --- ข้อกำหนด fully contracted 90° V-notch (ISO 1438 / USBR) ---
    # 0.05 <= h <= 0.38 m, h/P <= 0.4, h/B <= 0.2, P >= 0.45 m, B >= 0.90 m
    P = max(0.45, hmax / 0.4, args.p)
    B = max(0.90, hmax / 0.2, args.b)
    notch_depth = max(args.notch_depth, math.ceil((hmax + 0.08) * 20) / 20)
    notch_top_width = 2 * notch_depth  # tan(45°) = 1
    h_tap = 4 * hmax, 5 * hmax  # ตำแหน่งวัดระดับน้ำเหนือน้ำ
    l_approach = max(10 * hmax, args.l_approach)
    qmin = q_from_h(0.05)

    # --- ระดับ (อ้างอิงพื้นรางนำน้ำ = ±0.000) ---
    el_vertex = P
    el_max_head = P + hmax
    el_notch_top = P + notch_depth
    el_wall_top = el_notch_top + args.freeboard
    el_tailwater_limit = el_vertex - 0.06  # น้ำท้ายต้องต่ำกว่ายอด V อย่างน้อย 60 มม.

    # --- บ่อปั๊ม ---
    qp = args.pump_factor * qmax  # อัตราสูบ
    el_overflow = el_tailwater_limit
    el_alarm = el_overflow - 0.06
    el_start = el_alarm - 0.08
    el_floor = args.sump_floor
    el_stop = el_floor + args.pump_submergence
    area = args.sump_l * args.sump_w
    v_active = area * (el_start - el_stop)
    v_required = qp * (3600 / args.starts) / 4  # V = Qp·Tmin/4
    starts_worst = 3600 * qp / (4 * v_active)  # เกิดเมื่อ Qin = Qp/2

    print("=" * 66)
    print(" ออกแบบ Weir V-notch 90° + บ่อปั๊มจุ่ม (Water recycle)")
    print("=" * 66)
    print(f" Qmax ออกแบบ                 : {qmax*1000:7.2f} L/s  ({qmax*3600:6.1f} m³/h)")
    print(f" hmax (เหนือยอด V)            : {hmax*1000:7.1f} mm")
    print(f" Qmin ที่วัดได้ (h = 50 mm)    : {qmin*1000:7.2f} L/s  ({qmin*3600:6.2f} m³/h)")
    print("-" * 66)
    print(" แผ่นเวียร์ / รางนำน้ำ")
    print(f"  ความสูงยอด V จากพื้น (P)    : {P:6.3f} m")
    print(f"  ความกว้างรางนำน้ำ (B)       : {B:6.3f} m")
    print(f"  ความลึกร่อง V              : {notch_depth:6.3f} m  (กว้างปาก {notch_top_width:.3f} m)")
    print(f"  ความยาวรางนำน้ำ (ตรง)       : {l_approach:6.3f} m  (ขั้นต่ำ 10·hmax)")
    print(f"  จุดวัดระดับเหนือแผ่นเวียร์    : {h_tap[0]:.2f}–{h_tap[1]:.2f} m (4–5·hmax)")
    print("-" * 66)
    print(" ระดับ (พื้นรางนำน้ำ = ±0.000 m)")
    for name, el in [
        ("สันกำแพง", el_wall_top),
        ("ขอบบนร่อง V", el_notch_top),
        ("น้ำสูงสุดเหนือน้ำ (Qmax)", el_max_head),
        ("ยอด V (Vertex, ศูนย์ของ h)", el_vertex),
        ("ท่อน้ำล้น / ระดับน้ำท้ายสูงสุด", el_overflow),
        ("High-level alarm", el_alarm),
        ("ปั๊ม START", el_start),
        ("ปั๊ม STOP", el_stop),
        ("พื้นบ่อปั๊ม", el_floor),
    ]:
        print(f"  {name:<32}: {el:+7.3f} m")
    print("-" * 66)
    print(" บ่อปั๊มจุ่ม")
    print(f"  อัตราสูบ (≥ {args.pump_factor:.1f}·Qmax)          : {qp*1000:6.2f} L/s  ({qp*3600:5.1f} m³/h)")
    print(f"  ขนาดบ่อ (ภายใน)             : {args.sump_l:.2f} × {args.sump_w:.2f} m")
    print(f"  ปริมาตรทำงาน (Start–Stop)   : {v_active:6.2f} m³  (ต้องการ ≥ {v_required:.2f} m³)")
    print(f"  จำนวนครั้ง start สูงสุด      : {starts_worst:6.1f} ครั้ง/ชม. (จำกัด {args.starts})")
    print("-" * 66)

    checks = [
        ("0.05 ≤ hmax ≤ 0.38 m", 0.05 <= hmax <= 0.38),
        ("h/P ≤ 0.4", hmax / P <= 0.4),
        ("h/B ≤ 0.2", hmax / B <= 0.2),
        ("P ≥ 0.45 m", P >= 0.45),
        ("B ≥ 0.90 m", B >= 0.90),
        ("ร่อง V ลึกกว่า hmax + 80 mm", notch_depth >= hmax + 0.08 - 1e-9),
        ("ระดับ START ต่ำกว่ายอด V ≥ 60 mm", el_start <= el_tailwater_limit),
        ("ปริมาตรทำงานบ่อปั๊มเพียงพอ", v_active >= v_required),
    ]
    print(" ตรวจสอบเกณฑ์")
    ok_all = True
    for text, ok in checks:
        ok_all &= ok
        print(f"  [{'OK' if ok else 'NG'}] {text}")
    print("=" * 66)
    if not ok_all:
        print(" !! มีรายการไม่ผ่าน ให้ปรับขนาด/ระดับใหม่")

    rows = []
    h = 0.05
    while h <= max(hmax, min(0.38, notch_depth - 0.05)) + 1e-9:
        rows.append((h, q_from_h(h)))
        h = round(h + 0.005, 3)
    if args.csv:
        with open(args.csv, "w", encoding="utf-8") as f:
            f.write("h_mm,Q_L_per_s,Q_m3_per_h\n")
            for h, q in rows:
                f.write(f"{h*1000:.0f},{q*1000:.3f},{q*3600:.2f}\n")
        print(f" บันทึกตาราง rating curve -> {args.csv}")
    else:
        print(f" Rating table (h เหนือยอด V) — เกิน {hmax*1000:.0f} mm = เกินช่วงออกแบบ")
        print("   h [mm]   Q [L/s]   Q [m³/h]")
        for h, q in rows[::2]:
            print(f"   {h*1000:6.0f}   {q*1000:7.2f}   {q*3600:8.2f}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--qmax", type=float, default=10.0, help="อัตราการไหลสูงสุด [L/s] (default 10)")
    p.add_argument("--p", type=float, default=0.45, help="ความสูงยอด V จากพื้นราง [m]")
    p.add_argument("--b", type=float, default=0.90, help="ความกว้างรางนำน้ำ [m]")
    p.add_argument("--notch-depth", type=float, default=0.25, help="ความลึกร่อง V [m]")
    p.add_argument("--l-approach", type=float, default=2.0, help="ความยาวรางนำน้ำ [m]")
    p.add_argument("--freeboard", type=float, default=0.20, help="ระยะเผื่อเหนือขอบร่อง V [m]")
    p.add_argument("--pump-factor", type=float, default=1.1, help="อัตราสูบ / Qmax")
    p.add_argument("--sump-l", type=float, default=1.80, help="ความยาวบ่อปั๊ม (ภายใน) [m]")
    p.add_argument("--sump-w", type=float, default=1.20, help="ความกว้างบ่อปั๊ม (ภายใน) [m]")
    p.add_argument("--sump-floor", type=float, default=-1.00, help="ระดับพื้นบ่อปั๊ม [m]")
    p.add_argument("--pump-submergence", type=float, default=0.60,
                   help="ระดับ STOP เหนือพื้นบ่อ [m] (ต้องท่วมมอเตอร์ตามสเปกผู้ผลิต)")
    p.add_argument("--starts", type=int, default=10, help="จำนวน start สูงสุดต่อชั่วโมง")
    p.add_argument("--csv", help="บันทึก rating table เป็นไฟล์ CSV")
    design(p.parse_args())

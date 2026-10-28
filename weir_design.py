#!/usr/bin/env python3
"""
ออกแบบ/ตรวจสอบ Weir V-notch 90° (fully contracted) โดยมีบ่อปั๊มจุ่มอยู่ด้านน้ำเข้า (ก่อนเวียร์)

ลำดับการไหล:
    ท่อน้ำเข้า -> บ่อน้ำเข้า/บ่อปั๊ม (มี baffle กันน้ำกระฉอก) -> ปั๊มจุ่มสูบไป Water recycle
               -> น้ำส่วนที่เหลือล้นเข้ารางนำน้ำ -> แผ่นกันคลื่นรูพรุน -> V-notch 90° -> ท่อน้ำออก
    เวียร์จึงวัด "น้ำที่ไหลออกจริง" = Qin - Qrecycle

สมการ Kindsvater-Shen (ISO 1438 / USBR Water Measurement Manual):
    Q = Ce * (8/15) * sqrt(2g) * tan(θ/2) * he^2.5
    he = h + kh
    สำหรับ θ = 90°:  Ce = 0.578,  kh = 0.00085 m
    => Q [m³/s] ≈ 1.365 * (h + 0.00085)^2.5

ใช้งาน:
    python3 weir_design.py                       # ค่าตั้งต้น Qmax 10 L/s, recycle 5 L/s
    python3 weir_design.py --qmax 15 --q-recycle 8
    python3 weir_design.py --csv rating_table.csv
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
    qr = args.q_recycle / 1000
    # กรณีออกแบบเวียร์: ปั๊มหยุด (เสีย/ซ่อม) น้ำทั้งหมดต้องผ่านเวียร์ได้
    hmax = h_from_q(qmax)

    # --- ข้อกำหนด fully contracted 90° V-notch (ISO 1438 / USBR) ---
    # 0.05 <= h <= 0.38 m, h/P <= 0.4, h/B <= 0.2, P >= 0.45 m, B >= 0.90 m
    P = max(0.45, hmax / 0.4, args.p)
    B = max(0.90, hmax / 0.2, args.b)
    notch_depth = max(args.notch_depth, math.ceil((hmax + 0.08) * 20) / 20)
    notch_top_width = 2 * notch_depth  # tan(45°) = 1
    h_tap = 4 * hmax, 5 * hmax  # ตำแหน่งวัดระดับน้ำเหนือน้ำ
    l_approach = max(10 * hmax, args.l_approach)
    v_approach = qmax / (B * (P + hmax))
    qmin = q_from_h(0.05)

    # --- ระดับ (อ้างอิงพื้นรางนำน้ำ = ±0.000) ---
    el_vertex = P
    el_max_head = P + hmax
    el_notch_top = P + notch_depth
    el_wall_top = el_notch_top + args.freeboard
    el_tailwater_limit = el_vertex - 0.06  # น้ำท้ายต้องต่ำกว่ายอด V อย่างน้อย 60 มม.

    # --- บ่อปั๊ม (ด้านน้ำเข้า) ---
    # ระดับน้ำในบ่อถูกกำหนดโดยเวียร์: ปกติอยู่ระหว่างยอด V ถึง P + hmax
    # START ต่ำกว่ายอด V เล็กน้อย -> เมื่อ Qin > Qr ปั๊มเดินต่อเนื่อง
    # STOP  ป้องกันปั๊มแห้งเมื่อ Qin < Qr
    el_floor = args.sump_floor
    el_start = el_vertex - args.start_below_vertex
    el_stop = el_floor + args.pump_submergence
    el_inlet_baffle_bottom = el_floor + args.baffle_gap
    area = args.sump_l * args.sump_w
    v_active = area * (el_start - el_stop)
    v_required = qr * (3600 / args.starts) / 4  # V = Qp·Tmin/4
    starts_worst = 3600 * qr / (4 * v_active)  # เกิดเมื่อ Qin = Qr/2
    q_weir_normal = max(qmax - qr, 0)
    h_normal = h_from_q(q_weir_normal) if q_weir_normal > 0 else 0

    print("=" * 70)
    print(" Weir V-notch 90° + บ่อปั๊มจุ่มด้านน้ำเข้า (Water recycle)")
    print("=" * 70)
    print(f" Qin สูงสุด                    : {qmax*1000:7.2f} L/s  ({qmax*3600:6.1f} m³/h)")
    print(f" Q recycle (อัตราสูบ)          : {qr*1000:7.2f} L/s  ({qr*3600:6.1f} m³/h)")
    print(f" Q ผ่านเวียร์ ปกติ (Qin-Qr)     : {q_weir_normal*1000:7.2f} L/s  (h = {h_normal*1000:.0f} mm)")
    print(f" Q ผ่านเวียร์ สูงสุด (ปั๊มหยุด)  : {qmax*1000:7.2f} L/s  (hmax = {hmax*1000:.1f} mm)")
    print(f" Qmin ที่วัดได้ (h = 50 mm)     : {qmin*1000:7.2f} L/s  ({qmin*3600:6.2f} m³/h)")
    print("-" * 70)
    print(" แผ่นเวียร์ / รางนำน้ำ")
    print(f"  ความสูงยอด V จากพื้น (P)    : {P:6.3f} m")
    print(f"  ความกว้างรางนำน้ำ (B)       : {B:6.3f} m")
    print(f"  ความลึกร่อง V              : {notch_depth:6.3f} m  (กว้างปาก {notch_top_width:.3f} m)")
    print(f"  ความยาวรางนำน้ำ (ตรง)       : {l_approach:6.3f} m  (ขั้นต่ำ 10·hmax)")
    print(f"  ความเร็วน้ำในราง (Qmax)     : {v_approach:6.3f} m/s (ควร < 0.15)")
    print(f"  จุดวัดระดับเหนือแผ่นเวียร์    : {h_tap[0]:.2f}–{h_tap[1]:.2f} m (4–5·hmax)")
    print("-" * 70)
    print(" ระดับ (พื้นรางนำน้ำ = ±0.000 m)")
    for name, el in [
        ("สันกำแพง / ขอบบน baffle", el_wall_top),
        ("ขอบบนร่อง V", el_notch_top),
        ("น้ำสูงสุด (ปั๊มหยุด, Qmax)", el_max_head),
        ("ยอด V (Vertex, ศูนย์ของ h)", el_vertex),
        ("ระดับน้ำท้ายสูงสุดที่ยอมได้", el_tailwater_limit),
        ("ปั๊ม START", el_start),
        ("สันกำแพงขั้น (บ่อปั๊ม→ราง)", 0.0),
        ("ปั๊ม STOP (Low level)", el_stop),
        ("ขอบล่าง baffle น้ำเข้า", el_inlet_baffle_bottom),
        ("พื้นบ่อปั๊ม", el_floor),
    ]:
        print(f"  {name:<34}: {el:+7.3f} m")
    print("-" * 70)
    print(" บ่อน้ำเข้า / บ่อปั๊ม")
    print(f"  ขนาดบ่อ (ภายใน)             : {args.sump_l:.2f} × {args.sump_w:.2f} m")
    print(f"  ปริมาตรทำงาน (Start–Stop)   : {v_active:6.2f} m³  (ต้องการ ≥ {v_required:.2f} m³)")
    print(f"  จำนวนครั้ง start สูงสุด      : {starts_worst:6.1f} ครั้ง/ชม. (จำกัด {args.starts})")
    print("-" * 70)

    checks = [
        ("0.05 ≤ hmax ≤ 0.38 m", 0.05 <= hmax <= 0.38),
        ("h/P ≤ 0.4", hmax / P <= 0.4),
        ("h/B ≤ 0.2", hmax / B <= 0.2),
        ("P ≥ 0.45 m", P >= 0.45),
        ("B ≥ 0.90 m", B >= 0.90),
        ("ความเร็วในรางนำน้ำ < 0.15 m/s", v_approach < 0.15),
        ("ร่อง V ลึกกว่า hmax + 80 mm", notch_depth >= hmax + 0.08 - 1e-9),
        ("Q recycle < Qin สูงสุด (มีน้ำผ่านเวียร์)", qr < qmax),
        ("START ต่ำกว่ายอด V", el_start < el_vertex),
        ("STOP สูงกว่าขอบล่าง baffle (กันอากาศเข้าปั๊ม)", el_stop > el_inlet_baffle_bottom),
        ("ปริมาตรทำงานบ่อปั๊มเพียงพอ", v_active >= v_required),
    ]
    print(" ตรวจสอบเกณฑ์")
    ok_all = True
    for text, ok in checks:
        ok_all &= ok
        print(f"  [{'OK' if ok else 'NG'}] {text}")
    print("=" * 70)
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
    p.add_argument("--qmax", type=float, default=10.0, help="อัตราการไหลเข้าสูงสุด [L/s] (default 10)")
    p.add_argument("--q-recycle", type=float, default=5.0, help="อัตราสูบไป Water recycle [L/s] (default 5)")
    p.add_argument("--p", type=float, default=0.45, help="ความสูงยอด V จากพื้นราง [m]")
    p.add_argument("--b", type=float, default=0.90, help="ความกว้างรางนำน้ำ [m]")
    p.add_argument("--notch-depth", type=float, default=0.25, help="ความลึกร่อง V [m]")
    p.add_argument("--l-approach", type=float, default=2.0, help="ความยาวรางนำน้ำ [m]")
    p.add_argument("--freeboard", type=float, default=0.20, help="ระยะเผื่อเหนือขอบร่อง V [m]")
    p.add_argument("--sump-l", type=float, default=1.40, help="ความยาวบ่อปั๊ม (ภายใน) [m]")
    p.add_argument("--sump-w", type=float, default=1.20, help="ความกว้างบ่อปั๊ม (ภายใน) [m]")
    p.add_argument("--sump-floor", type=float, default=-1.00, help="ระดับพื้นบ่อปั๊ม [m]")
    p.add_argument("--baffle-gap", type=float, default=0.30, help="ช่องลอดใต้ baffle น้ำเข้า [m]")
    p.add_argument("--start-below-vertex", type=float, default=0.10, help="ระดับ START ต่ำกว่ายอด V [m]")
    p.add_argument("--pump-submergence", type=float, default=0.60,
                   help="ระดับ STOP เหนือพื้นบ่อ [m] (ต้องท่วมมอเตอร์ตามสเปกผู้ผลิต)")
    p.add_argument("--starts", type=int, default=10, help="จำนวน start สูงสุดต่อชั่วโมง")
    p.add_argument("--csv", help="บันทึก rating table เป็นไฟล์ CSV")
    design(p.parse_args())

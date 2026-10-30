#!/usr/bin/env python3
"""
ออกแบบ/ตรวจสอบบ่อเวียร์ V-notch 90° (fully contracted)

ลำดับการไหลในบ่อเวียร์:
    น้ำเข้า -> โซนรับน้ำ -> ผนังกั้นลอดใต้ -> แผ่นกันคลื่นรูพรุน -> ช่วงตรงหน้าเวียร์
           -> แผ่น V-notch 90° -> ช่องท้ายเวียร์ -> ท่อออก 8"

สมการ Kindsvater-Shen (ISO 1438 / USBR Water Measurement Manual):
    Q = Ce * (8/15) * sqrt(2g) * tan(θ/2) * he^2.5,   he = h + kh
    สำหรับ θ = 90°:  Ce = 0.578,  kh = 0.00085 m
    => Q [m³/s] ≈ 1.365 * (h + 0.00085)^2.5

ใช้งาน:
    python3 weir_design.py                     # Qmax 100 m³/h, ปกติ 52 m³/h
    python3 weir_design.py --qmax 120 --qnormal 60
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
    qmax = args.qmax / 3600  # m³/h -> m³/s
    hmax = h_from_q(qmax)

    # --- ข้อกำหนด fully contracted 90° V-notch (ISO 1438 / USBR) ---
    # 0.05 <= h <= 0.38 m, h/P <= 0.4, h/B <= 0.2, P >= 0.45 m, B >= 0.90 m
    P = max(0.45, hmax / 0.4, args.p)
    B = max(0.90, hmax / 0.2, args.b)
    notch_depth = max(args.notch_depth, math.ceil((hmax + 0.08) * 20) / 20)
    l_approach = max(10 * hmax, args.l_approach)
    v_approach = qmax / (B * (P + hmax))
    v_gap = qmax / (B * args.baffle_gap)

    # --- ระดับ (พื้นบ่อเวียร์ = ±0.000) ---
    el_vertex = P
    el_max = P + hmax
    el_notch_top = P + notch_depth
    el_wall_top = el_notch_top + args.freeboard
    el_tail_limit = el_vertex - 0.06

    # --- น้ำท้ายเวียร์: ท่อออกที่พื้น คิดเป็น orifice (กรณีท่อไหลเต็มที่ปากท่อ) ---
    d_out = args.d_out
    a_out = math.pi * d_out ** 2 / 4
    v_out = qmax / a_out
    h_orifice = (qmax / (0.6 * a_out)) ** 2 / (2 * G)
    el_tail = d_out / 2 + h_orifice

    print("=" * 66)
    print(" บ่อเวียร์ V-notch 90° (fully contracted)")
    print("=" * 66)
    print(" ระดับน้ำเหนือยอด V (h)")
    for name, qh in [("สูงสุด", args.qmax), ("เฉลี่ย", args.qavg), ("ปกติ", args.qnormal)]:
        print(f"  Q {name:<7} {qh:6.1f} m³/h  ->  h = {h_from_q(qh/3600)*100:5.1f} cm")
    print("-" * 66)
    print(" ขนาด")
    print(f"  ความสูงยอด V จากพื้น (P)      : {P:5.2f} m")
    print(f"  ความกว้างภายในบ่อ (B)         : {B:5.2f} m")
    print(f"  ร่อง V ลึก / ปากกว้าง          : {notch_depth:5.2f} / {2*notch_depth:.2f} m")
    print(f"  ช่วงตรงหน้าเวียร์              : {l_approach:5.2f} m  (≥ 10·hmax = {10*hmax:.2f})")
    print(f"  จุดวัดระดับเหนือแผ่นเวียร์      : {args.x_tap:5.2f} m  (4–5·hmax = {4*hmax:.2f}–{5*hmax:.2f})")
    print(f"  ความเร็วน้ำหน้าเวียร์ (Qmax)    : {v_approach:5.3f} m/s (ควร < 0.15)")
    print(f"  ความเร็วลอดใต้ผนังกั้น         : {v_gap:5.3f} m/s")
    print(f"  ความเร็วในท่อออก Ø{d_out*1000:.0f} mm    : {v_out:5.2f} m/s")
    print("-" * 66)
    print(" ระดับ (พื้นบ่อ = ±0.000 m)")
    for name, el in [
        ("สันกำแพง", el_wall_top),
        ("ขอบบนร่อง V", el_notch_top),
        (f"น้ำสูงสุด ({args.qmax:.0f} m³/h)", el_max),
        (f"น้ำปกติ ({args.qnormal:.0f} m³/h)", P + h_from_q(args.qnormal / 3600)),
        ("ยอด V (h = 0)", el_vertex),
        ("น้ำท้ายสูงสุดที่ยอมได้", el_tail_limit),
        ("น้ำท้ายโดยประมาณ (Qmax)", el_tail),
        ("ขอบล่างผนังกั้น", args.baffle_gap),
        ("ท้องท่อออก", 0.0),
    ]:
        print(f"  {name:<28}: {el:+6.3f} m")
    print("-" * 66)

    checks = [
        ("0.05 ≤ hmax ≤ 0.38 m", 0.05 <= hmax <= 0.38),
        ("h/P ≤ 0.4", hmax / P <= 0.4),
        ("h/B ≤ 0.2", hmax / B <= 0.2),
        ("P ≥ 0.45 m", P >= 0.45),
        ("B ≥ 0.90 m", B >= 0.90),
        ("ความเร็วหน้าเวียร์ < 0.15 m/s", v_approach < 0.15),
        ("ร่อง V ลึก ≥ hmax + 80 mm", notch_depth >= hmax + 0.08 - 1e-9),
        ("จุดวัดระดับอยู่ในช่วง 4–5·hmax", 4 * hmax - 1e-9 <= args.x_tap <= 5 * hmax + 1e-9),
        ("น้ำท้ายต่ำกว่ายอด V ≥ 60 mm", el_tail <= el_tail_limit),
        ("ขอบล่างผนังกั้นต่ำกว่ายอด V", args.baffle_gap < el_vertex),
    ]
    print(" ตรวจสอบเกณฑ์")
    for text, ok in checks:
        print(f"  [{'OK' if ok else 'NG'}] {text}")
    print("=" * 66)

    rows = [(h / 100, q_from_h(h / 100)) for h in range(5, int(notch_depth * 100) - 4)]
    if args.csv:
        with open(args.csv, "w", encoding="utf-8") as f:
            f.write("h_cm,Q_m3_per_h,Q_L_per_s\n")
            for h, q in rows:
                f.write(f"{h*100:.0f},{q*3600:.2f},{q*1000:.3f}\n")
        print(f" บันทึกตาราง rating curve -> {args.csv}")
    else:
        print(" Rating table")
        print("   h [cm]   Q [m³/h]   Q [L/s]")
        for h, q in rows:
            print(f"   {h*100:6.0f}   {q*3600:8.1f}   {q*1000:7.2f}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--qmax", type=float, default=100.0, help="อัตราการไหลสูงสุดผ่านเวียร์ [m³/h]")
    p.add_argument("--qavg", type=float, default=62.0, help="อัตราการไหลเฉลี่ย [m³/h]")
    p.add_argument("--qnormal", type=float, default=52.0, help="อัตราการไหลปกติ [m³/h]")
    p.add_argument("--p", type=float, default=0.60, help="ความสูงยอด V จากพื้นบ่อ [m]")
    p.add_argument("--b", type=float, default=1.20, help="ความกว้างภายในบ่อ [m]")
    p.add_argument("--notch-depth", type=float, default=0.30, help="ความลึกร่อง V [m]")
    p.add_argument("--l-approach", type=float, default=2.20, help="ความยาวช่วงตรงหน้าเวียร์ [m]")
    p.add_argument("--x-tap", type=float, default=1.00, help="ระยะจุดวัดระดับเหนือแผ่นเวียร์ [m]")
    p.add_argument("--baffle-gap", type=float, default=0.25, help="ช่องลอดใต้ผนังกั้น [m]")
    p.add_argument("--freeboard", type=float, default=0.20, help="ระยะเผื่อเหนือขอบบนร่อง V [m]")
    p.add_argument("--d-out", type=float, default=0.200, help="เส้นผ่านศูนย์กลางท่อออก [m] (8\" ≈ 0.200)")
    p.add_argument("--csv", help="บันทึก rating table เป็นไฟล์ CSV")
    design(p.parse_args())

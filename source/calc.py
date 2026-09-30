"""Engineering calculations behind every worked example in the handbook.

All numbers quoted in the text come from here (placeholders {{key}}), so the
text, tables and charts stay consistent with each other.
"""
import math

G = 9.81
V = {}  # formatted values for the text


def put(key, value, nd=1, unit=""):
    if isinstance(value, str):
        V[key] = value
    else:
        V[key] = f"{value:,.{nd}f}" + (f" {unit}" if unit else "")
    return value


def area(D):
    return math.pi * D * D / 4


def hw_loss(L, Q, C, D):
    """Hazen-Williams head loss (m); L m, Q m3/s, D m."""
    if Q <= 0:
        return 0.0
    return 10.67 * L * Q ** 1.852 / (C ** 1.852 * D ** 4.8704)


def swamee_jain(Re, eps, D):
    return 0.25 / (math.log10(eps / (3.7 * D) + 5.74 / Re ** 0.9)) ** 2


def dw_loss(L, Q, D, eps, nu=0.801e-6):
    v = Q / area(D)
    Re = v * D / nu
    f = swamee_jain(Re, eps, D)
    return f * L / D * v * v / (2 * G), f, Re, v


def vh(v):
    return v * v / (2 * G)


def p_atm_kpa(z):
    return 101.325 * (1 - 2.25577e-5 * z) ** 5.25588


# water properties (T degC -> density kg/m3, vapour pressure kPa, kinematic viscosity m2/s)
WATER = {
    10: (999.7, 1.228, 1.306e-6),
    15: (999.1, 1.705, 1.139e-6),
    20: (998.2, 2.339, 1.004e-6),
    25: (997.0, 3.169, 0.893e-6),
    30: (995.7, 4.246, 0.801e-6),
    35: (994.0, 5.628, 0.724e-6),
    40: (992.2, 7.384, 0.658e-6),
    50: (988.0, 12.35, 0.553e-6),
    60: (983.2, 19.94, 0.474e-6),
    70: (977.8, 31.19, 0.413e-6),
    80: (971.8, 47.39, 0.365e-6),
    90: (965.3, 70.14, 0.326e-6),
    100: (958.4, 101.33, 0.294e-6),
}


def bisect(f, a, b, n=200):
    fa = f(a)
    for _ in range(n):
        m = (a + b) / 2
        fm = f(m)
        if (fm > 0) == (fa > 0):
            a, fa = m, fm
        else:
            b = m
    return (a + b) / 2


class Pump:
    """Quadratic H-Q, parabolic efficiency, rising NPSH3 (illustrative catalogue pump).

    Q unit is whatever the caller uses (m3/h or L/s); q_to_si converts to m3/s.
    """

    def __init__(self, H0, b, c, Qb, eta_max, n0, n2, npsh_exp=2.0, q_to_si=1 / 3600, speed=1480):
        self.H0, self.b, self.c = H0, b, c
        self.Qb, self.eta_max = Qb, eta_max
        self.n0, self.n2, self.ne = n0, n2, npsh_exp
        self.k = q_to_si
        self.speed = speed

    def H(self, Q, r=1.0):
        # affinity: H(Q, r) = r^2 * H(Q/r)
        return r * r * (self.H0 + self.b * Q / r - self.c * (Q / r) ** 2)

    def eta(self, Q, r=1.0):
        x = Q / (self.Qb * r)
        return max(self.eta_max * (2 * x - x * x), 0.0)

    def P(self, Q, r=1.0, rho=995.7):
        """Shaft power kW."""
        x = Q / (self.Qb * r)
        if x < 0.02:
            # limit at shut-off: rho g H0 Qb / (2 eta_max), scaled by r^3
            return rho * G * self.H(0, r) * self.Qb * r * self.k / (2 * self.eta_max) / 1000
        return rho * G * Q * self.k * self.H(Q, r) / self.eta(Q, r) / 1000

    def NPSH3(self, Q, r=1.0):
        x = Q / (self.Qb * r)
        return r * r * (self.n0 + self.n2 * x ** self.ne)

    def Hbep(self, r=1.0):
        return self.H(self.Qb * r, r)


def fmtn(v, nd=1):
    return f"{v:,.{nd}f}"


# ---------------------------------------------------------------------------
# Chapter examples (small)
# ---------------------------------------------------------------------------

def small_examples():
    # Unit example: 250 L/s @ 3.5 bar
    put("u_q_m3h", 250 * 3.6, 0)
    put("u_h", 3.5 * 100000 / (998.2 * G), 1)

    # Head loss comparison DN300 DI, 1 km, 150 L/s
    Q, D, L = 0.150, 0.300, 1000
    v = Q / area(D)
    put("hl_v", v, 2)
    nu = WATER[30][2]
    Re = v * D / nu
    put("hl_re", Re / 1e5, 2)
    eps = 0.10e-3
    f = swamee_jain(Re, eps, D)
    put("hl_f", f, 4)
    hdw = f * L / D * v * v / (2 * G)
    put("hl_dw", hdw, 2)
    put("hl_vh", vh(v), 3)
    for C in (100, 120, 130, 140):
        put(f"hl_hw{C}", hw_loss(L, Q, C, D), 2)
    put("hl_rel", 1e3 * eps / D * 1000 / 1000, 5)
    put("hl_epsD", eps / D, 6)
    # minor loss example: sum K = 6.3
    put("hl_minor", 6.3 * vh(v), 2)

    # Affinity example 1480 -> 1300 rpm
    Q1, H1, P1, n1, n2 = 500, 47.5, 76.0, 1480, 1300
    r = n2 / n1
    put("af_r", r, 3)
    put("af_q", Q1 * r, 0)
    put("af_h", H1 * r * r, 1)
    put("af_p", P1 * r ** 3, 1)

    # 60 Hz catalogue -> 50 Hz
    r = 1480 / 1780
    put("hz_r", r, 4)
    q_gpm, h_ft = 600, 150
    q = q_gpm * 0.2271
    h = h_ft * 0.3048
    put("hz_q60", q, 1)
    put("hz_h60", h, 1)
    put("hz_q50", q * r, 1)
    put("hz_h50", h * r * r, 1)
    put("hz_hpct", (1 - r * r) * 100, 0)

    # Trim example 400 -> 370 mm
    d1, d2 = 400, 370
    r = d2 / d1
    put("tr_r", r, 3)
    put("tr_q", 500 * r, 0)
    put("tr_h", 47.5 * r * r, 1)
    put("tr_p", 76 * r ** 3, 1)

    # Specific speed examples
    nq = 1480 * math.sqrt(540 / 3600 / 2) / 45.6 ** 0.75
    put("ns_ex1", nq, 1)
    put("ns_ex1_us", nq * 51.64, 0)

    # Power example: 0.2 m3/s at 40 m, eta 0.8, motor 0.95
    Ph = 998.2 * G * 0.2 * 40 / 1000
    put("pw_h", Ph, 1)
    put("pw_s", Ph / 0.80, 1)
    put("pw_e", Ph / 0.80 / 0.95, 1)

    # NPSH suction-lift example (site 50 m MSL, 30 degC, lift 4.5 m, losses 0.8 m)
    rho, pv, _ = WATER[30]
    pa = p_atm_kpa(50)
    Ha = pa * 1000 / (rho * G)
    Hv = pv * 1000 / (rho * G)
    put("np_pa", pa, 1)
    put("np_ha", Ha, 2)
    put("np_hv", Hv, 2)
    npsha = Ha - Hv - 4.5 - 0.8
    put("np_a", npsha, 2)
    put("np_ratio", npsha / 3.5, 2)
    put("np_margin", npsha - 3.5, 2)
    npsha2 = Ha - Hv - 2.5 - 0.5
    put("np_a2", npsha2, 2)
    put("np_ratio2", npsha2 / 3.5, 2)

    # Joukowsky example
    a, dv = 1100, 1500 / 3600 / area(0.7)
    put("wh_v", dv, 2)
    put("wh_dh", a * dv / G, 0)
    put("wh_tc", 2 * 4500 / a, 1)

    # Submergence example (HI 9.8 form)
    Q, D = 0.5, 0.65
    vb = Q / area(D)
    Fd = vb / math.sqrt(G * D)
    S = D * (1 + 2.3 * Fd)
    put("sb_v", vb, 2)
    put("sb_fd", Fd, 3)
    put("sb_s", S, 2)
    put("sb_d_calc", math.sqrt(4 * Q / (math.pi * 1.7)), 3)

    # Wet-well volume example Q = 60 L/s, Z = 10 starts/h
    put("ww_T", 60 / 10, 0)
    put("ww_V", 0.060 * 360 / 4, 1)

    # LCC example
    i, n = 0.05, 15
    pvf = (1 - (1 + i) ** -n) / i
    put("lcc_pvf", pvf, 2)
    return pvf


# ---------------------------------------------------------------------------
# Worked example 1 - high-lift pump station (water production)
# ---------------------------------------------------------------------------
EX1 = dict(
    Qt=1500.0, n_duty=3, q=500.0,
    LWL=100.0, HWL=104.0, CL=98.5, OUT=138.0,
    Dm=0.70, Lm=4500.0, Cm=120.0, Km=4.1,
    Ds=0.35, Ls=6.0, Ks=0.7, Dd=0.30, Ld=10.0, Kd=3.3, Cb=130.0,
    site=100.0, T=30,
)
P1 = Pump(H0=58.0, b=0.004, c=5.0e-5, Qb=540.0, eta_max=0.86, n0=2.2, n2=2.6,
          npsh_exp=2.0, q_to_si=1 / 3600, speed=1480)


def ex1_losses(q_each, n):
    e = EX1
    qs = q_each / 3600
    Qm = qs * n
    vs = qs / area(e["Ds"])
    vd = qs / area(e["Dd"])
    vm = Qm / area(e["Dm"])
    hs = hw_loss(e["Ls"], qs, e["Cb"], e["Ds"]) + e["Ks"] * vh(vs)
    hd = hw_loss(e["Ld"], qs, e["Cb"], e["Dd"]) + e["Kd"] * vh(vd)
    hmf = hw_loss(e["Lm"], Qm, e["Cm"], e["Dm"])
    hmm = e["Km"] * vh(vm)
    return dict(hs=hs, hd=hd, hmf=hmf, hmm=hmm, vs=vs, vd=vd, vm=vm)


def ex1_sys(Qtot, static):
    """System head (m) vs total station flow (m3/h), main only + branch for one of n pumps (n chosen by caller)."""
    e = EX1
    Qm = Qtot / 3600
    vm = Qm / area(e["Dm"])
    return static + hw_loss(e["Lm"], Qm, e["Cm"], e["Dm"]) + e["Km"] * vh(vm)


def ex1_branch(q):
    l = ex1_losses(q, 1)
    return l["hs"] + l["hd"]


def ex1_op(n, static, r=1.0):
    f = lambda q: P1.H(q, r) - ex1_branch(q) - ex1_sys(n * q, static)
    q = bisect(f, 1.0, 1200.0)
    return q


def example1():
    e = EX1
    rho, pv, _ = WATER[e["T"]]
    put("e1_hs_max", e["OUT"] - e["LWL"], 1)
    put("e1_hs_min", e["OUT"] - e["HWL"], 1)
    l = ex1_losses(e["q"], e["n_duty"])
    for k in ("vs", "vd", "vm"):
        put("e1_" + k, l[k], 2)
    for k in ("hs", "hd", "hmf", "hmm"):
        put("e1_" + k, l[k], 2)
    hs_f = hw_loss(e["Ls"], e["q"] / 3600, e["Cb"], e["Ds"])
    hd_f = hw_loss(e["Ld"], e["q"] / 3600, e["Cb"], e["Dd"])
    put("e1_hs_f", hs_f, 3)
    put("e1_hs_m", l["hs"] - hs_f, 3)
    put("e1_hd_f", hd_f, 3)
    put("e1_hd_m", l["hd"] - hd_f, 3)
    put("e1_vh_s", vh(l["vs"]), 3)
    put("e1_vh_d", vh(l["vd"]), 3)
    put("e1_vh_m", vh(l["vm"]), 4)
    tot = l["hs"] + l["hd"] + l["hmf"] + l["hmm"]
    put("e1_loss", tot, 2)
    put("e1_tdh_max", 38.0 + tot, 1)
    put("e1_tdh_min", 34.0 + tot, 1)
    put("e1_design_h", 38.0 + tot, 1)
    # system-curve table for chapter 4 (3 pumps sharing flow)
    rows_t = []
    for Q in (0, 500, 1000, 1500, 1800):
        qs = Q / 3600
        vm = qs / area(e["Dm"])
        hmf = hw_loss(e["Lm"], qs, e["Cm"], e["Dm"])
        hmm = e["Km"] * vh(vm)
        hb = ex1_branch(Q / 3)
        hmf_new = hw_loss(e["Lm"], qs, 140.0, e["Dm"])
        rows_t.append(f"<tr><td class='num'>{Q:,.0f}</td><td class='num'>{vm:.2f}</td><td class='num'>{hmf:.2f}</td>"
                      f"<td class='num'>{hmm + hb:.2f}</td><td class='num'><b>{38 + hmf + hmm + hb:.1f}</b></td>"
                      f"<td class='num'>{34 + hmf + hmm + hb:.1f}</td><td class='num'>{34 + hmf_new + hmm + hb:.1f}</td></tr>")
    V["e1_sys_table"] = "".join(rows_t)
    put("e1_hmf_new", hw_loss(e["Lm"], 1500 / 3600, 140.0, e["Dm"]), 2)
    # pump data at design
    q = e["q"]
    put("p1_h_at_q", P1.H(q), 1)
    put("p1_eta_at_q", P1.eta(q) * 100, 1)
    put("p1_hbep", P1.Hbep(), 1)
    put("p1_H0", P1.H0, 0)
    put("p1_qb", P1.Qb, 0)
    put("p1_emax", P1.eta_max * 100, 0)
    put("p1_ratio", P1.H0 / P1.Hbep(), 2)
    # operating points
    rows = []
    pmax = 0
    for n in (3, 2, 1):
        for static, lvl, name in ((38.0, e["LWL"], "LWL"), (34.0, e["HWL"], "HWL")):
            qo = ex1_op(n, static)
            H = P1.H(qo)
            eta = P1.eta(qo)
            Pw = P1.P(qo, rho=rho)
            pmax = max(pmax, Pw)
            ls = ex1_losses(qo, n)
            Ha = p_atm_kpa(e["site"]) * 1000 / (rho * G)
            Hv = pv * 1000 / (rho * G)
            npsha = Ha - Hv + (lvl - e["CL"]) - ls["hs"]
            npsh3 = P1.NPSH3(qo)
            rows.append(dict(n=n, static=static, lvl=name, q=qo, Q=n * qo, H=H, eta=eta, P=Pw,
                             pct=qo / P1.Qb * 100, npsha=npsha, npsh3=npsh3, vm=ls["vm"]))
    V["e1_rows"] = rows
    r33 = rows[0]
    put("e1_op_q", r33["q"], 0)
    put("e1_op_Q", r33["Q"], 0)
    put("e1_op_h", r33["H"], 1)
    put("e1_op_eta", r33["eta"] * 100, 1)
    put("e1_op_p", r33["P"], 1)
    put("e1_op_pct", r33["pct"], 0)
    put("e1_op_npsha", r33["npsha"], 2)
    put("e1_op_npsh3", r33["npsh3"], 2)
    put("e1_op_npshr", r33["npsha"] / r33["npsh3"], 2)
    r1 = rows[5]
    put("e1_ro_q", r1["q"], 0)
    put("e1_ro_h", r1["H"], 1)
    put("e1_ro_pct", r1["pct"], 0)
    put("e1_ro_p", r1["P"], 1)
    put("e1_ro_eta", r1["eta"] * 100, 1)
    put("e1_ro_npsha", r1["npsha"], 2)
    put("e1_ro_npsh3", r1["npsh3"], 2)
    put("e1_ro_vm", r1["vm"], 2)
    put("e1_pmax", pmax, 1)
    put("e1_p2hwl", rows[3]["P"], 1)
    put("e1_npsh_minratio", min(r["npsha"] / r["npsh3"] for r in rows), 2)
    put("e1_pmax_115", pmax * 1.10, 1)
    # site atmospheric
    Ha = p_atm_kpa(e["site"]) * 1000 / (rho * G)
    Hv = pv * 1000 / (rho * G)
    put("e1_pa", p_atm_kpa(e["site"]), 2)
    put("e1_ha", Ha, 2)
    put("e1_hv", Hv, 2)
    # VFD speed to hold 500 m3/h with 1 pump? -> find speed for single pump to deliver 500 at HWL
    rr = bisect(lambda r: P1.H(500, r) - ex1_branch(500) - ex1_sys(500, 34.0), 0.6, 1.0)
    put("e1_vfd_r", rr * 100, 1)
    put("e1_vfd_n", rr * 1480, 0)
    put("e1_vfd_eta", P1.eta(500, rr) * 100, 1)
    put("e1_vfd_p", P1.P(500, rr, rho=rho), 1)
    put("e1_vfd_h", P1.H(500, rr), 1)
    V["e1_vfd_rr"] = rr
    # 3 pumps at LWL: energy
    motor_eta = 0.955
    hrs = 20 * 365
    Pin = r33["P"] / motor_eta
    put("e1_pin", Pin, 1)
    E = 3 * Pin * hrs
    put("e1_E", E / 1e6, 2)
    vol = r33["Q"] * hrs
    put("e1_vol", vol / 1e6, 2)
    put("e1_spec", 3 * Pin / r33["Q"], 3)
    tariff = 4.5
    put("e1_cost", E * tariff / 1e6, 2)
    # comparison pump with 80% eff at same point
    Pin_b = rho * G * r33["q"] / 3600 * r33["H"] / 0.78 / 1000 / motor_eta
    put("e1_pin_b", Pin_b, 1)
    dE = 3 * (Pin_b - Pin) * hrs
    put("e1_dE", dE / 1000, 0)
    put("e1_dcost", dE * tariff / 1e6, 2)
    pvf = (1 - 1.05 ** -15) / 0.05
    put("e1_dcost_pv", dE * tariff * pvf / 1e6, 1)
    # specific speed
    nq = 1480 * math.sqrt(P1.Qb / 3600 / 2) / P1.Hbep() ** 0.75
    put("e1_nq", nq, 1)
    nss = 1480 * math.sqrt(P1.Qb / 3600 / 2) / P1.NPSH3(P1.Qb) ** 0.75
    put("e1_nss", nss, 0)
    put("e1_nss_us", nss * 51.64, 0)
    put("e1_npsh3_bep", P1.NPSH3(P1.Qb), 2)
    # surge
    return rows


# ---------------------------------------------------------------------------
# Worked example 2 - wastewater lift station
# ---------------------------------------------------------------------------
EX2 = dict(
    pop=40.0, lpcd=200.0, ret=0.8, inf=0.10,
    Dm=0.45, Lm=2000.0, Cm=110.0, Km=3.6,
    Db=0.25, Lb=8.0, Kb=3.3, Cb=120.0,
    OUT=9.0, STOP=-5.60, START1=-4.90, START2=-4.60, HLA=-4.30, INV=-4.00, FLOOR=-6.60,
    Z=10, AW=(3.6, 4.2),
)
P2 = Pump(H0=34.0, b=0.0, c=0.0012155, Qb=100.0, eta_max=0.78, n0=2.0, n2=3.0,
          npsh_exp=2.0, q_to_si=1 / 1000, speed=1460)


def ex2_branch(q):
    e = EX2
    qs = q / 1000
    v = qs / area(e["Db"])
    return hw_loss(e["Lb"], qs, e["Cb"], e["Db"]) + e["Kb"] * vh(v)


def ex2_sys(Q, static):
    e = EX2
    Qs = Q / 1000
    v = Qs / area(e["Dm"])
    return static + hw_loss(e["Lm"], Qs, e["Cm"], e["Dm"]) + e["Km"] * vh(v)


def ex2_op(n, static, r=1.0):
    f = lambda q: P2.H(q, r) - ex2_branch(q) - ex2_sys(n * q, static)
    return bisect(f, 1.0, 200.0)


def example2():
    e = EX2
    rho = 998.0
    qavg = e["pop"] * 1000 * e["lpcd"] * e["ret"] / 1000  # m3/d
    put("e2_qavg_d", qavg, 0)
    qavg_ls = qavg * 1000 / 86400
    put("e2_qavg", qavg_ls, 1)
    pf = 1 + 14 / (4 + math.sqrt(e["pop"]))
    put("e2_pf", pf, 2)
    qinf = e["inf"] * qavg_ls
    put("e2_qinf", qinf, 1)
    qpk = pf * qavg_ls
    put("e2_qpk_dry", qpk, 1)
    put("e2_qpk", qpk + qinf, 1)
    put("e2_qdes", 185, 0)
    qmin = 0.35 * qavg_ls
    put("e2_qmin", qmin, 1)
    A = area(e["Dm"])
    put("e2_Am", A, 4)
    put("e2_v185", 0.185 / A, 2)
    put("e2_qmin_v06", 0.6 * A * 1000, 0)
    # alternative DN400 losses
    put("e2_hf400", hw_loss(e["Lm"], 0.185, e["Cm"], 0.40), 1)
    put("e2_v400", 0.185 / area(0.40), 2)
    put("e2_hf450", hw_loss(e["Lm"], 0.185, e["Cm"], 0.45), 2)
    # statics
    s_max = e["OUT"] - e["STOP"]
    s_2 = e["OUT"] - e["START2"]
    s_1 = e["OUT"] - e["START1"]
    put("e2_s_max", s_max, 2)
    put("e2_s_min", s_2, 2)
    put("e2_s_1", s_1, 2)
    # design TDH at 185 with 2 pumps, static max
    q = 92.5
    vb = q / 1000 / area(e["Db"])
    put("e2_vb", vb, 2)
    hb = ex2_branch(q)
    put("e2_hb", hb, 2)
    vm = 0.185 / A
    hmf = hw_loss(e["Lm"], 0.185, e["Cm"], e["Dm"])
    hmm = e["Km"] * vh(vm)
    put("e2_hmf", hmf, 2)
    put("e2_hmm", hmm, 2)
    put("e2_tdh", s_max + hmf + hmm + hb, 1)
    # operating points
    rows = []
    for n in (2, 1):
        for static, lvl in ((s_max, "STOP"), (s_1 if n == 1 else s_2, "START")):
            qo = ex2_op(n, static)
            rows.append(dict(n=n, static=static, lvl=lvl, q=qo, Q=n * qo, H=P2.H(qo), eta=P2.eta(qo),
                             P=P2.P(qo, rho=rho), pct=qo / P2.Qb * 100, v=n * qo / 1000 / A))
    V["e2_rows"] = rows
    r2 = rows[0]
    r1 = rows[2]
    put("e2_op2_q", r2["q"], 1)
    put("e2_op2_Q", r2["Q"], 1)
    put("e2_op2_h", r2["H"], 1)
    put("e2_op2_eta", r2["eta"] * 100, 1)
    put("e2_op2_p", r2["P"], 1)
    put("e2_op2_v", r2["v"], 2)
    put("e2_op1_q", r1["q"], 1)
    put("e2_op1_h", r1["H"], 1)
    put("e2_op1_eta", r1["eta"] * 100, 1)
    put("e2_op1_p", r1["P"], 1)
    put("e2_op1_v", r1["v"], 2)
    put("e2_op1_pct", r1["pct"], 0)
    put("e2_op2_pct", r2["pct"], 0)
    # max power across curve
    pmax = max(P2.P(qq, rho=rho) for qq in [i * 0.5 for i in range(1, 300)] if P2.H(qq) > 5)
    put("e2_pmax", pmax, 1)
    put("e2_hbep", P2.Hbep(), 1)
    nq = 1460 * math.sqrt(0.100) / P2.Hbep() ** 0.75
    put("e2_nq", nq, 0)
    # wet well
    q1 = r1["q"]
    T = 60 / e["Z"]
    Vreq = q1 / 1000 * T * 60 / 4
    put("e2_T", T, 0)
    put("e2_Vreq", Vreq, 1)
    dh = e["START1"] - e["STOP"]
    put("e2_dh", dh, 2)
    put("e2_Areq", Vreq / dh, 1)
    Aw = e["AW"][0] * e["AW"][1]
    put("e2_Aw", Aw, 1)
    Vact = Aw * dh
    put("e2_Vact", Vact, 1)
    Z = q1 / 1000 * 3600 / (4 * Vact)
    put("e2_Zact", Z, 1)
    # force main retention
    Vol = A * e["Lm"]
    put("e2_vol", Vol, 0)
    put("e2_ret_avg", Vol / (qavg_ls / 1000) / 3600, 1)
    put("e2_ret_min", Vol / (qmin / 1000) / 3600, 1)
    # VFD minimum speed for 0.6 m/s in force main with 1 pump at STOP static
    qv = 0.6 * A * 1000
    rr = bisect(lambda r: P2.H(qv, r) - ex2_branch(qv) - ex2_sys(qv, s_max), 0.5, 1.0)
    put("e2_vfd_r", rr * 100, 0)
    put("e2_vfd_hz", rr * 50, 1)
    V["e2_vfd_rr"] = rr
    # speed at which flow becomes zero (shut-off = static)
    r0 = math.sqrt(s_max / P2.H0)
    put("e2_r0", r0 * 100, 0)
    put("e2_hz0", r0 * 50, 1)
    # energy for average day
    return rows


# ---------------------------------------------------------------------------
# Worked example 3 - raw-water intake with large river level variation
# ---------------------------------------------------------------------------
EX3 = dict(LOW=2.0, FLOOD=9.5, OUT=18.0, Dm=1.0, Lm=1200.0, Cm=120.0, Km=4.0, kcol=4.0)
P3 = Pump(H0=28.0, b=0.0, c=34.0, Qb=0.50, eta_max=0.85, n0=4.0, n2=3.5, npsh_exp=2.5,
          q_to_si=1.0, speed=985)


def ex3_sys(Q, static):
    e = EX3
    v = Q / area(e["Dm"])
    return static + hw_loss(e["Lm"], Q, e["Cm"], e["Dm"]) + e["Km"] * vh(v)


def ex3_col(q):
    return EX3["kcol"] * q * q


def ex3_op(n, static, r=1.0):
    return bisect(lambda q: P3.H(q, r) - ex3_col(q) - ex3_sys(n * q, static), 0.01, 1.2)


def example3():
    e = EX3
    s_low = e["OUT"] - e["LOW"]
    s_fl = e["OUT"] - e["FLOOD"]
    put("e3_s_low", s_low, 1)
    put("e3_s_fl", s_fl, 1)
    rows = []
    for static, name in ((s_low, "น้ำต่ำสุด"), (s_fl, "น้ำหลาก")):
        q = ex3_op(2, static)
        rows.append(dict(name=name, static=static, q=q, H=P3.H(q), eta=P3.eta(q), P=P3.P(q, rho=997),
                         pct=q / P3.Qb * 100))
    V["e3_rows"] = rows
    put("e3_q_low", rows[0]["q"], 3)
    put("e3_pct_low", rows[0]["pct"], 0)
    put("e3_q_fl", rows[1]["q"], 3)
    put("e3_pct_fl", rows[1]["pct"], 0)
    put("e3_p_fl", rows[1]["P"], 0)
    put("e3_p_low", rows[0]["P"], 0)
    put("e3_h_low", rows[0]["H"], 1)
    put("e3_h_fl", rows[1]["H"], 1)
    put("e3_eta_fl", rows[1]["eta"] * 100, 1)
    put("e3_eta_low", rows[0]["eta"] * 100, 1)
    # VFD at flood to hold 0.5 m3/s per pump
    rr = bisect(lambda r: P3.H(0.5, r) - ex3_col(0.5) - ex3_sys(1.0, s_fl), 0.5, 1.0)
    V["e3_vfd_rr"] = rr
    put("e3_vfd_r", rr * 100, 1)
    put("e3_vfd_n", rr * 985, 0)
    put("e3_vfd_pct", 0.5 / (P3.Qb * rr) * 100, 0)
    put("e3_vfd_eta", P3.eta(0.5, rr) * 100, 1)
    put("e3_vfd_p", P3.P(0.5, rr, rho=997), 0)
    put("e3_npsh_fl", P3.NPSH3(rows[1]["q"]), 1)
    put("e3_npsh_bep", P3.NPSH3(0.5), 1)
    put("e3_hbep", P3.Hbep(), 1)
    put("e3_nq", 985 * math.sqrt(P3.Qb) / P3.Hbep() ** 0.75, 0)
    rho, pv, _ = WATER[30]
    Ha = p_atm_kpa(0) * 1000 / (rho * G)
    Hv = pv * 1000 / (rho * G)
    npsha = Ha - Hv + (e["LOW"] - 0.60) - 0.02
    put("e3_npsha_low", npsha, 1)
    put("e3_npsh3_low", P3.NPSH3(rows[0]["q"]), 1)
    put("e3_npsh_ratio", npsha / P3.NPSH3(rows[0]["q"]), 2)
    put("e3_col", ex3_col(0.5), 1)
    put("e3_hmf", hw_loss(e["Lm"], 1.0, e["Cm"], e["Dm"]), 2)
    put("e3_hmm", e["Km"] * vh(1.0 / area(e["Dm"])), 2)
    put("e3_vm", 1.0 / area(e["Dm"]), 2)
    put("e3_tdh_low", s_low + hw_loss(e["Lm"], 1.0, e["Cm"], e["Dm"]) + e["Km"] * vh(1.0 / area(e["Dm"])) + ex3_col(0.5), 1)
    put("e3_tdh_fl", s_fl + hw_loss(e["Lm"], 1.0, e["Cm"], e["Dm"]) + e["Km"] * vh(1.0 / area(e["Dm"])) + ex3_col(0.5), 1)
    put("e3_pmax", max(P3.P(q / 100, rho=997) for q in range(5, 75)), 0)
    return rows


def exercises():
    rho, pv, nu = WATER[30]
    # 1 head from gauges
    dp = (4.2 + 0.35) * 1e5
    vd = 0.040 / area(0.15)
    vs = 0.040 / area(0.20)
    put("x1_hp", dp / (rho * G), 2)
    put("x1_vd", vd, 2)
    put("x1_vs", vs, 2)
    put("x1_hv", (vd ** 2 - vs ** 2) / (2 * G), 2)
    put("x1_h", dp / (rho * G) + (vd ** 2 - vs ** 2) / (2 * G), 1)
    # 2 Hazen-Williams HDPE
    put("x2_v", 0.25 / area(0.44), 2)
    put("x2_hf", hw_loss(3000, 0.25, 140, 0.44), 1)
    put("x2_hf_old", hw_loss(3000, 0.25, 130, 0.44), 1)
    # 3 operating point
    q = math.sqrt(20 / (8 / 300 ** 2 + 1.2e-4))
    put("x3_q", q, 0)
    put("x3_h", 40 - 1.2e-4 * q * q, 1)
    put("x3_k", 8 / 300 ** 2 * 1e5, 3)
    # 4 affinity
    r = 1200 / 1450
    put("x4_r", r, 4)
    put("x4_q", 300 * r, 0)
    put("x4_h", 28 * r * r, 1)
    put("x4_p", 30 * r ** 3, 1)
    # 5 NPSH at 300 m, 35 C
    rho35, pv35, _ = WATER[35]
    pa = p_atm_kpa(300)
    Ha = pa * 1000 / (rho35 * G)
    Hv = pv35 * 1000 / (rho35 * G)
    n = Ha - Hv + 1.2 - 0.6
    put("x5_pa", pa, 1)
    put("x5_ha", Ha, 2)
    put("x5_hv", Hv, 2)
    put("x5_n", n, 2)
    put("x5_r", n / 5.2, 2)
    # 6 submergence
    V6 = 0.25 / area(0.45)
    F6 = V6 / math.sqrt(G * 0.45)
    put("x6_v", V6, 2)
    put("x6_f", F6, 3)
    put("x6_s", 0.45 * (1 + 2.3 * F6), 2)
    # 7 wet well
    put("x7_v", 0.045 * 300 / 4, 2)
    put("x7_dh", 0.045 * 300 / 4 / 6.25, 2)
    # 8 energy
    ph = rho * G * 0.15 * 32 / 1000
    ps = ph / 0.80
    pe = ps / 0.94
    put("x8_ph", ph, 1)
    put("x8_ps", ps, 1)
    put("x8_pe", pe, 1)
    put("x8_kwh", pe * 16 * 365 / 1000, 0)
    put("x8_cost", pe * 16 * 365 * 4.5 / 1e6, 2)
    put("x8_es", 32 / (367 * 0.80 * 0.94), 3)
    # 9 hammer
    put("x9_dh", 400 * 1.5 / G, 0)
    put("x9_tc", 2 * 1500 / 400, 1)
    # 10 parallel
    q1 = math.sqrt(20 / 2.5e-4)
    q2 = math.sqrt(20 / 4e-4)
    put("x10_q1", q1, 0)
    put("x10_q2", q2, 0)
    put("x10_Q2", 2 * q2, 0)
    put("x10_gain", (2 * q2 / q1 - 1) * 100, 0)
    put("x10_h1", 50 - 2e-4 * q1 * q1, 1)
    put("x10_h2", 50 - 2e-4 * q2 * q2, 1)


def tables():
    """HTML table bodies for the worked examples."""
    lv = {"LWL": "ต่ำสุด (LWL)", "HWL": "สูงสุด (HWL)"}
    out = []
    for r in V["e1_rows"]:
        ok = 70 <= r["pct"] <= 120
        cls = "" if ok else " class='bad'"
        out.append(f"<tr{cls}><td class='c'>{r['n']}</td><td>{lv[r['lvl']]}</td><td class='num'>{r['q']:,.0f}</td>"
                   f"<td class='num'>{r['Q']:,.0f}</td><td class='num'>{r['H']:.1f}</td><td class='num'>{r['eta'] * 100:.1f}</td>"
                   f"<td class='num'>{r['P']:.1f}</td><td class='num'><b>{r['pct']:.0f}%</b></td><td class='num'>{r['npsha']:.1f}</td>"
                   f"<td class='num'>{r['npsh3']:.1f}</td><td class='num'>{r['npsha'] / r['npsh3']:.2f}</td>"
                   f"<td class='c'>{'ใน POR' if ok else 'นอก POR'}</td></tr>")
    V["e1_op_table"] = "".join(out)
    lv2 = {"STOP": "ระดับหยุด", "START": "ระดับสั่งเดิน"}
    out = []
    for r in V["e2_rows"]:
        out.append(f"<tr><td class='c'>{r['n']}</td><td>{lv2[r['lvl']]}</td><td class='num'>{r['static']:.2f}</td><td class='num'>{r['q']:.1f}</td>"
                   f"<td class='num'>{r['Q']:.1f}</td><td class='num'>{r['H']:.1f}</td><td class='num'>{r['eta'] * 100:.1f}</td>"
                   f"<td class='num'>{r['P']:.1f}</td><td class='num'><b>{r['pct']:.0f}%</b></td><td class='num'>{r['v']:.2f}</td></tr>")
    V["e2_op_table"] = "".join(out)
    out = []
    for r in V["e3_rows"]:
        bad = r["pct"] > 115
        cls = " class='bad'" if bad else ""
        out.append(f"<tr{cls}><td>{r['name']}</td><td class='num'>{r['static']:.1f}</td><td class='num'>{r['q']:.3f}</td>"
                   f"<td class='num'>{r['H']:.1f}</td><td class='num'>{r['eta'] * 100:.1f}</td><td class='num'>{r['P']:.0f}</td>"
                   f"<td class='num'><b>{r['pct']:.0f}%</b></td><td class='num'>{P3.NPSH3(r['q']):.1f}</td></tr>")
    rr = V["e3_vfd_rr"]
    out.append(f"<tr class='ok'><td>น้ำหลาก + VFD {rr * 100:.1f}%</td><td class='num'>{EX3['OUT'] - EX3['FLOOD']:.1f}</td><td class='num'>0.500</td>"
               f"<td class='num'>{P3.H(0.5, rr):.1f}</td><td class='num'>{P3.eta(0.5, rr) * 100:.1f}</td><td class='num'>{P3.P(0.5, rr, rho=997):.0f}</td>"
               f"<td class='num'><b>{0.5 / (P3.Qb * rr) * 100:.0f}%</b></td><td class='num'>{P3.NPSH3(0.5, rr):.1f}</td></tr>")
    V["e3_op_table"] = "".join(out)


def run_all():
    small_examples()
    example1()
    example2()
    example3()
    exercises()
    tables()
    return V


if __name__ == "__main__":
    run_all()
    for k, v in V.items():
        if not isinstance(v, list):
            print(k, "=", v)
    for k in ("e1_rows", "e2_rows", "e3_rows"):
        for r in V[k]:
            print(k, {a: (round(b, 3) if isinstance(b, float) else b) for a, b in r.items()})

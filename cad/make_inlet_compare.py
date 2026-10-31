import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
from matplotlib.patches import Rectangle, Polygon
import numpy as np
fm.fontManager.addfont('/usr/share/fonts/opentype/tlwg/Loma.otf'); fm.fontManager.addfont('/usr/share/fonts/opentype/tlwg/Loma-Bold.otf')
plt.rcParams['font.family'] = ['Loma', 'DejaVu Sans']
T, TOP, OD, ID = 0.20, 1.20, 0.168, 0.154
ZAVG, ZMAX = 0.958, 0.980
fig, axs = plt.subplots(2, 1, figsize=(13, 10))
for ax, zin, ttl, ok in [(axs[0], 1.10, "ตอนนี้: ท่อกึ่งกลาง +1.10", False), (axs[1], 1.00, "เสนอ: ท่อกึ่งกลาง +1.00", True)]:
    # water
    ax.add_patch(Rectangle((0, 0.55), 1.15, ZAVG - 0.55, color='#9ecae1', zorder=1))
    ax.plot([0, 1.15], [ZMAX, ZMAX], ls='--', c='#3182bd', lw=1)
    ax.text(1.16, ZMAX, " น้ำสูงสุด +0.98", va='bottom', fontsize=11, color='#3182bd')
    ax.text(1.16, ZAVG, " น้ำปกติ +0.96", va='top', fontsize=11, color='#3182bd')
    # wall (head wall) with hatch, hole for pipe
    ax.add_patch(Rectangle((-T, 0.55), T, TOP - 0.55, fc='#d9d9d9', ec='#333', hatch='///', zorder=2))
    # baffle wall at x=1.00
    ax.add_patch(Rectangle((1.00, 0.55), 0.10, TOP - 0.55, fc='#d9d9d9', ec='#333', hatch='///', zorder=2))
    ax.text(1.05, 1.215, "ผนังกันน้ำกระแทก", ha='center', fontsize=11)
    # pipe
    ax.add_patch(Rectangle((-0.75, zin - OD/2), 0.85, OD, fc='#f4a259', ec='#333', zorder=3))
    ax.add_patch(Rectangle((-0.75, zin - ID/2), 0.85, ID, fc='#fde3c8', ec='none', zorder=3))
    ax.text(-0.72, zin - OD/2 - 0.035, 'ท่อน้ำเข้า 6"', fontsize=12)
    # jet
    v = 1.49; x0 = 0.10
    if zin - ID/2 > ZAVG:
        drop = zin - ZAVG; xr = v*np.sqrt(2*drop/9.81)
        xs = np.linspace(0, xr, 30); zs = zin - 9.81/2*(xs/v)**2
        ax.fill_between(x0+xs, zs - ID*0.45, zs + ID*0.45, color='#6baed6', alpha=0.85, zorder=4)
        for k in range(6):
            ax.plot(x0+xr+0.02*np.cos(k), ZAVG+0.03+0.03*np.sin(k*1.7), 'o', ms=4, color='white', mec='#6baed6', zorder=5)
        ax.text(0.40, 1.10, "น้ำพุ่งตกลงผิวน้ำ\n→ กระฉอก / มีฟอง / เสียงดัง", fontsize=11, color='#b45309')
    else:
        ax.add_patch(Polygon([(x0, zin-ID/2), (x0, zin+ID/2), (0.55, ZAVG), (0.55, zin-ID/2-0.05)], color='#6baed6', alpha=0.8, zorder=4))
        ax.text(0.40, 1.10, "ปากท่อจมน้ำ 4–6 cm\n→ น้ำไหลเข้าใต้ผิวน้ำ เงียบกว่า", fontsize=11, color='#15803d')
    # dims: cover above pipe
    top_pipe = zin + OD/2
    cov = TOP - top_pipe
    xd = -0.30
    col = 'red' if not ok else 'green'
    ax.annotate('', xy=(-0.10, TOP), xytext=(-0.10, top_pipe), arrowprops=dict(arrowstyle='<->', color=col, lw=2), zorder=6)
    ax.annotate(f"คอนกรีตเหนือท่อเหลือ {cov*1000:.0f} mm {'✘ บางเกินไป' if not ok else '✔ พอ'}", xy=(-0.10, (TOP + top_pipe)/2),
                xytext=(0.15, 1.265), fontsize=13, color=col, fontweight='bold',
                arrowprops=dict(arrowstyle='->', color=col), bbox=dict(fc='white', ec=col, boxstyle='round'))
    # levels
    for z, lab in [(TOP, "ขอบผนัง +1.20"), (zin, f"กึ่งกลางท่อ {zin:+.2f}")]:
        ax.plot([-0.95, -T], [z, z], c='#555', lw=0.8, ls=':')
        ax.text(-0.95, z + 0.006, lab, fontsize=11, color='#333')
    ax.set_title(ttl, fontsize=15, fontweight='bold', color='green' if ok else '#b91c1c')
    ax.set_xlim(-1.0, 1.50); ax.set_ylim(0.80, 1.32); ax.axis('off')
fig.suptitle("เทียบระดับท่อน้ำเข้า 6\" (ช่วงต้นช่อง 1 — รูปตัดตามยาว)", fontsize=17, fontweight='bold')
fig.text(0.5, 0.025, "(แนวตั้งขยายประมาณ 3 เท่าให้เห็นชัด)   ไม่เปลี่ยน: เวลาน้ำค้าง / เวียร์ / Flow meter / ความสูงผนัง   •   ต้องเช็คหน้างาน: ท่อต้นทางลดลง 10 cm ได้ และปั๊มต้นทางมีเช็ควาล์ว",
         ha='center', fontsize=12)
fig.tight_layout(rect=(0, 0.06, 1, 0.94))
fig.savefig('cad/inlet_compare.png', dpi=150, facecolor='white')

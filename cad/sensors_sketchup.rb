# encoding: UTF-8
# วาดเซนเซอร์ 2 ตัว + กล่อง Flow meter ตามขนาดใน datasheet (หน่วย mm)
#   1) WTW UV 705 IQ SAC (หัววัด BOD)  — datasheet D2.16: Ø60, ยาว 774, รวม socket 865
#   2) Badger DL10 (หัววัดระดับน้ำของ Flow meter) — datasheet IS-4000: 81 × 51 × 51, เกลียว G1
#   3) Badger IS-4000 (กล่องแสดงผล)      — datasheet: 164 × 148 × 60, แผ่นยึด 65 × 249
# ใช้งาน: SketchUp > Extensions > Developer > Ruby Console
#   load 'C:/temp/sensors_sketchup.rb'    (หรือเปิดไฟล์ด้วย Notepad แล้ว copy ทั้งหมดไปวางใน Ruby Console)
# ระบบพิกัดเดียวกับโมเดลบ่อ: ±0 = พื้นช่อง 2–3, x = 0 ผิวในผนังหัวบ่อ, น้ำไหลตามแกน x (สีแดง)

model = Sketchup.active_model
model.start_operation('เซนเซอร์', true)

def pt(x, y, z) Geom::Point3d.new(x.mm, y.mm, z.mm) end

def mat(model, name, rgb)
  m = model.materials[name] || model.materials.add(name)
  m.color = Sketchup::Color.new(*rgb)
  m
end

# ทรงกระบอกตั้งตามแกน z (ฐานที่ z0 สูง h)
def cyl(ents, cx, cy, z0, r, h, material, seg = 32)
  g = ents.add_group
  f = g.entities.add_face(g.entities.add_circle(pt(cx, cy, z0), Z_AXIS, r.mm, seg))
  f.reverse! if f.normal.z < 0
  f.pushpull(h.mm)
  g.material = material
  g
end

# กล่อง (x1..x2, y1..y2, z1..z2)
def blk(ents, x1, x2, y1, y2, z1, z2, material)
  g = ents.add_group
  f = g.entities.add_face(pt(x1, y1, z1), pt(x2, y1, z1), pt(x2, y2, z1), pt(x1, y2, z1))
  f.reverse! if f.normal.z < 0
  f.pushpull((z2 - z1).mm)
  g.material = material
  g
end

ti    = mat(model, 'ไทเทเนียม (BOD)', [175, 178, 182])
dark  = mat(model, 'ช่องวัด (BOD)', [40, 40, 45])
black = mat(model, 'พลาสติกดำ', [30, 30, 30])
pvdf  = mat(model, 'PVDF (DL10)', [235, 235, 225])
alu   = mat(model, 'อะลูมิเนียมพ่นสี (IS-4000)', [70, 110, 160])
lcd   = mat(model, 'จอ LCD', [150, 190, 160])
ss    = mat(model, 'สแตนเลส', [120, 140, 170])
cable = mat(model, 'สายไฟ', [20, 20, 20])

# ---------------------------------------------------------------- 1) WTW UV 705 IQ SAC
# จุดอ้างอิง = ปลายหัววัด (ล่างสุด) แกนตั้งขึ้น / ช่องวัด 5 mm อยู่ห่างปลาย 381
uv = model.definitions['WTW UV 705 IQ SAC'] || model.definitions.add('WTW UV 705 IQ SAC')
if uv.entities.length == 0
  e = uv.entities
  cyl(e, 0, 0, 0, 30, 371, ti)              # ตัวหัววัดช่วงล่าง
  cyl(e, 0, 0, 371, 30, 20, dark)           # ช่องวัด (แถบสีเข้ม 20 mm แทนช่องกว้าง 5 mm)
  cyl(e, 0, 0, 391, 30, 383, ti)            # ตัวหัววัดช่วงบน (ถึง 774)
  cyl(e, 0, 0, 774, 22, 91, black)          # socket SACIQ (ถึง 865)
  cyl(e, 0, 0, 865, 4, 400, cable)          # สาย
end

# ---------------------------------------------------------------- 2) Badger DL10
# จุดอ้างอิง = หน้าหัววัด (ล่างสุด ต้องหันลงหาผิวน้ำ)
dl = model.definitions['Badger DL10'] || model.definitions.add('Badger DL10')
if dl.entities.length == 0
  e = dl.entities
  cyl(e, 0, 0, 0, 25.5, 81, pvdf)           # ตัวหัววัด 51 × 81
  cyl(e, 0, 0, 81, 16.5, 20, pvdf)          # เกลียว G1 (ขันเข้าคาน)
  cyl(e, 0, 0, 101, 4, 300, cable)          # สาย
end

# ---------------------------------------------------------------- 3) Badger IS-4000
# จุดอ้างอิง = กึ่งกลางด้านหลังของแผ่นยึด ที่ระดับล่างสุด / ติดผนังด้านหลัง (แกน -y)
is4 = model.definitions['Badger IS-4000'] || model.definitions.add('Badger IS-4000')
if is4.entities.length == 0
  e = is4.entities
  blk(e, -32.5, 32.5, 0, 5, 0, 249, ss)             # แผ่นยึด 65 × 249
  blk(e, -82, 82, 5, 65, 50, 198, alu)              # กล่อง 164 × 148 ลึก 60
  blk(e, -50, 50, 65, 67, 120, 180, lcd)            # จอ
  cyl(e, -40, 35, 30, 10, 20, black)                # ช่องร้อยสาย M20 (2 ช่อง)
  cyl(e, 40, 35, 30, 10, 20, black)
end

ents = model.active_entities
root = ents.add_group
root.name = 'เซนเซอร์'
r = root.entities

# ---------------------------------------------------------------- วางเรียงโชว์ข้างบ่อ (พร้อมป้าย)
sy = -1700
r.add_instance(uv, Geom::Transformation.new(pt(3000, sy, 0)))
r.add_text("WTW UV 705 IQ SAC (BOD)\nØ60 ยาว 774 / รวม socket 865\nช่องวัดห่างปลาย 381", pt(3000, sy, 900), Geom::Vector3d.new(0, -300.mm, 200.mm))
r.add_instance(dl, Geom::Transformation.new(pt(3700, sy, 0)))
r.add_text("Badger DL10 (Flow meter)\n51 × 81 เกลียว G1\nวัดได้ 50–1,250 mm", pt(3700, sy, 120), Geom::Vector3d.new(0, -300.mm, 300.mm))
r.add_instance(is4, Geom::Transformation.new(pt(4300, sy, 0)))
r.add_text("Badger IS-4000\nกล่อง 164 × 148 × 60\nแผ่นยึด 65 × 249", pt(4300, sy + 60, 220), Geom::Vector3d.new(0, -300.mm, 300.mm))

# ---------------------------------------------------------------- วางในตำแหน่งจริงตามแบบ (ช่อง 3)
# Flow meter: ห่างแผ่นเวียร์ 0.80 (x = 4000) กลางราง (y = 625) หน้าหัววัด +1.10 ขันเข้าคานสแตนเลส
r.add_instance(dl, Geom::Transformation.new(pt(4000, 625, 1100)))
# BOD: ต้นรางตรง + 0.30 (x = 3300) ห่างผนังข้าง 0.15 (y = 150) ปลาย +0.20 แนวตั้ง
r.add_instance(uv, Geom::Transformation.new(pt(3300, 150, 200)))
cyl(r, 3300, 150, 1065, 21, 175, ss)                      # ท่อจับหัววัด Ø42 ถึงระดับขอบบ่อ
blk(r, 3280, 3320, -200, 171, 1200, 1240, ss)             # แขนยึดวางบนขอบผนัง
r.add_text("ช่องวัด BOD อยู่ที่ +0.58\nน้ำหยุดไหลค้างที่ +0.50 → ช่องวัดแห้ง\nต้องเลือกวิธีติดตั้ง (ดูหมายเหตุ)", pt(3300, 120, 581), Geom::Vector3d.new(0, -600.mm, 300.mm))
# กล่อง IS-4000: ตำแหน่งยังไม่กำหนด — วางไว้นอกผนังข้างช่อง 3 ตรงกับหัววัด เพื่อดูขนาด
r.add_instance(is4, Geom::Transformation.new(pt(4000, -200, 1300)) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 180.degrees))

model.commit_operation
puts 'วาดเซนเซอร์เสร็จแล้ว (กลุ่มชื่อ "เซนเซอร์")'

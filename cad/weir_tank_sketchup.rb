# encoding: UTF-8
# วาดบ่อวัดน้ำ 3 ช่อง (ปั๊มจุ่ม | ม่านน้ำ | เวียร์ V-notch 90°) หน่วย mm — สร้างจาก cad/make_3d.py
# ใช้งาน: SketchUp > Extensions > Developer > Ruby Console แล้วพิมพ์  load 'C:/path/weir_tank_sketchup.rb'
# ระดับ ±0 = ผิวพื้นช่อง 2–3 / x = 0 ที่ผิวในผนังหัวบ่อ (น้ำไหลตามแกน x)
model = Sketchup.active_model
model.start_operation('บ่อวัดน้ำ', true)
def pt(x, y, z) Geom::Point3d.new(x.mm, y.mm, z.mm) end
mats = {}
mats['คอนกรีต'] = model.materials['คอนกรีต'] || model.materials.add('คอนกรีต'); mats['คอนกรีต'].color = Sketchup::Color.new(190, 190, 185); mats['คอนกรีต'].alpha = 1.0
mats['สแตนเลส'] = model.materials['สแตนเลส'] || model.materials.add('สแตนเลส'); mats['สแตนเลส'].color = Sketchup::Color.new(120, 140, 170); mats['สแตนเลส'].alpha = 1.0
mats['ท่อ'] = model.materials['ท่อ'] || model.materials.add('ท่อ'); mats['ท่อ'].color = Sketchup::Color.new(235, 150, 60); mats['ท่อ'].alpha = 1.0
mats['อุปกรณ์'] = model.materials['อุปกรณ์'] || model.materials.add('อุปกรณ์'); mats['อุปกรณ์'].color = Sketchup::Color.new(230, 160, 40); mats['อุปกรณ์'].alpha = 1.0
mats['เครื่องวัด'] = model.materials['เครื่องวัด'] || model.materials.add('เครื่องวัด'); mats['เครื่องวัด'].color = Sketchup::Color.new(240, 240, 245); mats['เครื่องวัด'].alpha = 1.0
mats['น้ำ'] = model.materials['น้ำ'] || model.materials.add('น้ำ'); mats['น้ำ'].color = Sketchup::Color.new(90, 160, 220); mats['น้ำ'].alpha = 0.45
tags = {}
tags['คอนกรีต'] = model.layers['คอนกรีต'] || model.layers.add('คอนกรีต')
tags['แผ่นสแตนเลส'] = model.layers['แผ่นสแตนเลส'] || model.layers.add('แผ่นสแตนเลส')
tags['ท่อ'] = model.layers['ท่อ'] || model.layers.add('ท่อ')
tags['ปั๊มและเครื่องวัด'] = model.layers['ปั๊มและเครื่องวัด'] || model.layers.add('ปั๊มและเครื่องวัด')
tags['น้ำ'] = model.layers['น้ำ'] || model.layers.add('น้ำ')
root = model.active_entities.add_group
root.name = 'บ่อวัดน้ำ 3 ช่อง'
def solid(root, name, tag, mat)
  g = root.entities.add_group; g.name = name; g.layer = tag; g.material = mat
  yield g.entities
  g
end
solid(root, 'พื้นช่อง 1', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(-200,-1325.0,-1500), pt(2100,-1325.0,-1500), pt(2100,2575.0,-1500), pt(-200,2575.0,-1500))
  f.reverse! if f.normal.z < 0
  f.pushpull(200.mm)
end
solid(root, 'ผนังหัวบ่อ', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(-200,-1325.0,-1300), pt(0,-1325.0,-1300), pt(0,2575.0,-1300), pt(-200,2575.0,-1300))
  f.reverse! if f.normal.z < 0
  f.pushpull(2500.mm)
end
solid(root, 'ผนังข้างช่อง 1 (ซ้าย)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(0,-1325.0,-1500), pt(2300,-1325.0,-1500), pt(2300,-1125.0,-1500), pt(0,-1125.0,-1500))
  f.reverse! if f.normal.z < 0
  f.pushpull(2700.mm)
end
solid(root, 'ผนังข้างช่อง 1 (ขวา)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(0,2375.0,-1500), pt(2300,2375.0,-1500), pt(2300,2575.0,-1500), pt(0,2575.0,-1500))
  f.reverse! if f.normal.z < 0
  f.pushpull(2700.mm)
end
solid(root, 'ผนังปลายช่อง 1 (ซ้าย)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2100,-1125.0,-1500), pt(2300,-1125.0,-1500), pt(2300,0,-1500), pt(2100,0,-1500))
  f.reverse! if f.normal.z < 0
  f.pushpull(2700.mm)
end
solid(root, 'ผนังปลายช่อง 1 (ขวา)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2100,1250,-1500), pt(2300,1250,-1500), pt(2300,2375.0,-1500), pt(2100,2375.0,-1500))
  f.reverse! if f.normal.z < 0
  f.pushpull(2700.mm)
end
solid(root, 'ผนังกันน้ำกระแทก', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(1000,-1125.0,-1000), pt(1100,-1125.0,-1000), pt(1100,2375.0,-1000), pt(1000,2375.0,-1000))
  f.reverse! if f.normal.z < 0
  f.pushpull(2200.mm)
end
solid(root, 'ช่อง 2 ขอบม่านน้ำ (ผนังปลายช่อง 1 ช่วงกลาง)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2100,0,-1500), pt(2300,0,-1500), pt(2300,1250,-1500), pt(2100,1250,-1500))
  f.reverse! if f.normal.z < 0
  f.pushpull(2400.mm)
end
solid(root, 'พื้นช่อง 3', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2300,-200,-200), pt(5700,-200,-200), pt(5700,1450,-200), pt(2300,1450,-200))
  f.reverse! if f.normal.z < 0
  f.pushpull(200.mm)
end
solid(root, 'ผนังข้างช่อง 3 (ซ้าย)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2300,-200,0), pt(5700,-200,0), pt(5700,0,0), pt(2300,0,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(1200.mm)
end
solid(root, 'ผนังข้างช่อง 3 (ขวา)', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2300,1250,0), pt(5700,1250,0), pt(5700,1450,0), pt(2300,1450,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(1200.mm)
end
solid(root, 'ผนังท้ายบ่อ', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(5500,0,0), pt(5700,0,0), pt(5700,1250,0), pt(5500,1250,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(1200.mm)
end
solid(root, 'ผนัง ① ลอดใต้', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2650,0,150), pt(2750,0,150), pt(2750,1250,150), pt(2650,1250,150))
  f.reverse! if f.normal.z < 0
  f.pushpull(1050.mm)
end
solid(root, 'ผนัง ② ล้นข้าม', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(2900,0,0), pt(3000,0,0), pt(3000,1250,0), pt(2900,1250,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(250.mm)
end
solid(root, 'กำแพงใต้แผ่นเวียร์', tags['คอนกรีต'], mats['คอนกรีต']) do |e|
  f = e.add_face(pt(4800,0,0), pt(5000,0,0), pt(5000,1250,0), pt(4800,1250,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(400.mm)
end
solid(root, 'แผ่นเวียร์ V-notch 90° SS304 หนา 6', tags['แผ่นสแตนเลส'], mats['สแตนเลส']) do |e|
  f = e.add_face(pt(4794,-100.0,300), pt(4794,1350.0,300), pt(4794,1350.0,860), pt(4794,885.0,860), pt(4794,885.0,760), pt(4794,625.0,500), pt(4794,365.0,760), pt(4794,365.0,860), pt(4794,-100.0,860))
  f.reverse! if f.normal.x < 0
  f.pushpull(6.mm)
end
solid(root, 'แผ่นขอบปลายช่อง 2 SS', tags['แผ่นสแตนเลส'], mats['สแตนเลส']) do |e|
  f = e.add_face(pt(2294,0,900), pt(2300,0,900), pt(2300,1250,900), pt(2294,1250,900))
  f.reverse! if f.normal.z < 0
  f.pushpull(20.mm)
end
solid(root, 'คาน Flow meter', tags['แผ่นสแตนเลส'], mats['สแตนเลส']) do |e|
  f = e.add_face(pt(3950,-200,1200), pt(4050,-200,1200), pt(4050,1450,1200), pt(3950,1450,1200))
  f.reverse! if f.normal.z < 0
  f.pushpull(50.mm)
end
solid(root, 'ท่อน้ำเข้า 6"', tags['ท่อ'], mats['ท่อ']) do |e|
  f = e.add_face(e.add_circle(pt(-800,625.0,1000), X_AXIS, 84.0.mm, 24))
  f.reverse! if f.normal.x < 0
  f.pushpull(900.mm)
end
solid(root, 'ท่อน้ำออก 8"', tags['ท่อ'], mats['ท่อ']) do |e|
  f = e.add_face(e.add_circle(pt(5480,625.0,120.0), X_AXIS, 109.mm, 24))
  f.reverse! if f.normal.x < 0
  f.pushpull(820.mm)
end
solid(root, 'ปั๊มจุ่ม 10 m³/ชม.', tags['ปั๊มและเครื่องวัด'], mats['อุปกรณ์']) do |e|
  f = e.add_face(pt(1400.0,925.0,-1300), pt(1800.0,925.0,-1300), pt(1800.0,1325.0,-1300), pt(1400.0,1325.0,-1300))
  f.reverse! if f.normal.z < 0
  f.pushpull(550.mm)
end
solid(root, 'ท่อปั๊ม recycle', tags['ปั๊มและเครื่องวัด'], mats['อุปกรณ์']) do |e|
  f = e.add_face(e.add_circle(pt(1720,1125.0,-750), Z_AXIS, 30.mm, 24))
  f.reverse! if f.normal.z < 0
  f.pushpull(2250.mm)
end
solid(root, 'Flow meter (DL10)', tags['ปั๊มและเครื่องวัด'], mats['เครื่องวัด']) do |e|
  f = e.add_face(e.add_circle(pt(4000,625.0,1100), Z_AXIS, 26.mm, 24))
  f.reverse! if f.normal.z < 0
  f.pushpull(81.mm)
end
solid(root, 'หัววัด BOD', tags['ปั๊มและเครื่องวัด'], mats['เครื่องวัด']) do |e|
  f = e.add_face(e.add_circle(pt(3300,190,200), Z_AXIS, 30.mm, 24))
  f.reverse! if f.normal.z < 0
  f.pushpull(774.mm)
end
solid(root, 'น้ำช่อง 1 (หน้าผนังกันน้ำกระแทก)', tags['น้ำ'], mats['น้ำ']) do |e|
  f = e.add_face(pt(0,-1125.0,-1300), pt(1000,-1125.0,-1300), pt(1000,2375.0,-1300), pt(0,2375.0,-1300))
  f.reverse! if f.normal.z < 0
  f.pushpull(2258.mm)
end
solid(root, 'น้ำช่อง 1 (โซนปั๊ม)', tags['น้ำ'], mats['น้ำ']) do |e|
  f = e.add_face(pt(1100,-1125.0,-1300), pt(2100,-1125.0,-1300), pt(2100,2375.0,-1300), pt(1100,2375.0,-1300))
  f.reverse! if f.normal.z < 0
  f.pushpull(2258.mm)
end
solid(root, 'น้ำช่อง 2', tags['น้ำ'], mats['น้ำ']) do |e|
  f = e.add_face(pt(2100,0,900), pt(2300,0,900), pt(2300,1250,900), pt(2100,1250,900))
  f.reverse! if f.normal.z < 0
  f.pushpull(60.mm)
end
solid(root, 'น้ำช่อง 3', tags['น้ำ'], mats['น้ำ']) do |e|
  f = e.add_face(pt(2300,0,0), pt(4794,0,0), pt(4794,1250,0), pt(2300,1250,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(676.mm)
end
solid(root, 'น้ำหลังเวียร์', tags['น้ำ'], mats['น้ำ']) do |e|
  f = e.add_face(pt(5000,0,0), pt(5500,0,0), pt(5500,1250,0), pt(5000,1250,0))
  f.reverse! if f.normal.z < 0
  f.pushpull(211.mm)
end
model.commit_operation
Sketchup.active_model.active_view.zoom_extents
puts 'วาดบ่อวัดน้ำเสร็จแล้ว'

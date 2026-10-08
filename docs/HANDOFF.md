# Handoff – Plant Piping TH (SketchUp extension)

Summary of the previous chat so a new session can continue. Repo `artkantaphit43/-`,
branch `claude/sketchup-water-plumbing-plugin-d83v6f`, current version **1.11.0**
(`dist/artk_plant_pipe-1.11.0.rbz`). Tests: `rake test` (186 runs, all green).

**1.11.0 รวมทุก branch ของปลั๊กอินนี้ไว้ที่ branch นี้แล้ว** (งานจากแชตอื่นที่แยกออกจาก 1.6.0):
**1.6.1** (`dist/artk_plant_pipe-1.6.1.rbz`, branch `claude/sketchup-pipe-end-center-fm0hq9`) = 1.6.0 + ปลายท่อเปิดมีกลุ่ม
`Pipe End Center` (วงกลมจริง `add_arc` 360° ตรงกับ mesh + construction point) → SketchUp สแนป Center ได้เอง
(`Builder#add_end_center`). ผู้ใช้เลือกต่อจาก 1.6 เพราะไม่ชอบสีของ 1.7 (2026-10-02).
**1.6.2** (`dist/artk_plant_pipe-1.6.2.rbz`, branch `claude/sketchup-editable-pipe-fittings-pfgyf5`) = 1.6.1 + ท่อแก้ไขได้:
ปัญหาเดิม = ทุกคำสั่งอ่านเส้นแนว `cl` ไม่ใช่รูปทรง → ยืดท่อด้วย Push/Pull/Scale แล้วข้อต่อสแนปปลายเก่า, Rebuild หดกลับ.
`lib/run_edit.rb` (ย้ายจุด cl + พาวาล์ว/ซัพพอร์ต/ข้อต่อปลายท่อตาม, จุดต่อแนวอื่นล็อก; `measure_pipe` อ่านปลายท่อจาก mesh),
`su/run_editor.rb` (`RunEditor.apply/inspect/sync`, `AutoSync` = ModelObserver อ่านกลับหลังแก้ / ออกจากกลุ่มท่อ, op แบบ transparent;
`sync_context` ตอนเปิดเครื่องมือ), `su/stretch_tool.rb` (ยืด/ย้ายท่อ), คำสั่ง *ตรวจท่อ* (`Commands.check_pipes`),
ข้อต่อจากคลังที่ปลายท่อผูกกับแนวท่อ (`end_part` บน instance, `Builder#place_end_part`). อ่านกลับอัตโนมัติเฉพาะ
ปลายเปิดที่ยืด/หดตามแนว; เลื่อนข้าง/หมุน/Scale ขนาด/ยืดเข้าข้อต่อ → แจ้งเตือนแล้วกลับตามข้อมูลเมื่อ Rebuild.
pipe `geom` บันทึก `ea/eb` (ระยะท่อเข้าข้อต่อ) ตั้งแต่ 1.6.2. ยังไม่ได้ลองใน SketchUp จริง.

## ผู้ใช้ต้องการอะไร (สรุป)
- ปลั๊กอิน SketchUp (.rbz + ไอคอน) งานระบบน้ำ/ประปา/ท่อโรงงาน – ทำให้ถูกต้อง ครบ มีเหตุผล
- อุปกรณ์ต้องสมจริง **คัดลอกจากไฟล์ .skp ที่ผู้ใช้ส่งมา** (ไม่ใช่วาดเองแบบการ์ตูน) และแยกวัสดุให้ถูก
- ชอบคำตอบ **สั้น กระชับ ได้ใจความ** (ภาษาไทย)
- ไม่ชอบให้ต้องสั่งซ้ำ/เสียเครดิต – ตรวจงานให้ละเอียดก่อนส่ง (render/test)
- **สำคัญมาก: ไฟล์ที่วาดด้วยเวอร์ชันเก่าต้องใช้ต่อได้เสมอ** – ทำตาม docs/DATA_FORMAT.md ทุกครั้งที่ออกเวอร์ชันใหม่
  (ห้ามเปลี่ยน/ลบ key เดิม, ถ้าจำเป็นให้เพิ่ม step ใน DataFormat + fixture ของเวอร์ชันก่อนหน้าใน test/fixtures)
- อุปกรณ์ต้องตามมาตรฐาน – ห้ามขยายทั้งชิ้นตามท่อ ถ้าของจริงไม่ได้โตตามนั้น (ขยายเฉพาะส่วนต่อท่อ)

## สิ่งที่ทำแล้ว (ตามเวอร์ชัน)
- **v1.0–1.3**: ท่อกลวง, ข้องอ/Tee อัตโนมัติ, วาล์วหลายตระกูล, ซัพพอร์ตพื้น/แขวน 8 แบบ, สีตามวัสดุ/ตามระบบ,
  ความละเอียด 2 ระดับ, คำนวณขนาด, ไฮดรอลิก, clash, BOM (CSV)
- **v1.4**: ตัวอ่านไฟล์ .skp เอง (`tools/refs/skp_reader.rb`) + ตัวคัดลอก (`tools/refs/extract.rb`) →
  คลังอุปกรณ์จริง (`src/artk_plant_pipe/refs/refs.json|bin`, thumbs, textures) · ใช้อัตโนมัติตามวัสดุท่อ
  (GI เกลียว, เหล็ก SW/BW, PVC มอก.17, PVC Sch40, วาล์วหน้าแปลน, บัตเตอร์ฟลาย JIS10K, lug, พลาสติก) +
  หน้าแปลนประกบ · ระยะตัดท่อจากขนาดจริงของข้อต่อ · เกท > 4" ใช้โมเดล 4" ปรับสเกลตาม B16.10/B16.5
- **v1.5**: หน้าต่างตั้งค่าส่วนวาล์วเหลือแค่ "คลังอุปกรณ์จริง" · สแนปที่วงกลมปลายต่อ
  (อินไลน์ = บนท่อตรง, ข้อต่อ/ก๊อก = ปลายท่อ, เกจ = บนท่อ) · เลือกรุ่นขนาดเท่าท่อ / ปรับสเกล ·
  เพิ่มมิเตอร์น้ำ (หน้าปัด texture), ก๊อกน้ำ (ปรับเป็น ½" จริง), เกจ 0–4/6/10/16/25 bar (666 รายการ)
- **v1.6**: วาดตามเส้นไกด์ (จุด snap ใช้ตรง ๆ) · เริ่ม/จบที่ข้องอ → กลายเป็นสามทาง (ขนาดต่าง = stub + reducer) ·
  เลือกสีท่อเอง (checkbox + color picker) · HDPE แข็ง vs HDPE ม้วน (ดัดโค้ง R ≥ 25×OD SDR11 / 27×OD SDR17,
  ไม่พอ → ข้องอหลอมไฟฟ้า, BOM นับม้วน) · ป้ายช่อง "ชนิดท่อ / วัสดุ" ชัดขึ้น

- **v1.7**: มิเตอร์น้ำขนาดตาม ISO 4064 DN15–50 (ขยายเฉพาะส่วนต่อท่อ ตัวเรือน/หน้าปัดโตแบบของจริง), ก๊อก ½"–1" ·
  ระบบเวอร์ชันข้อมูล `fmt` + ตัวแปลงอัตโนมัติ (lib/data_format.rb, su/migrate.rb) + ทดสอบไฟล์จริงจาก v1.6

- **v1.8**: มิเตอร์ Woltman หน้าแปลน DN65–300 สร้างเอง (lib/meter_models.rb) ตาม ISO 4064 + EN 1092-2 PN16,
  หน้าตาตามรูปผู้ใช้ (ตัวฟ้า หัวอ่านเทา ไม่มีฝา) + หน้าแปลนประกบ
- **v1.9**: สแนป Center ปลายท่อ (เริ่ม/จบ), จบที่ปลายท่ออีกแนว = ต่อแนวเดียว · มิเตอร์ Woltman สีเหมือนวาล์ว
  (ไม่ทาสีตัวเรือน → ใช้สี valve_cast ของ instance), โบลท์ครบชุดตรงรูหน้าแปลนประกบ (Refs.flange_bolting) ·
  แก้หน้าปัดมิเตอร์สีเพี้ยน (ห้ามตั้ง color ให้วัสดุที่มี texture)
- **v1.9.1**: definition ในไฟล์ผู้ใช้ที่สร้างจากเวอร์ชันเก่าถูกใช้ซ้ำ (ชื่อเดิม) → เก็บ `rev` บน definition
  (MeterModels::REV / Refs.geometry_rev) แล้วสร้างใหม่ทับที่เดิมเมื่อเปิดไฟล์ (RefModels.stale/refresh ใน Migrate.model)
  **แก้รูปทรงอุปกรณ์ที่สร้างเองเมื่อไร ต้องเพิ่ม REV ทุกครั้ง**
- **v1.10**: ซัพพอร์ตร่วมท่อข้างเคียง (Supports.group/fill, SupportBuilder.place/adapt/create_multi) –
  ขนาน ≤5°, ช่องว่างผิว ≤ support_group_mm (600), BOP ต่าง ≤300, กว้าง ≤2.5 m, แขนเสา ≤1.2 m · packer ใต้ท่อที่สูงกว่า ·
  ซัพพอร์ตร่วมเก็บ at/dir/members/signature → adapt หลังวาดท่อ/Rebuild
- **v1.10.1**: จุดที่สแนป (เส้นไกด์/ขอบ/จุด) ใช้ตรง ๆ ทุกระบบ – ท่อระบาย (SAN/SD/V) ไม่ใส่ความลาดทับจุดสแนปแล้ว
  (ความลาดอัตโนมัติเฉพาะจุดอิสระ) + เตือนถ้าลาดน้อยกว่าขั้นต่ำ · **แก้อะไรต้องทดสอบทุกระบบ ไม่ใช่แค่น้ำประปา**
- **v1.10.2**: ปุ่ม "ดูดสีจากโมเดล" (su/color_pick_tool.rb – eyedropper ของ input color ใช้ใน HtmlDialog ไม่ได้) + ช่องรหัสสี
- **v1.11.0**: รวม branch 1.6.1 (Center ปลายท่อ) + 1.6.2 (ท่อแก้ไขได้) เข้าสายนี้ · **ไม่รวม** 1.7.0 realistic-materials
  (ผู้ใช้ไม่ชอบสี) – ถ้าจะรวม ให้ทำเป็นตัวเลือก color scheme 'realistic' ไม่ใช่ค่าเริ่มต้น ·
  ตรวจคลัง: `tools/refs/extract.rb` ปรับ circle fit (least squares), U-trap ปลายขนานกันได้, สามทางที่ไม่มีหน้าปลาย run
  (mirrored) → สกัดใหม่ทั้งหมดแล้ว**รับเฉพาะ 4 ชิ้นที่ซ่อม** (item `rev` 2 → definition เก่ารีบิวด์ตอนเปิดไฟล์) ชิ้นอื่น byte เดิม ·
  ไฟล์ต้นฉบับผู้ใช้: piping=114d1e22, pvc=15235bc6, sch40=08be19ef, valves=27c78d10, meter=d07691db, faucet=5099144e,
  gauge=3df0d85c (~/.claude/uploads) · Library: ซ่อน spool/ซ้ำ (`RefBrowser.hidden?`), ตัวกรองขนาด `fits()` (grow/range/any),
  UI กะทัดรัด (preferences_key ใหม่ → ขนาดเริ่ม 400×620)
- **ส่งไฟล์ .rbz ให้ผู้ใช้ด้วย SendUserFile ทุกครั้งที่ออกเวอร์ชัน** (ผู้ใช้หาไฟล์ใน repo ไม่เจอ)

## ข้อจำกัด / งานที่อาจทำต่อ
- **[ผู้ใช้สั่งไว้ – ทำในรอบหน้า]** ซัพพอร์ตร่วม: ท่อที่วางบนแผ่นรอง (packer) ขาเหล็กยู (U-bolt) ยังจบที่ใต้ท่อ
  ไม่ลงถึงคาน → ต้องให้ขา U-bolt ทะลุแผ่นรองลงไปยึดที่คาน/แขน (Supports.trapeze/hframe/bracket: down_to = z_top
  ไม่ใช่ z − r) และตรวจกับ Trapeze ด้วย
- เริ่มจากปลายท่อแนวหนึ่งแล้วจบที่ข้องอของอีกแนว → ยังไม่รวมเป็นสามทาง (ให้เริ่มวาดที่ข้องอแทน)
- เสนอไว้: ข้อลดเยื้องศูนย์ (FOT ด้านดูดปั๊ม / FOB ท่อบนแร็ก, ไอน้ำ) + เตือนท่อระบายที่ลดขนาดตามทิศการไหล
- ยังไม่ได้ทดสอบใน SketchUp จริง (ทดสอบด้วย stub + render จำลอง)

## ไฟล์อ้างอิงของผู้ใช้ (ใช้สร้างคลังใหม่)
piping (GI/เหล็ก), FITTING_PVC, Schedule_40, VALVEDATABASE, water meter, faucet, pressure_guage –
คำสั่ง: ดู README หัวข้อ "สำหรับนักพัฒนา" (`ruby tools/refs/extract.rb …` แล้ว `tools/refs/thumbs.*`)

## โครงสร้างโค้ด
`src/artk_plant_pipe/lib` (Ruby ล้วน, ทดสอบได้), `su/` (SketchUp: builder, ref_builder, ref_models,
ref_browser, pipe_tool …), `ui/` (settings.html, library.html), `test/` (minitest + su_stub), `tools/`.

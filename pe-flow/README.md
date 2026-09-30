# PE Project Control Flow (A4 portrait)

แหล่งที่มาของไฟล์ `../PE-Project-Control-Flow.pdf` — คู่มือ Flow การควบคุมโครงการสำหรับ PE
ตั้งแต่ทำสัญญา → เตรียมเริ่มงาน → ขออนุมัติ → ควบคุมงาน → ส่งงวด/เบิกเงิน → ส่งมอบงาน → ระยะรับประกัน

- `index.html` — เนื้อหาทั้ง 14 หน้า (แก้ข้อความที่นี่)
- `style.css` — รูปแบบ/สี
- `flow.js` — วาดลูกศรเชื่อมกล่องอัตโนมัติ (กำหนดเส้นใน `<script class="edges">` ของแต่ละ Flow)
- `fonts/` — IBM Plex Sans Thai (SIL Open Font License)

สร้าง PDF ใหม่หลังแก้ไข:

```sh
node pe-flow/build.mjs            # เขียนทับ PE-Project-Control-Flow.pdf
```

ต้องมี Node.js + Playwright (Chromium)

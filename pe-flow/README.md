# PE Project Control Flow (A4 portrait)

แหล่งที่มาของไฟล์ `../PE-Project-Control-Flow.pdf` — คู่มือ Flow การควบคุมโครงการสำหรับ PE
ตั้งแต่ทำสัญญา → เตรียมเริ่มงาน → ขออนุมัติ → ควบคุมงาน → ส่งงวด/เบิกเงิน → ส่งมอบงาน → ระยะรับประกัน

- `index.html` — ฉบับเต็ม 14 หน้า → `PE-Project-Control-Flow.pdf`
- `summary.html` — สรุป 1 หน้า → `PE-Project-Control-Flow-1page.pdf`
- `style.css` — รูปแบบ/สี
- `flow.js` — วาดลูกศรเชื่อมกล่องอัตโนมัติ (กำหนดเส้นใน `<script class="edges">` ของแต่ละ Flow)
- `fonts/` — IBM Plex Sans Thai (SIL Open Font License)

สร้าง PDF ใหม่หลังแก้ไข:

```sh
node pe-flow/build.mjs            # สร้าง PDF ทั้ง 2 ไฟล์ ไว้ที่โฟลเดอร์หลักของ repo
```

ต้องมี Node.js + Playwright (Chromium)

---
name: commit-convention
description: รูปแบบ commit message, ชื่อ branch และ PR ของ repo นี้ ใช้ทุกครั้งก่อน commit หรือเปิด PR
---

# Commit Convention

## Commit message
ใช้รูปแบบ Conventional Commits:

```
<type>: <สรุปสั้นๆ ไม่เกิน 72 ตัวอักษร>

<รายละเอียดว่าเปลี่ยนอะไรและทำไม (ถ้าจำเป็น)>
```

`type` ที่ใช้:
- `feat`: เพิ่มความสามารถใหม่
- `fix`: แก้บั๊ก
- `docs`: แก้เอกสาร / README / สกิล
- `refactor`: ปรับโค้ดโดยไม่เปลี่ยนการทำงาน
- `test`: เพิ่มหรือแก้ test
- `chore`: งานจิปาถะ (config, dependencies)

ตัวอย่าง: `feat: add login page`

- เขียน commit message เป็นภาษาอังกฤษ
- 1 commit = 1 เรื่อง อย่ารวมหลายเรื่องใน commit เดียว

## Branch
- ห้าม push ตรงเข้า `main`
- ตั้งชื่อ branch แบบ `<type>/<คำอธิบายสั้น>` เช่น `feat/login-page`
  (ถ้า session กำหนดชื่อ branch มาให้แล้ว ให้ใช้ตามนั้น)

## Pull Request
- หัวข้อ PR ใช้รูปแบบเดียวกับ commit message
- ในเนื้อหา PR ให้มี: **ทำอะไร**, **ทำไม**, **ทดสอบยังไง**
- เปิด PR เฉพาะเมื่อเจ้าของ repo ขอเท่านั้น

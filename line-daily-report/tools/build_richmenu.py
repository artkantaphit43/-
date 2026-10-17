"""สร้างรูป Rich Menu (เมนูกรอบสี่เหลี่ยมใต้แชต) + ตำแหน่งปุ่ม

ใช้: python3 build_richmenu.py <โฟลเดอร์ผลลัพธ์>
ได้ richmenu.jpg และ richmenu.json (ตำแหน่งปุ่มในพิกัดของรูป ใช้ตอนสร้างเมนูผ่าน LINE API)
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
W, H = 2500, 1686            # ขนาดวาด (ใหญ่ เพื่อความคม)
FINAL = (1250, 843)          # ขนาดไฟล์จริง (LINE: กว้าง 800-2500, กว้าง/สูง >= 1.45)
SARABUN = os.path.expanduser('~/.fonts/Sarabun-Bold.ttf')
SARABUN_REG = os.path.expanduser('~/.fonts/Sarabun-Regular.ttf')
EMOJI = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'

BG = '#EEF3F3'
TEAL = '#0A9A9A'
SLATE = '#34495E'
PAD, GAP, RADIUS = 60, 44, 48

# ปุ่มบน 2 ปุ่มใหญ่ ปุ่มล่าง 3 ปุ่ม — text = ข้อความที่ส่งเมื่อกด
TOP = [
    {'emoji': '📋', 'title': 'Daily Report', 'sub': 'รายงานประจำวัน', 'color': TEAL, 'text': 'เริ่ม'},
    {'emoji': '🛠️', 'title': 'Punch List', 'sub': 'รายการงานแก้ไข', 'color': SLATE, 'text': 'punch list'},
]
BOTTOM = [
    {'emoji': '↩️', 'title': 'ย้อนกลับ', 'text': 'ย้อนกลับ'},
    {'emoji': '📊', 'title': 'ดูสรุป', 'text': 'สถานะ'},
    {'emoji': '📤', 'title': 'ส่งรายงาน', 'text': 'ส่ง'},
    {'emoji': '📁', 'title': 'โครงการ', 'text': 'โครงการ'},
]


def emoji_img(ch, size):
    font = ImageFont.truetype(EMOJI, 109)
    tmp = Image.new('RGBA', (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((80, 80), ch, font=font, embedded_color=True, anchor='mm')
    tmp = tmp.crop(tmp.getbbox())
    scale = size / max(tmp.size)
    return tmp.resize((round(tmp.width * scale), round(tmp.height * scale)), Image.LANCZOS)


img = Image.new('RGB', (W, H), BG)
d = ImageDraw.Draw(img)
areas = []

top_h = int((H - 2 * PAD - GAP) * 0.6)
top_w = (W - 2 * PAD - GAP) // 2
for i, b in enumerate(TOP):
    x0 = PAD + i * (top_w + GAP)
    y0 = PAD
    box = (x0, y0, x0 + top_w, y0 + top_h)
    d.rounded_rectangle(box, RADIUS, fill=b['color'])
    cx = x0 + top_w // 2
    e = emoji_img(b['emoji'], 230)
    img.paste(e, (cx - e.width // 2, y0 + 110), e)
    d.text((cx, y0 + 470), b['title'], font=ImageFont.truetype(SARABUN, 140), fill='white', anchor='mm')
    d.text((cx, y0 + 600), b['sub'], font=ImageFont.truetype(SARABUN_REG, 90), fill='#E6F2F2', anchor='mm')
    areas.append((box, b['text']))

bot_y0 = PAD + top_h + GAP
bot_h = H - PAD - bot_y0
n = len(BOTTOM)
bot_w = (W - 2 * PAD - (n - 1) * GAP) // n
for i, b in enumerate(BOTTOM):
    x0 = PAD + i * (bot_w + GAP)
    box = (x0, bot_y0, x0 + bot_w, bot_y0 + bot_h)
    d.rounded_rectangle(box, RADIUS, fill='white', outline='#CFE3E3', width=6)
    cx = x0 + bot_w // 2
    e = emoji_img(b['emoji'], 150)
    img.paste(e, (cx - e.width // 2, bot_y0 + bot_h // 2 - 180), e)
    d.text((cx, bot_y0 + bot_h // 2 + 90), b['title'], font=ImageFont.truetype(SARABUN, 105), fill=TEAL, anchor='mm')
    areas.append((box, b['text']))

img = img.resize(FINAL, Image.LANCZOS)
img.save(os.path.join(OUT, 'richmenu.jpg'), 'JPEG', quality=86, optimize=True)

scale = FINAL[0] / W
spec = {
    'size': {'width': FINAL[0], 'height': FINAL[1]},
    'areas': [{
        'bounds': {'x': round(x0 * scale), 'y': round(y0 * scale),
                   'width': round((x1 - x0) * scale), 'height': round((y1 - y0) * scale)},
        'action': {'type': 'message', 'text': text},
    } for (x0, y0, x1, y1), text in areas],
}
json.dump(spec, open(os.path.join(OUT, 'richmenu.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('saved', os.path.getsize(os.path.join(OUT, 'richmenu.jpg')), 'bytes')

"""ฝังแม่แบบ Excel, รูปเลขวงกลม (1-20) และ Rich Menu ลงท้าย Code.gs

ใช้: python3 embed_assets.py <template.xlsx> <Code.gs>
(Rich Menu อ่านจาก richmenu.jpg / richmenu.json ในโฟลเดอร์เดียวกับ template.xlsx — สร้างด้วย build_richmenu.py)
"""
import base64
import io
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

TEMPLATE, CODE = sys.argv[1], sys.argv[2]
MARKER = '// ===== ข้อมูลฝัง (สร้างโดย tools/embed_assets.py — ห้ามแก้ด้วยมือ) =====\n'


def circle_png(n):
    size = 96
    img = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((4, 4, size - 5, size - 5), fill='white', outline='black', width=5)
    font = ImageFont.truetype('DejaVuSans.ttf', 50 if n < 10 else 40)
    d.text((size / 2, size / 2 + 1), str(n), fill='black', font=font, anchor='mm')
    img = img.resize((48, 48), Image.LANCZOS).quantize(colors=16)
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


code = open(CODE, encoding='utf-8').read()
code = code[:code.index(MARKER) + len(MARKER)]
xlsx = base64.b64encode(open(TEMPLATE, 'rb').read()).decode()
circles = ',\n'.join(f"  '{circle_png(n)}'" for n in range(1, 21))
tools = os.path.dirname(os.path.abspath(TEMPLATE))
menu_jpg = base64.b64encode(open(os.path.join(tools, 'richmenu.jpg'), 'rb').read()).decode()
menu_spec = json.dumps(json.load(open(os.path.join(tools, 'richmenu.json'), encoding='utf-8')), ensure_ascii=False)
code += f"const TEMPLATE_XLSX_B64 = '{xlsx}';\n\nconst CIRCLE_PNG_B64 = [\n{circles},\n];\n"
code += f"\nconst RICHMENU_SPEC = {menu_spec};\n\nconst RICHMENU_JPG_B64 = '{menu_jpg}';\n"
open(CODE, 'w', encoding='utf-8').write(code)
print('embedded', len(xlsx), 'chars of template')

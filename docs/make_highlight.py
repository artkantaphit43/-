import subprocess, re, html, glob
from PIL import Image, ImageDraw, ImageFont
U = glob.glob('/root/.claude/uploads/e4e8288a-a3e1-5cad-bb6c-78e74f665a4d/')[0]
MAN = glob.glob(U+'65540030*.pdf')[0]; DS = glob.glob(U+'be569245*.pdf')[0]; UV = glob.glob(U+'9bf5ae0d*.pdf')[0]
DPI = 130; K = DPI/72
F = ImageFont.truetype('/usr/share/fonts/opentype/tlwg/Loma.otf', 22)
FB = ImageFont.truetype('/usr/share/fonts/opentype/tlwg/Loma-Bold.otf', 30)
FN = ImageFont.truetype('/usr/share/fonts/opentype/tlwg/Loma-Bold.otf', 20)

def words(pdf, p):
    out = subprocess.run(['pdftotext','-f',str(p),'-l',str(p),'-bbox',pdf,'-'],capture_output=True,text=True).stdout
    return [(float(a),float(b),float(c),float(d),html.unescape(w)) for a,b,c,d,w in
            re.findall(r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<', out)]

def find(ws, phrase, nth=0):
    t = phrase.split(); hits=[]
    for i in range(len(ws)-len(t)+1):
        if all(ws[i+j][4]==t[j] for j in range(len(t))):
            seg = ws[i:i+len(t)]
            hits.append((min(s[0] for s in seg),min(s[1] for s in seg),max(s[2] for s in seg),max(s[3] for s in seg)))
    assert hits, phrase
    return hits[nth]

def page(pdf, p, title, marks):
    base = f'/tmp/hl/pg'
    subprocess.run(['pdftoppm','-f',str(p),'-l',str(p),'-r',str(DPI),'-png','-singlefile',pdf,base],check=True)
    im = Image.open(base+'.png').convert('RGB'); W,H = im.size
    ws = words(pdf,p)
    side = 560; canvas = Image.new('RGB',(W+side,H+70),'white'); canvas.paste(im,(0,70))
    ov = Image.new('RGBA',canvas.size,(0,0,0,0)); d = ImageDraw.Draw(ov)
    dc = ImageDraw.Draw(canvas)
    dc.rectangle([0,0,W+side,62],fill=(30,60,110)); dc.text((20,14),title,font=FB,fill='white')
    ny = 100
    for n,(spec,note) in enumerate(marks,1):
        boxes = [spec] if isinstance(spec[0],(int,float)) else [find(ws,s) if isinstance(s,str) else find(ws,*s) for s in spec]
        for b in boxes:
            x0,y0,x1,y1 = [v*K for v in b]; y0+=70; y1+=70
            d.rectangle([x0-3,y0-2,x1+3,y1+2],fill=(255,230,0,110),outline=(230,120,0,255),width=2)
        x0,y0 = boxes[0][0]*K, boxes[0][1]*K+70
        x1b = boxes[0][2]*K
        d.ellipse([x1b-4,y0-24,x1b+18,y0-2],fill=(220,30,30,255))
        d.text((x1b+7,y0-13),str(n),font=FN,fill='white',anchor='mm')
        # note on side
        lines = note.split('\n'); h = 30*len(lines)+16
        d.rounded_rectangle([W+15,ny,W+side-15,ny+h],8,fill=(255,248,200,255),outline=(230,120,0,255),width=2)
        d.ellipse([W+25,ny+8,W+51,ny+34],fill=(220,30,30,255)); d.text((W+38,ny+21),str(n),font=FN,fill='white',anchor='mm')
        for i,l in enumerate(lines): d.text((W+62,ny+8+30*i),l,font=F,fill=(20,20,20))
        ny += h+14
    canvas = Image.alpha_composite(canvas.convert('RGBA'),ov).convert('RGB')
    return canvas

P = []
P.append(page(DS,1,'Flow meter IS-4000 — Data sheet หน้า 1',[
  (['minimal foam'],'น้ำต้องมีฟองน้อย\n=> มีผนัง ① ② ตัดฟองแล้ว'),
  (['V-notch weir (30°, 45°, 60°, 90°);'],'รองรับ V-notch 90° มีสูตรในเครื่องแล้ว'),
  (['where the sediment does not build up.'],'ตะกอนต้องไม่สะสมหน้าเวียร์\n=> ล้างรางเป็นระยะ'),
]))
P.append(page(DS,2,'Flow meter — สเปกหัววัด DL10 (Data sheet หน้า 2)',[
  (['DL 10 Ultrasonic'],'รุ่นที่ใช้ = DL10 (คอลัมน์นี้)'),
  (['0…49.21 in. (0…1250 mm)'],'วัดได้ไกลสุด 1.25 m\n=> หัววัดห่างยอด V ไม่เกิน 1.25 m'),
  ([('2°',0)],'คลื่นแคบ => ติดกลางราง ใต้หัววัดโล่ง'),
  (['0.125 in. (3 mm)'],'แม่นยำ +/-3 mm'),
  (['2 in. (50 mm)'],'ระยะบอด 5 cm => หน้าหัววัดต้องสูงกว่า\nน้ำสูงสุด >= 5 cm (แนะนำ 20–30 cm)'),
  ([('G1',0)],'เกลียวยึด G1 (1 นิ้ว)'),
]))
P.append(page(MAN,9,'Flow meter — คู่มือ หน้า 9: ตำแหน่งติดตั้งบนเวียร์',[
  ((59,448,228,578),'หัววัดอยู่ต้นน้ำ ห่างแผ่นเวียร์\n>= 3–4 h (h = ความสูงน้ำเหนือยอด V)\nh สูงสุด 0.21 => >= 0.63–0.84 m\n=> ใช้ประมาณ 0.9 m'),
]))
P.append(page(MAN,15,'Flow meter — คู่มือ หน้า 15: ตั้งค่า Offset',[
  (['To calculate the offset, measure the distance from the zero flow position'],'Offset = ระยะหัววัดถึงจุดศูนย์ − 1,250 mm\n(ค่าติดลบ)'),
  (['For a weir, the zero flow position is the bottom of the notch, not the'],'เวียร์: จุดศูนย์ = ยอด V ไม่ใช่พื้นราง'),
  (['when the water level is below the notch or when the channel is dry.'],'น้ำต่ำกว่ายอด V จออ่านติดลบ = ปกติ'),
]))
P.append(page(MAN,29,'Flow meter — คู่มือ หน้า 29: ถ้าค่าเพี้ยน',[
  ([('not too close to walls',0)],'อย่าติดชิดผนังหรือโครงสร้าง'),
  (['steady smooth surface'],'ผิวน้ำใต้หัววัดต้องนิ่ง เรียบ'),
  (['Install a stilling well'],'มีลม/คลื่น => ทำท่อพักน้ำนิ่ง\n(stilling well)'),
]))
P.append(page(UV,5,'BOD probe UV 705 IQ SAC — Data sheet',[
  ([('774',0),('Ø 60',0),('891',0)],'ยาว 774 mm (891 รวมปลอกกันกระแทก)\nØ60 mm'),
  (['Municipal wastewater with a low proportion of industrial wastewater,'],'ปรับมาสำหรับน้ำเสียชุมชน\n=> ต้องสอบเทียบกับผล BOD แล็บ'),
  ([('0.0 ... 500.0 mg/l',2)],'รุ่น 705 วัด BOD ได้ 0–500 mg/L'),
  (['≤ 3 m/s'],'ความเร็วน้ำ <= 3 m/s (ช่อง 3 ~ 0.02 (ผ่าน))'),
  (['Maximum 1 bar (incl. sensor connection cable)'],'แรงดัน <= 1 bar (จมลึกได้ ~10 m)'),
  (['Approx. 8.82 lb (4 kg)'],'หนัก 4 kg => ขาจับต้องแข็งแรง'),
  (['without connecting cable (order SACIQ separately)'],'ไม่รวมสาย! ต้องสั่งสาย SACIQ แยก\n+ ชุดควบคุม IQ Sensor Net'),
]))
P[0].save('/home/user/-/docs_sensor_highlight.pdf',save_all=True,append_images=P[1:],resolution=DPI)
for i,p in enumerate(P): p.save(f'/tmp/hl/p{i}.png')
print('ok')

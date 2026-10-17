/**
 * LINE Daily Report Bot (Google Apps Script)
 *
 * พนักงานส่งข้อความ + รูปเข้า LINE OA -> ระบบเก็บรูปลง Google Drive
 * -> พิมพ์ "ส่ง" -> ได้รายงาน PDF ตามฟอร์ม FM_Daily Report กลับมาในแชต + บันทึกลง Google Sheets
 *
 * Script Properties ที่ต้องตั้ง:
 *   LINE_CHANNEL_ACCESS_TOKEN  (จำเป็น)
 *   ALLOWED_SOURCE_IDS         (ไม่บังคับ) userId/groupId ที่อนุญาต คั่นด้วย ,
 */

// ===== ตั้งค่า (แก้ให้ตรงกับบริษัทได้) =====
const CONFIG = {
  REPORT_TITLE: 'รายงานประจำวัน (Daily Report)',
  FORM_CODE: 'FM_Daily Report_R02',
  LOGO_FILE_ID: '', // อัปโหลดโลโก้ขึ้น Google Drive แล้วใส่ File ID ตรงนี้

  // รายชื่อผู้เขียนรายงาน / ผู้ควบคุมงาน (แสดงเป็นปุ่มให้กดเลือกในไลน์ ได้สูงสุด 13 ชื่อ)
  REPORTERS: [
    'อัจฉราวี เพชรสุวรรณ',
    'นิติธรรม สุวรรณ',
    'ธนพล วงษ์ศิริ',
    'ศิริภัสสร ธรรมใจ',
    'อัญชนา ชำนาญ',
    'กันตพิชญ์ ใยมุง',
    'กรรณิการ์ ยืนยงค์',
  ],

  // ข้อมูลโครงการ: พิมพ์ "โครงการ: PJ 942" แล้วระบบเติมชื่อ/สถานที่/ลักษณะงานให้
  // (เพิ่มโครงการใหม่ได้จากในไลน์ด้วยคำสั่ง "เพิ่มโครงการ" ไม่ต้องแก้โค้ด)
  PROJECTS: {
    'PJ 942': {
      name: 'งานติดตั้งระบบท่อน้ำภายนอกอาคารด้วยท่อ HDPE',
      location: 'SAHAMITFOODS (PLANT 2) LIMITED',
      jobType: 'Underground piping and Piping installation.',
    },
  },

  DEFAULT_START: '09.00 น.',
  DEFAULT_END: '17.00 น.',

  WEATHER_OPTIONS: ['ฝนตก', 'แดดจัด', 'ปกติ'],

  // เครื่องจักร: พิมพ์ "รถยนต์: 3" หรือ "รถเครน: 1 ขนาด 25"
  MACHINES: [
    { key: 'crane', label: 'รถเครน', sized: true, aliases: ['รถเครน', 'เครน'] },
    { key: 'hiab', label: 'รถเฮียบ', sized: true, aliases: ['รถเฮียบ', 'เฮียบ', 'hiab'] },
    { key: 'concrete', label: 'รถปูน', sized: true, aliases: ['รถปูน'] },
    { key: 'car', label: 'รถยนต์', aliases: ['รถยนต์', 'รถ'] },
    { key: 'other', label: 'อื่นๆ', aliases: ['อื่นๆ', 'อื่น ๆ', 'เครื่องจักรอื่น'] },
  ],

  // บรรทัดที่เป็นรหัสโครงการ ใช้แบ่งกลุ่มงาน เช่น "PJ 942" หรือ "PJ 943, 944"
  GROUP_PATTERN: /^PJ\s*\d[\d,\s]*$/i,

  PHOTOS_PER_ROW: 2,
  PHOTO_WIDTH: 245,
  FONT: 'Sarabun',
  ROOT_FOLDER_NAME: 'LINE Daily Report',
};

const CMD_SUBMIT = /^(ส่ง|ส่งรายงาน|เสร็จ|จบ|submit)$/i;
const CMD_CANCEL = /^(ยกเลิก|cancel)$/i;
const CMD_STATUS = /^(สถานะ|เช็ค|เช็ก|status)$/i;
const CMD_HELP = /^(ฟอร์ม|วิธีใช้|help|\?)$/i;
const CMD_NAME = /^(ชื่อ|เลือกชื่อ)$/i;
const CMD_ADD_PROJECT = /^(➕\s*)?เพิ่มโครงการ/;
const CMD_LIST_PROJECTS = /^(โครงการ|รายการโครงการ|โครงการทั้งหมด)$/;
const CMD_DELETE_PROJECT = /^ลบโครงการ[:：\s]+(.+)$/;
const CMD_PLAN = /^(แผน|แผนงาน|แผนพรุ่งนี้|พรุ่งนี้|work ?plan)$/i;
const CMD_TODAY = /^(วันนี้|งานวันนี้)$/i;

const THAI_MONTHS = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
const THAI_MONTHS_SHORT = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

const CHECKED = '☑';
const UNCHECKED = '☐';
const GRAY = '#D9D9D9';
const RED = '#C00000';

// ===== Webhook =====

function doPost(e) {
  const events = JSON.parse(e.postData.contents).events || [];
  events.forEach(event => {
    try {
      handleEvent_(event);
    } catch (err) {
      console.error(err && err.stack || err);
      if (event.replyToken) reply_(event.replyToken, '❌ เกิดข้อผิดพลาด: ' + err.message);
    }
  });
  return ContentService.createTextOutput('OK');
}

function doGet() {
  return ContentService.createTextOutput('LINE Daily Report bot is running.');
}

function handleEvent_(event) {
  if (event.type === 'join' || event.type === 'follow') {
    reply_(event.replyToken, helpText_());
    return;
  }
  if (event.type !== 'message' || !isAllowed_(event.source)) return;

  const msg = event.message;
  if (msg.type === 'text') {
    handleText_(event, msg.text.trim());
  } else if (msg.type === 'image') {
    // ไม่ตอบกลับทุกรูป เพื่อไม่ให้แชตรก (ส่งทีละหลายรูปได้)
    withSession_(event.source, session => addPhoto_(session, msg.id));
  }
}

function handleText_(event, text) {
  const source = event.source;
  const token = event.replyToken;
  if (CMD_HELP.test(text)) return reply_(token, helpText_());
  if (CMD_NAME.test(text)) return reply_(token, reporterPicker_('เลือกชื่อผู้เขียนรายงาน 👇'));
  if (CMD_ADD_PROJECT.test(text)) return reply_(token, ...addProjectFromText_(text));
  if (CMD_LIST_PROJECTS.test(text)) return reply_(token, projectPicker_(projectListText_()));
  const del = text.match(CMD_DELETE_PROJECT);
  if (del) return reply_(token, deleteProject_(del[1]));

  if (CMD_CANCEL.test(text)) {
    deleteSession_(source);
    return reply_(token, '🗑️ ยกเลิกรายงานที่ค้างอยู่แล้ว');
  }

  if (CMD_STATUS.test(text)) {
    const session = loadSession_(source);
    return reply_(token, session ? summaryText_(session) : 'ยังไม่มีรายงานที่ค้างอยู่');
  }

  if (CMD_SUBMIT.test(text)) {
    const session = loadSession_(source);
    if (!session || (!session.today.items.length && !session.photos.length)) {
      return reply_(token, 'ยังไม่มีข้อมูลรายงาน พิมพ์ "ฟอร์ม" เพื่อดูวิธีกรอก');
    }
    if (!session.reporter) {
      return reply_(token, reporterPicker_('ยังไม่ได้เลือกผู้เขียนรายงาน เลือกชื่อแล้วพิมพ์ "ส่ง" อีกครั้ง 👇'));
    }
    // เผื่อโครงการเพิ่งถูกเพิ่มหลังจากเลือกรหัสไปแล้ว
    if (session.project.code && !session.project.name) setProject_(session, session.project.code);
    const result = buildReport_(session);
    saveUserDefaults_(source, session);
    deleteSession_(source);
    return replyOrPush_(token, source,
      `✅ สร้างรายงานเรียบร้อย\n${session.project.code || ''} • ${thaiDateShort_(session.date)}\n` +
      `ผู้เขียนรายงาน: ${session.reporter}\n\n📄 PDF:\n${result.pdfUrl}`);
  }

  const session = withSession_(source, s => applyText_(s, text));
  const summary = '📝 บันทึกแล้ว\n' + summaryText_(session);
  if (!session.reporter) return reply_(token, summary, reporterPicker_('เลือกชื่อผู้เขียนรายงาน 👇'));
  if (!session.project.code) return reply_(token, summary, projectPicker_());
  if (!session.project.name) {
    return reply_(token, summary,
      projectPicker_(`⚠️ ยังไม่มีข้อมูล ${session.project.code} ในระบบ กด "➕ เพิ่มโครงการ" ได้เลย 👇`));
  }
  reply_(token, summary + '\n\nส่งรูปต่อได้เลย หรือพิมพ์ "ส่ง" เพื่อออกรายงาน');
}

// ===== แปลงข้อความเป็นข้อมูลรายงาน =====

/** ช่องข้อมูลแบบ "หัวข้อ: ค่า" — sec คือส่วนที่กำลังกรอกอยู่ (วันนี้ หรือ แผนพรุ่งนี้) */
const FIELD_HANDLERS = [
  { aliases: ['ผู้รายงาน', 'ผู้เขียนรายงาน', 'ผู้บันทึก'], set: (s, v) => { s.reporter = matchName_(v); } },
  { aliases: ['ผู้ควบคุมงาน', 'หัวหน้า', 'หัวหน้างาน'], set: (s, v) => { s.supervisor = matchName_(v); } },
  { aliases: ['โครงการ', 'project', 'pj'], set: (s, v) => setProject_(s, v) },
  { aliases: ['ชื่อโครงการ'], set: (s, v) => { s.project.name = v; } },
  { aliases: ['สถานที่', 'สถานที่ปฏิบัติงาน', 'location'], set: (s, v) => { s.project.location = v; } },
  { aliases: ['ลักษณะงาน', 'ลักษณะโครงการ'], set: (s, v) => { s.project.jobType = v; } },
  { aliases: ['เริ่มงาน', 'เวลาเริ่ม', 'เวลาเริ่มงาน'], set: (s, v) => { s.start = formatTime_(v); } },
  { aliases: ['เลิกงาน', 'จบงาน', 'เวลาจบ', 'เวลาจบงาน'], set: (s, v) => { s.end = formatTime_(v); } },
  { aliases: ['คน', 'คนงาน', 'กำลังพล'], set: (s, v, sec) => { sec.manpower = v.replace(/คน/g, '').trim(); } },
  { aliases: ['อากาศ', 'สภาพอากาศ'], set: (s, v) => { s.weather = v; } },
  { aliases: ['ช่วงฝนตก', 'ฝนตกช่วง', 'เวลาฝนตก'], set: (s, v) => { s.rainTime = v; } },
  { aliases: ['อุณหภูมิ'], set: (s, v) => { s.temp = v.replace(/องศา.*|°.*/g, '').trim(); } },
  { aliases: ['ผลกระทบ'], set: (s, v) => { s.impact = v; } },
  { aliases: ['อุบัติเหตุ'], set: (s, v) => { s.accident = v; } },
  { aliases: ['หมายเหตุ'], set: (s, v) => { s.notes = v; } },
  { aliases: ['ปัญหา', 'ปัญหาอุปสรรค'], set: (s, v, sec) => { lastItem_(sec).problem = v; } },
  { aliases: ['ความคืบหน้า', 'คืบหน้า'], set: (s, v, sec) => { lastItem_(sec).progress = formatPercent_(v); } },
];

function applyText_(session, text) {
  text.split(/\r?\n/).forEach(raw => {
    const line = raw.trim();
    if (!line || /^#?(รายงาน|report)$/i.test(line)) return;
    if (CMD_PLAN.test(line)) {
      session.section = 'plan';
      return;
    }
    if (CMD_TODAY.test(line)) {
      session.section = 'today';
      return;
    }

    const sec = session[session.section];
    if (CONFIG.GROUP_PATTERN.test(line)) {
      sec.group = line.replace(/^PJ\s*/i, 'PJ ');
      if (!session.project.code) setProject_(session, line);
      return;
    }

    // "1. ประชุมแผนงาน 100%" = งานใหม่
    const numbered = line.match(/^\d+\s*[.)]\s*(.*)$/);
    if (numbered) return addItem_(sec, numbered[1]);

    const kv = line.match(/^([^:：]+)[:：]\s*(.*)$/);
    if (kv) {
      const key = kv[1].trim().toLowerCase();
      const value = kv[2].trim();
      const field = FIELD_HANDLERS.find(f => f.aliases.some(a => a.toLowerCase() === key));
      if (field) return field.set(session, value, sec);
      const machine = CONFIG.MACHINES.find(m => m.aliases.some(a => a.toLowerCase() === key));
      if (machine) {
        sec.machines[machine.key] = parseMachine_(value);
        return;
      }
    }
    addItem_(sec, line);
  });
}

function addItem_(sec, text) {
  const pct = text.match(/\s*(\d+(?:\.\d+)?)\s*%\s*$/);
  sec.items.push({
    group: sec.group || '',
    title: pct ? text.slice(0, pct.index).trim() : text,
    progress: pct ? pct[1] + '%' : '',
    problem: '',
  });
}

function lastItem_(sec) {
  if (!sec.items.length) addItem_(sec, '-');
  return sec.items[sec.items.length - 1];
}

function normalizeCode_(value) {
  const m = value.match(/PJ\s*(\d+)/i);
  return m ? 'PJ ' + m[1] : value.trim();
}

function setProject_(session, value) {
  const code = normalizeCode_(value);
  const preset = getProjects_()[code] || {};
  session.project = Object.assign({ code: code, name: '', location: '', jobType: '' }, preset, { code: code });
}

// ===== จัดการโครงการจากในไลน์ (เก็บใน Script Properties) =====

function getSavedProjects_() {
  const raw = PropertiesService.getScriptProperties().getProperty('PROJECTS');
  return raw ? JSON.parse(raw) : {};
}

function getProjects_() {
  return Object.assign({}, CONFIG.PROJECTS, getSavedProjects_());
}

/** "เพิ่มโครงการ" อย่างเดียว = ส่งแบบฟอร์มให้กรอก, มีข้อมูลต่อท้าย = บันทึกโครงการ */
function addProjectFromText_(text) {
  const project = {};
  let code = '';
  text.split(/\r?\n/).slice(1).forEach(line => {
    const kv = line.trim().match(/^([^:：]+)[:：]\s*(.*)$/);
    if (!kv || !kv[2].trim()) return;
    const key = kv[1].trim().toLowerCase();
    const value = kv[2].trim();
    if (['รหัส', 'รหัสโครงการ', 'pj', 'code'].includes(key)) code = normalizeCode_(value);
    else if (['ชื่อ', 'ชื่อโครงการ'].includes(key)) project.name = value;
    else if (['สถานที่', 'สถานที่ปฏิบัติงาน'].includes(key)) project.location = value;
    else if (['ลักษณะงาน', 'ลักษณะโครงการ'].includes(key)) project.jobType = value;
  });

  if (!code) {
    return [
      'คัดลอกข้อความด้านล่าง เติมข้อมูล แล้วส่งกลับมา 👇',
      'เพิ่มโครงการ\nรหัส: PJ \nชื่อโครงการ: \nสถานที่: \nลักษณะงาน: ',
    ];
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const saved = getSavedProjects_();
    const existed = !!getProjects_()[code];
    saved[code] = Object.assign({ name: '', location: '', jobType: '' }, saved[code], project);
    PropertiesService.getScriptProperties().setProperty('PROJECTS', JSON.stringify(saved));
    const p = saved[code];
    return [`✅ ${existed ? 'แก้ไข' : 'เพิ่ม'}โครงการ ${code} แล้ว\n` +
      `ชื่อ: ${p.name || '-'}\nสถานที่: ${p.location || '-'}\nลักษณะงาน: ${p.jobType || '-'}\n\n` +
      `ใช้งาน: พิมพ์ "โครงการ: ${code}"`];
  } finally {
    lock.releaseLock();
  }
}

function deleteProject_(value) {
  const code = normalizeCode_(value);
  const saved = getSavedProjects_();
  if (!saved[code]) {
    return CONFIG.PROJECTS[code]
      ? `${code} ถูกตั้งไว้ในโค้ด (CONFIG.PROJECTS) ลบจากไลน์ไม่ได้`
      : `ไม่พบโครงการ ${code}`;
  }
  delete saved[code];
  PropertiesService.getScriptProperties().setProperty('PROJECTS', JSON.stringify(saved));
  return `🗑️ ลบโครงการ ${code} แล้ว`;
}

function projectListText_() {
  const projects = getProjects_();
  const codes = Object.keys(projects);
  if (!codes.length) return 'ยังไม่มีโครงการ กด "➕ เพิ่มโครงการ" ได้เลย 👇';
  return '📁 โครงการทั้งหมด\n' + codes.map(c => `• ${c} — ${projects[c].name || '-'}`).join('\n') +
    '\n\nเลือกโครงการ หรือเพิ่มใหม่ 👇';
}

function matchName_(value) {
  const v = value.trim();
  return CONFIG.REPORTERS.find(n => n === v) ||
    CONFIG.REPORTERS.find(n => n.split(' ')[0] === v.split(' ')[0]) ||
    v;
}

function parseMachine_(value) {
  const size = value.match(/ขนาด\s*([\d.]+)/);
  const qty = value.replace(/ขนาด\s*[\d.]+\s*(ตัน)?/, '').match(/\d+/);
  return { qty: qty ? qty[0] : '', size: size ? size[1] : '', text: value };
}

function formatTime_(v) {
  const m = v.match(/^(\d{1,2})(?:[.:](\d{2}))?\s*(น\.?)?$/);
  if (!m) return v;
  return `${('0' + m[1]).slice(-2)}.${m[2] || '00'} น.`;
}

function formatPercent_(v) {
  const n = v.match(/\d+(?:\.\d+)?/);
  return n ? n[0] + '%' : v;
}

function addPhoto_(session, messageId) {
  const res = UrlFetchApp.fetch(`https://api-data.line.me/v2/bot/message/${messageId}/content`, {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  const blob = res.getBlob().setName(`${session.date}_${messageId}.jpg`);
  const file = getSubFolder_(getRootFolder_(), 'รูปภาพ', session.date).createFile(blob);
  const item = session.today.items[session.today.items.length - 1];
  const caption = item ? [item.group, item.title].filter(Boolean).join(' : ') : (session.today.group || '');
  session.photos.push({ id: file.getId(), caption: caption });
}

// ===== สร้างรายงาน (Google Doc -> PDF) =====

const PAGE_WIDTH = 523; // A4 กว้าง 595pt - ขอบซ้ายขวา 36pt

function buildReport_(session) {
  const folder = getSubFolder_(getRootFolder_(), 'รายงาน', session.date);
  const fileName = `FM_Daily_Report_${(session.project.code || 'PJ').replace(/\s/g, '')}_` +
    `${session.date.replace(/-/g, '')}_${session.reporter.split(' ')[0]}`;
  const doc = DocumentApp.create(fileName);
  const body = doc.getBody();
  body.setPageWidth(595.28).setPageHeight(841.89)
    .setMarginTop(28).setMarginBottom(28).setMarginLeft(36).setMarginRight(36);
  doc.addFooter().appendParagraph(CONFIG.FORM_CODE).setAttributes(fontAttrs_(7));

  const logoPara = body.getParagraphs()[0].setAlignment(DocumentApp.HorizontalAlignment.RIGHT);
  if (CONFIG.LOGO_FILE_ID) {
    const logo = logoPara.appendInlineImage(DriveApp.getFileById(CONFIG.LOGO_FILE_ID).getBlob());
    scaleImage_(logo, 120);
  }

  appendHeaderSection_(body, session);
  appendConditionSection_(body, session);
  appendPhotoSection_(body, session);
  appendSummarySection_(body, session);
  appendSafetySection_(body, session);
  appendPlanSection_(body, session);
  appendSignatureSection_(body, session);
  tightenGaps_(body);

  doc.saveAndClose();
  const docFile = DriveApp.getFileById(doc.getId());
  docFile.moveTo(folder);
  const pdfFile = folder.createFile(docFile.getAs(MimeType.PDF)).setName(fileName + '.pdf');
  try {
    pdfFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (err) {
    console.warn('ตั้งค่าแชร์ลิงก์ไม่ได้ (โดเมนอาจปิดไว้): ' + err.message);
  }

  logToSheet_(session, pdfFile.getUrl(), docFile.getUrl());
  return { pdfUrl: pdfFile.getUrl(), docUrl: docFile.getUrl() };
}

function appendHeaderSection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  addTable_(body, [[{ text: CONFIG.REPORT_TITLE, bold: true, align: center, size: 13 }]], [PAGE_WIDTH]);
  const label = text => ({ text: text, bold: true });
  addTable_(body, [
    [{ text: 'รายละเอียดโครงการ (Project Detail)', bold: true, align: center, bg: GRAY }, '',
      label('วันที่ (Date)'), { text: dateDash_(s.date), align: center }],
    [label('ชื่อโครงการ (Project Name)'), { text: s.project.name || s.project.code || '-', bold: true, align: center },
      label('ผู้เขียนรายงาน (Prepared by)'), { text: s.reporter, align: center }],
    [label('สถานที่ปฏิบัติงาน (Location)'), { text: s.project.location || '-', bold: true, align: center },
      label('เวลาเริ่มงาน (Start Time)'), { text: s.start || CONFIG.DEFAULT_START, align: center }],
    [label('ลักษณะโครงการ (Job Type)'), { text: s.project.jobType || '-', bold: true, align: center },
      label('เวลาจบงาน (End Time)'), { text: s.end || CONFIG.DEFAULT_END, align: center }],
  ], [130, 141, 130, 122]);
}

function appendConditionSection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  const weather = CONFIG.WEATHER_OPTIONS
    .map(opt => `${s.weather && s.weather.indexOf(opt) >= 0 ? CHECKED : UNCHECKED} ${opt}`).join('      ');
  const hasImpact = /^มี/.test(s.impact || '');
  addTable_(body, [
    [{ text: 'กำลังพล (Manpower)', bold: true, align: center, bg: GRAY },
      { text: 'เครื่องจักร (Machinery) — ชนิด / จำนวน (คัน)', bold: true, align: center, bg: GRAY }],
    [{ text: `${s.today.manpower || '-'} คน`, align: center }, machineLines_(s.today.machines)],
    [{ text: 'สภาพอากาศ (Weather Condition)', bold: true, align: center, bg: GRAY },
      { text: 'หมายเหตุ', bold: true, align: center, bg: GRAY }],
    [[weather,
      `ช่วงเวลาที่ฝนตก :  ${s.rainTime || '-'}  น.`,
      `อุณหภูมิเฉลี่ย :  ${s.temp || '-'}  องศาเซลเซียส`],
    { text: s.notes || '-', align: center }],
    [{ text: 'ผลกระทบของสภาพอากาศต่อการปฏิบัติงาน (Schedule impact)', bold: true, align: center, bg: GRAY }, ''],
    [[`${hasImpact ? CHECKED : UNCHECKED} มีผลกระทบต่อการทำงาน` +
      (hasImpact ? ' : ' + s.impact.replace(/^มี(ผลกระทบ)?\s*/, '') : ''),
    `${hasImpact ? UNCHECKED : CHECKED} ไม่มีผลกระทบต่อการทำงาน`], ''],
  ], [261, 262]);
}

function machineLines_(machines) {
  return CONFIG.MACHINES.map(m => {
    const v = machines[m.key];
    const box = v ? CHECKED : UNCHECKED;
    if (m.key === 'other') return `${box} อื่นๆ โปรดระบุ ${v ? ': ' + v.text : ''}`;
    const size = m.sized ? ` ขนาด ${v && v.size ? v.size : '......'} ตัน` : '';
    return `${box} ${m.label}${size}  —  ${v && v.qty ? v.qty : '-'}`;
  });
}

function appendPhotoSection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  addTable_(body, [[[
    { text: 'ภาพถ่ายหน้างาน', bold: true, align: center },
    { text: s.project.code || '', bold: true, align: center, size: 14 },
  ]]], [PAGE_WIDTH]);
  if (!s.photos.length) return;

  const perRow = CONFIG.PHOTOS_PER_ROW;
  const rows = [];
  for (let i = 0; i < s.photos.length; i += perRow) rows.push(new Array(perRow).fill(''));
  const table = addTable_(body, rows, new Array(perRow).fill(PAGE_WIDTH / perRow));

  s.photos.forEach((photo, i) => {
    const cell = table.getCell(Math.floor(i / perRow), i % perRow);
    const para = cell.getChild(0).asParagraph().setAlignment(center);
    scaleImage_(para.appendInlineImage(DriveApp.getFileById(photo.id).getBlob()), CONFIG.PHOTO_WIDTH);
    cell.appendParagraph(`(${i + 1}) ${photo.caption}`).setAlignment(center).setAttributes(fontAttrs_(8));
  });
}

function appendSummarySection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  addTable_(body, [[{ text: 'สรุปผลการปฏิบัติงาน (Work Summary)', bold: true, align: center, bg: GRAY }]],
    [PAGE_WIDTH]);
  const rows = [[
    { text: 'รายละเอียดงาน (Detail)', bold: true, align: center },
    { text: 'เปอร์เซ็นต์ความคืบหน้า', bold: true, align: center },
    { text: 'ปัญหาอุปสรรค', bold: true, align: center },
  ]];
  groupItems_(s.today.items).forEach(g => {
    if (g.group) rows.push([{ text: g.group, bold: true }, '', '']);
    g.items.forEach((it, i) => rows.push([`${i + 1}.${it.title}`,
      { text: it.progress || '', align: center }, it.problem || '']));
  });
  if (rows.length === 1) rows.push(['-', '', '']);
  addTable_(body, rows, [303, 90, 130]);
}

function appendSafetySection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  const acc = (s.accident || '').trim();
  const hasAccident = acc && !/^(ไม่มี|-|no|none)/i.test(acc);
  addTable_(body, [
    [{ text: 'รายงานด้านความปลอดภัย', bold: true, align: center, bg: GRAY },
      `${hasAccident ? UNCHECKED : CHECKED} ไม่มีอุบัติเหตุเกิดขึ้นในโครงการ`,
      `${hasAccident ? CHECKED : UNCHECKED} มีอุบัติเหตุเกิดขึ้นในโครงการ`],
    [{ text: 'ระบุอุบัติเหตุที่เกิดขึ้น (ถ้ามี) :', bold: true },
      { text: hasAccident ? acc.replace(/^มี(อุบัติเหตุ)?\s*/, '') || acc : '-', align: center }, ''],
  ], [200, 162, 161]);
}

function appendPlanSection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  const plan = s.plan;
  addTable_(body, [[{ text: `รายละเอียดแผนงานวันถัดไป (Work Plan) วันที่ ${dateSlash_(nextDay_(s.date))}`,
    bold: true, align: center, color: RED }]], [PAGE_WIDTH]);

  const details = [];
  groupItems_(plan.items).forEach(g => {
    if (g.group) details.push(g.group);
    g.items.forEach((it, i) => details.push(`${i + 1}.${it.title}`));
  });
  addTable_(body, [
    [{ text: 'กำลังพล (Manpower)', bold: true, align: center, color: RED },
      { text: 'เครื่องจักร (Machinery) — ชนิด / จำนวน (คัน)', bold: true, align: center, color: RED }],
    [{ text: `${plan.manpower || '-'} คน`, align: center, color: RED }, { lines: machineLines_(plan.machines), color: RED }],
    [{ text: 'รายละเอียดงาน (Detail)', bold: true, align: center, color: RED }, ''],
    [{ lines: details.length ? details : ['-'], color: RED }, ''],
  ], [261, 262]);
}

function appendSignatureSection_(body, s) {
  const center = DocumentApp.HorizontalAlignment.CENTER;
  const date = thaiDateShort_(s.date);
  const sign = (title, name, signedDate) => ({
    lines: ['', `${title}  ${name || '........................'}`, `วันที่/Date:  ${signedDate || '........................'}`],
    align: center,
  });
  addTable_(body, [[
    sign('ลงชื่อผู้บันทึก', s.reporter, date),
    sign('ลงชื่อผู้ควบคุมงาน', s.supervisor || s.reporter, date),
    sign('ลงชื่อลูกค้า', '', ''),
  ]], [174, 175, 174], { border: 0 });
}

function groupItems_(items) {
  const groups = [];
  items.forEach(it => {
    const last = groups[groups.length - 1];
    if (last && last.group === it.group) last.items.push(it);
    else groups.push({ group: it.group, items: [it] });
  });
  return groups;
}

// ===== ตัวช่วยจัดหน้าเอกสาร =====

function fontAttrs_(size, bold, color) {
  const a = {};
  a[DocumentApp.Attribute.FONT_FAMILY] = CONFIG.FONT;
  a[DocumentApp.Attribute.FONT_SIZE] = size;
  a[DocumentApp.Attribute.BOLD] = !!bold;
  a[DocumentApp.Attribute.FOREGROUND_COLOR] = color || '#000000';
  return a;
}

/**
 * rows: แต่ละช่องเป็น string, array ของบรรทัด หรือ { text|lines, bold, align, bg, color, size }
 */
function addTable_(body, rows, widths, opt) {
  const table = body.appendTable(rows.map(r => r.map(() => '')));
  table.setBorderWidth(opt && opt.border === 0 ? 0 : 0.5).setBorderColor('#000000');
  widths.forEach((w, i) => table.setColumnWidth(i, w));
  rows.forEach((row, r) => row.forEach((content, c) => fillCell_(table.getCell(r, c), content)));
  return table;
}

function fillCell_(cell, content) {
  const spec = content && typeof content === 'object' && !Array.isArray(content) ? content : { lines: content };
  const lines = [].concat(spec.lines !== undefined ? spec.lines : spec.text);
  cell.setPaddingTop(2).setPaddingBottom(2).setPaddingLeft(4).setPaddingRight(4);
  if (spec.bg) cell.setBackgroundColor(spec.bg);

  lines.forEach((line, i) => {
    const item = line && typeof line === 'object' ? line : { text: line };
    const text = item.text === undefined || item.text === null ? '' : String(item.text);
    // Google Docs ไม่ยอมให้ใส่ข้อความว่าง: ย่อหน้าแรกของช่องว่างอยู่แล้ว ส่วนบรรทัดถัดไปใช้ช่องว่างแทน
    let p;
    if (i === 0) {
      p = cell.getChild(0).asParagraph();
      if (text) p.setText(text);
    } else {
      p = cell.appendParagraph(text || ' ');
    }
    p.setSpacingBefore(0).setSpacingAfter(0).setLineSpacing(1)
      .setAlignment(item.align || spec.align || DocumentApp.HorizontalAlignment.LEFT)
      .setAttributes(fontAttrs_(item.size || spec.size || 9, item.bold || spec.bold, item.color || spec.color));
  });
}

function scaleImage_(img, width) {
  const ratio = width / img.getWidth();
  img.setWidth(width).setHeight(Math.round(img.getHeight() * ratio));
}

/** ย่อบรรทัดว่างที่คั่นระหว่างตาราง ให้ตารางต่อกันเป็นฟอร์มเดียว */
function tightenGaps_(body) {
  for (let i = 1; i < body.getNumChildren(); i++) {
    const el = body.getChild(i);
    if (el.getType() !== DocumentApp.ElementType.PARAGRAPH) continue;
    if (el.asParagraph().getText() !== '') continue;
    if (body.getChild(i - 1).getType() !== DocumentApp.ElementType.TABLE) continue;
    el.asParagraph().setSpacingBefore(0).setSpacingAfter(0).setLineSpacing(1).setAttributes(fontAttrs_(1));
  }
}

function logToSheet_(session, pdfUrl, docUrl) {
  const sheet = getSheet_();
  sheet.appendRow([
    new Date(),
    session.date,
    session.project.code,
    session.reporter,
    session.today.manpower,
    session.weather,
    session.temp,
    session.accident,
    session.today.items.map(it => `${it.group ? it.group + ' ' : ''}${it.title} ${it.progress}`.trim()).join('\n'),
    session.photos.length,
    pdfUrl,
    docUrl,
  ]);
}

// ===== Session (ข้อมูลที่ค้างไว้ของแต่ละคน) =====

function sessionKey_(source) {
  return 'S_' + (source.groupId || source.roomId || 'dm') + '_' + source.userId;
}

function loadSession_(source) {
  const raw = PropertiesService.getScriptProperties().getProperty(sessionKey_(source));
  return raw ? JSON.parse(raw) : null;
}

function deleteSession_(source) {
  PropertiesService.getScriptProperties().deleteProperty(sessionKey_(source));
}

function newSession_(source) {
  const raw = PropertiesService.getScriptProperties().getProperty('U_' + source.userId);
  const defaults = raw ? JSON.parse(raw) : {};
  const session = {
    date: today_(),
    reporter: defaults.reporter || '',
    supervisor: defaults.supervisor || '',
    project: { code: '', name: '', location: '', jobType: '' },
    section: 'today',
    today: { manpower: '', machines: {}, items: [], group: '' },
    plan: { manpower: '', machines: {}, items: [], group: '' },
    photos: [],
  };
  if (defaults.projectCode) setProject_(session, defaults.projectCode);
  return session;
}

/** จำชื่อผู้รายงาน/โครงการล่าสุดไว้ ครั้งหน้าไม่ต้องเลือกใหม่ */
function saveUserDefaults_(source, session) {
  PropertiesService.getScriptProperties().setProperty('U_' + source.userId, JSON.stringify({
    reporter: session.reporter,
    supervisor: session.supervisor,
    projectCode: session.project.code,
  }));
}

/** โหลด session (สร้างใหม่ถ้ายังไม่มี) แก้ไข แล้วบันทึก โดยล็อกกันรูปหลายรูปเข้าพร้อมกัน */
function withSession_(source, mutate) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const session = loadSession_(source) || newSession_(source);
    mutate(session);
    PropertiesService.getScriptProperties().setProperty(sessionKey_(source), JSON.stringify(session));
    return session;
  } finally {
    lock.releaseLock();
  }
}

function summaryText_(s) {
  const lines = [`📋 ${s.project.code || 'ยังไม่ระบุโครงการ'} • ${thaiDateShort_(s.date)}`,
    `ผู้เขียนรายงาน: ${s.reporter || '❗ยังไม่เลือก'}`];
  if (s.today.manpower) lines.push(`กำลังพล: ${s.today.manpower} คน`);
  if (s.weather) lines.push(`อากาศ: ${s.weather}${s.temp ? ' / ' + s.temp + '°C' : ''}`);
  if (s.accident) lines.push(`อุบัติเหตุ: ${s.accident}`);
  groupItems_(s.today.items).forEach(g => {
    if (g.group) lines.push(g.group);
    g.items.forEach((it, i) => lines.push(`${i + 1}. ${it.title} ${it.progress}`.trim()));
  });
  lines.push(`📷 รูป ${s.photos.length} รูป`);
  if (s.plan.items.length || s.plan.manpower) lines.push(`🗓️ แผนพรุ่งนี้ ${s.plan.items.length} งาน`);
  if (s.section === 'plan') lines.push('(ตอนนี้กำลังกรอก "แผนพรุ่งนี้" พิมพ์ "วันนี้" เพื่อกลับ)');
  return lines.join('\n');
}

function helpText_() {
  return [
    '📋 วิธีส่งรายงานประจำวัน',
    '',
    '① ข้อมูลทั่วไป',
    'โครงการ: PJ 942',
    'คน: 4',
    'อากาศ: ปกติ  (ฝนตก/แดดจัด/ปกติ)',
    'อุณหภูมิ: 32',
    'รถยนต์: 3',
    'ผลกระทบ: ไม่มี',
    'อุบัติเหตุ: ไม่มี',
    '',
    '② งานวันนี้ (พิมพ์งาน แล้วส่งรูปของงานนั้นตาม)',
    'PJ 942',
    '1. ประชุมแผนงาน 100%',
    '→ ส่งรูป',
    'PJ 69014',
    '1. ติดตามงานชุดปรับคืนน้ำเสีย 5%',
    '→ ส่งรูป',
    '',
    '③ แผนพรุ่งนี้ (ถ้ามี)',
    'แผนพรุ่งนี้',
    'คน: 11',
    'รถยนต์: 5',
    'PJ 942',
    '1. ต่อท่อ HDPE',
    '',
    '④ พิมพ์ "ส่ง" เพื่อรับไฟล์ PDF',
    '',
    'คำสั่งอื่น: "ชื่อ" เลือกผู้เขียนรายงาน, "สถานะ" ดูข้อมูลที่กรอก, "ยกเลิก" เริ่มใหม่',
    'โครงการ: "เพิ่มโครงการ", "รายการโครงการ", "ลบโครงการ: PJ xxx"',
  ].join('\n');
}

// ===== LINE API =====

function token_() {
  const t = PropertiesService.getScriptProperties().getProperty('LINE_CHANNEL_ACCESS_TOKEN');
  if (!t) throw new Error('ยังไม่ได้ตั้งค่า LINE_CHANNEL_ACCESS_TOKEN ใน Script Properties');
  return t;
}

function isAllowed_(source) {
  const list = PropertiesService.getScriptProperties().getProperty('ALLOWED_SOURCE_IDS');
  if (!list) return true;
  const allowed = list.split(',').map(s => s.trim());
  return [source.groupId, source.roomId, source.userId].some(id => id && allowed.includes(id));
}

function lineApi_(path, payload) {
  return UrlFetchApp.fetch('https://api.line.me/v2/bot/' + path, {
    method: payload ? 'post' : 'get',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + token_() },
    payload: payload ? JSON.stringify(payload) : undefined,
    muteHttpExceptions: true,
  });
}

function toMessage_(m) {
  return typeof m === 'string' ? { type: 'text', text: m } : m;
}

function reply_(replyToken, ...messages) {
  return lineApi_('message/reply', { replyToken: replyToken, messages: messages.map(toMessage_) });
}

/** การสร้าง PDF อาจนานจน reply token หมดอายุ ถ้าตอบไม่สำเร็จให้ส่งแบบ push แทน */
function replyOrPush_(replyToken, source, text) {
  const res = reply_(replyToken, text);
  if (res.getResponseCode() === 200) return;
  lineApi_('message/push', {
    to: source.groupId || source.roomId || source.userId,
    messages: [toMessage_(text)],
  });
}

function quickReply_(text, options) {
  return {
    type: 'text',
    text: text,
    quickReply: {
      items: options.slice(0, 13).map(o => ({
        type: 'action',
        action: { type: 'message', label: o.label.slice(0, 20), text: o.text },
      })),
    },
  };
}

function reporterPicker_(text) {
  return quickReply_(text, CONFIG.REPORTERS.map(n => ({ label: n, text: 'ผู้รายงาน: ' + n })));
}

/** ปุ่มเลือกโครงการ (12 โครงการล่าสุด) + ปุ่มเพิ่มโครงการ */
function projectPicker_(text) {
  const options = Object.keys(getProjects_()).slice(-12)
    .map(code => ({ label: code, text: 'โครงการ: ' + code }));
  options.push({ label: '➕ เพิ่มโครงการ', text: 'เพิ่มโครงการ' });
  return quickReply_(text || 'เลือกโครงการ 👇 (หรือพิมพ์ "โครงการ: PJ xxx")', options);
}

// ===== Google Drive / Sheets =====

function getRootFolder_() {
  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('ROOT_FOLDER_ID');
  if (id) return DriveApp.getFolderById(id);
  const folder = DriveApp.createFolder(CONFIG.ROOT_FOLDER_NAME);
  props.setProperty('ROOT_FOLDER_ID', folder.getId());
  return folder;
}

function getSubFolder_(parent, ...names) {
  return names.reduce((folder, name) => {
    const it = folder.getFoldersByName(name);
    return it.hasNext() ? it.next() : folder.createFolder(name);
  }, parent);
}

function getSheet_() {
  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('SHEET_ID');
  if (id) return SpreadsheetApp.openById(id).getSheets()[0];

  const ss = SpreadsheetApp.create('LINE Daily Report - บันทึก');
  DriveApp.getFileById(ss.getId()).moveTo(getRootFolder_());
  const sheet = ss.getSheets()[0];
  sheet.appendRow(['เวลาส่ง', 'วันที่รายงาน', 'โครงการ', 'ผู้เขียนรายงาน', 'กำลังพล', 'สภาพอากาศ',
    'อุณหภูมิ', 'อุบัติเหตุ', 'งาน', 'จำนวนรูป', 'PDF', 'Google Doc']);
  sheet.setFrozenRows(1);
  props.setProperty('SHEET_ID', ss.getId());
  return sheet;
}

// ===== วันที่ =====

function today_() {
  return Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyy-MM-dd');
}

function parseIso_(iso) {
  return iso.split('-').map(Number);
}

function nextDay_(iso) {
  const [y, m, d] = parseIso_(iso);
  return Utilities.formatDate(new Date(Date.UTC(y, m - 1, d + 1)), 'UTC', 'yyyy-MM-dd');
}

/** 17-10-26 */
function dateDash_(iso) {
  const [y, m, d] = iso.split('-');
  return `${d}-${m}-${y.slice(2)}`;
}

/** 18/10/2026 */
function dateSlash_(iso) {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

/** 17 ต.ค. 69 */
function thaiDateShort_(iso) {
  const [y, m, d] = parseIso_(iso);
  return `${d} ${THAI_MONTHS_SHORT[m - 1]} ${String(y + 543).slice(2)}`;
}

// ===== รันครั้งแรกจากหน้า Editor เพื่อขอสิทธิ์และสร้างโฟลเดอร์/ชีต =====

function setup() {
  token_();
  const folder = getRootFolder_();
  const sheet = getSheet_();
  UrlFetchApp.fetch('https://api.line.me/v2/bot/info', {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  DocumentApp.create('ทดสอบสิทธิ์').saveAndClose();
  console.log('โฟลเดอร์: ' + folder.getUrl());
  console.log('ชีตบันทึก: ' + sheet.getParent().getUrl());
  console.log('พร้อมใช้งาน ✅ ต่อไปให้ Deploy เป็น Web app');
}

/** ทดสอบสร้างรายงานตัวอย่างโดยไม่ต้องผ่านไลน์ (กด Run ในหน้า Editor) */
function testReport() {
  const session = newSession_({ userId: 'test' });
  session.reporter = CONFIG.REPORTERS[0];
  applyText_(session, [
    'โครงการ: PJ 942', 'คน: 4', 'อากาศ: ปกติ', 'อุณหภูมิ: 32', 'รถยนต์: 3',
    'ผลกระทบ: ไม่มี', 'อุบัติเหตุ: ไม่มี',
    'PJ 942', '1. ประชุมแผนงาน 100%',
    'PJ 69014', '1. ติดตามงานชุดปรับคืนน้ำเสีย 5%',
    'แผนพรุ่งนี้', 'คน: 11', 'รถยนต์: 5',
    'PJ 942', '1. ต่อท่อ HDPE', 'PJ 943, 944, 945, 946', '1. เดินไฟฟ้าสำหรับออฟฟิศและงานเชื่อมท่อ',
  ].join('\n'));
  console.log('PDF: ' + buildReport_(session).pdfUrl);
}

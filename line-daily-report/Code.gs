/**
 * LINE Daily Report Bot (Google Apps Script)
 *
 * พนักงานส่งข้อความ + รูปเข้า LINE OA -> ระบบเก็บรูปลง Google Drive
 * -> พิมพ์ "ส่ง" -> ได้รายงาน PDF กลับมาในแชต + บันทึกลง Google Sheets
 *
 * Script Properties ที่ต้องตั้ง:
 *   LINE_CHANNEL_ACCESS_TOKEN  (จำเป็น)
 *   ALLOWED_SOURCE_IDS         (ไม่บังคับ) userId/groupId ที่อนุญาต คั่นด้วย ,
 */

// ===== ตั้งค่ารูปแบบรายงาน (แก้ให้ตรงกับฟอร์มของบริษัทได้) =====
const CONFIG = {
  REPORT_TITLE: 'รายงานการปฏิบัติงานประจำวัน (Daily Report)',
  COMPANY_NAME: '',
  // ข้อมูลทั่วไปของรายงาน: พนักงานพิมพ์ "ชื่อช่อง: ค่า" เช่น "อุณหภูมิ: 33"
  FIELDS: [
    { key: 'site', label: 'โครงการ / สถานที่', aliases: ['โครงการ', 'สถานที่', 'ไซต์', 'site'] },
    { key: 'weather', label: 'สภาพอากาศ', aliases: ['อากาศ', 'สภาพอากาศ', 'ฝน', 'ฝนตก'] },
    { key: 'temp', label: 'อุณหภูมิ (°C)', aliases: ['อุณหภูมิ', 'temp'] },
    { key: 'workers', label: 'จำนวนคนงาน', aliases: ['คนงาน', 'จำนวนคนงาน'] },
    { key: 'accident', label: 'อุบัติเหตุ', aliases: ['อุบัติเหตุ'] },
    { key: 'note', label: 'หมายเหตุ', aliases: ['หมายเหตุ', 'note'] },
  ],
  PHOTOS_PER_ROW: 2,
  PHOTO_WIDTH: 240,
  ROOT_FOLDER_NAME: 'LINE Daily Report',
};

const CMD_SUBMIT = /^(ส่ง|ส่งรายงาน|เสร็จ|จบ|submit)$/i;
const CMD_CANCEL = /^(ยกเลิก|cancel)$/i;
const CMD_STATUS = /^(สถานะ|เช็ค|เช็ก|status)$/i;
const CMD_HELP = /^(ฟอร์ม|วิธีใช้|help|\?)$/i;

const THAI_MONTHS = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];

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
  if (CMD_HELP.test(text)) return reply_(event.replyToken, helpText_());

  if (CMD_CANCEL.test(text)) {
    deleteSession_(source);
    return reply_(event.replyToken, '🗑️ ยกเลิกรายงานที่ค้างอยู่แล้ว');
  }

  if (CMD_STATUS.test(text)) {
    const session = loadSession_(source);
    return reply_(event.replyToken, session ? summaryText_(session) : 'ยังไม่มีรายงานที่ค้างอยู่');
  }

  if (CMD_SUBMIT.test(text)) {
    const session = loadSession_(source);
    if (!session || (!session.items.length && !Object.keys(session.fields).length)) {
      return reply_(event.replyToken, 'ยังไม่มีข้อมูลรายงาน พิมพ์ "ฟอร์ม" เพื่อดูวิธีกรอก');
    }
    if (!session.name) session.name = getDisplayName_(source);
    const result = buildReport_(session);
    deleteSession_(source);
    return replyOrPush_(event.replyToken, source,
      `✅ สร้างรายงานเรียบร้อย\n${session.name} • ${thaiDate_(session.date)}\n\n📄 PDF:\n${result.pdfUrl}`);
  }

  const session = withSession_(source, s => applyText_(s, text));
  reply_(event.replyToken, '📝 บันทึกแล้ว\n' + summaryText_(session) +
    '\n\nส่งรูปต่อได้เลย หรือพิมพ์ "ส่ง" เพื่อออกรายงาน');
}

// ===== แปลงข้อความเป็นข้อมูลรายงาน =====

function applyText_(session, text) {
  text.split(/\r?\n/).forEach(raw => {
    const line = raw.trim();
    if (!line || /^#?(รายงาน|report)$/i.test(line)) return;

    // "1. เทพื้นชั้น 2" หรือ "2) ติดตั้งท่อ" = เริ่มงานใหม่
    const numbered = line.match(/^\d+\s*[.)]\s*(.*)$/);
    if (numbered) return startItem_(session, numbered[1]);

    const kv = line.match(/^([^:：]+)[:：]\s*(.*)$/);
    if (kv) {
      const key = kv[1].trim().toLowerCase();
      const value = kv[2].trim();
      if (/^งาน/.test(key)) return startItem_(session, value); // "งาน:", "งานที่ 2:"
      if (/^รายละเอียด/.test(key)) return appendDetail_(session, value);
      const field = CONFIG.FIELDS.find(f => f.aliases.some(a => a.toLowerCase() === key));
      if (field) {
        session.fields[field.key] = value;
        return;
      }
    }
    appendDetail_(session, line);
  });
}

function startItem_(session, title) {
  session.items.push({ title: title, details: [], photos: [] });
}

function appendDetail_(session, text) {
  if (!session.items.length) return startItem_(session, text);
  session.items[session.items.length - 1].details.push(text);
}

function addPhoto_(session, messageId) {
  const res = UrlFetchApp.fetch(`https://api-data.line.me/v2/bot/message/${messageId}/content`, {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  const blob = res.getBlob().setName(`${session.date}_${messageId}.jpg`);
  const file = getSubFolder_(getRootFolder_(), 'รูปภาพ', session.date).createFile(blob);
  if (!session.items.length) startItem_(session, 'รูปภาพประกอบ');
  session.items[session.items.length - 1].photos.push(file.getId());
}

// ===== สร้างรายงาน =====

function buildReport_(session) {
  const folder = getSubFolder_(getRootFolder_(), 'รายงาน', session.date);
  const fileName = `DailyReport_${session.date}_${session.name}`;
  const doc = DocumentApp.create(fileName);
  const body = doc.getBody();
  body.setMarginTop(36).setMarginBottom(36).setMarginLeft(42).setMarginRight(42);

  body.getParagraphs()[0].setText(CONFIG.REPORT_TITLE)
    .setHeading(DocumentApp.ParagraphHeading.HEADING1)
    .setAlignment(DocumentApp.HorizontalAlignment.CENTER);
  if (CONFIG.COMPANY_NAME) {
    body.appendParagraph(CONFIG.COMPANY_NAME).setAlignment(DocumentApp.HorizontalAlignment.CENTER);
  }

  const infoRows = [['วันที่', thaiDate_(session.date)], ['ผู้รายงาน', session.name]]
    .concat(CONFIG.FIELDS.map(f => [f.label, session.fields[f.key] || '-']));
  const infoTable = body.appendTable(infoRows);
  infoTable.setColumnWidth(0, 150);
  for (let r = 0; r < infoTable.getNumRows(); r++) {
    infoTable.getCell(r, 0).setBackgroundColor('#EEEEEE').editAsText().setBold(true);
  }

  body.appendParagraph('รายละเอียดงาน').setHeading(DocumentApp.ParagraphHeading.HEADING2);
  session.items.forEach((item, i) => {
    body.appendParagraph(`${i + 1}. ${item.title || 'งาน'}`).setHeading(DocumentApp.ParagraphHeading.HEADING3);
    item.details.forEach(d => body.appendParagraph(d));
    if (item.photos.length) appendPhotos_(body, item.photos);
  });

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

function appendPhotos_(body, photoIds) {
  const perRow = CONFIG.PHOTOS_PER_ROW;
  const rows = [];
  for (let i = 0; i < photoIds.length; i += perRow) rows.push(new Array(perRow).fill(''));
  const table = body.appendTable(rows).setBorderWidth(0);

  photoIds.forEach((id, i) => {
    const cell = table.getCell(Math.floor(i / perRow), i % perRow);
    const para = cell.getChild(0).asParagraph().setAlignment(DocumentApp.HorizontalAlignment.CENTER);
    const img = para.appendInlineImage(DriveApp.getFileById(id).getBlob());
    const ratio = CONFIG.PHOTO_WIDTH / img.getWidth();
    img.setWidth(CONFIG.PHOTO_WIDTH).setHeight(Math.round(img.getHeight() * ratio));
  });
}

function logToSheet_(session, pdfUrl, docUrl) {
  const sheet = getSheet_();
  sheet.appendRow([
    new Date(),
    session.date,
    session.name,
    ...CONFIG.FIELDS.map(f => session.fields[f.key] || ''),
    session.items.map((it, i) => `${i + 1}. ${it.title}`).join('\n'),
    session.items.reduce((n, it) => n + it.photos.length, 0),
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

/** โหลด session (สร้างใหม่ถ้ายังไม่มี) แก้ไข แล้วบันทึก โดยล็อกกันรูปหลายรูปเข้าพร้อมกัน */
function withSession_(source, mutate) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const session = loadSession_(source) || {
      date: today_(),
      name: '',
      fields: {},
      items: [],
    };
    mutate(session);
    PropertiesService.getScriptProperties().setProperty(sessionKey_(source), JSON.stringify(session));
    return session;
  } finally {
    lock.releaseLock();
  }
}

function summaryText_(session) {
  const lines = [`📋 รายงานวันที่ ${thaiDate_(session.date)}`];
  CONFIG.FIELDS.forEach(f => {
    if (session.fields[f.key]) lines.push(`• ${f.label}: ${session.fields[f.key]}`);
  });
  session.items.forEach((it, i) => lines.push(`${i + 1}. ${it.title} (รูป ${it.photos.length})`));
  return lines.join('\n');
}

function helpText_() {
  return [
    '📋 วิธีส่งรายงานประจำวัน',
    '',
    '1) พิมพ์ข้อมูลทั่วไป (ส่งครั้งเดียว):',
    'โครงการ: อาคาร A',
    'อากาศ: ฝนตกช่วงบ่าย',
    'อุณหภูมิ: 32',
    'คนงาน: 8',
    'อุบัติเหตุ: ไม่มี',
    '',
    '2) พิมพ์งานทีละข้อ แล้วส่งรูปของงานนั้นตามทันที:',
    '1. เทพื้นชั้น 2  → ส่งรูป',
    '2. ติดตั้งท่อน้ำ  → ส่งรูป',
    '',
    '3) พิมพ์ "ส่ง" เพื่อรับไฟล์ PDF',
    '',
    'คำสั่งอื่น: "สถานะ" ดูข้อมูลที่กรอกแล้ว, "ยกเลิก" เริ่มใหม่',
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

function reply_(replyToken, text) {
  return lineApi_('message/reply', { replyToken: replyToken, messages: [{ type: 'text', text: text }] });
}

/** การสร้าง PDF อาจนานจน reply token หมดอายุ ถ้าตอบไม่สำเร็จให้ส่งแบบ push แทน */
function replyOrPush_(replyToken, source, text) {
  const res = reply_(replyToken, text);
  if (res.getResponseCode() === 200) return;
  lineApi_('message/push', {
    to: source.groupId || source.roomId || source.userId,
    messages: [{ type: 'text', text: text }],
  });
}

function getDisplayName_(source) {
  const path = source.groupId ? `group/${source.groupId}/member/${source.userId}`
    : source.roomId ? `room/${source.roomId}/member/${source.userId}`
      : `profile/${source.userId}`;
  const res = lineApi_(path);
  return res.getResponseCode() === 200 ? JSON.parse(res.getContentText()).displayName : 'ไม่ทราบชื่อ';
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
  sheet.appendRow(['เวลาส่ง', 'วันที่รายงาน', 'ผู้รายงาน', ...CONFIG.FIELDS.map(f => f.label),
    'งาน', 'จำนวนรูป', 'PDF', 'Google Doc']);
  sheet.setFrozenRows(1);
  props.setProperty('SHEET_ID', ss.getId());
  return sheet;
}

// ===== วันที่ =====

function today_() {
  return Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyy-MM-dd');
}

function thaiDate_(isoDate) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return `${d} ${THAI_MONTHS[m - 1]} ${y + 543}`;
}

// ===== รันครั้งแรกจากหน้า Editor เพื่อขอสิทธิ์และสร้างโฟลเดอร์/ชีต =====

function setup() {
  token_();
  const folder = getRootFolder_();
  const sheet = getSheet_();
  UrlFetchApp.fetch('https://api.line.me/v2/bot/info', {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  console.log('โฟลเดอร์: ' + folder.getUrl());
  console.log('ชีตบันทึก: ' + sheet.getParent().getUrl());
  console.log('พร้อมใช้งาน ✅ ต่อไปให้ Deploy เป็น Web app');
}

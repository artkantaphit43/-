/**
 * Punch List LINE Bot — เวอร์ชัน Google Apps Script
 *
 * ส่งรูป + พิมพ์รายละเอียดในกลุ่มไลน์ → บอทบันทึกลง Google Sheet (1 กลุ่ม = 1 ไฟล์)
 * รูปเก็บใน Google Drive, มี Sheet ภาพรวมทุกโครงการ, สรุป PDF ทุกวันจันทร์
 *
 * วิธีติดตั้ง: ดู apps-script/README.md
 */

/********** ตั้งค่า (แก้แค่ตรงนี้) **********/
const LINE_TOKEN = 'ใส่ Channel access token ตรงนี้';
const WEEKLY_REPORT = true;   // วันจันทร์ 07:00 บันทึก PDF + ส่งสรุปเข้ากลุ่ม
const SHARE_WITH_LINK = true; // คนที่มีลิงก์เปิดดู Sheet / รูป / PDF ได้ (ไม่ต้องมีบัญชี Google)
const ROOT_FOLDER_NAME = 'Punch List';
const TZ = 'Asia/Bangkok';
/*******************************************/

const LINE_API = 'https://api.line.me/v2/bot';
const LINE_DATA_API = 'https://api-data.line.me/v2/bot';
const PENDING_TTL_MS = 30 * 60 * 1000;

// คอลัมน์ในชีตโครงการ (แถว 1 = หัวรายงาน, แถว 2 = หัวตาราง, ข้อมูลเริ่มแถว 3)
const HEADERS = ['#', 'รูป', 'ตำแหน่ง', 'รายละเอียด', 'ผู้รับผิดชอบ', 'ความสำคัญ', 'สถานะ',
  'ผู้แจ้ง', 'วันที่แจ้ง', 'วันที่ปิด', 'ความคิดเห็น / ประวัติ', 'รูปทั้งหมด', 'photoIds'];
const C = { no: 1, thumb: 2, loc: 3, desc: 4, who: 5, pri: 6, status: 7, reporter: 8,
  created: 9, closed: 10, notes: 11, links: 12, ids: 13 };
const FIRST_ROW = 3;
const ST_OPEN = 'ค้าง';
const ST_DONE = 'เสร็จแล้ว';

// ชีตภาพรวม (Sheet ที่ใส่โค้ดนี้)
const INDEX_HEADERS = ['โครงการ', 'ค้าง', 'เสร็จ', 'ทั้งหมด', 'อัปเดตล่าสุด', 'Google Sheet', 'โฟลเดอร์รูป / PDF', 'chatId'];

const HELP = `📋 วิธีใช้ Punch List Bot

➊ ส่งรูปหน้างาน (กี่รูปก็ได้)
➋ พิมพ์รายละเอียดตามหลังรูป
   ตำแหน่ง / รายละเอียด @ผู้รับผิดชอบ ด่วน
   เช่น: ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน
→ บอทบันทึกลง Google Sheet พร้อมเลขที่ให้

ไม่มีรูป: ขึ้นต้นด้วย + เช่น "+ ห้องน้ำ 2 / ยาแนวหลุด"

คำสั่ง
• รายการ — ดูงานค้าง
• ทั้งหมด — ดูทุกรายการ
• ลิงก์ — ลิงก์ Google Sheet ของโครงการนี้
• รายงาน — ทำ PDF ตอนนี้เลย
• เสร็จ 3 — ปิดรายการ #3 (ส่งรูปก่อนได้ = รูปหลังแก้)
• เปิด 3 — เปิดรายการ #3 ใหม่
• #3 ข้อความ — เพิ่มความคิดเห็นในรายการ #3
• ลบ 3 — ลบรายการ #3
• ตั้งชื่อ ชื่อโครงการ — เปลี่ยนชื่อโครงการ
• ยกเลิก — ล้างรูปที่ส่งค้างไว้`;

/* ========================= Web app ========================= */

// เปิด URL ของ web app ในเบราว์เซอร์ → ได้ Webhook URL ไปใส่ใน LINE
function doGet() {
  ensureSetup();
  const p = PropertiesService.getScriptProperties();
  const url = ScriptApp.getService().getUrl();
  const indexUrl = SpreadsheetApp.openById(p.getProperty('INDEX_ID')).getUrl();
  let body;
  if (p.getProperty('CONNECTED')) {
    body = `<h2>✅ บอทเชื่อมกับ LINE แล้ว</h2>
      <p>ภาพรวมทุกโครงการ: <a href="${indexUrl}" target="_blank">เปิด Sheet ภาพรวม</a></p>`;
  } else {
    const hook = `${url}?key=${p.getProperty('KEY')}`;
    body = `<h2>ขั้นสุดท้าย: คัดลอก Webhook URL นี้ไปใส่ใน LINE</h2>
      <textarea readonly onclick="this.select()" style="width:100%;height:90px;font-size:14px">${hook}</textarea>
      <ol>
        <li>LINE Developers Console → channel ของบอท → แท็บ <b>Messaging API</b></li>
        <li><b>Webhook URL</b> → Edit → วาง → Update</li>
        <li>เปิด <b>Use webhook</b></li>
        <li>เชิญบอทเข้ากลุ่มไลน์หน้างาน แล้วพิมพ์ <b>วิธีใช้</b></li>
      </ol>
      <p style="color:#888">หน้านี้จะแสดง URL แค่จนกว่าบอทจะได้รับข้อความแรกจากไลน์</p>`;
  }
  return HtmlService.createHtmlOutput(
    `<meta name="viewport" content="width=device-width,initial-scale=1">
     <div style="font-family:sans-serif;max-width:640px;margin:24px auto;padding:0 16px">${body}</div>`
  ).setTitle('Punch List Bot');
}

function doPost(e) {
  const p = PropertiesService.getScriptProperties();
  if (!e || !e.parameter || !p.getProperty('KEY') || e.parameter.key !== p.getProperty('KEY')) {
    return ContentService.createTextOutput('forbidden');
  }
  if (!p.getProperty('CONNECTED')) p.setProperty('CONNECTED', '1');

  const events = JSON.parse(e.postData.contents).events || [];
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    for (const ev of events) {
      try {
        handleEvent(ev);
      } catch (err) {
        console.error(err && err.stack || err);
      }
    }
  } finally {
    lock.releaseLock();
  }
  return ContentService.createTextOutput('ok');
}

/* ========================= Setup ========================= */

function ensureSetup() {
  const p = PropertiesService.getScriptProperties();
  if (!p.getProperty('KEY')) p.setProperty('KEY', Utilities.getUuid().replace(/-/g, ''));

  if (!p.getProperty('INDEX_ID')) {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) throw new Error('ต้องสร้างโค้ดจากเมนู ส่วนขยาย → Apps Script ในไฟล์ Google Sheet');
    ss.setSpreadsheetTimeZone(TZ);
    const sh = ss.getSheets()[0];
    sh.setName('ภาพรวมโครงการ');
    sh.getRange(1, 1, 1, INDEX_HEADERS.length).setValues([INDEX_HEADERS])
      .setFontWeight('bold').setBackground('#eef2f7');
    sh.setFrozenRows(1);
    sh.setColumnWidth(1, 220);
    sh.hideColumns(INDEX_HEADERS.length);
    p.setProperty('INDEX_ID', ss.getId());
  }

  if (!p.getProperty('ROOT_ID')) {
    p.setProperty('ROOT_ID', DriveApp.createFolder(ROOT_FOLDER_NAME).getId());
  }

  if (WEEKLY_REPORT && !ScriptApp.getProjectTriggers().some((t) => t.getHandlerFunction() === 'weeklyReport')) {
    ScriptApp.newTrigger('weeklyReport').timeBased()
      .onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(7).inTimezone(TZ).create();
  }
}

/* ========================= Parser ========================= */

const COMMANDS = [
  { type: 'help', re: /^(help|วิธีใช้|ช่วยด้วย|\?)$/i },
  { type: 'list', re: /^(list|รายการ|ค้าง|งานค้าง)$/i },
  { type: 'listAll', re: /^(list all|ทั้งหมด|รายการทั้งหมด)$/i },
  { type: 'link', re: /^(link|ลิงก์|ลิงค์|sheet|ชีท)$/i },
  { type: 'report', re: /^(report|รายงาน|สรุป|pdf)$/i },
  { type: 'cancel', re: /^(ยกเลิก|cancel)$/i },
  { type: 'done', re: /^(ปิด|เสร็จ|done|close)\s*#?(\d+)\s*([\s\S]*)$/i },
  { type: 'reopen', re: /^(เปิด|เปิดใหม่|reopen)\s*#?(\d+)\s*([\s\S]*)$/i },
  { type: 'delete', re: /^(ลบ|delete)\s*#?(\d+)$/i },
  { type: 'note', re: /^#(\d+)\s+([\s\S]+)$/ },
  { type: 'setTitle', re: /^(ตั้งชื่อ|ชื่อโครงการ|project)\s+([\s\S]+)$/i },
];
const HIGH_PRIORITY = /(^|\s)(ด่วน(มาก)?|urgent|!!)(?=\s|$)/i;
const ITEM_PREFIX = /^(\+|punch\b|แจ้ง\b)\s*/i;

function parseCommand(text) {
  const t = String(text || '').trim();
  for (const { type, re } of COMMANDS) {
    const m = t.match(re);
    if (!m) continue;
    if (type === 'done' || type === 'reopen') return { type, no: Number(m[2]), note: m[3].trim() };
    if (type === 'delete') return { type, no: Number(m[2]) };
    if (type === 'note') return { type, no: Number(m[1]), note: m[2].trim() };
    if (type === 'setTitle') return { type, title: m[2].trim() };
    return { type };
  }
  return null;
}

function hasItemPrefix(text) {
  return ITEM_PREFIX.test(String(text || '').trim());
}

// "ตำแหน่ง / รายละเอียด @ผู้รับผิดชอบ ด่วน"
function parseItem(text) {
  let t = String(text || '').trim().replace(ITEM_PREFIX, '');
  let priority = 'ปกติ';
  if (HIGH_PRIORITY.test(t)) {
    priority = 'ด่วน';
    t = t.replace(HIGH_PRIORITY, ' ');
  }
  const assignees = [];
  t = t.replace(/(^|\s)@([^\s@]+)/g, (_, pre, name) => {
    assignees.push(name);
    return pre;
  });
  let location = '';
  // "/" ต้องมีเว้นวรรครอบ เพื่อไม่ให้ตัด "ท่อ 1/2 นิ้ว"; "|" ไม่ต้อง
  const sep = t.match(/\s+\/\s+|\s*\|\s*/);
  if (sep && sep.index > 0 && t.slice(sep.index + sep[0].length).trim()) {
    location = t.slice(0, sep.index);
    t = t.slice(sep.index + sep[0].length);
  }
  const clean = (s) => s.split('\n').map((l) => l.replace(/[ \t]+/g, ' ').trim()).filter(Boolean).join('\n');
  return { location: clean(location), description: clean(t), assignee: assignees.join(', '), priority };
}

/* ========================= LINE API ========================= */

function lineFetch(url, options) {
  const res = UrlFetchApp.fetch(url, Object.assign({
    headers: { Authorization: 'Bearer ' + LINE_TOKEN },
    muteHttpExceptions: true,
  }, options || {}));
  if (res.getResponseCode() >= 300) {
    console.error(`LINE ${res.getResponseCode()} ${url}: ${res.getContentText()}`);
    return null;
  }
  return res;
}

function lineSend(path, body) {
  return lineFetch(`${LINE_API}/message/${path}`, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(body),
  });
}

function reply(replyToken, messages) {
  if (replyToken && messages && messages.length) lineSend('reply', { replyToken, messages: messages.slice(0, 5) });
}

function push(to, messages) {
  lineSend('push', { to, messages: messages.slice(0, 5) });
}

function lineJson(url) {
  const res = lineFetch(url);
  try {
    return res ? JSON.parse(res.getContentText()) : {};
  } catch (err) {
    return {};
  }
}

function displayName(source) {
  if (!source.userId) return '';
  const url = source.type === 'group' ? `${LINE_API}/group/${source.groupId}/member/${source.userId}`
    : source.type === 'room' ? `${LINE_API}/room/${source.roomId}/member/${source.userId}`
      : `${LINE_API}/profile/${source.userId}`;
  return lineJson(url).displayName || '';
}

function chatName(source) {
  if (source.type === 'group') return lineJson(`${LINE_API}/group/${source.groupId}/summary`).groupName || '';
  if (source.type === 'user') return displayName(source);
  return '';
}

/* ========================= โครงการ (1 แชท = 1 ไฟล์) ========================= */

function chatIdOf(source) {
  return source.groupId || source.roomId || source.userId;
}

function getJson(key) {
  const v = PropertiesService.getScriptProperties().getProperty(key);
  return v ? JSON.parse(v) : null;
}

function setJson(key, value) {
  PropertiesService.getScriptProperties().setProperty(key, JSON.stringify(value));
}

function now() {
  return new Date();
}

function fmtDate(d) {
  return d ? Utilities.formatDate(new Date(d), TZ, 'd/M/yy HH:mm') : '';
}

function safeName(s) {
  return String(s || '').replace(/[\\/:*?"<>|\[\]]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80);
}

function getProject(chatId, source) {
  const saved = getJson('chat:' + chatId);
  if (saved) return saved;
  return createProject(chatId, source);
}

function createProject(chatId, source) {
  ensureSetup();
  const p = PropertiesService.getScriptProperties();
  const title = safeName(chatName(source)) || 'โครงการ ' + Utilities.formatDate(now(), TZ, 'd-M-yy HHmm');

  const folder = DriveApp.getFolderById(p.getProperty('ROOT_ID')).createFolder(title);
  const photoFolder = folder.createFolder('รูป');
  const pdfFolder = folder.createFolder('รายงาน PDF');

  const ss = SpreadsheetApp.create('Punch List - ' + title);
  ss.setSpreadsheetTimeZone(TZ);
  DriveApp.getFileById(ss.getId()).moveTo(folder);
  formatProjectSheet(ss.getSheets()[0], title);

  if (SHARE_WITH_LINK) {
    for (const f of [DriveApp.getFileById(ss.getId()), folder]) {
      f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    }
  }

  const project = {
    chatId, title, seq: 0,
    sheetId: ss.getId(), sheetUrl: ss.getUrl(),
    folderId: folder.getId(), folderUrl: folder.getUrl(),
    photoFolderId: photoFolder.getId(), pdfFolderId: pdfFolder.getId(),
  };
  setJson('chat:' + chatId, project);
  updateIndex(project);
  return project;
}

function formatProjectSheet(sh, title) {
  sh.setName('Punch List');
  sh.getRange(1, 1).setValue('Punch List — ' + title).setFontSize(14).setFontWeight('bold');
  sh.getRange(1, C.desc).setFormula(
    `="ค้าง "&COUNTIF(G${FIRST_ROW}:G,"${ST_OPEN}")&"   เสร็จ "&COUNTIF(G${FIRST_ROW}:G,"${ST_DONE}")&"   ทั้งหมด "&COUNT(A${FIRST_ROW}:A)`
  ).setFontWeight('bold');
  sh.getRange(2, 1, 1, HEADERS.length).setValues([HEADERS])
    .setFontWeight('bold').setBackground('#eef2f7').setVerticalAlignment('middle');
  sh.setFrozenRows(2);
  const widths = { [C.no]: 40, [C.thumb]: 130, [C.loc]: 120, [C.desc]: 260, [C.who]: 110, [C.pri]: 80,
    [C.status]: 85, [C.reporter]: 100, [C.created]: 105, [C.closed]: 105, [C.notes]: 300, [C.links]: 110 };
  for (const col in widths) sh.setColumnWidth(Number(col), widths[col]);
  sh.hideColumns(C.ids);
  sh.getRange(`A${FIRST_ROW}:M`).setVerticalAlignment('top').setWrap(true);
  sh.getRange(`I${FIRST_ROW}:J`).setNumberFormat('d/m/yy HH:mm');

  const status = sh.getRange(`G${FIRST_ROW}:G`);
  const pri = sh.getRange(`F${FIRST_ROW}:F`);
  sh.setConditionalFormatRules([
    SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo(ST_OPEN)
      .setBackground('#fff1e6').setFontColor('#c2410c').setRanges([status]).build(),
    SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo(ST_DONE)
      .setBackground('#e7f7ee').setFontColor('#15803d').setRanges([status]).build(),
    SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('ด่วน')
      .setFontColor('#b91c1c').setBold(true).setRanges([pri]).build(),
  ]);
}

function projectSheet(project) {
  return SpreadsheetApp.openById(project.sheetId).getSheets()[0];
}

function readItems(sh) {
  const n = sh.getLastRow() - FIRST_ROW + 1;
  if (n <= 0) return [];
  return sh.getRange(FIRST_ROW, 1, n, HEADERS.length).getValues()
    .map((r, i) => ({
      row: FIRST_ROW + i,
      no: Number(r[C.no - 1]),
      location: r[C.loc - 1],
      description: r[C.desc - 1],
      assignee: r[C.who - 1],
      priority: r[C.pri - 1],
      status: r[C.status - 1],
      reporter: r[C.reporter - 1],
      notes: r[C.notes - 1],
      photoIds: String(r[C.ids - 1] || '').split(',').filter(Boolean),
    }))
    .filter((i) => i.no);
}

function findItem(sh, no) {
  return readItems(sh).find((i) => i.no === no) || null;
}

function thumbFormula(fileId) {
  return fileId ? `=IMAGE("https://drive.google.com/thumbnail?id=${fileId}&sz=w400")` : '';
}

function setPhotoCells(sh, row, ids) {
  sh.getRange(row, C.ids).setValue(ids.join(','));
  if (!ids.length) return sh.getRange(row, C.links).setValue('');
  const labels = ids.map((_, i) => `รูป ${i + 1}`);
  const text = labels.join('\n');
  const rich = SpreadsheetApp.newRichTextValue().setText(text);
  let pos = 0;
  ids.forEach((id, i) => {
    rich.setLinkUrl(pos, pos + labels[i].length, `https://drive.google.com/file/d/${id}/view`);
    pos += labels[i].length + 1;
  });
  sh.getRange(row, C.links).setRichTextValue(rich.build());
}

function appendNote(sh, item, text, by) {
  const line = `${fmtDate(now())} ${by || ''}: ${text}`.replace(/ :/, ':');
  const notes = item.notes ? item.notes + '\n' + line : line;
  sh.getRange(item.row, C.notes).setValue(notes);
  return notes;
}

function updateIndex(project) {
  const index = SpreadsheetApp.openById(PropertiesService.getScriptProperties().getProperty('INDEX_ID')).getSheets()[0];
  let open = 0;
  let done = 0;
  try {
    for (const i of readItems(projectSheet(project))) i.status === ST_DONE ? done++ : open++;
  } catch (err) {
    console.error(err);
  }
  const values = [[project.title, open, done, open + done, now(),
    project.sheetUrl, project.folderUrl, project.chatId]];
  const last = index.getLastRow();
  const ids = last > 1 ? index.getRange(2, 8, last - 1, 1).getValues().map((r) => r[0]) : [];
  const at = ids.indexOf(project.chatId);
  const row = at >= 0 ? at + 2 : last + 1;
  index.getRange(row, 1, 1, values[0].length).setValues(values);
  index.getRange(row, 5).setNumberFormat('d/m/yy HH:mm');
}

/* ========================= รูปที่รอข้อความ ========================= */

function pendingKey(chatId, userId) {
  return `pend:${chatId}:${userId}`;
}

function pendingPhotos(chatId, userId) {
  const p = getJson(pendingKey(chatId, userId));
  if (!p || now().getTime() - p.at > PENDING_TTL_MS) return [];
  return p.ids;
}

function clearPending(chatId, userId) {
  PropertiesService.getScriptProperties().deleteProperty(pendingKey(chatId, userId));
}

/* ========================= Handlers ========================= */

function handleEvent(ev) {
  if (!ev.source) return;
  let messages = null;
  if (ev.type === 'message' && ev.message.type === 'image') messages = onImage(ev);
  else if (ev.type === 'message' && ev.message.type === 'text') messages = onText(ev);
  else if (ev.type === 'join' || ev.type === 'follow') {
    const project = getProject(chatIdOf(ev.source), ev.source);
    messages = [text(HELP), text(`📊 Google Sheet ของโครงการนี้\n${project.sheetUrl}`)];
  }
  if (messages) reply(ev.replyToken, messages);
}

function text(t) {
  return { type: 'text', text: t };
}

function onImage(ev) {
  const chatId = chatIdOf(ev.source);
  const userId = ev.source.userId || 'unknown';
  const project = getProject(chatId, ev.source);

  const res = lineFetch(`${LINE_DATA_API}/message/${ev.message.id}/content`);
  if (!res) return [text('ดาวน์โหลดรูปไม่สำเร็จ ลองส่งใหม่อีกครั้ง')];
  const blob = res.getBlob().setName(`${Utilities.formatDate(now(), TZ, 'yyMMdd-HHmmss')}-${ev.message.id}.jpg`);
  const file = DriveApp.getFolderById(project.photoFolderId).createFile(blob);
  if (SHARE_WITH_LINK) file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);

  const ids = pendingPhotos(chatId, userId).concat(file.getId());
  setJson(pendingKey(chatId, userId), { ids, at: now().getTime() });

  // ส่งหลายรูปพร้อมกัน ไลน์ส่ง imageSet มา → ตอบครั้งเดียวที่รูปแรก
  const set = ev.message.imageSet;
  const first = set ? set.index === 1 : ids.length === 1;
  return first ? [text('📷 รับรูปแล้ว พิมพ์รายละเอียดต่อได้เลย\nเช่น: ห้อง 301 / สีผนังไม่เรียบ @ทีมสี')] : null;
}

function onText(ev) {
  const chatId = chatIdOf(ev.source);
  const userId = ev.source.userId || 'unknown';
  const msg = ev.message.text;
  const cmd = parseCommand(msg);

  if (cmd && cmd.type === 'help') return [text(HELP)];

  if (!cmd) {
    // ข้อความทั่วไปในกลุ่ม: สร้างรายการเมื่อมีรูปค้างอยู่ หรือขึ้นต้นด้วย "+" เท่านั้น
    const photos = pendingPhotos(chatId, userId);
    if (!photos.length && !hasItemPrefix(msg)) return null;
    const fields = parseItem(msg);
    if (!fields.description) return [text('กรุณาพิมพ์รายละเอียดด้วย เช่น: ห้อง 301 / สีผนังไม่เรียบ')];
    const project = getProject(chatId, ev.source);
    const item = addItem(project, fields, photos, displayName(ev.source));
    clearPending(chatId, userId);
    return [itemBubble(item, project, '🆕 บันทึกแล้ว')];
  }

  const project = getProject(chatId, ev.source);
  const sh = projectSheet(project);

  switch (cmd.type) {
    case 'list':
    case 'listAll': {
      const all = readItems(sh);
      const items = cmd.type === 'list' ? all.filter((i) => i.status !== ST_DONE) : all;
      return [listBubble(`${project.title} — ${cmd.type === 'list' ? 'งานค้าง' : 'ทั้งหมด'}`, items, all, project)];
    }

    case 'link':
      return [text(`📊 Google Sheet: ${project.title}\n${project.sheetUrl}\n\n📁 รูป + PDF\n${project.folderUrl}`)];

    case 'report': {
      const pdf = exportPdf(project);
      return [text(`📄 PDF ${project.title}\n${pdf.getUrl()}\n\n📊 Sheet ล่าสุด\n${project.sheetUrl}`)];
    }

    case 'cancel': {
      const n = pendingPhotos(chatId, userId).length;
      clearPending(chatId, userId);
      return [text(n ? `ล้างรูปที่ค้างไว้ ${n} รูปแล้ว` : 'ไม่มีรูปค้างอยู่')];
    }

    case 'done':
    case 'reopen': {
      const item = findItem(sh, cmd.no);
      if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
      const done = cmd.type === 'done';
      item.status = done ? ST_DONE : ST_OPEN;
      sh.getRange(item.row, C.status).setValue(item.status);
      sh.getRange(item.row, C.closed).setValue(done ? now() : '');
      const label = done ? 'ปิดงาน' : 'เปิดใหม่';
      item.notes = appendNote(sh, item, cmd.note ? `${label} — ${cmd.note}` : label, displayName(ev.source));
      // รูปที่ส่งก่อนพิมพ์ "เสร็จ N" = รูปหลังแก้
      const after = done ? pendingPhotos(chatId, userId) : [];
      if (after.length) {
        item.photoIds = item.photoIds.concat(after);
        setPhotoCells(sh, item.row, item.photoIds);
        clearPending(chatId, userId);
      }
      updateIndex(project);
      return [itemBubble(item, project, done ? '✅ ปิดงานแล้ว' : '↩️ เปิดใหม่')];
    }

    case 'delete': {
      const item = findItem(sh, cmd.no);
      if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
      sh.deleteRow(item.row);
      for (const id of item.photoIds) {
        try {
          DriveApp.getFileById(id).setTrashed(true);
        } catch (err) {
          console.error(err);
        }
      }
      updateIndex(project);
      return [text(`🗑 ลบรายการ #${cmd.no} แล้ว`)];
    }

    case 'note': {
      const item = findItem(sh, cmd.no);
      if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
      appendNote(sh, item, cmd.note, displayName(ev.source));
      return [text(`📝 เพิ่มความคิดเห็นใน #${cmd.no} แล้ว`)];
    }

    case 'setTitle': {
      const title = safeName(cmd.title);
      if (!title) return [text('กรุณาพิมพ์ชื่อโครงการด้วย')];
      project.title = title;
      setJson('chat:' + chatId, project);
      SpreadsheetApp.openById(project.sheetId).rename('Punch List - ' + title);
      sh.getRange(1, 1).setValue('Punch List — ' + title);
      DriveApp.getFolderById(project.folderId).setName(title);
      updateIndex(project);
      return [text(`ตั้งชื่อโครงการเป็น "${title}" แล้ว`)];
    }
  }
  return null;
}

function addItem(project, fields, photoIds, reporter) {
  const sh = projectSheet(project);
  project.seq = Math.max(project.seq || 0, ...readItems(sh).map((i) => i.no)) + 1;
  setJson('chat:' + project.chatId, project);

  const created = now();
  sh.appendRow([project.seq, thumbFormula(photoIds[0]), fields.location, fields.description, fields.assignee,
    fields.priority, ST_OPEN, reporter, created, '', '', '', '']);
  const row = sh.getLastRow();
  setPhotoCells(sh, row, photoIds);
  if (photoIds.length) sh.setRowHeight(row, 100);
  updateIndex(project);

  return { row, no: project.seq, ...fields, status: ST_OPEN, reporter, photoIds, notes: '' };
}

/* ========================= PDF + สรุปรายสัปดาห์ ========================= */

function exportPdf(project) {
  const ss = SpreadsheetApp.openById(project.sheetId);
  const gid = ss.getSheets()[0].getSheetId();
  const url = `https://docs.google.com/spreadsheets/d/${project.sheetId}/export?format=pdf&gid=${gid}` +
    '&size=A4&portrait=false&fitw=true&gridlines=true&sheetnames=false&printtitle=false&pagenum=CENTER' +
    '&top_margin=0.4&bottom_margin=0.4&left_margin=0.4&right_margin=0.4';
  const blob = UrlFetchApp.fetch(url, { headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() } })
    .getBlob().setName(`${project.title} ${Utilities.formatDate(now(), TZ, 'yyyy-MM-dd HHmm')}.pdf`);
  const file = DriveApp.getFolderById(project.pdfFolderId).createFile(blob);
  if (SHARE_WITH_LINK) file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return file;
}

// ทำงานเองทุกวันจันทร์ 07:00 (ตั้งโดย ensureSetup)
function weeklyReport() {
  const all = PropertiesService.getScriptProperties().getProperties();
  for (const key in all) {
    if (key.indexOf('chat:') !== 0) continue;
    const project = JSON.parse(all[key]);
    try {
      const items = readItems(projectSheet(project));
      if (!items.length) continue;
      const open = items.filter((i) => i.status !== ST_DONE).length;
      const pdf = exportPdf(project);
      updateIndex(project);
      push(project.chatId, [text(
        `📅 สรุปประจำสัปดาห์: ${project.title}\nค้าง ${open} · เสร็จ ${items.length - open} · ทั้งหมด ${items.length}\n\n📄 PDF\n${pdf.getUrl()}\n\n📊 Sheet ล่าสุด\n${project.sheetUrl}`
      )]);
    } catch (err) {
      console.error(key, err);
    }
  }
}

/* ========================= Flex Message ========================= */

const COLORS = { open: '#E0752D', done: '#2E9E5B', high: '#D93025', muted: '#8A8F98', text: '#1F2328' };

function trunc(s, n) {
  s = String(s || '');
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function flexRow(label, value, color) {
  return {
    type: 'box', layout: 'baseline', spacing: 'sm',
    contents: [
      { type: 'text', text: label, size: 'sm', color: COLORS.muted, flex: 2 },
      { type: 'text', text: String(value || '-'), size: 'sm', color: color || COLORS.text, flex: 5, wrap: true },
    ],
  };
}

function sheetButton(project, style) {
  return {
    type: 'box', layout: 'vertical',
    contents: [{ type: 'button', style, height: 'sm', action: { type: 'uri', label: 'เปิด Google Sheet', uri: project.sheetUrl } }],
  };
}

function itemBubble(item, project, heading) {
  const done = item.status === ST_DONE;
  return {
    type: 'flex',
    altText: `Punch #${item.no}: ${trunc(item.description, 80)}`,
    contents: {
      type: 'bubble',
      body: {
        type: 'box', layout: 'vertical', spacing: 'md',
        contents: [
          {
            type: 'box', layout: 'horizontal',
            contents: [
              { type: 'text', text: heading, size: 'xs', color: COLORS.muted, weight: 'bold' },
              { type: 'text', text: item.status, size: 'xs', weight: 'bold', align: 'end', color: done ? COLORS.done : COLORS.open },
            ],
          },
          { type: 'text', text: `#${item.no} ${trunc(item.description, 120)}`, weight: 'bold', size: 'lg', wrap: true },
          {
            type: 'box', layout: 'vertical', spacing: 'xs',
            contents: [
              flexRow('ตำแหน่ง', item.location),
              flexRow('ผู้รับผิดชอบ', item.assignee),
              flexRow('ความสำคัญ', item.priority, item.priority === 'ด่วน' ? COLORS.high : undefined),
              flexRow('รูป', `${item.photoIds.length} รูป`),
              flexRow('ผู้แจ้ง', item.reporter),
            ],
          },
        ],
      },
      footer: sheetButton(project, 'link'),
    },
  };
}

function listBubble(title, items, all, project) {
  const MAX = 25;
  const open = all.filter((i) => i.status !== ST_DONE).length;
  const rows = items.slice(0, MAX).map((i) => {
    const done = i.status === ST_DONE;
    return {
      type: 'box', layout: 'horizontal', spacing: 'sm',
      contents: [
        { type: 'text', text: `#${i.no}`, size: 'sm', color: COLORS.muted, flex: 1 },
        {
          type: 'text', text: trunc([i.location, i.description].filter(Boolean).join(' · '), 60) || '-',
          size: 'sm', flex: 6, wrap: true, color: done ? COLORS.muted : COLORS.text,
          decoration: done ? 'line-through' : 'none',
        },
        {
          type: 'text', text: done ? '✓' : i.priority === 'ด่วน' ? 'ด่วน' : ' ',
          size: 'xs', flex: 1, align: 'end', color: done ? COLORS.done : COLORS.high,
        },
      ],
    };
  });
  if (items.length > MAX) rows.push({ type: 'text', text: `…และอีก ${items.length - MAX} รายการ`, size: 'xs', color: COLORS.muted });
  if (!rows.length) rows.push({ type: 'text', text: 'ไม่มีรายการ 🎉', size: 'sm', color: COLORS.muted });

  return {
    type: 'flex',
    altText: `${title}: ค้าง ${open} รายการ`,
    contents: {
      type: 'bubble', size: 'giga',
      body: {
        type: 'box', layout: 'vertical', spacing: 'md',
        contents: [
          { type: 'text', text: trunc(title, 60), weight: 'bold', size: 'lg', wrap: true },
          { type: 'text', text: `ค้าง ${open} · เสร็จ ${all.length - open} · ทั้งหมด ${all.length}`, size: 'sm', color: COLORS.muted },
          { type: 'separator' },
          { type: 'box', layout: 'vertical', spacing: 'sm', contents: rows },
        ],
      },
      footer: sheetButton(project, 'primary'),
    },
  };
}

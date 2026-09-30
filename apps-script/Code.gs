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

// ชีตโครงการ: แถว 1 = ชื่อรายงาน, แถว 2 = สรุปจำนวน, แถว 3 = หัวตาราง, ข้อมูลเริ่มแถว 4
// หัวข้อตามฟอร์มบริษัท: ลำดับ, รายการแก้ไข, กำหนดวันเริ่ม, กำหนดแล้วเสร็จ, สถานะ, หมายเหตุ
// + ที่เพิ่ม: โปรเจค (หลายโปรเจคในพื้นที่เดียวกัน เช่น ท่อประปา / ท่อน้ำเย็น), รูปก่อน/หลังแก้ไข (หลักฐาน),
//   พื้นที่ (หาจุดเจอ), ผู้รับผิดชอบ, วันที่เสร็จจริง (เทียบกับแผน), ผู้แจ้ง
const HEADERS = ['ลำดับ', 'โปรเจค', 'รูปก่อนแก้ไข', 'พื้นที่ / ตำแหน่ง', 'รายการแก้ไข', 'ผู้รับผิดชอบ',
  'กำหนดวันเริ่ม', 'กำหนดแล้วเสร็จ', 'สถานะ', 'รูปหลังแก้ไข', 'วันที่แล้วเสร็จจริง', 'หมายเหตุ',
  'ผู้แจ้ง / วันที่แจ้ง', 'ลิงก์รูปทั้งหมด', 'beforeIds', 'afterIds'];
const C = { no: 1, work: 2, before: 3, loc: 4, desc: 5, who: 6, start: 7, due: 8, status: 9, after: 10,
  closed: 11, notes: 12, reporter: 13, links: 14, beforeIds: 15, afterIds: 16 };
const LAST_VISIBLE = C.links;
const STAMP_COL = C.after; // "สถานะ ณ วันที่" ใน PDF (แถว 2 ด้านขวา)
const colL = (c) => String.fromCharCode(64 + c); // 1 → A

// แท็บรายชื่อโปรเจค: ผู้ใช้พิมพ์ชื่อเอง (คอลัมน์ A) + คำย่อ (B), คอลัมน์ C–F นับให้อัตโนมัติ
const WORKS_SHEET = 'รายชื่อโปรเจค';
const WORKS_HEADERS = ['ชื่อโปรเจค (พิมพ์เพิ่มได้เลย)', 'คำย่อ (ไม่บังคับ)', 'ทั้งหมด', 'ค้าง', 'เสร็จแล้ว', 'เลยกำหนด'];
const WORKS_EXAMPLES = ['ท่อประปา', 'ท่อน้ำเย็น', 'ท่อสตีม'];
const WORKS_ROWS = 50;
const TITLE_ROW = 1;
const SUMMARY_ROW = 2;
const HEADER_ROW = 3;
const FIRST_ROW = 4;
const ST_WAIT = 'รอดำเนินการ';
const ST_WIP = 'กำลังแก้ไข';
const ST_DONE = 'เสร็จแล้ว';
const URGENT_TAG = '[ด่วน] ';
const THEME = { header: '#d9ead3', title: '#274e13', band: '#f6faf4', border: '#c9d6c3' };

// ชีตภาพรวม (Sheet ที่ใส่โค้ดนี้)
const INDEX_HEADERS = ['โครงการ', 'ค้าง', 'เสร็จ', 'ทั้งหมด', 'อัปเดตล่าสุด', 'Google Sheet', 'โฟลเดอร์รูป / PDF', 'chatId'];

const HELP = `📋 วิธีใช้ Punch List Bot

➊ ส่งรูปหน้างาน (กี่รูปก็ได้)
➋ พิมพ์รายละเอียดตามหลังรูป
   พื้นที่ / รายการแก้ไข @ผู้รับผิดชอบ เริ่ม วันที่ ภายใน วันที่
   เช่น: ห้อง 301 / สีผนังไม่เรียบ @ทีมสี เริ่ม 5/10 ภายใน 12/10
   (ใส่แค่บางส่วนก็ได้, พิมพ์ "ด่วน" ถ้าเร่ง)
→ บอทบันทึกลง Google Sheet พร้อมลำดับให้

โปรเจค (เช่น ท่อประปา / ท่อน้ำเย็น)
• ใส่ชื่อหรือคำย่อในข้อความ: ท่อประปา ห้อง 301 / รั่วซึม
• หรือตั้งไว้ครั้งเดียว: โปรเจค ท่อประปา (รายการต่อไปเข้าโปรเจคนี้เอง)
• โปรเจค — ดูรายชื่อ + จำนวนค้าง
• เพิ่มโปรเจค ท่อลม — เพิ่มชื่อใหม่

ไม่มีรูป: ขึ้นต้นด้วย + เช่น "+ ห้องน้ำ 2 / ยาแนวหลุด"

คำสั่ง
• รายการ — ดูงานค้าง (รายการ ท่อประปา = เฉพาะโปรเจค)
• ทั้งหมด — ดูทุกรายการ
• ลิงก์ — ลิงก์ Google Sheet ของโครงการนี้
• รายงาน — ทำ PDF ตอนนี้เลย
• เริ่ม 3 — รายการ #3 กำลังแก้ไข
• เสร็จ 3 — ปิดรายการ #3 (ส่งรูปก่อน = รูปหลังแก้ไข)
• เปิด 3 — เปิดรายการ #3 ใหม่
• #3 ข้อความ — เพิ่มหมายเหตุในรายการ #3
• #3 เริ่ม 5/10 ภายใน 12/10 — แก้กำหนดวัน
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
  { type: 'listAll', re: /^(list all|ทั้งหมด|รายการทั้งหมด)(?:\s+([\s\S]+))?$/i },
  { type: 'list', re: /^(list|รายการ|ค้าง|งานค้าง)(?:\s+([\s\S]+))?$/i },
  { type: 'addWork', re: /^(เพิ่มโปรเจค|เพิ่มโปรเจ็ค|add project)\s+([\s\S]+)$/i },
  { type: 'work', re: /^(โปรเจค|โปรเจ็ค|project)(?:\s+([\s\S]+))?$/i },
  { type: 'link', re: /^(link|ลิงก์|ลิงค์|sheet|ชีท)$/i },
  { type: 'report', re: /^(report|รายงาน|สรุป|pdf)$/i },
  { type: 'cancel', re: /^(ยกเลิก|cancel)$/i },
  { type: 'start', re: /^(เริ่ม|เริ่มงาน|start)\s*#?(\d+)$/i },
  { type: 'done', re: /^(ปิด|เสร็จ|done|close)\s*#?(\d+)\s*([\s\S]*)$/i },
  { type: 'reopen', re: /^(เปิด|เปิดใหม่|reopen)\s*#?(\d+)\s*([\s\S]*)$/i },
  { type: 'delete', re: /^(ลบ|delete)\s*#?(\d+)$/i },
  { type: 'note', re: /^#(\d+)\s+([\s\S]+)$/ },
  { type: 'setTitle', re: /^(ตั้งชื่อ|ชื่อโครงการ)\s+([\s\S]+)$/i },
];
const HIGH_PRIORITY = /(^|\s)(ด่วน(มาก)?|urgent|!!)(?=\s|$)/i;
const ITEM_PREFIX = /^(\+|punch\b|แจ้ง\b)\s*/i;

function parseCommand(text) {
  const t = String(text || '').trim();
  for (const { type, re } of COMMANDS) {
    const m = t.match(re);
    if (!m) continue;
    if (type === 'done' || type === 'reopen') return { type, no: Number(m[2]), note: m[3].trim() };
    if (type === 'delete' || type === 'start') return { type, no: Number(m[2]) };
    if (type === 'note') return { type, no: Number(m[1]), note: m[2].trim() };
    if (type === 'setTitle') return { type, title: m[2].trim() };
    if (type === 'list' || type === 'listAll' || type === 'work' || type === 'addWork') {
      return { type, arg: (m[2] || '').trim() };
    }
    return { type };
  }
  return null;
}

function hasItemPrefix(text) {
  return ITEM_PREFIX.test(String(text || '').trim());
}

// วันที่แบบไทย: 5/10, 5/10/26, 5/10/69 (พ.ศ.), 5/10/2026, 5/10/2569
const DATE = '(\\d{1,2})[/.-](\\d{1,2})(?:[/.-](\\d{2,4}))?';
const START_RE = new RegExp(`(^|\\s)(?:เริ่ม|เริ่มงาน|start)\\s*${DATE}(?=\\s|$)`, 'i');
const DUE_RE = new RegExp(`(^|\\s)(?:ภายใน|เสร็จภายใน|กำหนดเสร็จ|ถึง|due)\\s*${DATE}(?=\\s|$)`, 'i');

function toDate(d, m, y) {
  let year = y ? Number(y) : Number(Utilities.formatDate(now(), TZ, 'yyyy'));
  if (y && y.length === 2) year = year >= 50 ? 2500 + year - 543 : 2000 + year; // 69 = พ.ศ. 2569
  if (year > 2400) year -= 543;
  const date = new Date(year, Number(m) - 1, Number(d), 12); // เที่ยงวัน กันวันเลื่อนเพราะ timezone
  return date.getMonth() === Number(m) - 1 && date.getDate() === Number(d) ? date : null;
}

// ดึง "เริ่ม 5/10" และ "ภายใน 12/10" ออกจากข้อความ
function extractDates(text) {
  let t = String(text || '');
  const out = { start: null, due: null };
  for (const [key, re] of [['start', START_RE], ['due', DUE_RE]]) {
    const m = t.match(re);
    if (!m) continue;
    const date = toDate(m[2], m[3], m[4]);
    if (!date) continue;
    out[key] = date;
    t = t.replace(re, '$1');
  }
  out.rest = t;
  return out;
}

// "พื้นที่ / รายการแก้ไข @ผู้รับผิดชอบ เริ่ม 5/10 ภายใน 12/10 ด่วน"
function parseItem(text) {
  const dates = extractDates(String(text || '').trim().replace(ITEM_PREFIX, ''));
  let t = dates.rest;
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
  return {
    location: clean(location), description: clean(t), assignee: assignees.join(', '), priority,
    start: dates.start, due: dates.due,
  };
}

// หาโปรเจคในข้อความ (ชื่อหรือคำย่อ ต้องมีเว้นวรรคคั่น) → { work, rest }
function matchWork(text, works) {
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const tokens = [];
  for (const w of works) {
    tokens.push([w.name, w.name]);
    if (w.abbr) tokens.push([w.abbr, w.name]);
  }
  tokens.sort((a, b) => b[0].length - a[0].length); // ชื่อยาวก่อน กัน "ท่อ" ชน "ท่อประปา"
  for (const [token, name] of tokens) {
    const re = new RegExp(`(^|\\s)${esc(token)}(?=\\s|/|\\||$)`, 'i');
    if (re.test(text)) return { work: name, rest: text.replace(re, '$1') };
  }
  return { work: '', rest: text };
}

function findWork(arg, works) {
  const a = String(arg || '').trim().toLowerCase();
  return works.find((w) => w.name.toLowerCase() === a || (w.abbr && w.abbr.toLowerCase() === a)) || null;
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
  sh.setHiddenGridlines(true);
  sh.hideColumns(C.beforeIds, 2);

  // แถว 1: ชื่อรายงาน
  sh.getRange(TITLE_ROW, 1, 1, LAST_VISIBLE).merge()
    .setValue('PUNCH LIST : ' + title)
    .setFontSize(16).setFontWeight('bold').setFontColor(THEME.title).setVerticalAlignment('middle');
  sh.setRowHeight(TITLE_ROW, 36);

  // แถว 2: สรุปจำนวน (สูตรนับเอง) + ช่องวันที่ของ PDF ทางขวา
  const rng = (col) => `${col}${FIRST_ROW}:${col}`;
  const ST = colL(C.status);
  sh.getRange(SUMMARY_ROW, 1, 1, STAMP_COL - 1).merge().setFormula(
    `="${ST_WAIT} "&COUNTIF(${rng(ST)},"${ST_WAIT}")` +
    `&"   •   ${ST_WIP} "&COUNTIF(${rng(ST)},"${ST_WIP}")` +
    `&"   •   ${ST_DONE} "&COUNTIF(${rng(ST)},"${ST_DONE}")` +
    `&"   •   เลยกำหนด "&COUNTIFS(${rng(colL(C.due))},"<"&TODAY(),${rng(ST)},"<>${ST_DONE}")` +
    `&"   •   ทั้งหมด "&COUNT(${rng('A')})`
  ).setFontColor('#555555');
  sh.getRange(SUMMARY_ROW, STAMP_COL, 1, LAST_VISIBLE - STAMP_COL + 1).merge().setHorizontalAlignment('right').setFontWeight('bold');

  // แถว 3: หัวตาราง (สีเขียวตามฟอร์มเดิม)
  sh.getRange(HEADER_ROW, 1, 1, HEADERS.length).setValues([HEADERS]);
  sh.getRange(HEADER_ROW, 1, 1, LAST_VISIBLE)
    .setFontWeight('bold').setBackground(THEME.header).setHorizontalAlignment('center').setVerticalAlignment('middle')
    .setWrap(true)
    .setBorder(true, true, true, true, true, false, THEME.border, SpreadsheetApp.BorderStyle.SOLID);
  sh.setRowHeight(HEADER_ROW, 40);
  sh.setFrozenRows(HEADER_ROW);

  const widths = { [C.no]: 50, [C.work]: 100, [C.before]: 110, [C.loc]: 120, [C.desc]: 240, [C.who]: 100, [C.start]: 90,
    [C.due]: 90, [C.status]: 100, [C.after]: 110, [C.closed]: 95, [C.notes]: 260, [C.reporter]: 110, [C.links]: 90 };
  for (const col in widths) sh.setColumnWidth(Number(col), widths[col]);

  const col = (c) => sh.getRange(FIRST_ROW, c, sh.getMaxRows() - FIRST_ROW + 1, 1);
  const LAST = colL(LAST_VISIBLE);
  sh.getRange(`A${FIRST_ROW}:${LAST}`).setVerticalAlignment('middle').setWrap(true).setFontSize(10);
  for (const c of [C.no, C.start, C.due, C.status, C.closed]) col(c).setHorizontalAlignment('center');
  for (const c of [C.start, C.due, C.closed]) col(c).setNumberFormat('d/m/yy');
  col(C.status).setDataValidation(SpreadsheetApp.newDataValidation()
    .requireValueInList([ST_WAIT, ST_WIP, ST_DONE], true).setAllowInvalid(false).build());

  const all = sh.getRange(`A${FIRST_ROW}:${LAST}`);
  const status = sh.getRange(`${ST}${FIRST_ROW}:${ST}`);
  const DUE = colL(C.due);
  const DESC = colL(C.desc);
  const due = sh.getRange(`${DUE}${FIRST_ROW}:${DUE}`);
  const desc = sh.getRange(`${DESC}${FIRST_ROW}:${DESC}`);
  const rule = () => SpreadsheetApp.newConditionalFormatRule();
  sh.setConditionalFormatRules([
    rule().whenTextEqualTo(ST_DONE).setBackground('#d9f2e3').setFontColor('#137333').setBold(true).setRanges([status]).build(),
    rule().whenTextEqualTo(ST_WIP).setBackground('#fff2cc').setFontColor('#9a6700').setBold(true).setRanges([status]).build(),
    rule().whenTextEqualTo(ST_WAIT).setBackground('#fce8e6').setFontColor('#c5221f').setBold(true).setRanges([status]).build(),
    // เลยกำหนดแล้วยังไม่เสร็จ → กำหนดแล้วเสร็จเป็นสีแดง
    rule().whenFormulaSatisfied(`=AND($${DUE}${FIRST_ROW}<>"",$${DUE}${FIRST_ROW}<TODAY(),$${ST}${FIRST_ROW}<>"${ST_DONE}")`)
      .setBackground('#c5221f').setFontColor('#ffffff').setBold(true).setRanges([due]).build(),
    rule().whenFormulaSatisfied(`=LEFT($${DESC}${FIRST_ROW},${URGENT_TAG.length - 1})="${URGENT_TAG.trim()}"`)
      .setFontColor('#c5221f').setBold(true).setRanges([desc]).build(),
    // สลับสีแถว (เฉพาะแถวที่มีข้อมูล)
    rule().whenFormulaSatisfied(`=AND(ISNUMBER($A${FIRST_ROW}),ISEVEN(ROW()))`).setBackground(THEME.band).setRanges([all]).build(),
  ]);

  // ปุ่มกรองที่หัวตาราง (เลือกดูทีละโปรเจค / สถานะ ได้เหมือน Excel)
  sh.getRange(HEADER_ROW, 1, sh.getMaxRows() - HEADER_ROW + 1, LAST_VISIBLE).createFilter();

  const works = createWorksSheet(sh.getParent());
  // dropdown โปรเจคจากแท็บรายชื่อ (พิมพ์ชื่อที่ไม่มีในรายชื่อก็ได้)
  col(C.work).setDataValidation(SpreadsheetApp.newDataValidation()
    .requireValueInRange(works.getRange(2, 1, WORKS_ROWS, 1), true).setAllowInvalid(true).build());
}

function worksRowFormulas(r) {
  const P = `'Punch List'!`;
  const rng = (c) => `${P}$${colL(c)}$${FIRST_ROW}:$${colL(c)}`;
  const W = rng(C.work);
  const S = rng(C.status);
  const guard = (f) => `=IF($A${r}="","",${f})`;
  return [
    guard(`COUNTIF(${W},$A${r})`),
    guard(`COUNTIFS(${W},$A${r},${S},"<>${ST_DONE}")`),
    guard(`COUNTIFS(${W},$A${r},${S},"${ST_DONE}")`),
    guard(`COUNTIFS(${W},$A${r},${rng(C.due)},"<"&TODAY(),${S},"<>${ST_DONE}")`),
  ];
}

function createWorksSheet(ss) {
  const ws = ss.insertSheet(WORKS_SHEET);
  ws.getRange(1, 1, 1, WORKS_HEADERS.length).setValues([WORKS_HEADERS])
    .setFontWeight('bold').setBackground(THEME.header).setHorizontalAlignment('center');
  ws.setFrozenRows(1);
  ws.setColumnWidth(1, 220);
  ws.setColumnWidth(2, 130);
  const rows = [];
  for (let r = 2; r < 2 + WORKS_ROWS; r++) rows.push(worksRowFormulas(r));
  ws.getRange(2, 3, WORKS_ROWS, 4).setFormulas(rows).setHorizontalAlignment('center');
  ws.getRange(2, 1, WORKS_EXAMPLES.length, 1).setValues(WORKS_EXAMPLES.map((w) => [w]));
  ws.getRange(2, 1, WORKS_ROWS, 2).setBackground('#fffdf2'); // ช่องให้พิมพ์เอง
  return ws;
}

function worksSheet(project) {
  return SpreadsheetApp.openById(project.sheetId).getSheetByName(WORKS_SHEET);
}

function readWorks(project) {
  const ws = worksSheet(project);
  if (!ws) return [];
  return ws.getRange(2, 1, WORKS_ROWS, 6).getValues()
    .map((r) => ({ name: String(r[0] || '').trim(), abbr: String(r[1] || '').trim(),
      all: r[2], open: r[3], done: r[4], late: r[5] }))
    .filter((w) => w.name);
}

function addWork(project, name) {
  const ws = worksSheet(project);
  const names = ws.getRange(2, 1, WORKS_ROWS, 1).getValues().map((r) => String(r[0] || '').trim());
  const at = names.indexOf('');
  if (at >= 0) return ws.getRange(2 + at, 1).setValue(name);
  const r = ws.getLastRow() + 1;
  ws.getRange(r, 1).setValue(name);
  ws.getRange(r, 3, 1, 4).setFormulas([worksRowFormulas(r)]);
}

function projectSheet(project) {
  return SpreadsheetApp.openById(project.sheetId).getSheets()[0];
}

function readItems(sh) {
  const n = sh.getLastRow() - FIRST_ROW + 1;
  if (n <= 0) return [];
  const ids = (v) => String(v || '').split(',').filter(Boolean);
  return sh.getRange(FIRST_ROW, 1, n, HEADERS.length).getValues()
    .map((r, i) => {
      const desc = String(r[C.desc - 1] || '');
      const urgent = desc.indexOf(URGENT_TAG) === 0;
      return {
        row: FIRST_ROW + i,
        no: Number(r[C.no - 1]),
        work: r[C.work - 1],
        location: r[C.loc - 1],
        description: urgent ? desc.slice(URGENT_TAG.length) : desc,
        priority: urgent ? 'ด่วน' : 'ปกติ',
        assignee: r[C.who - 1],
        start: r[C.start - 1] || null,
        due: r[C.due - 1] || null,
        status: r[C.status - 1],
        notes: r[C.notes - 1],
        reporter: String(r[C.reporter - 1] || '').split('\n')[0],
        beforeIds: ids(r[C.beforeIds - 1]),
        afterIds: ids(r[C.afterIds - 1]),
      };
    })
    .filter((i) => i.no);
}

function findItem(sh, no) {
  return readItems(sh).find((i) => i.no === no) || null;
}

// รูปแนวตั้ง: ขอรูปย่อตามความสูง แล้วให้ IMAGE() ย่อพอดีช่อง (คงสัดส่วน)
function thumbFormula(fileId) {
  return fileId ? `=IMAGE("https://drive.google.com/thumbnail?id=${fileId}&sz=h600")` : '';
}

const PHOTO_ROW_HEIGHT = 150;

function setPhotoCells(sh, row, beforeIds, afterIds) {
  sh.getRange(row, C.beforeIds, 1, 2).setValues([[beforeIds.join(','), afterIds.join(',')]]);
  sh.getRange(row, C.before).setFormula(thumbFormula(beforeIds[0]));
  sh.getRange(row, C.after).setFormula(thumbFormula(afterIds[afterIds.length - 1]));
  if (beforeIds.length || afterIds.length) sh.setRowHeight(row, PHOTO_ROW_HEIGHT);

  const links = beforeIds.map((id, i) => [`ก่อน ${i + 1}`, id]).concat(afterIds.map((id, i) => [`หลัง ${i + 1}`, id]));
  if (!links.length) return sh.getRange(row, C.links).setValue('');
  const rich = SpreadsheetApp.newRichTextValue().setText(links.map((l) => l[0]).join('\n'));
  let pos = 0;
  for (const [label, id] of links) {
    rich.setLinkUrl(pos, pos + label.length, `https://drive.google.com/file/d/${id}/view`);
    pos += label.length + 1;
  }
  sh.getRange(row, C.links).setRichTextValue(rich.build());
}

function appendNote(sh, item, text, by) {
  const line = `${fmtDate(now())} ${by || ''}: ${text}`.replace(/ :/, ':');
  const notes = item.notes ? item.notes + '\n' + line : line;
  sh.getRange(item.row, C.notes).setValue(notes);
  return notes;
}

function fmtDay(d) {
  return d ? Utilities.formatDate(new Date(d), TZ, 'd/M/yy') : '';
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
  return first ? [text('📷 รับรูปแล้ว พิมพ์รายละเอียดต่อได้เลย\nเช่น: ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ภายใน 12/10')] : null;
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
    const project = getProject(chatId, ev.source);
    const found = matchWork(String(msg).replace(ITEM_PREFIX, ''), readWorks(project));
    const fields = parseItem(found.rest);
    if (!fields.description) return [text('กรุณาพิมพ์รายละเอียดด้วย เช่น: ห้อง 301 / สีผนังไม่เรียบ')];
    fields.work = found.work || project.defaultWork || '';
    const item = addItem(project, fields, photos, displayName(ev.source));
    clearPending(chatId, userId);
    return [itemBubble(item, project, '🆕 บันทึกแล้ว')];
  }

  const project = getProject(chatId, ev.source);
  const sh = projectSheet(project);

  switch (cmd.type) {
    case 'list':
    case 'listAll': {
      let all = readItems(sh);
      let scope = project.title;
      if (cmd.arg) {
        const w = findWork(cmd.arg, readWorks(project));
        if (!w) return [text(`ไม่พบโปรเจค "${cmd.arg}"\nพิมพ์ "โปรเจค" เพื่อดูรายชื่อ`)];
        all = all.filter((i) => i.work === w.name);
        scope += ' · ' + w.name;
      }
      const items = cmd.type === 'list' ? all.filter((i) => i.status !== ST_DONE) : all;
      return [listBubble(`${scope} — ${cmd.type === 'list' ? 'งานค้าง' : 'ทั้งหมด'}`, items, all, project)];
    }

    case 'work': {
      const works = readWorks(project);
      if (!cmd.arg) {
        const lines = works.map((w) => `• ${w.name}${w.abbr ? ` (${w.abbr})` : ''} — ค้าง ${w.open || 0}${w.late ? ` · เลยกำหนด ${w.late}` : ''}`);
        return [text(`📂 โปรเจคใน ${project.title}\n${lines.join('\n') || '(ยังไม่มี)'}\n\n` +
          `ตอนนี้แจ้งเข้า: ${project.defaultWork || 'ไม่ระบุ'}\n` +
          `เปลี่ยน: โปรเจค ชื่อ · เลิกตั้ง: โปรเจค ไม่ระบุ · เพิ่ม: เพิ่มโปรเจค ชื่อ`)];
      }
      if (/^(ไม่ระบุ|ยกเลิก|-|none)$/i.test(cmd.arg)) {
        project.defaultWork = '';
        setJson('chat:' + chatId, project);
        return [text('เลิกตั้งโปรเจคแล้ว รายการต่อไปจะไม่ระบุโปรเจค (ยกเว้นพิมพ์ชื่อในข้อความ)')];
      }
      const w = findWork(cmd.arg, works);
      if (!w) return [text(`ไม่มี "${cmd.arg}" ในรายชื่อ\nเพิ่มด้วย: เพิ่มโปรเจค ${cmd.arg}`)];
      project.defaultWork = w.name;
      setJson('chat:' + chatId, project);
      return [text(`📂 รายการที่แจ้งต่อจากนี้จะเข้าโปรเจค "${w.name}"\n(พิมพ์ชื่อโปรเจคอื่นในข้อความเพื่อแจ้งข้ามได้)`)];
    }

    case 'addWork': {
      const name = cmd.arg.replace(/\s+/g, ' ').trim().slice(0, 60);
      if (findWork(name, readWorks(project))) return [text(`มี "${name}" อยู่แล้ว`)];
      addWork(project, name);
      return [text(`➕ เพิ่มโปรเจค "${name}" แล้ว\nใส่คำย่อได้ที่แท็บ "${WORKS_SHEET}" ใน Sheet`)];
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

    case 'start': {
      const item = findItem(sh, cmd.no);
      if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
      item.status = ST_WIP;
      sh.getRange(item.row, C.status).setValue(ST_WIP);
      item.notes = appendNote(sh, item, 'เริ่มแก้ไข', displayName(ev.source));
      updateIndex(project);
      return [itemBubble(item, project, '🔧 เริ่มแก้ไข')];
    }

    case 'done':
    case 'reopen': {
      const item = findItem(sh, cmd.no);
      if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
      const done = cmd.type === 'done';
      item.status = done ? ST_DONE : ST_WAIT;
      sh.getRange(item.row, C.status).setValue(item.status);
      sh.getRange(item.row, C.closed).setValue(done ? now() : '');
      const label = done ? 'ปิดงาน' : 'เปิดใหม่';
      item.notes = appendNote(sh, item, cmd.note ? `${label} — ${cmd.note}` : label, displayName(ev.source));
      // รูปที่ส่งก่อนพิมพ์ "เสร็จ N" = รูปหลังแก้ไข
      const after = done ? pendingPhotos(chatId, userId) : [];
      if (after.length) {
        item.afterIds = item.afterIds.concat(after);
        setPhotoCells(sh, item.row, item.beforeIds, item.afterIds);
        clearPending(chatId, userId);
      }
      updateIndex(project);
      return [itemBubble(item, project, done ? '✅ ปิดงานแล้ว' : '↩️ เปิดใหม่')];
    }

    case 'delete': {
      const item = findItem(sh, cmd.no);
      if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
      sh.deleteRow(item.row);
      for (const id of item.beforeIds.concat(item.afterIds)) {
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
      // "#3 เริ่ม 5/10 ภายใน 12/10" = แก้กำหนดวัน, ข้อความที่เหลือ = หมายเหตุ
      const d = extractDates(cmd.note);
      const changes = [];
      if (d.start) {
        sh.getRange(item.row, C.start).setValue(d.start);
        changes.push(`กำหนดวันเริ่ม ${fmtDay(d.start)}`);
      }
      if (d.due) {
        sh.getRange(item.row, C.due).setValue(d.due);
        changes.push(`กำหนดแล้วเสร็จ ${fmtDay(d.due)}`);
      }
      const rest = d.rest.replace(/\s+/g, ' ').trim();
      const note = changes.concat(rest ? [rest] : []).join(' — ');
      appendNote(sh, item, note, displayName(ev.source));
      return [text(changes.length ? `📅 #${cmd.no}: ${changes.join(', ')}` : `📝 เพิ่มหมายเหตุใน #${cmd.no} แล้ว`)];
    }

    case 'setTitle': {
      const title = safeName(cmd.title);
      if (!title) return [text('กรุณาพิมพ์ชื่อโครงการด้วย')];
      project.title = title;
      setJson('chat:' + chatId, project);
      SpreadsheetApp.openById(project.sheetId).rename('Punch List - ' + title);
      sh.getRange(TITLE_ROW, 1).setValue('PUNCH LIST : ' + title);
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

  const desc = (fields.priority === 'ด่วน' ? URGENT_TAG : '') + fields.description;
  const reporterCell = [reporter, fmtDate(now())].filter(Boolean).join('\n');
  sh.appendRow([project.seq, fields.work || '', '', fields.location, desc, fields.assignee, fields.start || '',
    fields.due || '', ST_WAIT, '', '', '', reporterCell, '', '', '']);
  const row = sh.getLastRow();
  sh.getRange(row, 1, 1, LAST_VISIBLE)
    .setBorder(true, true, true, true, true, false, THEME.border, SpreadsheetApp.BorderStyle.SOLID);
  setPhotoCells(sh, row, photoIds, []);
  updateIndex(project);

  return { row, no: project.seq, ...fields, status: ST_WAIT, reporter, beforeIds: photoIds, afterIds: [], notes: '' };
}

/* ========================= PDF + สรุปรายสัปดาห์ ========================= */

// PDF = สำเนาชั่วคราวของชีต จัดกลุ่มทีละโปรเจค (ตามลำดับในแท็บรายชื่อโปรเจค) แล้วลบทิ้ง
// Sheet หลักไม่ถูกแตะ ยังเรียงตามลำดับที่แจ้งเหมือนเดิม
function exportPdf(project) {
  const ss = SpreadsheetApp.openById(project.sheetId);
  const sh = ss.getSheets()[0];
  const at = now();
  const tmp = sh.copyTo(ss).setName('PDF ' + Utilities.formatDate(at, TZ, 'yyMMdd-HHmmss'));
  let blob;
  try {
    // "สถานะ ณ วันที่" อยู่ในแถวหัว (แถว 1–3 ถูก freeze → ซ้ำทุกหน้าของ PDF)
    tmp.getRange(SUMMARY_ROW, STAMP_COL)
      .setValue(`สถานะ ณ วันที่ ${Utilities.formatDate(at, TZ, 'd/M/yyyy เวลา HH:mm')} น.`);
    groupByWork(tmp, readWorks(project).map((w) => w.name));
    SpreadsheetApp.flush();

    const url = `https://docs.google.com/spreadsheets/d/${project.sheetId}/export?format=pdf&gid=${tmp.getSheetId()}` +
      '&size=A4&portrait=false&fitw=true&gridlines=false&sheetnames=false&printtitle=false&pagenum=CENTER&fzr=true' +
      '&top_margin=0.4&bottom_margin=0.4&left_margin=0.4&right_margin=0.4';
    blob = UrlFetchApp.fetch(url, { headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() } }).getBlob();
  } finally {
    ss.deleteSheet(tmp);
  }
  blob.setName(`${project.title} ${Utilities.formatDate(at, TZ, 'yyyy-MM-dd HHmm')}.pdf`);
  const file = DriveApp.getFolderById(project.pdfFolderId).createFile(blob);
  if (SHARE_WITH_LINK) file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return file;
}

// เรียงแถวตามโปรเจค แล้วแทรกแถบหัวกลุ่ม "📂 ท่อประปา — ทั้งหมด 5 · ค้าง 2 · เลยกำหนด 1"
function groupByWork(sh, workOrder) {
  const n = sh.getLastRow() - FIRST_ROW + 1;
  if (n <= 0) return;
  const items = readItems(sh);
  if (!items.some((i) => i.work)) return; // ไม่มีใครระบุโปรเจค → ไม่ต้องแบ่งกลุ่ม

  const NO_WORK = 'ไม่ระบุโปรเจค';
  const key = (w) => (!w ? 100000 : workOrder.indexOf(w) >= 0 ? workOrder.indexOf(w) : 50000);
  const KEY_COL = HEADERS.length + 1;
  const before = sh.getRange(FIRST_ROW, C.work, n, 1).getValues();
  sh.getRange(FIRST_ROW, KEY_COL, n, 1).setValues(before.map((r) => [key(r[0])]));
  sh.getRange(FIRST_ROW, 1, n, KEY_COL).sort([
    { column: KEY_COL, ascending: true },
    { column: C.work, ascending: true },
    { column: C.no, ascending: true },
  ]);
  sh.getRange(FIRST_ROW, KEY_COL, n, 1).clearContent();

  const today = new Date(Utilities.formatDate(now(), TZ, 'yyyy/MM/dd'));
  const stats = {};
  for (const i of items) {
    const w = i.work || NO_WORK;
    const s = stats[w] || (stats[w] = { all: 0, open: 0, late: 0 });
    s.all++;
    if (i.status !== ST_DONE) s.open++;
    if (i.status !== ST_DONE && i.due && new Date(i.due) < today) s.late++;
  }

  // แทรกจากล่างขึ้นบน เลขแถวด้านบนจะได้ไม่เลื่อน
  const works = sh.getRange(FIRST_ROW, C.work, n, 1).getValues().map((r) => r[0] || NO_WORK);
  for (let i = n - 1; i >= 0; i--) {
    if (i > 0 && works[i] === works[i - 1]) continue;
    const row = FIRST_ROW + i;
    const st = stats[works[i]];
    sh.insertRowBefore(row);
    sh.setRowHeight(row, 28);
    sh.getRange(row, 1, 1, LAST_VISIBLE).merge()
      .setValue(`📂 ${works[i]}   —   ทั้งหมด ${st.all}  ·  ค้าง ${st.open}${st.late ? `  ·  เลยกำหนด ${st.late}` : ''}`)
      .setFontWeight('bold').setFontSize(11).setFontColor(THEME.title).setBackground('#b6d7a8')
      .setHorizontalAlignment('left').setVerticalAlignment('middle')
      .setBorder(true, true, true, true, false, false, THEME.border, SpreadsheetApp.BorderStyle.SOLID);
  }
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
      // แยกตามโปรเจค: นับงานค้าง
      const byWork = {};
      for (const i of items) if (i.status !== ST_DONE) byWork[i.work || 'ไม่ระบุ'] = (byWork[i.work || 'ไม่ระบุ'] || 0) + 1;
      const workLines = Object.keys(byWork).map((w) => `• ${w} ค้าง ${byWork[w]}`).join('\n');
      push(project.chatId, [text(
        `📅 สรุปประจำสัปดาห์: ${project.title}\nค้าง ${open} · เสร็จ ${items.length - open} · ทั้งหมด ${items.length}` +
        `${workLines ? '\n' + workLines : ''}\n\n📄 PDF\n${pdf.getUrl()}\n\n📊 Sheet ล่าสุด\n${project.sheetUrl}`
      )]);
    } catch (err) {
      console.error(key, err);
    }
  }
}

/* ========================= Flex Message ========================= */

const COLORS = { open: '#C5221F', wip: '#9A6700', done: '#2E9E5B', high: '#D93025', muted: '#8A8F98', text: '#1F2328' };

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
              {
                type: 'text', text: item.status, size: 'xs', weight: 'bold', align: 'end',
                color: done ? COLORS.done : item.status === ST_WIP ? COLORS.wip : COLORS.open,
              },
            ],
          },
          { type: 'text', text: `#${item.no} ${trunc(item.description, 120) || '-'}`, weight: 'bold', size: 'lg', wrap: true },
          {
            type: 'box', layout: 'vertical', spacing: 'xs',
            contents: [
              flexRow('โปรเจค', item.work),
              flexRow('พื้นที่', item.location),
              flexRow('ผู้รับผิดชอบ', item.assignee),
              flexRow('กำหนดวันเริ่ม', fmtDay(item.start)),
              flexRow('กำหนดเสร็จ', fmtDay(item.due)),
              ...(item.priority === 'ด่วน' ? [flexRow('ความสำคัญ', 'ด่วน', COLORS.high)] : []),
              flexRow('รูป', `ก่อน ${item.beforeIds.length} · หลัง ${item.afterIds.length}`),
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
          type: 'text', text: trunc([i.work, i.location, i.description].filter(Boolean).join(' · '), 60) || '-',
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

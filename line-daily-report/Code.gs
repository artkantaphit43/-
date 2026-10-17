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
  // บริษัทสำหรับหัวกระดาษ (โลโก้อยู่ใน tools/logos/<key>.png)
  COMPANIES: [
    { key: 'aceken', label: 'Aceken' },
    { key: 'chemmettle', label: 'Chemmettle' },
    { key: 'metryscape', label: 'Metryscape' },
  ],

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

  PHOTO_MAX_HEIGHT: 200, // ความสูงรูปสูงสุดในกรอบภาพถ่าย (pixel) รูปน้อยจะใหญ่ รูปเยอะจะย่อให้พอดีกรอบ
  MIN_PHOTO_ROWS: 8, // ถ้าสรุปงาน/แผนงานยาวเกินตาราง จะยืมแถวจากกรอบรูป แต่กรอบรูปเหลืออย่างน้อยเท่านี้
  ROOT_FOLDER_NAME: 'LINE Daily Report',
};

const CMD_SUBMIT = /^(ส่ง|ส่งรายงาน|เสร็จ|จบ|submit)$/i;
const CMD_CANCEL = /^(ยกเลิก|cancel)$/i;
const CMD_STATUS = /^(สถานะ|เช็ค|เช็ก|status)$/i;
const CMD_HELP = /^(ฟอร์ม|วิธีใช้|help|\?|เริ่ม|เริ่มรายงาน|รายงาน|📋 เริ่มรายงาน)$/i;
const CMD_NAME = /^(ชื่อ|เลือกชื่อ)$/i;
const CMD_ADD_PROJECT = /^(➕\s*)?เพิ่มโครงการ/;
const CMD_LIST_PROJECTS = /^(โครงการ|รายการโครงการ|โครงการทั้งหมด)$/;
const CMD_DELETE_PROJECT = /^ลบโครงการ[:：\s]+(.+)$/;
const CMD_SIGNATURE = /^ลายเซ็น(?:[:：\s]+(.+))?$/;
const CMD_PUNCH = /^punch\s*list$/i;
const CMD_PLAN = /^(แผน|แผนงาน|แผนพรุ่งนี้|พรุ่งนี้|work ?plan)$/i;
const CMD_TODAY = /^(วันนี้|งานวันนี้)$/i;

const THAI_MONTHS = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
const THAI_MONTHS_SHORT = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

const CHECKED = '☑';
const UNCHECKED = '☐';

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
    reply_(event.replyToken, quickReply_('สวัสดีครับ 👋 บอทรายงานประจำวัน\nกด "เริ่มรายงาน" แล้วกดตอบตามปุ่มได้เลย',
      [{ label: '📋 เริ่มรายงาน', text: 'เริ่ม' }]));
    return;
  }
  if (!isAllowed_(event.source)) return;
  if (event.type === 'postback') return handlePostback_(event);
  if (event.type !== 'message') return;

  const msg = event.message;
  if (msg.type === 'text') {
    handleText_(event, msg.text.trim());
  } else if (msg.type === 'image') {
    const props = PropertiesService.getScriptProperties();
    const sigOwner = props.getProperty('SIGWAIT_' + event.source.userId);
    if (sigOwner) {
      saveSignature_(sigOwner, msg.id);
      props.deleteProperty('SIGWAIT_' + event.source.userId);
      return reply_(event.replyToken, `✅ บันทึกลายเซ็นของ ${sigOwner} แล้ว\nรายงานครั้งต่อไปจะใส่ลายเซ็นให้อัตโนมัติ`);
    }
    const session = withSession_(event.source, s => addPhoto_(s, msg.id));
    // ส่งหลายรูปพร้อมกัน ตอบครั้งเดียวตอนรูปสุดท้าย แชตจะได้ไม่รก
    if (msg.imageSet && msg.imageSet.index !== msg.imageSet.total) return;
    const last = session.photos[session.photos.length - 1];
    const count = session.photos.filter(p => p.project === last.project && p.title === last.title).length;
    const sec = session[session.section];
    reply_(event.replyToken, workPrompt_(session, sec, `📷 ได้รับรูปแล้ว${last.title ? ' — ' + last.title : ''} (${count} รูป)`));
  }
}

function handleText_(event, text) {
  const source = event.source;
  const token = event.replyToken;
  if (CMD_HELP.test(text)) {
    const s = withSession_(source, advance_);
    return reply_(token, withPrefix_(question_(s, s.awaiting), `📋 รายงานวันที่ ${thaiDateShort_(s.date)}\nกดตอบจากปุ่มด้านล่างได้เลย`));
  }
  if (CMD_NAME.test(text)) return reply_(token, reporterPicker_('เลือกชื่อผู้เขียนรายงาน 👇'));
  if (CMD_PUNCH.test(text)) return reply_(token, '🛠️ Punch List กำลังพัฒนา เร็ว ๆ นี้');
  if (CMD_ADD_PROJECT.test(text)) {
    withSession_(source, s => { s.awaiting = 'newproject-code'; });
    return reply_(token, '📁 พิมพ์รหัสโครงการที่จะเพิ่มหรือแก้ไข\nเช่น  PJ 950');
  }
  if (CMD_LIST_PROJECTS.test(text)) return reply_(token, projectPicker_(projectListText_()));
  const del = text.match(CMD_DELETE_PROJECT);
  if (del) return reply_(token, deleteProject_(del[1]));
  const sig = text.match(CMD_SIGNATURE);
  if (sig) {
    if (!sig[1]) return reply_(token, quickReply_('ตั้งลายเซ็นของใคร? 👇',
      CONFIG.REPORTERS.map(n => ({ label: n, text: 'ลายเซ็น: ' + n }))));
    const owner = matchName_(sig[1]);
    PropertiesService.getScriptProperties().setProperty('SIGWAIT_' + source.userId, owner);
    return reply_(token, `✍️ ส่งรูปลายเซ็นของ ${owner} มาได้เลย 1 รูป\n(เซ็นบนกระดาษขาวด้วยปากกาสีเข้ม ถ่ายให้ชิดลายเซ็น)`);
  }

  const pending = loadSession_(source);
  if (pending && pending.awaiting === 'newproject' && pending.newProject && !CMD_CANCEL.test(text)) {
    return handleNewProjectAnswer_(token, source, text);
  }
  if (pending && pending.awaiting === 'newproject-code' && /\d/.test(text)) {
    return reply_(token, startNewProject_(source, normalizeCode_(text), 'none'));
  }

  if (CMD_CANCEL.test(text)) {
    deleteSession_(source);
    return reply_(token, '🗑️ ยกเลิกรายงานที่ค้างอยู่แล้ว');
  }

  if (CMD_STATUS.test(text)) {
    const session = loadSession_(source);
    return reply_(token, session ? summaryFlex_(session) : 'ยังไม่มีรายงานที่ค้างอยู่');
  }

  if (CMD_SUBMIT.test(text)) {
    const session = loadSession_(source);
    if (!session || (!session.today.items.length && !session.photos.length)) {
      return reply_(token, quickReply_('ยังไม่มีงานในรายงาน', [{ label: '📋 เริ่มรายงาน', text: 'เริ่ม' }]));
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

  let added = 0;
  let newGroup = '';
  const session = withSession_(source, s => {
    const previous = s.awaiting;
    const section = s.section;
    const before = s[section].items.length;
    const group = s[section].group;
    applyText_(s, expandShortAnswer_(s, text));
    if (s.section === section) {
      added = s[section].items.length - before;
      if (s[section].group !== group) newGroup = s[section].group;
    }
    if (added || newGroup) s[s.section].workDone = false;
    advance_(s);
    if (previous === 'start' && !added) s.awaiting = 'end'; // แก้เวลาเริ่มแล้วถามเวลาเลิกต่อ
  });

  const isNew = code => code && !/,/.test(code) && !getProjects_()[code];
  if (isNew(session.project.code)) return reply_(token, startNewProject_(source, session.project.code, 'flow'));
  const sec = session[session.section];
  if (added) {
    const it = sec.items[sec.items.length - 1];
    return reply_(token, workPrompt_(session, sec,
      `📝 บันทึก ${it.group ? it.group + ' • ' : ''}${it.title}${it.progress ? ' ' + it.progress : ''}`));
  }
  if (newGroup && isNew(newGroup)) return reply_(token, startNewProject_(source, newGroup, 'work'));
  if (newGroup) return reply_(token, workPrompt_(session, sec, `📁 โครงการ ${newGroup}`, true));
  reply_(token, withPrefix_(question_(session, session.awaiting), '✅ บันทึกแล้ว'));
}

// ===== แปลงข้อความเป็นข้อมูลรายงาน =====

/** ช่องข้อมูลแบบ "หัวข้อ: ค่า" — sec คือส่วนที่กำลังกรอกอยู่ (วันนี้ หรือ แผนพรุ่งนี้) */
const FIELD_HANDLERS = [
  { aliases: ['ผู้รายงาน', 'ผู้เขียนรายงาน', 'ผู้บันทึก'], set: (s, v) => { s.reporter = matchName_(v); } },
  {
    aliases: ['หัวกระดาษ', 'บริษัท'],
    set: (s, v) => {
      const c = CONFIG.COMPANIES.find(x => x.label.toLowerCase() === v.toLowerCase() || x.key === v.toLowerCase());
      if (c) s.company = c.key;
    },
  },
  { aliases: ['ผู้ควบคุมงาน', 'หัวหน้า', 'หัวหน้างาน'], set: (s, v) => { s.supervisor = matchName_(v); } },
  { aliases: ['โครงการ', 'project', 'pj'], set: (s, v) => setProject_(s, v) },
  { aliases: ['ชื่อโครงการ'], set: (s, v) => { s.project.name = v; } },
  { aliases: ['สถานที่', 'สถานที่ปฏิบัติงาน', 'location'], set: (s, v) => { s.project.location = v; } },
  { aliases: ['ลักษณะงาน', 'ลักษณะโครงการ'], set: (s, v) => { s.project.jobType = v; } },
  { aliases: ['เวลา', 'เวลาทำงาน'], set: (s, v) => setWorkTime_(s, v) },
  { aliases: ['เริ่มงาน', 'เวลาเริ่ม', 'เวลาเริ่มงาน'], set: (s, v) => { s.start = formatTime_(v); } },
  { aliases: ['เลิกงาน', 'จบงาน', 'เวลาจบ', 'เวลาจบงาน'], set: (s, v) => { s.end = formatTime_(v); } },
  { aliases: ['คน', 'คนงาน', 'กำลังพล'], set: (s, v, sec) => { sec.manpower = v.replace(/คน/g, '').trim(); } },
  { aliases: ['อากาศ', 'สภาพอากาศ'], set: (s, v) => { s.weather = v; } },
  { aliases: ['ช่วงฝนตก', 'ฝนตกช่วง', 'เวลาฝนตก'], set: (s, v) => { s.rainTime = v; } },
  { aliases: ['อุณหภูมิ'], set: (s, v) => { s.temp = v.replace(/องศา.*|°.*/g, '').trim(); } },
  { aliases: ['ผลกระทบ'], set: (s, v) => { s.impact = v; } },
  { aliases: ['อุบัติเหตุ'], set: (s, v) => { s.accident = v; } },
  { aliases: ['หมายเหตุ'], set: (s, v) => { s.notes = v; } },
  {
    aliases: ['ปัญหา', 'ปัญหาอุปสรรค'],
    set: (s, v, sec) => {
      const it = lastItem_(sec);
      it.problem = /^(ไม่มี|-)$/.test(v) ? '' : v;
      it.done = true;
    },
  },
  { aliases: ['เครื่องจักร'], set: (s, v, sec) => { sec.machinesDone = true; } },
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

    // งานที่ยังไม่มีหัวข้อ PJ ให้อยู่ใต้โครงการหลักของรายงาน (ฟอร์มมีหัว PJ เสมอ)
    const addWork = title => {
      if (!sec.group && session.project.code) sec.group = session.project.code;
      addItem_(sec, title);
    };

    // "1. ประชุมแผนงาน 100%" = งานใหม่
    const numbered = line.match(/^\d+\s*[.)]\s*(.*)$/);
    if (numbered) return addWork(numbered[1]);

    const kv = line.match(/^([^:：]+)[:：]\s*(.*)$/);
    if (kv) {
      const key = kv[1].trim().toLowerCase();
      const value = kv[2].trim();
      // ช่องที่เว้นว่างในแบบฟอร์ม เช่น "รถเครน: " หรือ "โครงการ: PJ" ให้ข้ามไป
      const blank = !value || /^(-|pj|0)$/i.test(value);
      const field = FIELD_HANDLERS.find(f => f.aliases.some(a => a.toLowerCase() === key));
      if (field) {
        if (!blank || value === '0') field.set(session, value, sec);
        return;
      }
      const machine = CONFIG.MACHINES.find(m => m.aliases.some(a => a.toLowerCase() === key));
      if (machine) {
        if (blank) delete sec.machines[machine.key];
        else sec.machines[machine.key] = parseMachine_(value);
        return;
      }
    }
    addWork(line);
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
  const v = String(value).trim();
  const m = v.match(/^(?:PJ\s*)?(\d+)$/i) || v.match(/PJ\s*(\d+)/i);
  return m ? 'PJ ' + m[1] : v;
}

function setProject_(session, value) {
  const code = normalizeCode_(value);
  const preset = getProjects_()[code] || {};
  session.project = Object.assign({ code: code, name: '', location: '', jobType: '' }, preset, { code: code });
}

// ===== ฐานข้อมูลโครงการ (แท็บ "ฐานข้อมูลโครงการ" ในชีตบันทึก แก้ในชีตได้โดยตรง) =====

const PROJECT_SHEET = 'ฐานข้อมูลโครงการ';
const PROJECT_FIELDS = [
  { key: 'name', label: 'ชื่อโครงการ (Project Name)', example: 'งานติดตั้งระบบท่อน้ำภายนอกอาคารด้วยท่อ HDPE' },
  { key: 'location', label: 'สถานที่ปฏิบัติงาน (Location)', example: 'SAHAMITFOODS (PLANT 2) LIMITED' },
  { key: 'jobType', label: 'ลักษณะโครงการ (Job Type)', example: 'Underground piping and Piping installation.' },
];

function projectSheet_() {
  const ss = getSheet_().getParent();
  let sheet = ss.getSheetByName(PROJECT_SHEET);
  if (sheet) return sheet;

  sheet = ss.insertSheet(PROJECT_SHEET);
  sheet.appendRow(['รหัส PJ'].concat(PROJECT_FIELDS.map(f => f.label)));
  sheet.getRange(1, 1, 1, 4).setFontWeight('bold').setBackground('#E0F5F5');
  sheet.setFrozenRows(1);
  sheet.setColumnWidth(1, 100);
  sheet.setColumnWidths(2, 3, 320);
  // ย้ายโครงการเดิม (จากโค้ดและที่เคยเพิ่มผ่านไลน์) มาไว้ในตาราง
  const raw = PropertiesService.getScriptProperties().getProperty('PROJECTS');
  const seed = Object.assign({}, CONFIG.PROJECTS, raw ? JSON.parse(raw) : {});
  Object.keys(seed).forEach(code => sheet.appendRow([code].concat(PROJECT_FIELDS.map(f => seed[code][f.key] || ''))));
  return sheet;
}

/** { 'PJ 942': { name, location, jobType } } อ่านครั้งเดียวต่อการทำงานหนึ่งรอบ */
function getProjects_() {
  if (getProjects_.cache) return getProjects_.cache;
  const projects = {};
  projectSheet_().getDataRange().getDisplayValues().slice(1).forEach(row => {
    const code = normalizeCode_(row[0] || '');
    if (!code) return;
    projects[code] = {};
    PROJECT_FIELDS.forEach((f, i) => { projects[code][f.key] = row[i + 1]; });
  });
  getProjects_.cache = projects;
  return projects;
}

function saveProject_(code, data) {
  const sheet = projectSheet_();
  const codes = sheet.getRange(1, 1, sheet.getLastRow(), 1).getDisplayValues().map(r => normalizeCode_(r[0]));
  const values = [[code].concat(PROJECT_FIELDS.map(f => data[f.key] || ''))];
  const row = codes.indexOf(code, 1);
  if (row > 0) sheet.getRange(row + 1, 1, 1, 4).setValues(values);
  else sheet.appendRow(values[0]);
  getProjects_.cache = null;
}

function deleteProject_(value) {
  const code = normalizeCode_(value);
  const sheet = projectSheet_();
  const codes = sheet.getRange(1, 1, sheet.getLastRow(), 1).getDisplayValues().map(r => normalizeCode_(r[0]));
  const row = codes.indexOf(code, 1);
  if (row < 1) return `ไม่พบโครงการ ${code}`;
  sheet.deleteRow(row + 1);
  getProjects_.cache = null;
  return `🗑️ ลบโครงการ ${code} แล้ว`;
}

function projectSheetUrl_() {
  const sheet = projectSheet_();
  return `${sheet.getParent().getUrl()}#gid=${sheet.getSheetId()}`;
}

function projectListText_() {
  const projects = getProjects_();
  const codes = Object.keys(projects);
  const list = codes.length ? codes.map(c => `• ${c} — ${projects[c].name || '-'}`).join('\n') : 'ยังไม่มีโครงการ';
  return `📁 ฐานข้อมูลโครงการ\n${list}\n\nแก้ไขในตาราง:\n${projectSheetUrl_()}`;
}

/** โครงการที่ยังไม่มีในฐานข้อมูล: ถามชื่อ/สถานที่/ลักษณะงานทีละข้อ ครั้งเดียว — resume = ทำอะไรต่อหลังบันทึก */
function startNewProject_(source, code, resume) {
  withSession_(source, s => {
    s.newProject = { code: code, data: {}, step: 0, resume: resume };
    s.awaiting = 'newproject';
  });
  const known = getProjects_()[code];
  const intro = known ? `✏️ แก้ข้อมูล ${code}` : `📁 ${code} ยังไม่มีในฐานข้อมูล\nกรอกครั้งเดียว ครั้งต่อไประบบเติมให้อัตโนมัติ`;
  return withPrefix_(newProjectQuestion_(code, 0), intro);
}

function newProjectQuestion_(code, step) {
  const f = PROJECT_FIELDS[step];
  return quickReply_(`${['①', '②', '③'][step]} ${f.label} ของ ${code}?\nเช่น  ${f.example}`,
    [{ label: '⏭️ ข้าม', text: '-' }]);
}

function handleNewProjectAnswer_(token, source, text) {
  let finished = null;
  const session = withSession_(source, s => {
    const np = s.newProject;
    np.data[PROJECT_FIELDS[np.step].key] = /^(-|ข้าม)$/.test(text.trim()) ? '' : text.trim();
    np.step++;
    if (np.step < PROJECT_FIELDS.length) return;
    saveProject_(np.code, np.data);
    if (s.project.code === np.code || !s.project.code) setProject_(s, np.code);
    finished = np;
    s.newProject = null;
    advance_(s);
  });
  if (!finished) return reply_(token, newProjectQuestion_(session.newProject.code, session.newProject.step));

  const saved = `✅ บันทึก ${finished.code} ลงฐานข้อมูลแล้ว`;
  if (finished.resume === 'work') {
    return reply_(token, workPrompt_(session, session[session.section], `${saved}\n\n📁 โครงการ ${finished.code}`, true));
  }
  if (finished.resume === 'none') return reply_(token, saved);
  return reply_(token, withPrefix_(question_(session, session.awaiting), saved));
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

/** "8", "08:30", "21.00 น.", "3 ทุ่ม", "ทุ่มครึ่ง" -> "08.00 น." */
function formatTime_(v) {
  const t = v.trim().replace(/\s*น\.?$/, '');
  const thum = t.match(/^(\d{1,2})?\s*ทุ่ม(ครึ่ง)?$/);
  if (thum) return `${18 + Number(thum[1] || 1)}.${thum[2] ? '30' : '00'} น.`;
  const m = t.match(/^(\d{1,2})(?:[.:](\d{2}))?$/);
  if (!m) return v;
  return `${('0' + m[1]).slice(-2)}.${m[2] || '00'} น.`;
}

/** "08.00-21.00" หรือ "8 ถึง 3 ทุ่ม" -> ตั้งเวลาเริ่มและเวลาจบ */
function setWorkTime_(s, v) {
  const parts = v.split(/\s*(?:-|–|ถึง)\s*/);
  if (parts[0]) s.start = formatTime_(parts[0]);
  if (parts[1]) s.end = formatTime_(parts[1]);
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
  session.photos.push({
    id: file.getId(),
    project: item ? item.group : (session.today.group || ''),
    title: item ? item.title : '',
  });
}

// ===== สร้างรายงาน: คัดลอกแม่แบบ (ฟอร์ม Excel ของบริษัทที่แปลงเป็น Google Sheets) -> เติมข้อมูล -> PDF =====

/**
 * ตำแหน่งช่องในแม่แบบ = ฟอร์ม Excel เดิมเลื่อนลง 1 แถว (แถว 1 เป็นแถวโลโก้)
 * แถวเครื่องจักร: D = ชนิด, F = จำนวน
 */
const TPL = {
  date: 'E4', reporter: 'E5', start: 'E6', end: 'E7',
  projectName: 'B5', location: 'B6', jobType: 'B7',
  manpower: 'A9',
  weather: { 'ฝนตก': 'A11', 'แดดจัด': 'B11', 'ปกติ': 'C11' },
  rainTime: 'B12', temp: 'B13',
  machineRows: { crane: 10, hiab: 11, concrete: 12, car: 13, other: 14 },
  impactYes: 'A16', impactNo: 'A17', notes: 'D16',
  photoRows: [19, 36],
  summaryRows: [40, 49],
  accidentNo: 'D50', accidentYes: 'F50', accidentDetail: 'B51',
  planTitle: 'A52', planManpower: 'A54',
  planMachineRows: { crane: 55, hiab: 56, concrete: 57, car: 58, other: 60 },
  planRows: [56, 60],
  signRow: 63, signDateRow: 64,
  lastRow: 65, lastCol: 7,
};

function buildReport_(session) {
  const folder = getSubFolder_(getRootFolder_(), 'รายงาน', session.date);
  const fileName = `FM_Daily_Report_${(session.project.code || 'PJ').replace(/\s/g, '')}_` +
    `${session.date.replace(/-/g, '')}_${session.reporter.split(' ')[0]}`;
  const file = DriveApp.getFileById(getTemplateId_()).makeCopy(fileName, folder);
  const ss = SpreadsheetApp.openById(file.getId());
  const sheet = ss.getSheets()[0];

  const summary = workLines_(session.today.items, true);
  const plan = workLines_(session.plan.items, false);
  const row = resizeSections_(sheet, summary.length, plan.length);
  const at = ref => {
    const m = ref.match(/^([A-Z]+)(\d+)$/);
    return sheet.getRange(m[1] + row(Number(m[2])));
  };

  fillHeader_(at, session);
  fillConditions_(sheet, at, session);
  fillWorkRows_(sheet, summary, row(TPL.summaryRows[0]), row(TPL.summaryRows[1]), 4);
  fillSafety_(at, session);
  fillPlan_(sheet, at, row, session, plan);
  fillSignatures_(sheet, row, session);
  // แถวสุดท้ายของกรอบรูปอาจถูกยืมไป จึงนับจากแถวถัดไปที่ไม่ถูกลบ
  placePhotos_(sheet, session, row(TPL.photoRows[0]), row(TPL.photoRows[1] + 1) - 1);
  placeLogo_(sheet, session.company);
  SpreadsheetApp.flush();

  const pdfFile = folder.createFile(exportPdf_(ss.getId(), sheet.getSheetId(), row(TPL.lastRow)))
    .setName(fileName + '.pdf');
  try {
    pdfFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (err) {
    console.warn('ตั้งค่าแชร์ลิงก์ไม่ได้ (โดเมนอาจปิดไว้): ' + err.message);
  }

  logToSheet_(session, pdfFile.getUrl(), file.getUrl());
  return { pdfUrl: pdfFile.getUrl(), sheetUrl: file.getUrl() };
}

/** บรรทัดของตารางงาน: หัวข้อ PJ แล้วตามด้วยงาน "1.xxx" (เลขเริ่มใหม่ทุกโครงการ) */
function workLines_(items, boldGroups) {
  const lines = [];
  groupItems_(items).forEach(g => {
    if (g.group) lines.push({ text: g.group, bold: boldGroups });
    g.items.forEach((it, i) => lines.push({ text: `${i + 1}.${it.title}`, progress: it.progress, problem: it.problem }));
  });
  return lines;
}

/**
 * ตารางสรุปงานมี 10 บรรทัด แผนพรุ่งนี้มี 5 บรรทัด ถ้าเกินจะเพิ่มแถวและลดแถวกรอบรูปเท่ากัน
 * ทำให้ฟอร์มยังสูงเท่าเดิม (1 หน้าพอดี) คืนค่าฟังก์ชันแปลงเลขแถวแม่แบบ -> เลขแถวจริง
 */
function resizeSections_(sheet, summaryCount, planCount) {
  const [p0, p1] = TPL.photoRows;
  const [s0, s1] = TPL.summaryRows;
  const [q0, q1] = TPL.planRows;
  const maxBorrow = (p1 - p0 + 1) - CONFIG.MIN_PHOTO_ROWS;
  const planExtra = Math.min(Math.max(0, planCount - (q1 - q0 + 1)), maxBorrow);
  const summaryExtra = Math.min(Math.max(0, summaryCount - (s1 - s0 + 1)), maxBorrow - planExtra);
  const borrow = planExtra + summaryExtra;

  // แทรกจากล่างขึ้นบน เลขแถวด้านบนจะได้ไม่เลื่อน
  if (planExtra) {
    sheet.insertRowsAfter(q1 - 1, planExtra);
    sheet.setRowHeights(q1, planExtra, sheet.getRowHeight(q1 - 1));
    for (let i = 0; i < planExtra; i++) sheet.getRange(q1 + i, 1, 1, 3).merge();
  }
  if (summaryExtra) {
    sheet.insertRowsAfter(s1 - 1, summaryExtra);
    sheet.setRowHeights(s1, summaryExtra, sheet.getRowHeight(s1 - 1));
    for (let i = 0; i < summaryExtra; i++) {
      sheet.getRange(s1 + i, 1, 1, 4).merge();
      sheet.getRange(s1 + i, 6, 1, 2).merge();
    }
  }
  if (borrow) sheet.deleteRows(p1 - borrow + 1, borrow);

  return r => r - (r > p1 ? borrow : 0) + (r >= s1 ? summaryExtra : 0) + (r >= q1 ? planExtra : 0);
}

function put_(range, value) {
  range.setNumberFormat('@').setValue(value === undefined || value === null || value === '' ? '-' : String(value));
}

function check_(range, on) {
  range.setValue(String(range.getDisplayValue()).replace(/[☐☑]/, on ? CHECKED : UNCHECKED));
}

function fillHeader_(at, s) {
  put_(at(TPL.date), dateSlash_(s.date));
  put_(at(TPL.reporter), s.reporter);
  put_(at(TPL.start), s.start || CONFIG.DEFAULT_START);
  put_(at(TPL.end), s.end || CONFIG.DEFAULT_END);
  put_(at(TPL.projectName), s.project.name || s.project.code);
  put_(at(TPL.location), s.project.location);
  put_(at(TPL.jobType), s.project.jobType);
}

function fillConditions_(sheet, at, s) {
  put_(at(TPL.manpower), s.today.manpower ? `${s.today.manpower} คน` : '');
  Object.keys(TPL.weather).forEach(opt => check_(at(TPL.weather[opt]), !!s.weather && s.weather.indexOf(opt) >= 0));
  if (s.rainTime) put_(at(TPL.rainTime), s.rainTime);
  if (s.temp) put_(at(TPL.temp), s.temp);
  fillMachines_(sheet, TPL.machineRows, s.today.machines);
  const hasImpact = /^มี/.test(s.impact || '');
  check_(at(TPL.impactYes), hasImpact);
  check_(at(TPL.impactNo), !hasImpact);
  if (hasImpact) {
    const detail = s.impact.replace(/^มี(ผลกระทบ)?\s*/, '');
    if (detail) at(TPL.impactYes).setValue(at(TPL.impactYes).getDisplayValue() + ' : ' + detail);
  }
  put_(at(TPL.notes), s.notes);
}

/** rows: { crane: แถว, ... } ที่แปลงเป็นแถวจริงแล้ว */
function fillMachines_(sheet, rows, machines) {
  CONFIG.MACHINES.forEach(m => {
    const v = machines[m.key];
    if (!v) return;
    const label = sheet.getRange(rows[m.key], 4);
    let text = String(label.getDisplayValue()).replace(UNCHECKED, CHECKED);
    if (v.size) text = text.replace(/\.{3,}/, ' ' + v.size + ' ');
    if (m.key === 'other') text += ' : ' + v.text.replace(/\d+\s*(คัน)?\s*$/, '').trim();
    label.setValue(text);
    put_(sheet.getRange(rows[m.key], 6), v.qty);
  });
}

/** เติมตารางงาน (คอลัมน์ A = รายละเอียด, E = %, F = ปัญหา) ส่วนที่เกินจะตัดและใส่ … */
function fillWorkRows_(sheet, lines, firstRow, lastRow, progressCol) {
  const capacity = lastRow - firstRow + 1;
  const shown = lines.slice(0, capacity);
  if (lines.length > capacity) shown[capacity - 1] = { text: shown[capacity - 1].text + ' …' };
  shown.forEach((line, i) => {
    const r = firstRow + i;
    sheet.getRange(r, 1).setNumberFormat('@').setValue(line.text).setFontWeight(line.bold ? 'bold' : 'normal');
    if (progressCol && line.progress) sheet.getRange(r, progressCol + 1).setNumberFormat('@').setValue(line.progress);
    if (progressCol && line.problem) sheet.getRange(r, progressCol + 2).setNumberFormat('@').setValue(line.problem);
  });
}

function fillSafety_(at, s) {
  const acc = (s.accident || '').trim();
  const hasAccident = !!acc && !/^(ไม่มี|-|no|none)/i.test(acc);
  check_(at(TPL.accidentNo), !hasAccident);
  check_(at(TPL.accidentYes), hasAccident);
  put_(at(TPL.accidentDetail), hasAccident ? acc.replace(/^มี(อุบัติเหตุ)?\s*/, '') || acc : '-');
}

function fillPlan_(sheet, at, row, s, lines) {
  at(TPL.planTitle).setValue(`รายละเอียดแผนงานวันถัดไป (Work Plan) วันที่ ${dateSlash_(nextDay_(s.date))}`);
  put_(at(TPL.planManpower), s.plan.manpower ? `${s.plan.manpower} คน` : '');
  const rows = {};
  Object.keys(TPL.planMachineRows).forEach(k => { rows[k] = row(TPL.planMachineRows[k]); });
  fillMachines_(sheet, rows, s.plan.machines);
  fillWorkRows_(sheet, lines, row(TPL.planRows[0]), row(TPL.planRows[1]), 0);
}

/** ช่องลงชื่อ: มีรูปลายเซ็น (ตั้งด้วยคำสั่ง "ลายเซ็น") ใช้รูป ไม่มีก็พิมพ์ชื่อ */
function fillSignatures_(sheet, row, s) {
  const signRow = row(TPL.signRow);
  const date = thaiDateShort_(s.date);
  [[2, s.reporter], [4, s.supervisor || s.reporter]].forEach(([col, name]) => {
    sheet.getRange(row(TPL.signDateRow), col).setNumberFormat('@').setValue(date);
    const fileId = PropertiesService.getScriptProperties().getProperty('SIG_' + name);
    const img = fileId && insertDriveImage_(sheet, fileId, 400, col, signRow - 1);
    if (!img) {
      sheet.getRange(signRow, col).setNumberFormat('@').setValue(name.split(' ')[0]);
      return;
    }
    // วางลายเซ็นให้ฐานอยู่บนเส้นประของช่อง ความสูงไม่เกิน 2 แถว
    const colW = sheet.getColumnWidth(col);
    const rowH = sheet.getRowHeight(signRow);
    const prevH = sheet.getRowHeight(signRow - 1);
    const scale = Math.min((colW - 10) / img.getWidth(), (rowH + prevH - 4) / img.getHeight());
    const w = Math.round(img.getWidth() * scale);
    const h = Math.round(img.getHeight() * scale);
    img.setWidth(w).setHeight(h)
      .setAnchorCellXOffset(Math.round((colW - w) / 2))
      .setAnchorCellYOffset(Math.max(0, prevH + rowH - h - 2));
  });
}

// ===== ภาพถ่ายหน้างาน =====

/** โลโก้บริษัทที่เลือก ชิดขวาบนเหนือกรอบฟอร์ม (แถว 1) */
function placeLogo_(sheet, companyKey) {
  const b64 = COMPANY_LOGO_B64[companyKey];
  if (!b64) return;
  const colW = [];
  for (let c = 1; c <= TPL.lastCol; c++) colW.push(sheet.getColumnWidth(c));
  const img = sheet.insertImage(Utilities.newBlob(Utilities.base64Decode(b64), 'image/png', companyKey + '.png'), 1, 1);
  let h = sheet.getRowHeight(1) - 6;
  let w = Math.round(img.getWidth() * h / img.getHeight());
  if (w > 260) {
    h = Math.round(h * 260 / w);
    w = 260;
  }
  let x = colW.reduce((a, b) => a + b, 0) - w - 4;
  let c = 0;
  while (c < colW.length - 1 && x >= colW[c]) { x -= colW[c]; c++; }
  img.setAnchorCell(sheet.getRange(1, c + 1)).setAnchorCellXOffset(Math.round(x))
    .setAnchorCellYOffset(Math.round((sheet.getRowHeight(1) - h) / 2)).setWidth(w).setHeight(h);
}

/** รูปตามโครงการ -> งาน: [{ code, jobs: [{ title, ids }] }] ตามลำดับที่ส่ง */
function groupPhotos_(photos) {
  const projects = [];
  photos.forEach(photo => {
    const code = photo.project || '';
    let project = projects.find(p => p.code === code);
    if (!project) projects.push(project = { code: code, jobs: [] });
    let job = project.jobs.find(j => j.title === photo.title);
    if (!job) project.jobs.push(job = { title: photo.title, ids: [] });
    job.ids.push(photo.id);
  });
  return projects;
}

/**
 * จัดวางรูปในกรอบ (หน่วย pixel นับจากมุมซ้ายบนของกรอบ): ทุกโครงการมีป้าย PJ หนึ่งแถว
 * งานแต่ละงานมีเลขวงกลมนำหน้า รูปเรียงต่อกันไปทางขวาแล้วขึ้นบรรทัดใหม่
 * เลือกความสูงรูปที่ใหญ่ที่สุดที่ยังวางได้หมดภายในกรอบ
 */
function layoutPhotos_(projects, aspectOf, areaW, rowHeights) {
  const PAD = 8, GAP = 6, LABEL = 28, JOB_GAP = 16;
  const rowTops = [];
  let areaH = 0;
  rowHeights.forEach(h => { rowTops.push(areaH); areaH += h; });

  const tryHeight = (t, force) => {
    const out = { height: t, headers: [], numbers: [], photos: [] };
    let y = 4;
    for (const p of projects) {
      if (p.code) {
        const ri = rowTops.findIndex(top => top >= y - 0.5);
        if (ri < 0) return force ? out : null;
        out.headers.push({ rowIndex: ri, code: p.code });
        y = rowTops[ri] + rowHeights[ri] + GAP;
      }
      let x = PAD;
      p.jobs.forEach((job, n) => {
        job.ids.forEach((id, k) => {
          const w = Math.min(t * aspectOf(id), areaW - 2 * PAD - LABEL);
          const lead = k === 0 ? LABEL : 0;
          if (x + lead + w > areaW - PAD && x > PAD) {
            y += t + GAP;
            x = k === 0 ? PAD : PAD + LABEL;
          }
          if (k === 0) {
            out.numbers.push({ n: n + 1, x: x, y: y });
            x += LABEL;
          }
          out.photos.push({ id: id, x: x, y: y, w: w, h: t });
          x += w + GAP;
        });
        x += JOB_GAP;
      });
      y += t + GAP;
    }
    return force || y - GAP <= areaH - 4 ? out : null;
  };

  for (let t = CONFIG.PHOTO_MAX_HEIGHT; t >= 24; t -= 4) {
    const result = tryHeight(t, false);
    if (result) return result;
  }
  return tryHeight(24, true);
}

function placePhotos_(sheet, s, firstRow, lastRow) {
  if (!s.photos.length) return;
  const colW = [];
  for (let c = 1; c <= TPL.lastCol; c++) colW.push(sheet.getColumnWidth(c));
  const rowH = [];
  for (let r = firstRow; r <= lastRow; r++) rowH.push(sheet.getRowHeight(r));

  const projects = groupPhotos_(s.photos);
  const images = {};
  projects.forEach(p => p.jobs.forEach(j => j.ids.forEach(id => {
    const img = insertDriveImage_(sheet, id, 1000, 1, firstRow);
    if (img) images[id] = img;
  })));
  projects.forEach(p => p.jobs.forEach(j => { j.ids = j.ids.filter(id => images[id]); }));
  projects.forEach(p => { p.jobs = p.jobs.filter(j => j.ids.length); });

  const aspectOf = id => Math.min(2, Math.max(0.5, images[id].getWidth() / images[id].getHeight()));
  const layout = layoutPhotos_(projects, aspectOf, colW.reduce((a, b) => a + b, 0), rowH);

  const anchor = (x, y) => {
    let c = 0;
    while (c < colW.length - 1 && x >= colW[c]) { x -= colW[c]; c++; }
    let r = 0;
    while (r < rowH.length - 1 && y >= rowH[r]) { y -= rowH[r]; r++; }
    return { cell: sheet.getRange(firstRow + r, c + 1), dx: Math.round(x), dy: Math.round(y) };
  };
  const move = (img, x, y, w, h) => {
    const a = anchor(x, y);
    img.setAnchorCell(a.cell).setAnchorCellXOffset(a.dx).setAnchorCellYOffset(a.dy)
      .setWidth(Math.round(w)).setHeight(Math.round(h));
  };

  layout.headers.forEach(hd => {
    sheet.getRange(firstRow + hd.rowIndex, 4).setValue(hd.code)
      .setFontWeight('bold').setFontSize(13).setHorizontalAlignment('center').setVerticalAlignment('middle')
      .setBorder(true, true, true, true, false, false, '#000000', SpreadsheetApp.BorderStyle.SOLID_MEDIUM);
  });
  layout.numbers.forEach(num => {
    const b64 = CIRCLE_PNG_B64[num.n - 1];
    if (!b64) return;
    const img = sheet.insertImage(Utilities.newBlob(Utilities.base64Decode(b64), 'image/png', `n${num.n}.png`), 1, firstRow);
    move(img, num.x, num.y, 24, 24);
  });
  layout.photos.forEach(p => move(images[p.id], p.x, p.y, p.w, p.h));
}

const SHEET_IMAGE_TYPE = /^image\/(png|jpe?g|gif)$/i;

/**
 * รูปจาก Drive ที่ Google Sheets รับได้: ภาพย่อก่อน (Sheets รับรูปไม่เกิน ~1 ล้านพิกเซล) แล้วค่อยไฟล์จริง
 * ข้ามไฟล์ที่ไม่ใช่ PNG/JPEG/GIF (เช่น WebP หรือหน้า error)
 */
function imageCandidates_(fileId, size) {
  const blobs = [];
  const auth = { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() };
  try {
    const meta = UrlFetchApp.fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?fields=thumbnailLink`, {
      headers: auth, muteHttpExceptions: true,
    });
    const link = JSON.parse(meta.getContentText()).thumbnailLink;
    if (link) {
      const res = UrlFetchApp.fetch(link.replace(/=s\d+$/, '=s' + size), {
        headers: Object.assign({ Accept: 'image/jpeg,image/png' }, auth), muteHttpExceptions: true,
      });
      const blob = res.getBlob();
      if (res.getResponseCode() === 200 && SHEET_IMAGE_TYPE.test(blob.getContentType())) blobs.push(blob.setName(fileId + '.jpg'));
    }
  } catch (err) {
    console.warn('ย่อรูปไม่สำเร็จ ' + fileId + ': ' + err.message);
  }
  try {
    const blob = DriveApp.getFileById(fileId).getBlob();
    if (SHEET_IMAGE_TYPE.test(blob.getContentType()) && blob.getBytes().length < 2e6) blobs.push(blob);
  } catch (err) {
    console.warn('เปิดรูปไม่ได้ ' + fileId + ': ' + err.message);
  }
  return blobs;
}

/** วางรูปจาก Drive ลงชีต ลองทีละแบบ ถ้าใส่ไม่ได้ทั้งหมดให้ข้ามรูปนั้น (รายงานยังออกได้) */
function insertDriveImage_(sheet, fileId, size, col, row) {
  for (const blob of imageCandidates_(fileId, size)) {
    try {
      return sheet.insertImage(blob, col, row);
    } catch (err) {
      console.warn(`ใส่รูป ${fileId} ไม่ได้ (${blob.getContentType()}): ${err.message}`);
    }
  }
  return null;
}


// ===== แม่แบบและการส่งออก PDF =====

/** แม่แบบ Google Sheets ใน Drive (สร้างจาก TEMPLATE_XLSX_B64 ครั้งแรกที่ใช้งาน) */
function getTemplateId_() {
  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('TEMPLATE_ID');
  if (id) {
    try {
      if (!DriveApp.getFileById(id).isTrashed()) return id;
    } catch (err) {
      // ไฟล์ถูกลบ -> สร้างใหม่
    }
  }
  const newId = importTemplate_();
  props.setProperty('TEMPLATE_ID', newId);
  return newId;
}

/** อัปโหลดไฟล์ Excel แม่แบบ แล้วให้ Google แปลงเป็น Google Sheets */
function importTemplate_() {
  const xlsx = Utilities.base64Decode(TEMPLATE_XLSX_B64);
  const boundary = 'dailyreport' + Date.now();
  const meta = {
    name: 'แม่แบบ FM_Daily Report (ห้ามลบ)',
    mimeType: 'application/vnd.google-apps.spreadsheet',
    parents: [getRootFolder_().getId()],
  };
  const head = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(meta)}\r\n` +
    `--${boundary}\r\nContent-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n`;
  const payload = Utilities.newBlob(head).getBytes().concat(xlsx).concat(Utilities.newBlob(`\r\n--${boundary}--`).getBytes());
  const res = UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
    method: 'post',
    contentType: 'multipart/related; boundary=' + boundary,
    payload: payload,
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    muteHttpExceptions: true,
  });
  if (res.getResponseCode() !== 200) throw new Error('สร้างแม่แบบไม่สำเร็จ: ' + res.getContentText());
  const id = JSON.parse(res.getContentText()).id;
  // กันกรณีแปลงไฟล์แล้วฟอนต์ไม่ติดมา
  const sheet = SpreadsheetApp.openById(id).getSheets()[0];
  sheet.getRange(1, 1, TPL.lastRow, TPL.lastCol).setFontFamily('Sarabun');
  sheet.setHiddenGridlines(true);
  return id;
}

function exportPdf_(spreadsheetId, gid, lastRow) {
  const params = {
    format: 'pdf', size: 'A4', portrait: 'true', scale: '4', gridlines: 'false', printtitle: 'false',
    sheetnames: 'false', pagenum: 'UNDEFINED', fzr: 'false', attachment: 'false',
    horizontal_alignment: 'CENTER', vertical_alignment: 'TOP',
    top_margin: '0.3', bottom_margin: '0.3', left_margin: '0.25', right_margin: '0.25',
    gid: gid, r1: 0, c1: 0, r2: lastRow, c2: TPL.lastCol,
  };
  const query = Object.keys(params).map(k => `${k}=${params[k]}`).join('&');
  const res = UrlFetchApp.fetch(`https://docs.google.com/spreadsheets/d/${spreadsheetId}/export?${query}`, {
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
  });
  return res.getBlob();
}

function saveSignature_(name, messageId) {
  const res = UrlFetchApp.fetch(`https://api-data.line.me/v2/bot/message/${messageId}/content`, {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  const file = getSubFolder_(getRootFolder_(), 'ลายเซ็น').createFile(res.getBlob().setName(name + '.jpg'));
  PropertiesService.getScriptProperties().setProperty('SIG_' + name, file.getId());
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

function logToSheet_(session, pdfUrl, sheetUrl) {
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
    sheetUrl,
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

// ===== ถามทีละข้อด้วยปุ่ม (Quick Reply) และการ์ดสรุป (Flex Message) =====

const START_PRESETS = ['07.00', '07.30', '08.00', '08.30', '09.00', '09.30', '10.00'];
const END_PRESETS = ['16.00', '16.30', '17.00', '17.30', '18.00', '18.30', '19.00', '19.30', '20.00', '20.30',
  '21.00', '21.30', '22.00'];
const RAIN_PRESETS = ['08.00-10.00', '10.00-12.00', '13.00-15.00', '15.00-17.00', 'ทั้งวัน'];
const BRAND = '#0A9A9A';

const numbers_ = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);
const isPlan_ = s => s.section === 'plan';

/** ขั้นตอนการกรอก: done = กรอกแล้วหรือยัง, ask = คำถามพร้อมปุ่ม */
const STEPS = {
  company: {
    done: s => !!s.company,
    ask: () => quickReply_('🏢 หัวกระดาษรายงานเป็นของบริษัทไหน?',
      CONFIG.COMPANIES.map(c => ({ label: c.label, text: 'หัวกระดาษ: ' + c.label }))),
  },
  reporter: { done: s => !!s.reporter, ask: () => reporterPicker_('👤 ใครเป็นผู้เขียนรายงาน?') },
  supervisor: {
    done: s => !!s.supervisor,
    ask: () => quickReply_('🦺 ใครเป็นผู้ควบคุมงาน?\n(ชื่ออื่นพิมพ์เองได้)',
      CONFIG.REPORTERS.map(n => ({ label: n, text: 'ผู้ควบคุมงาน: ' + n }))),
  },
  project: { done: s => !!s.project.code, ask: () => projectPicker_('📁 วันนี้ทำโครงการไหน?') },
  start: {
    done: s => !!s.start,
    ask: () => quickReply_('⏰ เริ่มงานกี่โมง?\n(เวลาอื่นพิมพ์เองได้ เช่น 07.15)',
      START_PRESETS.map(t => ({ label: t, text: 'เริ่มงาน: ' + t }))),
  },
  end: {
    done: s => !!s.end,
    ask: () => quickReply_('⏰ เลิกงานกี่โมง?\n(เวลาอื่นพิมพ์เองได้ เช่น 20.45)',
      END_PRESETS.map(t => ({ label: t, text: 'เลิกงาน: ' + t }))),
  },
  manpower: {
    done: (s, sec) => !!sec.manpower,
    ask: s => quickReply_(`👷 คนงาน${isPlan_(s) ? 'พรุ่งนี้' : ''}กี่คน?\n(เกิน 12 คน พิมพ์ตัวเลขได้เลย)`,
      numbers_(1, 12).map(n => ({ label: `${n} คน`, text: `คน: ${n}` }))),
  },
  weather: {
    done: s => !!s.weather,
    ask: () => quickReply_('🌤️ สภาพอากาศวันนี้?', CONFIG.WEATHER_OPTIONS.map(w => ({ label: w, text: 'อากาศ: ' + w }))),
  },
  rain: {
    done: s => !/ฝนตก/.test(s.weather || '') || !!s.rainTime,
    ask: () => quickReply_('🌧️ ฝนตกช่วงไหน?\n(หรือพิมพ์เอง เช่น 13.30-14.00)',
      RAIN_PRESETS.map(t => ({ label: t, text: 'ฝนตกช่วง: ' + t }))),
  },
  temp: {
    done: s => !!s.temp,
    ask: () => quickReply_('🌡️ อุณหภูมิเฉลี่ยกี่องศา?', numbers_(28, 39).map(n => ({ label: `${n}°C`, text: `อุณหภูมิ: ${n}` }))),
  },
  machines: { done: (s, sec) => !!sec.machinesDone, ask: (s, sec) => machinePicker_(s, sec) },
  impact: {
    done: s => !!s.impact,
    ask: () => quickReply_('⛈️ สภาพอากาศมีผลกระทบต่อการทำงานไหม?', [
      { label: 'ไม่มีผลกระทบ', text: 'ผลกระทบ: ไม่มี' }, { label: 'มีผลกระทบ', text: 'ผลกระทบ: มี' }]),
  },
  accident: {
    done: s => !!s.accident,
    ask: () => quickReply_('🦺 วันนี้มีอุบัติเหตุไหม?', [
      { label: 'ไม่มีอุบัติเหตุ', text: 'อุบัติเหตุ: ไม่มี' }, { label: 'มีอุบัติเหตุ', text: 'อุบัติเหตุ: มี' }]),
  },
  problem: { done: () => true, ask: () => quickReply_('✏️ พิมพ์ปัญหา/อุปสรรคของงานนี้ได้เลย', []) },
  notes: { done: () => true, ask: () => quickReply_('🗒️ พิมพ์หมายเหตุได้เลย', [{ label: 'ไม่มี', text: 'หมายเหตุ: -' }]) },
  work: { done: (s, sec) => !!sec.workDone, ask: (s, sec) => workPrompt_(s, sec) },
  wrap: { done: () => false, ask: s => wrapPrompt_(s) },
};

const FLOW = {
  today: ['company', 'reporter', 'supervisor', 'project', 'start', 'end', 'manpower', 'weather', 'rain', 'temp', 'machines', 'impact', 'accident',
    'work', 'wrap'],
  plan: ['manpower', 'machines', 'work', 'wrap'],
};

/** ขั้นถัดไปที่ยังไม่ได้กรอก (เรียกใน withSession_ เพื่อจำว่ากำลังรอคำตอบข้อไหน) */
function advance_(s) {
  s.awaiting = FLOW[s.section].find(k => !STEPS[k].done(s, s[s.section]));
  return s.awaiting;
}

function question_(s, step) {
  const qty = step.match(/^qty:(\w+)$/);
  if (qty) return quantityPicker_(qty[1]);
  return STEPS[step].ask(s, s[s.section]);
}

function withPrefix_(message, prefix) {
  message.text = prefix + '\n\n' + message.text;
  return message;
}

/** พิมพ์แค่ตัวเลข/เวลา ตอบคำถามที่ค้างอยู่ได้เลย เช่น ถามคนงานแล้วพิมพ์ "15" */
function expandShortAnswer_(s, text) {
  const t = text.trim();
  const step = s.awaiting || '';
  if (step === 'manpower' && /^\d+\s*(คน)?$/.test(t)) return 'คน: ' + t;
  if (step === 'temp' && /^\d+(\.\d+)?\s*(°C|องศา)?$/.test(t)) return 'อุณหภูมิ: ' + t;
  if (step === 'start' && /^\d/.test(t)) return 'เริ่มงาน: ' + t;
  if (step === 'end' && /^\d|ทุ่ม/.test(t)) return 'เลิกงาน: ' + t;
  if (step === 'group' && /^(pj\s*)?\d[\d,\s]*$/i.test(t)) return 'PJ ' + t.replace(/^pj\s*/i, '');
  if (step === 'project' && /^(pj\s*)?\d+$/i.test(t)) return 'โครงการ: ' + normalizeCode_(t);
  if (step === 'rain' && /^\d/.test(t)) return 'ฝนตกช่วง: ' + t;
  if (step === 'notes' && !/[:：]/.test(t)) return 'หมายเหตุ: ' + t;
  if (step === 'problem' && !/[:：]/.test(t)) return 'ปัญหา: ' + t;
  if (step === 'supervisor' && !/[:：]/.test(t) && !/^\d+\s*[.)]/.test(t)) return 'ผู้ควบคุมงาน: ' + t;
  if (step === 'qty:other' && !/[:：]/.test(t)) return 'อื่นๆ: ' + t;
  const qty = step.match(/^qty:(\w+)$/);
  const machine = qty && CONFIG.MACHINES.find(m => m.key === qty[1]);
  if (machine && /^\d+/.test(t)) return `${machine.aliases[0]}: ${t}`;
  return text;
}

function machineText_(sec) {
  return CONFIG.MACHINES.filter(m => sec.machines[m.key])
    .map(m => `${m.label} ${sec.machines[m.key].qty || sec.machines[m.key].text}`).join(', ');
}

function machinePicker_(s, sec) {
  const chosen = machineText_(sec);
  const text = chosen ? `🚗 ตอนนี้มี: ${chosen}\nมีรถ/เครื่องจักรอื่นอีกไหม?`
    : `🚗 ${isPlan_(s) ? 'พรุ่งนี้' : 'วันนี้'}ใช้รถ/เครื่องจักรอะไรบ้าง?`;
  const options = [{ label: chosen ? '✅ ครบแล้ว' : '❌ ไม่มี', text: 'เครื่องจักร: ' + (chosen ? 'ครบ' : 'ไม่มี') }];
  CONFIG.MACHINES.forEach(m => {
    const v = sec.machines[m.key];
    options.push({ label: v ? `${m.label} (${v.qty || v.text})` : m.label, data: 'ask=qty:' + m.key });
  });
  return quickReply_(text, options);
}

function quantityPicker_(key) {
  const m = CONFIG.MACHINES.find(x => x.key === key);
  if (key === 'other') {
    return quickReply_('✏️ พิมพ์ชื่อเครื่องจักรและจำนวน\nเช่น  รถแบคโฮ 1', [{ label: '↩️ ย้อนกลับ', data: 'ask=machines' }]);
  }
  const hint = m.sized ? '\n(ระบุขนาดได้ เช่น พิมพ์ "1 ขนาด 25")' : '';
  return quickReply_(`${m.label}กี่คัน?${hint}`, numbers_(1, 8).map(n => ({ label: `${n} คัน`, text: `${m.aliases[0]}: ${n}` }))
    .concat([{ label: '🗑️ ไม่มี', text: `${m.aliases[0]}: -` }]));
}

/** เลขข้อถัดไปของโครงการที่กำลังกรอก */
function nextNumber_(sec) {
  return sec.items.filter(it => it.group === sec.group).length + 1;
}

/** งานล่าสุดของวันนี้ที่ยังไม่ได้กด "งานนี้เสร็จ" (ยังส่งรูป/ตอบปัญหาอุปสรรคได้) */
function openJob_(s) {
  if (isPlan_(s)) return null;
  const last = s.today.items[s.today.items.length - 1];
  return last && !last.done ? last : null;
}

function workButtons_(s) {
  const plan = isPlan_(s);
  if (openJob_(s)) {
    return [{ label: '📷 ถ่ายรูป', camera: true }, { label: '🖼️ เลือกรูป', cameraRoll: true },
      { label: '➡️ งานนี้เสร็จ', data: 'jobdone', display: '➡️ งานนี้เสร็จ' }];
  }
  const options = [];
  options.push({ label: '➕ งานโครงการอื่น', data: 'nextproject', display: '➕ งานโครงการอื่น' });
  const end = plan ? '🏁 จบแผนพรุ่งนี้' : '🏁 จบงานวันนี้';
  options.push({ label: end, data: 'endwork', display: end });
  return options;
}

/**
 * ขั้นกรอกงาน — lead: ข้อความนำ (งานที่เพิ่งบันทึก / รูปที่ได้รับ / โครงการใหม่)
 * บอกเลขข้อถัดไปพร้อมตัวอย่าง ให้พิมพ์ตามได้ทันที
 */
function workPrompt_(s, sec, lead, firstOfProject) {
  const plan = isPlan_(s);
  const n = nextNumber_(sec);
  const example = `${n}. วางท่อ HDPE${plan ? '' : ' 50%'}`;
  let text;
  if (!lead) {
    text = plan ? `🗓️ พิมพ์งานพรุ่งนี้ทีละข้อ\nเช่น  ${example}`
      : `📝 พิมพ์งานทีละข้อ แล้วส่งรูปของงานนั้นตาม\nเช่น  ${example}`;
  } else if (openJob_(s) && !firstOfProject) {
    text = `${lead}\n\n📷 ส่งรูปของงานนี้ได้เลย\nครบแล้วกด "➡️ งานนี้เสร็จ"`;
  } else {
    text = `${lead}\n\nพิมพ์งานข้อ ${n}\nเช่น  ${example}`;
  }
  return quickReply_(text, workButtons_(s));
}

function wrapPrompt_(s) {
  if (isPlan_(s)) {
    return quickReply_('🏁 บันทึกแผนพรุ่งนี้แล้ว', [
      { label: '📋 ดูสรุปก่อนส่ง', data: 'summary' },
      { label: '✅ ส่งรายงาน', text: 'ส่ง' },
      { label: '✏️ แก้ไข', data: 'edit' },
    ]);
  }
  return quickReply_('🏁 จบงานวันนี้แล้ว\nมีแผนงานพรุ่งนี้ไหม?', [
    { label: '🗓️ กรอกแผนพรุ่งนี้', text: 'แผนพรุ่งนี้' },
    { label: '📋 ดูสรุปก่อนส่ง', data: 'summary' },
    { label: '✅ ส่งรายงานเลย', text: 'ส่ง' },
    { label: '↩️ เพิ่มงานวันนี้', data: 'morework', display: '↩️ เพิ่มงานวันนี้' },
  ]);
}

function editMenu_() {
  return quickReply_('✏️ ต้องการแก้ข้อไหน?', [
    { label: '🏢 หัวกระดาษ', data: 'ask=company' },
    { label: '👤 ผู้เขียนรายงาน', data: 'ask=reporter' },
    { label: '🦺 ผู้ควบคุมงาน', data: 'ask=supervisor' },
    { label: '📁 โครงการ', data: 'ask=project' },
    { label: '⏰ เวลา', data: 'ask=start' },
    { label: '👷 คนงาน', data: 'ask=manpower' },
    { label: '🌤️ อากาศ', data: 'ask=weather' },
    { label: '🌡️ อุณหภูมิ', data: 'ask=temp' },
    { label: '🚗 เครื่องจักร', data: 'ask=machines' },
    { label: '⛈️ ผลกระทบ', data: 'ask=impact' },
    { label: '🦺 อุบัติเหตุ', data: 'ask=accident' },
    { label: '🗒️ หมายเหตุ', data: 'ask=notes' },
    { label: '🗓️ แผนพรุ่งนี้', text: 'แผนพรุ่งนี้' },
  ]);
}

/** การ์ดสรุปรายงาน พร้อมปุ่มแก้ไข / ส่งรายงาน */
function summaryFlex_(s) {
  const row = (label, value) => ({
    type: 'box', layout: 'baseline', spacing: 'sm',
    contents: [
      { type: 'text', text: label, size: 'sm', color: '#8C8C8C', flex: 3 },
      { type: 'text', text: String(value || '-'), size: 'sm', color: '#222222', flex: 6, wrap: true },
    ],
  });
  const heading = text => ({ type: 'text', text: text, weight: 'bold', size: 'sm', color: BRAND, margin: 'lg' });
  const workLines = (items, withProgress) => {
    const lines = [];
    groupItems_(items).forEach(g => {
      if (g.group) lines.push({ type: 'text', text: g.group, size: 'sm', weight: 'bold', margin: 'sm' });
      g.items.forEach((it, i) => lines.push({
        type: 'text', size: 'sm', wrap: true,
        text: `${i + 1}. ${it.title}${withProgress && it.progress ? '  ' + it.progress : ''}` +
          (withProgress && it.problem ? `\n   ⚠️ ${it.problem}` : ''),
      }));
    });
    return lines.length ? lines : [{ type: 'text', text: 'ยังไม่มี', size: 'sm', color: '#8C8C8C' }];
  };
  const time = `${s.start || CONFIG.DEFAULT_START} - ${s.end || CONFIG.DEFAULT_END}`;
  const weather = [s.weather, s.rainTime && `ฝน ${s.rainTime}`, s.temp && `${s.temp}°C`].filter(Boolean).join(' • ');

  const body = [
    row('หัวกระดาษ', (CONFIG.COMPANIES.find(c => c.key === s.company) || {}).label),
    row('ผู้รายงาน', s.reporter),
    row('ผู้ควบคุมงาน', s.supervisor),
    row('เวลา', time),
    row('คนงาน', s.today.manpower && `${s.today.manpower} คน`),
    row('อากาศ', weather),
    row('เครื่องจักร', machineText_(s.today) || (s.today.machinesDone ? 'ไม่มี' : '')),
    row('ผลกระทบ', s.impact),
    row('อุบัติเหตุ', s.accident),
    heading(`งานวันนี้  •  📷 ${s.photos.length} รูป`),
  ].concat(workLines(s.today.items, true));
  if (s.plan.items.length || s.plan.manpower) {
    body.push(heading('แผนพรุ่งนี้'));
    if (s.plan.manpower || machineText_(s.plan)) {
      body.push({ type: 'text', size: 'sm', wrap: true, color: '#555555',
        text: [s.plan.manpower && `คนงาน ${s.plan.manpower} คน`, machineText_(s.plan)].filter(Boolean).join(' • ') });
    }
    body.push(...workLines(s.plan.items, false));
  }

  return {
    type: 'flex',
    altText: 'สรุปรายงานประจำวัน',
    contents: {
      type: 'bubble',
      header: {
        type: 'box', layout: 'vertical', backgroundColor: BRAND, paddingAll: '16px',
        contents: [
          { type: 'text', text: 'รายงานประจำวัน', color: '#FFFFFF', weight: 'bold', size: 'lg' },
          { type: 'text', text: `${s.project.code || 'ยังไม่เลือกโครงการ'}  •  ${thaiDateShort_(s.date)}`,
            color: '#E0F5F5', size: 'sm' },
        ],
      },
      body: { type: 'box', layout: 'vertical', spacing: 'sm', contents: body },
      footer: {
        type: 'box', layout: 'horizontal', spacing: 'sm',
        contents: [
          { type: 'button', style: 'secondary', height: 'sm', action: { type: 'postback', label: '✏️ แก้ไข', data: 'edit' } },
          { type: 'button', style: 'primary', color: BRAND, height: 'sm', action: { type: 'message', label: '✅ ส่งรายงาน', text: 'ส่ง' } },
        ],
      },
    },
  };
}

/** ปุ่มที่กดแล้วไม่ต้องแสดงข้อความในแชต (เปิดคำถาม, ดูสรุป, เมนูแก้ไข) */
function handlePostback_(event) {
  const data = event.postback.data;
  const token = event.replyToken;
  if (data === 'summary') {
    const session = loadSession_(event.source);
    return reply_(token, session ? summaryFlex_(session) : 'ยังไม่มีรายงานที่ค้างอยู่');
  }
  if (data === 'edit') return reply_(token, editMenu_());
  if (data === 'jobdone') {
    const session = loadSession_(event.source);
    const job = session && openJob_(session);
    if (!job) return reply_(token, question_(session || newSession_(event.source), 'work'));
    return reply_(token, quickReply_(`⚠️ งาน "${job.title}" มีปัญหา/อุปสรรคไหม?`, [
      { label: '✅ ไม่มี', text: 'ปัญหา: ไม่มี' },
      { label: '⚠️ มี', data: 'ask=problem', display: '⚠️ มีปัญหา/อุปสรรค' },
    ]));
  }
  if (data === 'nextproject-main') {
    withSession_(event.source, s => { s.awaiting = 'project'; });
    return reply_(token, '📁 พิมพ์รหัสโครงการ\nเช่น  PJ 950');
  }
  if (data === 'nextproject') {
    withSession_(event.source, s => { s.awaiting = 'group'; });
    return reply_(token, '📁 พิมพ์รหัสโครงการถัดไป\nเช่น  PJ 69014');
  }
  if (data === 'endwork' || data === 'morework') {
    const session = withSession_(event.source, s => {
      if (data === 'morework') s.section = 'today';
      s[s.section].workDone = data === 'endwork';
      advance_(s);
    });
    return reply_(token, question_(session, session.awaiting));
  }
  const ask = data.match(/^ask=(.+)$/);
  if (!ask) return;
  const session = withSession_(event.source, s => {
    if (!ask[1].startsWith('qty:') && ask[1] !== 'machines' && ask[1] !== 'manpower') s.section = 'today';
    s.awaiting = ask[1];
  });
  reply_(token, question_(session, ask[1]));
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
  if (!options.length) return { type: 'text', text: text };
  return {
    type: 'text',
    text: text,
    quickReply: {
      items: options.slice(0, 13).map(o => ({ type: 'action', action: quickReplyAction_(o) })),
    },
  };
}

/** { label, text } = ส่งข้อความ, { label, data } = postback, { camera / cameraRoll } = เปิดกล้อง/อัลบั้ม */
function quickReplyAction_(o) {
  const label = o.label.slice(0, 20);
  if (o.camera) return { type: 'camera', label: label };
  if (o.cameraRoll) return { type: 'cameraRoll', label: label };
  if (o.data) return { type: 'postback', label: label, data: o.data, displayText: o.display };
  return { type: 'message', label: label, text: o.text };
}

function reporterPicker_(text) {
  return quickReply_(text, CONFIG.REPORTERS.map(n => ({ label: n, text: 'ผู้รายงาน: ' + n })));
}

/** ปุ่มเลือกโครงการ (12 โครงการล่าสุด) + ปุ่มเพิ่มโครงการ */
function projectPicker_(text) {
  const options = Object.keys(getProjects_()).slice(-12)
    .map(code => ({ label: code, text: 'โครงการ: ' + code }));
  options.push({ label: '➕ โครงการใหม่', data: 'nextproject-main', display: '➕ โครงการใหม่' });
  return quickReply_(text || 'เลือกโครงการ 👇 (หรือพิมพ์รหัส เช่น PJ 950)', options);
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

// ===== รันครั้งแรกจากหน้า Editor เพื่อขอสิทธิ์และสร้างโฟลเดอร์/ชีต/แม่แบบ =====

function setup() {
  token_();
  const folder = getRootFolder_();
  const sheet = getSheet_();
  UrlFetchApp.fetch('https://api.line.me/v2/bot/info', {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  const templateId = getTemplateId_();
  setupRichMenu();
  console.log('โฟลเดอร์: ' + folder.getUrl());
  console.log('ชีตบันทึก: ' + sheet.getParent().getUrl());
  console.log('แม่แบบฟอร์ม: https://docs.google.com/spreadsheets/d/' + templateId);
  console.log('พร้อมใช้งาน ✅ ต่อไปให้ Deploy เป็น Web app');
}

/** ติดตั้งเมนูกรอบสี่เหลี่ยมใต้แชต (Rich Menu) ให้ทุกคนที่แอดบอท — รันซ้ำได้ จะแทนเมนูเดิม */
function setupRichMenu() {
  const props = PropertiesService.getScriptProperties();
  const auth = { Authorization: 'Bearer ' + token_() };
  const old = props.getProperty('RICHMENU_ID');
  if (old) {
    UrlFetchApp.fetch('https://api.line.me/v2/bot/richmenu/' + old, { method: 'delete', headers: auth, muteHttpExceptions: true });
  }

  const spec = Object.assign({ selected: true, name: 'เมนูหลัก', chatBarText: 'เมนู' }, RICHMENU_SPEC);
  const created = lineApi_('richmenu', spec);
  if (created.getResponseCode() !== 200) throw new Error('สร้างเมนูไม่สำเร็จ: ' + created.getContentText());
  const id = JSON.parse(created.getContentText()).richMenuId;

  const upload = UrlFetchApp.fetch(`https://api-data.line.me/v2/bot/richmenu/${id}/content`, {
    method: 'post', contentType: 'image/jpeg', payload: Utilities.base64Decode(RICHMENU_JPG_B64),
    headers: auth, muteHttpExceptions: true,
  });
  if (upload.getResponseCode() !== 200) throw new Error('อัปโหลดรูปเมนูไม่สำเร็จ: ' + upload.getContentText());

  const setDefault = UrlFetchApp.fetch(`https://api.line.me/v2/bot/user/all/richmenu/${id}`, {
    method: 'post', headers: auth, muteHttpExceptions: true,
  });
  if (setDefault.getResponseCode() !== 200) throw new Error('ตั้งเมนูไม่สำเร็จ: ' + setDefault.getContentText());
  props.setProperty('RICHMENU_ID', id);
  console.log('ติดตั้งเมนูเรียบร้อย ✅ (ปิดแชตแล้วเปิดใหม่เพื่อดูเมนู)');
}

/** สร้างแม่แบบใหม่จากโค้ด (ใช้หลังอัปเดตโค้ดที่มีแม่แบบเวอร์ชันใหม่) */
function rebuildTemplate() {
  PropertiesService.getScriptProperties().deleteProperty('TEMPLATE_ID');
  console.log('แม่แบบใหม่: https://docs.google.com/spreadsheets/d/' + getTemplateId_());
}

/** ทดสอบสร้างรายงานตัวอย่าง (มีรูปตัวอย่าง) โดยไม่ต้องผ่านไลน์ — กด Run ในหน้า Editor */
function testReport() {
  const session = newSession_({ userId: 'test' });
  session.reporter = CONFIG.REPORTERS[0];
  session.supervisor = CONFIG.REPORTERS[1];
  session.company = CONFIG.COMPANIES[0].key;
  applyText_(session, [
    'โครงการ: PJ 942', 'เวลา: 08.00-21.00', 'คน: 9', 'อากาศ: ปกติ', 'อุณหภูมิ: 33', 'รถยนต์: 4',
    'ผลกระทบ: ไม่มี', 'อุบัติเหตุ: ไม่มี',
    'PJ 942', '1. ขุดดินวางท่อ (ต่อ) 60%', '2. วางท่อ HDPE ประปาภายนอกอาคาร (ต่อ) 50%', '3. ลงฐานออฟฟิศ 100%',
    '4. ย้ายเต็นท์เก็บอุปกรณ์ 0%',
    'PJ 69014', '1. ติดตามงานขุดปรับคันดินบ่อน้ำเสีย 5%',
    'แผนพรุ่งนี้', 'คน: 8', 'รถยนต์: 3',
    'PJ 942', '1. ขุดดินวางท่อ (ต่อ)', '2. วางท่อ HDPE ประปาภายนอกอาคาร (ต่อ)', '3. ย้ายเต็นท์เก็บอุปกรณ์',
  ].join('\n'));

  // รูปตัวอย่าง: 5 รูปงานที่ 1, 3 รูปงานที่ 2, 1 รูปงานที่ 3
  const folder = getSubFolder_(getRootFolder_(), 'รูปภาพ', 'ทดสอบ');
  const sample = [[0, 5], [1, 3], [2, 1]];
  let n = 0;
  sample.forEach(([itemIndex, count]) => {
    const item = session.today.items[itemIndex];
    for (let i = 0; i < count; i++, n++) {
      try {
        const blob = UrlFetchApp.fetch(`https://picsum.photos/seed/daily${n}/${n % 4 === 3 ? '600/800' : '800/600'}.jpg`).getBlob();
        const file = folder.createFile(blob.setName(`test${n}.jpg`));
        session.photos.push({ id: file.getId(), project: item.group, title: item.title });
      } catch (err) {
        console.warn('โหลดรูปตัวอย่างไม่ได้: ' + err.message);
      }
    }
  });
  Utilities.sleep(3000); // รอ Drive สร้างภาพย่อ
  const result = buildReport_(session);
  console.log('PDF: ' + result.pdfUrl);
  console.log('ไฟล์ Sheets: ' + result.sheetUrl);
}

// ===== ข้อมูลฝัง (สร้างโดย tools/embed_assets.py — ห้ามแก้ด้วยมือ) =====
const TEMPLATE_XLSX_B64 = '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';

const CIRCLE_PNG_B64 = [
  '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',
];

const COMPANY_LOGO_B64 = {
  aceken: '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',
  chemmettle: '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',
  metryscape: 'iVBORw0KGgoAAAANSUhEUgAAAQsAAACgCAMAAAAsJ7n5AAAASFBMVEX///////7+///+/v/9///9/v/9/v78/v/8/f77/P319vbb29zExcaYmJpWVlk5Oj42ODs2Njo1Njs1Njo1Njk0NjsxMjUnKCxHi5B2AAARiElEQVR42u2daXuzrBKAfbVGQBaTWPz///TMDLuaxLRJj/YpH3o1buDNMAuMWrWvKrySfcXbnyy86lXFu1ddrnphw5T5WRiAwqgX1vhKFnLSPwkDUOhpryyUtT8IA1FYu1sWk/k5GITC7FcupsHYH9IZDsV+WUhrhuFnYDgU1z3LxWR/RjI8iv2yqKVSGmG8XWc4FJf9soBrVWBWQXDfLRlBKvbLglW9lGBKru+GkVDsWl9YO1AT3wkjQ7FrFr6J74SRo7ju2qZCea9kFCj2bVMnNKtvhFGi2LNcKCz6jTCiMd05i7arqASt8QYYM6nYsU1twKZCUU4u3gBjgWLfNjXqizfAWKLYuR0ZhiFr6ithzHXFQXytd8BYkYqd2xH9LhirKPZrR5iPzd4BY22A7N2OqGm4vgGGl4rDsHD64rooL4CxPkD2zcKa4foGGDdRHCM2u+am9ZtzoHNdMQzjoWIzM9pX+RkzqbgMozWfl52zqFNsNhplcqn+Boz5ABnskCz3ruc7Q2xmhby+RDIWKEYrhdk7C1ZnsdnYV/L8AslY6ApAUfW7Z+FsqiU3/HPsWSWHb0vGcoAACoYsxsPEZsCiEt+HsTZAKl4dgQWtm41nz4IDHGO/Y1oXAwSlgrNDsHCxWWSBW74jGSQApTEFFO0RWNAcn4/NHIvvwZih8AOkPQQL1oV1s8iinQ+TJ2AsUYyEomXH0RfXnMXXYTgUc13RHoaFjLFZZPFVGEtd4aXiQCx8bJZYfE1n3BwgRxojPjbLWHxFMhYobEJxDBZNis1yFs/DWKKwCcVxbKqPzQoWz8K4KxUHsaknF5st5OJJGPd0xZH0BcVmpe68BUPeuImlMS1RHMiOpNiMt3MYhdzfgLEwpnMUx/W1npWMB7riMPqiSetmSxbbYGxAcQw7whaxWXtvmKzAKHXFZRXFQeQirZutsXgM47GuOJYduaUvNsDYMkAOHZvd1RmFNXloTI8lF2ux2VbJ8FJxuT9ADh6bbZOMjQPkOGNkPTbbYlq3oziOTV2NzTbA2KgrDmVT/brZHRbrMObG9HwTxXFs6iN9cSM2UbrUqHdQHD82u69AR1vq03soDhSbncfxIYulZKR8nssjFEfRF/dis7uScd2oKw41x3cnNtsG4yGKY8hF3SswIttYLIZJyrp5gOKXxGYPYVw2oPgtsdkjGI8HSHvodbMnYAyjeYzi98Rm903rr2FBNvVhbPYgah1+xxjZGJs9cMd/h+4MOY1PyMWXYPyq2OzBTNfwC3yt7bHZ9yTj+Otmz8D4BbFZtT02+45k/LrY7BswjuJfhIeWn2OxMvP7C+b4vqIvntUZh1krGsYt81pbJON65DUBb1NdqDr2/LkiNrvjR4vN8Fmap0uvSxhHXkOsU2x2HUGNyueKSm+LOPzach6bXa/TF8psAvTAOQes7VWIzXCa//kyLCY/r0fORcGsxvP1VeWwOUor7wJ5C4yj+VovhHE9ZE5jFpu9EMZ4xFzX+J7GV0vGAXOg3brZhF74S4uH0RQszn7frtfNzq8vIAPLZybcrl3HZpfxDWXlWZrP3csFvvv4DeVsxrNs8mesRl/RfudyRP/GkipqeLZZNGyvduR9JaunvrF9TywYf18pev/W9h2xOHr5Y/HH4o/FH4tvsWDt9q3//8LeyuJj7fJdW69aTrZlK5tbxJu/2Q1TyW7ZUFbVMwc41MnWzfC8/rssuKiW34bqan+BdS/o0dZUez1zkVjuMzHuftWz1obt+YVCFwlRbEieWJ2Ru+O63WEB/r4WzRzciTPtAqS5cyygOayd+98CeiXbKqrqxHIPOmsB/pTOl4Y7Fpjdg8fnIuC2KyUl7GjzjmIfYvYtq+Shw1nxg1/zVjfdRhYrEQ9G5O4BIP/Ueih07KOtg9ay8a944Ro2TvEtJydhJjuZHlnwSihtcaZQqz71HcMpM9wOewz0SC619PUs3nWp9Xg9KgYv4u+j0kX7Jl1tZWGm5VO00r3GKDxh52fxfaQYn7uj4BGKDSwM/R7gRnRfua7vR/xei+92OsaHm/SRLuuPt7r3WpGdKmXcdrgw7BB1FJmuY3oW0QtN4bIdRkCsvHhVuDG12z7BYv5OBsaEr7KUgDGxcFsvl6GUC4MPh1i8kUmHcYBbPW3eYACOZBj9bwnbZEcI030TGGNwcWNG2oH3kcWm/L++/JgVsUASeoReGMMuYDFcCrlgW1kMIHe8K0eICSx0KnAf/q6l+w294fbI2rMYDf68Ag3fgHD7qFEaB8Z1rPtoh9W4DmlsvEEvXROIPFRtbTGAfRV99gYZYDHaUZ60vdhxHPqaexZj1nC1ncVoZjXKafAtzjTyBzYkkvfrh/D7A3V4aCgQqCsmqbPCS7fisHBcJt1wN9ItDC6yK6Af+v9YqNsMV6totVpIbTKxYHh+MaNDLLTRNA2tTZj4wjEC1UcbU2+2I3D9KKJxhnGwSyWSsbj5W1f8xHO+oC6xZSgY/vst/iVtPfSdgX4E1wDumocZInyvHeifCjwMVgONatYCaFkaNshikqLHle4eR64m+fYs+JO+lmPhhZj0EwfVb67fYIH/6rQrCQbo0Tivj+tuw3XoK4EWhdeZbqXe5cHPyKUbQYHWQu3TRDtiBB7ESU5HLfCE77A4Z0sPvvMSi5g/wrezOGW7SBPDeBAMCYEonMKTyyN2sfOnQj8zkqHkcLLyPTz42UFQOLrukk0dBF6gYbxR0zVnAS2+NwN0k0UcE9hf1+GSWGRTbJtYNBwHQyYXTv/gT2mzwY6eB2ptKZJ36QfXrRSdRqNK19MQ+5zGiMILfDjrllhMWX4Me0pfXP0o9J2Y9EXNVSzl1xlvyQXCk7mkYW9PaLjxbxzrCH1Em0qOVqKGkvMfW51578/QyqJWZ1NVjxIANwJmKejOgSyUa7Zs+HYWV3MenXj7z1/itfwrIwF8yh7ZwEII8J9B+X6aPvQH3jZ4Irrsc9wK8gL2dFB9plp8366uTmF9YH9ssC7E4tOCk1VhQ02yI0OWH7O+krDOAq08SjE+aQ4dc0Y5NInFNWWPPGThjrUlNfdRzcGi8GWDF90US37VFF9/QCya9UVLB6Go1skF9IDsZSZ1xCK5nU+yEE6KyQmFinCcfEkuLs7vBGcpGqaWkrtA+IbLzDjxqpbobyO85H8VXvdSLCrf4NMpskBth5yie44shq/KhRHo+UyEBJ3QyOJZfXHBZUW86eKLkc7hvA7Ozcruj6GfZegLk2glg75Ya3vD0ZnEvCj6qmx40ymyuFw/P2GkTPGZLerLmE2n+tUJoHUWMOAEKnnwW8n/qTIWT9qRTxLKYb7ySQ7XsHKXoPIou3Gw4b0YN+wI+SPnM8UXqJidh+9Z0FDQSqQ4tbQjT9hUZHHCOzn7UcAyFs/6F32P/TYmzTl3PjKp8P6UH5gc503Iv2iSVklXB1s6pLQ35ygTi/Mo3ZxJvLob49G/4E+yqMiYUkjFP3IWLBT0ZbbZVGnP8A8r7tud3BRvHXQRdkdDMsTxFLwlvzO02IUiNiouL3hOLs4kAm0C6Hwt9HR8eZKF6x60VgWLjzqUbquv5Z3umZosD8a2gJeF0QinOQh/bxiPwE3jDA7sgfEpRZNZ26S4oKGgYb3u7DF4yQJt74N3vuVPzPF5uUiRes6Ci1i2+uDR6T6x2ywAvfM5QToUdG16lTQMhRHiVO7iVIfUxWw2qIA+WDRicVmk5ocxkpr+JIsO20utTSxw7mk5f/EoHuGlt73KAlxwnGRRSkIvoy5k+czXMA1a0/yFJSXprx3ntcmX4Kc7LIr5i9XPIK+zuDhXD+Ar8lUKFnY5r7UhTk1zNrcOluRXTH72yrhJGGTU0LzW1T3k6Mca48mO5peP+mIpF0M+4yk3sxhRLijud7MeNQs+OIbZn5/hvQRlltAdFnHOIo6SpVyg/E+jcdOd2dPcjIE7itN+cSL0xEjQUijj5oFoOJIPvi4X6TtYn+N2FmbwIQBzqrjO5aJM4i7v3eb+rVdvYdiPZrbTls5wTbNW1PvZDLYzskL5PTQPTlbILq5m0FtxIcKaXBRl2xjp3KoG7/IggLl8IBCVRSaSOEV9fXJHzbKW3FIEc0sUSXn6nYXLgcoRi6jmr4Wt/FPRsIcWALir+pRmdcKqDI9NzctiVWfTPDjcAk1mFiza5K3V8yUotnZU9rvJ18fa2weTY7Fc8fKicUrrZk04u14kSMEdfqw6lot1vW0snGO5spzZrS5NstlRN3+zBwffXU5d7Fm7mmvhql/Jvrie+pdz8FcWLBr2j5Rug1xU/0ppHrJg4l8p/CEL3v8rhdfd3xjZPEbaf0V3sj+b+udffI0F5z9VNVvk6vH/M4tZWAERVN38DIp5BPXah0G+wqJcMmCtUuuLly9Hga+UyZbD6DHG5v+aW1yFJTBMsOpo0uMxi65jX36IhcVpzH42/9k/eniMvZlUFVYYcPqJWJgNctF9XZ7DmThx+hyL+kaa1etY9LgaqeAvyOdWFhzku/9STjpO5auafUEu2IkrJd46iNyqaO96y7NgxSzJyswHZhyptAqGmrfLk4hYcQpdgLvcXAbSoBOLJintkgXnRU6lXyiN3QQn0QFFPczVU04/zX5nU0GpyXgMXgvsCFOTdOM/yEU+ccdWUnpcQvRHfkQbBw0cXZxC03bMT1PC6BIh5bWnfIFwZMGCzpnlGeCZVRwtWEdTmKJQT/G7mf2OzcJZvpTAD0OCrhUyvROLPtkS1uLbC2TVnMr4DeQiPBpa4xE989ntrBWyErChikaaLhBmeXHGt4n3LqSSvqqMxcmdw8suwKT6lF5fwZkM/5ySLs7rSfWymOCXKoOhCv9KaiT829d4uFxhocYp5CufGMfk5kmVU4uYiHYN2ZocX3thVMxMhP/MNIUHjVml7DRS9mnQmDrkhWPm0zjpsFbYZzmPFneI3HDgEojmdfgP82GUSmkl+LYyaGmohz7POdlJa7+4QfvHyaSFSemaDFiMEfVJ4JlzFpMBbTqlFCElhJrmjyXAFulT+xXcjVBDxgJUcUIjcbfUPjO/YDFYura758SCzhHVrFIiwD46nxmke2noj9MhuGxzlqLHegJz4367/XVvTM+lCZVJfIxAhDtQFUFYspBV2IIZUWBr8U4YW+iLioSN6wFErSrkosruS4Ni7ohAt5QLHMF4AM9ZsFoPKPFTkZrkWTCfzkrpMaDydWCB1UI9n4EF3RueE/dLyvgJH4JGSJUfL0hIa75kYXtMzA+febZaGaOlaMpMomBHqIWY4ZGzkOBThvuqNGaecmS6YAFDj4tQV2TBag5dBsIu+3Jg5iw0Lt1rzk8ZC0w1EX6MMLwPV2/Yb5XGx1IoPxhZqMqvF9G5kjp3zgJfmRZZCGNdHsDCjoQ+5HhCXciFLOUC++cZuWgZyKGaVzpjwelPV8pFTddMctFUYkhyoV16fWTRhLTppj9rTLkvWIBzXbBwVfTgWJU+jmfRtUlfmFssJCZVrOsLQ9eeXFZjri/cJcuE1K5eYfERWKAEj2qhL2TUF1gv/JYsPnxQrvtSdrrvusRiyljg8vhKDmCSC0oLxsVgPWehQ74lmplRpTEypTFC1mBhR044RheVFrpzIBYGWdhoJ8BujHpMdsQ6u+IXydGOkH1cYdGgYgVvBdddZfBtm+4kpfhgziV3jogEZ4EvYkzZt37BFVMywR74MxjDq7X4M7PzvTj7p5rQmp/ifzOTH8WPfAPBZv4F9Go4U7qfbSNlfECglzAIpGxCfwn0L1CCvChQZayNlcUgAm5nRDJVMXHQdPQjC704W330BN02z4KxIk/QnZsesmRSkpsfuqHKHFR3Gl/OX/C19eGPuIXyrVzS1eyc6HfyhuqVKVOwvGbpsSrSWRX542w2r5WH5DeWasuIhbEsHmHZ9BgOMnB4ppSFwrM4Zr72fL/S/Mziz0o8gg8dYL0mqbp5PFKMPjzq3VNJUBEYdfNDE0RFQEz19o/rRZeU1OP/ABPz2SQJ1S5kAAAAAElFTkSuQmCC',
};

const RICHMENU_SPEC = {"size": {"width": 1250, "height": 843}, "areas": [{"bounds": {"x": 30, "y": 30, "width": 584, "height": 456}, "action": {"type": "message", "text": "เริ่ม"}}, {"bounds": {"x": 636, "y": 30, "width": 584, "height": 456}, "action": {"type": "message", "text": "punch list"}}, {"bounds": {"x": 30, "y": 508, "width": 382, "height": 304}, "action": {"type": "message", "text": "สถานะ"}}, {"bounds": {"x": 434, "y": 508, "width": 382, "height": 304}, "action": {"type": "message", "text": "ส่ง"}}, {"bounds": {"x": 838, "y": 508, "width": 382, "height": 304}, "action": {"type": "message", "text": "โครงการ"}}]};

const RICHMENU_JPG_B64 = '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';

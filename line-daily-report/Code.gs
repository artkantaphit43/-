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
const CMD_NEW = /^(🆕\s*)?เริ่มใหม่$/;
const CMD_UNDO = /^(↩️\s*)?(ย้อนกลับ|undo)$/i;
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
      [{ label: '📋 เริ่มรายงาน', text: 'เริ่ม' }], true));
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
  if (CMD_NEW.test(text)) {
    deleteSession_(source);
    return startReport_(token, source);
  }
  if (CMD_HELP.test(text)) {
    const pending = loadSession_(source);
    if (pending && (pending.company || pending.today.items.length || pending.photos.length)) {
      return reply_(token, quickReply_(`📋 มีรายงานที่ทำค้างไว้\n${[pending.project.code, thaiDateShort_(pending.date),
        `${pending.today.items.length} งาน`, `📷 ${pending.photos.length} รูป`].filter(Boolean).join(' • ')}\n\nทำต่อ หรือเริ่มใหม่?`, [
        { label: '▶️ ทำต่อ', data: 'continue', display: '▶️ ทำต่อ' },
        { label: '🆕 เริ่มใหม่', text: 'เริ่มใหม่' },
        { label: '📋 ดูสรุป', data: 'summary' },
      ], true));
    }
    return startReport_(token, source);
  }
  if (CMD_NAME.test(text)) return reply_(token, reporterPicker_('เลือกชื่อผู้เขียนรายงาน 👇'));
  if (CMD_PUNCH.test(text)) return reply_(token, '🛠️ Punch List กำลังพัฒนา เร็ว ๆ นี้');
  if (CMD_UNDO.test(text)) return handleUndo_(token, source);
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
      return reply_(token, quickReply_('ยังไม่มีงานในรายงาน', [{ label: '📋 เริ่มรายงาน', text: 'เริ่ม' }], true));
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
  const file = DriveApp.getFileById(getTemplateId_(session.company)).makeCopy(fileName, folder);
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

/** โลโก้บริษัท ชิดขวาบนเหนือกรอบฟอร์ม (แถว 1) — ใส่ไว้ในแม่แบบของแต่ละบริษัทตอนสร้าง */
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

/**
 * แม่แบบ Google Sheets ของแต่ละบริษัทใน Drive (ฟอร์มเดียวกัน ต่างกันที่โลโก้)
 * สร้างจาก TEMPLATE_XLSX_B64 ครั้งแรกที่ใช้งาน แก้แม่แบบของบริษัทใดบริษัทหนึ่งใน Sheets ได้โดยไม่กระทบบริษัทอื่น
 */
function getTemplateId_(companyKey) {
  const company = CONFIG.COMPANIES.find(c => c.key === companyKey) || CONFIG.COMPANIES[0];
  const props = PropertiesService.getScriptProperties();
  const key = 'TEMPLATE_ID_' + company.key;
  const id = props.getProperty(key);
  if (id) {
    try {
      if (!DriveApp.getFileById(id).isTrashed()) return id;
    } catch (err) {
      // ไฟล์ถูกลบ -> สร้างใหม่
    }
  }
  const newId = importTemplate_(company);
  props.setProperty(key, newId);
  return newId;
}

/** อัปโหลดไฟล์ Excel แม่แบบ ให้ Google แปลงเป็น Google Sheets แล้วใส่โลโก้ของบริษัท */
function importTemplate_(company) {
  const xlsx = Utilities.base64Decode(TEMPLATE_XLSX_B64);
  const boundary = 'dailyreport' + Date.now();
  const meta = {
    name: `แม่แบบ FM_Daily Report - ${company.label} (ห้ามลบ)`,
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
  placeLogo_(sheet, company.key);
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
  const props = PropertiesService.getScriptProperties();
  props.deleteProperty(sessionKey_(source));
  clearHistory_(props, sessionKey_(source));
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

// ประวัติสำหรับปุ่ม "ย้อนกลับ": เก็บสถานะย้อนหลัง HISTORY_SIZE ขั้น ช่องละ 1 Script Property (วนใช้ช่องเดิม)
const HISTORY_SIZE = 15;

function historyMeta_(props, key) {
  return JSON.parse(props.getProperty('HN_' + key) || '{"count":0,"size":0}');
}

function pushHistory_(source, raw) {
  const props = PropertiesService.getScriptProperties();
  const key = sessionKey_(source);
  const meta = historyMeta_(props, key);
  props.setProperty(`H_${key}_${meta.count % HISTORY_SIZE}`, raw);
  meta.count++;
  meta.size = Math.min(meta.size + 1, HISTORY_SIZE);
  props.setProperty('HN_' + key, JSON.stringify(meta));
}

function clearHistory_(props, key) {
  props.deleteProperty('HN_' + key);
  for (let i = 0; i < HISTORY_SIZE; i++) props.deleteProperty(`H_${key}_${i}`);
}

/** ย้อนกลับ 1 ขั้น: คืนค่า session ก่อนหน้า (null = ย้อนจนว่างแล้ว, undefined = ย้อนไม่ได้) */
function undo_(source) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const props = PropertiesService.getScriptProperties();
    const key = sessionKey_(source);
    const meta = historyMeta_(props, key);
    if (!meta.size) return undefined;
    meta.count--;
    meta.size--;
    const raw = props.getProperty(`H_${key}_${meta.count % HISTORY_SIZE}`);
    props.setProperty('HN_' + key, JSON.stringify(meta));
    if (!raw) {
      props.deleteProperty(key);
      return null;
    }
    props.setProperty(key, raw);
    return JSON.parse(raw);
  } finally {
    lock.releaseLock();
  }
}

/** ถามคำถามที่ค้างอยู่อีกครั้ง (หลังย้อนกลับ) */
function askAgain_(s) {
  const step = s.awaiting;
  if (step === 'newproject' && s.newProject) return newProjectQuestion_(s.newProject.code, s.newProject.step);
  if (step === 'group') return quickReply_('📁 พิมพ์รหัสโครงการถัดไป\nเช่น  PJ 69014', []);
  if (step === 'newproject-code') return quickReply_('📁 พิมพ์รหัสโครงการที่จะเพิ่มหรือแก้ไข\nเช่น  PJ 950', []);
  if (step === 'edit') return editMenu_();
  if (step && (STEPS[step] || /^qty:/.test(step))) return question_(s, step);
  advance_(s);
  return question_(s, s.awaiting);
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
    const props = PropertiesService.getScriptProperties();
    const before = props.getProperty(sessionKey_(source));
    const session = before ? JSON.parse(before) : newSession_(source);
    mutate(session);
    const after = JSON.stringify(session);
    props.setProperty(sessionKey_(source), after);
    // จำสถานะก่อนหน้าไว้ให้ปุ่ม "ย้อนกลับ" (รวมถึงคำถามที่แสดงอยู่ จะได้ย้อนกลับไปหน้าก่อนได้ทีละขั้น)
    if (before !== after) pushHistory_(source, before || '');
    return session;
  } finally {
    lock.releaseLock();
  }
}

// ===== ถามทีละข้อด้วยปุ่ม (Quick Reply) และการ์ดสรุป (Flex Message) =====

const START_PRESETS = ['07.00', '07.30', '08.00', '08.30', '09.00', '09.30', '10.00'];
const END_PRESETS = ['16.00', '16.30', '17.00', '17.30', '18.00', '18.30', '19.00', '19.30', '20.00', '20.30',
  '21.00']; // เวลาอื่นใช้ปุ่ม "เลือกเวลาอื่น" (ไลน์รับปุ่มได้ 13 ปุ่ม)
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
    ask: () => quickReply_('⏰ เริ่มงานกี่โมง?',
      START_PRESETS.map(t => ({ label: t, text: 'เริ่มงาน: ' + t })).concat([{ label: '🕐 เลือกเวลาอื่น', picker: 'start' }])),
  },
  end: {
    done: s => !!s.end,
    ask: () => quickReply_('⏰ เลิกงานกี่โมง?',
      END_PRESETS.map(t => ({ label: t, text: 'เลิกงาน: ' + t })).concat([{ label: '🕐 เลือกเวลาอื่น', picker: 'end' }])),
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
  jobproblem: {
    done: () => true,
    ask: s => quickReply_(`⚠️ งาน "${(openJob_(s) || {}).title || ''}" มีปัญหา/อุปสรรคไหม?`, [
      { label: '✅ ไม่มี', text: 'ปัญหา: ไม่มี' },
      { label: '⚠️ มี', data: 'ask=problem', display: '⚠️ มีปัญหา/อุปสรรค' },
    ]),
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
  const open = openJob_(s);
  if (!lead && open) {
    text = `📝 ${open.title}\n\n📷 ส่งรูปของงานนี้ได้เลย\nครบแล้วกด "➡️ งานนี้เสร็จ"`;
  } else if (!lead) {
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
  return quickReply_('✏️ ต้องการแก้ข้อไหน?\n(ย้อนกลับ: กดปุ่มในเมนูด้านล่าง)', [
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
  ], true);
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

function startReport_(token, source) {
  const s = withSession_(source, advance_);
  return reply_(token, withPrefix_(question_(s, s.awaiting), `📋 รายงานวันที่ ${thaiDateShort_(s.date)}\nกดตอบจากปุ่มด้านล่างได้เลย`));
}

function handleUndo_(token, source) {
  const restored = undo_(source);
  if (restored === undefined) return reply_(token, quickReply_('ย้อนกลับต่อไม่ได้แล้ว', [{ label: '📋 เริ่มรายงาน', text: 'เริ่ม' }], true));
  if (restored === null) return reply_(token, quickReply_('↩️ ย้อนกลับแล้ว (ยังไม่มีข้อมูลรายงาน)', [{ label: '📋 เริ่มรายงาน', text: 'เริ่ม' }], true));
  return reply_(token, withPrefix_(askAgain_(restored), '↩️ ย้อนกลับแล้ว'));
}

/** ปุ่มที่กดแล้วไม่ต้องแสดงข้อความในแชต (เปิดคำถาม, ดูสรุป, เมนูแก้ไข) */
function handlePostback_(event) {
  const data = event.postback.data;
  const token = event.replyToken;
  if (data === 'summary') {
    const session = loadSession_(event.source);
    return reply_(token, session ? summaryFlex_(session) : 'ยังไม่มีรายงานที่ค้างอยู่');
  }
  if (data === 'edit') {
    withSession_(event.source, s => { s.awaiting = 'edit'; });
    return reply_(token, editMenu_());
  }
  if (data === 'undo') return handleUndo_(token, event.source);
  if (data === 'continue') return startReport_(token, event.source);
  const picked = data.match(/^time=(start|end)$/);
  if (picked && event.postback.params && event.postback.params.time) {
    const label = picked[1] === 'start' ? 'เริ่มงาน' : 'เลิกงาน';
    return handleText_(event, `${label}: ${event.postback.params.time}`);
  }
  if (data === 'jobdone') {
    const session = withSession_(event.source, s => { s.awaiting = openJob_(s) ? 'jobproblem' : 'work'; });
    return reply_(token, question_(session, session.awaiting));
  }
  if (data === 'nextproject-main') {
    withSession_(event.source, s => { s.awaiting = 'project'; });
    return reply_(token, quickReply_('📁 พิมพ์รหัสโครงการ\nเช่น  PJ 950', []));
  }
  if (data === 'nextproject') {
    withSession_(event.source, s => { s.awaiting = 'group'; });
    return reply_(token, quickReply_('📁 พิมพ์รหัสโครงการถัดไป\nเช่น  PJ 69014', []));
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

/** ข้อความที่มีตัวเลือก (จาก quickReply_) แสดงเป็นปุ่มด้านล่างแชต (Quick Reply) */
function toMessage_(m) {
  if (typeof m === 'string') return { type: 'text', text: m };
  if (m.type !== 'text' || !m.options) return m;
  let options = m.options;
  if (!m.noBack) options = options.slice(0, 12).concat([{ label: '↩️ ย้อนกลับ', data: 'undo', display: '↩️ ย้อนกลับ' }]);
  const message = { type: 'text', text: m.text };
  if (options.length) message.quickReply = { items: options.slice(0, 13).map(o => ({ type: 'action', action: quickReplyAction_(o) })) };
  return message;
}

/**
 * คำถามพร้อมตัวเลือก — options: { label, text } ส่งข้อความ, { label, data } postback,
 * { camera / cameraRoll } เปิดกล้อง/อัลบั้ม, { picker: 'start'|'end' } วงล้อเลือกเวลา
 * ทุกคำถามมีปุ่ม "↩️ ย้อนกลับ" ต่อท้าย (ยกเว้น noBack) — ไลน์รับปุ่มได้สูงสุด 13 ปุ่ม
 */
function quickReply_(text, options, noBack) {
  return { type: 'text', text: text, options: options, noBack: !!noBack };
}

function quickReplyAction_(o) {
  const label = o.label.slice(0, 20);
  if (o.camera) return { type: 'camera', label: label };
  if (o.cameraRoll) return { type: 'cameraRoll', label: label };
  if (o.picker) return { type: 'datetimepicker', label: label, data: 'time=' + o.picker, mode: 'time' };
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
  setupRichMenu();
  console.log('โฟลเดอร์: ' + folder.getUrl());
  console.log('ชีตบันทึก: ' + sheet.getParent().getUrl());
  CONFIG.COMPANIES.forEach(c => {
    console.log(`แม่แบบ ${c.label}: https://docs.google.com/spreadsheets/d/${getTemplateId_(c.key)}`);
  });
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

/** สร้างแม่แบบใหม่ทั้ง 3 บริษัทจากโค้ด (ใช้หลังอัปเดตโค้ดที่มีแม่แบบเวอร์ชันใหม่) แม่แบบเก่าย้ายลงถังขยะ */
function rebuildTemplate() {
  const props = PropertiesService.getScriptProperties();
  ['TEMPLATE_ID'].concat(CONFIG.COMPANIES.map(c => 'TEMPLATE_ID_' + c.key)).forEach(key => {
    const old = props.getProperty(key);
    if (old) {
      try {
        DriveApp.getFileById(old).setTrashed(true);
      } catch (err) {
        // ไฟล์ถูกลบไปแล้ว
      }
      props.deleteProperty(key);
    }
  });
  CONFIG.COMPANIES.forEach(c => {
    console.log(`แม่แบบ ${c.label}: https://docs.google.com/spreadsheets/d/${getTemplateId_(c.key)}`);
  });
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
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUgICBSUlIAAAABAQGgoKDb29v+/v4AAAACAgJ5eXkAAAATExMAAACCgoLs7Oy2trbGU/sQAAAAEHRSTlPq/j6A////Afz+Sfy0/v/+7crBWgAAAfhJREFUeNqVlL+L02AYxz99k9gERK6W4lCEjhbvIB0E5U7IcmvpoQUn8R8oZCtyIMXNrXCDq+J4ypVOgkvgJnFo8MA6FqGIHKVuSW2Sc3jzo20O5bLkfd7P+z4/3vf5voUul3+C/4Ltg1KpcpoDysHUgaBZMdeB0nRolEplgmlMVPlrOo2HNmBsz6arOxrOvR0bwDt7FJQzoEwK9Z5c6B9tRWYKmkqnl2Tjj81pAhTnyM4K8OqBCSh7YP66tVra6du7ntwx0daLbkXSlYa9Doq0QMB7bQN4rU8gYNLYPMByBIJl77s0L34+iMELfYAgUloAnL/b/REDzZyg7Gn6CQCzJ6935xIExn1fYF6T1vVv+2mQZwqCvieNm1tZdHuBoG/m71UxUHFu5EEUIMDKAxUEOHkQ/Lt9ruzKql3iR0Vgu3kQeghsI7X9ZNAvInD/pEBPBm9CBL6QrRN1D73uc7mg1kNFhAOZ4jH68QKApVtDoPXuyBTb7Ur7KQAv/RYq1EYyxVfwWYaYCRDweNlfT9YY7IOAJRtgwUAeYm25DgYibuqvxY+r84f27RiEVmfFmTFW3UQfw/Ao1Yded6upcMLaxTgmeue3cDMNjqwvZ30AY+eDOgOg0M3kPEHMUKvuqs7DocVoPs/m02YIT6oWqMPz5NoKV359/gK6c5JMV5WjEAAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVTU1MUFBQAAAABAQHJycmioqL+/v4AAAACAgJ7e3sAAACDg4MTExMAAADr6+u2traj3cNdAAAAEHRSTlP+2D6A////Afz+Sf78tP/+LI5yiwAAAkBJREFUeNqVlD9oE1Ecxz/33l2S61ASlCItJQVBFKxcsYNDhJYuTuWW4BbSVRBukRZBCIgVHOS0OLc4CUU8OnQrnHSoQ8WjDoouAWlopdKAmFy9/HG4y11SC+It773f576/93u/9/s9ZZGzP8E/wdWFXG5k+y8gF/YdCOZHjEEgSw6zudx5glpE1HAoObOTFqBPHtX6FVPO3LgF0NybDs4lQFaVsUr4o7+R7RgxKKl3K71o/E8ztd4e0ln+khygeSEwPJAFMA7y/Ufbfna9GbqqpgYPXe6Ee6SwBkGaMghYl6dA01gHAfW50wmc7oKyGIwMewD7mzu3aqFW5ldNQVc1ATI3H7tLT0KFNlNHFtT0GwA1ZZiPLucPAFqK4QuMMFj/3sbSpcqNKGCJwG6GCwuov43mJwjWZpJwzGhUh1BxhhOQ/RWO7QABEwlwn8e3JKAa26UVzTunyudYsfqrJHbVNR5wpquffpk+V6YRC5bjzTQEZTdarcQCWg0Elh4udDsWYKeRhcPUMQBP3YsxOGz4ghNZAch4erFYnAcgY9ioKC0HoOHyHiQAgZtFRbM3PWBoSgAnXwEevjBRIbsF4L9OMrCrgIBi2x6sBd0rgizQ1nfqA6CTfRcmceL3oGJNRNW+l3nVb79fGY+qvW2qd5J86wea1+uPl62VuD8yV9zRuHHaE939iGTm68JLevCDufXNBtCv7Wo/AFAWk3b2kEdoo15oKYSX9PH256rvN2J7XAzt1TETtI3vkb3n6j9enz+feKuOf4iO1AAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVUVFQbGxvQ0NChoaEAAAABAQH+/v4AAAACAgJ6enoTExMAAADs7OwAAACCgoK2trZp2NL4AAAAEHRSTlP+5///PoD/Afz+/En/tP7+M3W6NAAAAlZJREFUeNqVlD1oE2EYx3/33uXaU5BESs2gpV0U2yqHoENJNZUO4gcEBMFCJe3QSeG26lJCB+1UosWpoJFCB1G4xdlABwUdYotNEbWhdQhS2iw27SWXOLyX3KUK4i3P8fze57n3/3ycMsnfH8E/wcWxSKTzxx9AG1uxoXKmM94KtFGbnkjkKJVVj2jSjNo9NyzA6NteDUYM2SdPWADl5fFKhw+0nBLNyIPOdNiNN8GouJdp3MbJd682gGZPW76AcrQSB9QYXCp0B6WtPO7flRE5vVV00pWpdKxW0EYSBHzQD4By8jUIyHUdLOCGCwLX+inFz18eeCjB87YcAleYAHx+VCg+zQKgducQtNWluCsvhxdP7UqRJQtlciifbyZfvrYJwJO5LUGm7H/13GFpLQdBKiD7zi+v5u1o2Ed8EO+4CkC9goCE53Vn5h8ckq8hUGPGetFr5rfhWRlAPbyn+XkqE8dTr8zAlDRSqffHp643UwmwmzHO7ZoXDIJE2M9WV6RVQghSBR8Ynq3tIUgagU7UpU3rCLIOAHoWWPPEZqoI9pUkwO7Ix4mlxKw8FE6jxjB2ikDtWN93c3/NK9xeVKCmOwG0F9Ni5o2c6LF9Ew3MDQAGB7/e8u7QpYKA8066dRaMzE1QY7jGu1ILqIXfy0k0ndaIjOoN9VL7YtA/kur3NqqaEHf9YTSKoWxjPxZqc8mGXz9d6G0uTtWsFz2iT5XUrL+DbxNfNtMAxtlnoS1Z+Ul/nUso24R6s8E9ry4kWN/Z8f2oMU9U7sLAGqFPaqNtyn//fX4D7liw367lCg4AAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEWCgoJXV1cLCwsAAAABAQHLy8v+/v4AAAACAgJ5eXkAAAATExMAAADs7Oy2trYoKCjg/l/sAAAAEHRSTlP+/s0+gP//Afz+Sfy0//7/rlR70gAAAi1JREFUeNqVlD9oE1Ecxz9575q7CEJCKaWkhUy2VCLXQVyiZOhShNBODiIUVxGKS9cTh26lGRyViIubJQodPXQSBY9WCtolg6VWW1KhNNfkrnF49y53VRBvee/9vu/9/nx/399llvn7J/gnUF4oFEa2/gDkwjcXghsjdhqQNZeZQmGYYDdCDLXU3JmyA1jlw93kixl3asIB8DcfBcMDQLYyl9bUxdO7+TM7BmryzprO5nTb3tUxpPt4Z1CAP+bZHsgK2PujydI+PLvcUa5aQ+mi589UjCEW00CWeZAV3pRepYGgPt5FwNH18wRu9UEQLH7Rhh/Tal3Nugj6sqqBF72IJ/sIWTGsDc3wjnEAQJib8gV2nGx7NU5YImj4+ti4pndOF4GjW9Orj2lAWgjcVnRaeRLnexYgYEkdzLwdA4qriPHjej4GckmVrNw/Lx/lyvQSVCZdHb8fNX0dLweCagmAjFksTp42G8qPgcDxAOgnA4Q+sjLXOQCQ7fbJXvGmouHh546s7Gfb+l52+LXa/TrxBV2xdL5RZqmBIBO6sXKCqLdeHoHRmNTAxagDD7pVBOTfxS+2o1HJgIBZy0mHsJxZENCjkQa6rCsSS700sC4itW+aG0n7vaWJSO1hVd4ehLH2DE/PRzN8HhdpTnvFeHDCUv+rbvDTI+GBmg/4Pvfxwi0XsK5cjUSXWR6McwtxiFH0knMeNqt8arcH9lgM4cvxKhhvf0Z27eo//j6/ASWZpIKsO4lkAAAAAElFTkSuQmCC',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVTU1MVFRWpqanPz88AAAABAQH+/v4AAAACAgJ7e3sUFBQAAACDg4MAAADr6+u2trbNIw+CAAAAEHRSTlP+2///PoD/Afz+/En+tP/+G4DkJQAAAkRJREFUeNqVlE9oE0EUh7+d3aSJgiRS2t6atl5soywURUvU1KMgBARFMNAe9CAKOVnwIOs/LJ5WchMKgXrwIsRbD60NFFRQYaWaehCag4gHTXOp2SbZxMPOZje1IO5l3sw37zfz3ry3yhx7f4J/gtOz8fjAt7+ANrtehOaRgXQv0LJFRuLxgzTLkmjukC2OnM8B0YlqOegxXTx0KgdQ/3S22e8DzVKmDHej/SzmpLsgK24a3m3sjUTZA1rxQc4PoH6imQbUFJypDAdDW3uS/O16WOHeoGccVypMrhf0MQMC3mm7QD39AgRYo7sTOOqAMuf0H7AA1vPAdR1AHV7VNRyRsQC2lgGzABBKWLpGX0cGNzLmedi1XE0jvSGVnaegywvnERTqEkT803MNBEbCy1LgXSMIijU5a11b8UCniejq8n356oI0VTdAOZufNh9K2wlWyf6LC5cSlWCVSKlJqBs39pICTrYDUpmYDzpyVEIIDF8XRY5tG8FM1AePpG2GEZQabkIsIOHaFFoIdhQDYPvcyvxj4767KWaipohu/gD2xSc/vLfH5B3sIYFqDgHYL++J+Vuu0t0dHTWFEv8FMHi0OrHkgkSlgYBjLbO3FqKlC6CmcKJvaj2gHXvrJlFv9HoUVFnUa5HnwfXbRlIWdfvy4J0l/wRl+7PXH4vtfLc/Iocr493Gaemd15JErtTUkt+Dq5mvayZANPkq9NNN9JzfzjWUKqHxUrDPW4sZNre2/HXUlAzKOj71hdBH1Xs25b//Pn8A+6itBGDQmIcAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEWOjo4cHBzOzs5hYWEAAAABAQH+/v4AAAACAgJ7e3sTExMAAADr6+sAAAC3t7dISEhJDYCIAAAAEHRSTlP+5v//PoD/Afz+/En/tP7+io5h3AAAAlFJREFUeNqVlD1oE2EYgJ/77nK5qtXEn1CEQrpUKC0E0Q42lejQwSngICrBxMUoHUIpBHE5XdwkLmYRDVQUnQKic9DFQSRqCVYonqAoCk2lpc1/Hb4vyZ0VxFvu3ve59/3e30/L8vdH8E9wPBUMhr5sA0bqfRGaE6GYFxiJIiPB4F6aFUUM+UoUR6ZtwBpfqbgtThSHhm2A2rsbzf19YJS10YL8sXEx0I71QEIkCt1oGpVwpQuM4pzdT6B2qBlTYNp/xZ1aPrOoQHnTm3SmLYFJ0gtMkqBHeTP01Atatw80EFAe/7OAL9ogaGd+KA+PT07JtO/7ywjaIiLBs6vOtxkA9HAZLasFl6XnmXTo7qlzAByurgpiPmmwtfQ89kDqiRsICjUpPNJ6ZcFuILDDUojMu/pqYVDcrfINHHRGVZe2mhiQSQK0HD2NPy/JJgjIAbCLPSM36xvSYsAzPtnhM/Yl95Rk1OdagfP+5DZX68zDzk647yoeAGAHMVhHAs2HwHZkr6WhFDo1BElLHhF2oIMM1zbRo5/NKgBLqTU6g/sA+LVRE9Q1GcmU9TCdH5SdCeTQowxUvwOI6+byq2uqN7UhgZ4LSSE9V38ijVP1CAIii6q1s1+PqFXRQcBRy/bOgmWfBgENCl7QoCCLGBnwgpyuRvRl/Y5bfzk3rkArfst1irXkK3X3Y6Gz0Btfc8wZ6y1OK7L1URHz3qpeAtCjAM7Z1+JCCbAmJn0/ZeWz/XVeRVvBN1Zy73lrIc6narWvV66gU5489gHfW91RQWj/ffv8BpfcrluVFb/YAAAAAElFTkSuQmCC',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVQUFATExMAAAABAQGenp7V1dX+/v4AAAACAgJ7e3sAAACCgoITExMAAADs7Oy2tra/OSO8AAAAEHRSTlP+2z6A////Afz+Sf78tP/+PfMY8gAAAipJREFUeNqVlM9r1EAYhp/MJN1N0bKLUmRL6V4FK5H20MMKW4oXDyUIxVtpT4Ig5FbwtCJ4NeIf0OJJ2IOh98JCD3qoGKugeFqQllYqbi+7SbM/PCSZ3bQFMZfMfE/m++adeb9oG1z+CP4Jbq0Xi5O7F4BcP/AgWp60skCueiwWi9eJDhOix69Vb3HWAczZk8PRFXe8pWkHoLM/H10bAtnUpmrxh8F2oW8psKo/qaW7Cb5VD9Ma0nvxYyigcyOyfJAVsI5mRqXtvprrxKmaY1nRa/24xhhOFuRYAwF1eQ50rDoIaC2dP8D5AWgb0eSED3DgAOE2gJzZtHUGuu0D3P0IhAAY1ZfIip57B8DXB6XSo+opQFezAoGVbHaqXq+795MNSwRuRxXNWwvxwAkRbFUVaDfs5DLG0fEmFOiGhXjQixBQViAYH96rgKYC1VRq/5x9agsZ+6hUfad1eapu6Iymsq0LtZEGgrWGuqAztbaNwDEVeJaO3Byycjz2J56Z9waJPo7bgSCUiXVOw7I6MxeB1vWS2vk0U9QoIDDcRJZ2JQXPQxsBhZ14evVzCvY0ELDSc7NeMP0VkBV65vtWBvQLH+JDLJ9lV2yJxO37+bej8ae16cTtPVt/PDSjeWT4aX+86b5W/ZG/2SipxumVBwcJyS+3hD/swU/2zk8XwLy9Z/yO5W4M29lHnmCU/DhSAWDw5eH3ZhC0VVyZobc5ZYOx/SuJp6n+4+/zF+48o7eYHW5VAAAAAElFTkSuQmCC',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEWPj48dHR1gYGAAAAABAQHIyMj+/v4AAAACAgJ7e3sTExMAAAC2trYAAADr6+tJSUmpPY5DAAAAEHRSTlP+5v8+gP//Afz+/En+tP/+G112DgAAAlNJREFUeNqVlE9o03AUxz/5Nf03HaRjzAkq2XXO0YtD54r1oN7GDh6cbNDBkF2ECMJ0F+sOird4UxAsbHgOXoQdpFKcF5EwavEiC16sClvx39Y2TT380jVxgphL3vt98r557+W9KIv8/RL8E2TmUqmB8j6gzpUtaGYGsmGgzloMpVJ9NCs+UeVt1ho6WgBio1uVYMQ5azBTAGiUl5v9XaDayoW8fHB3Xmtl98CsyOQ72eyW9UoHqNaNQreAxsVm1geZ+EKwtEWj7AN7J1y00ZIgRjYMVHIQmeCFXgqD1oP+BgKc0T8b+NEDgWtUpTvz7My6tG7Hiwg8MQWAu258mkkDENUdBPG2LO5pvDJv/pJF1gwE2YiMr91LLG1IQFpFYDako2tws1fahToCU5eOA/R+93ueRGDVpKNdhUc90m43EWBI5/KRtdPLS9LeAQGmdGK5hc8DOWkng1Pi5q8fqqaDU+JLjanXXue/7JdKaD1wRQlITWkAeE4avLhMUYkiMBxf1YSDvuntIDBiANSx4Ievm4sjKLZktK6BUpcNtV0EdUU6uVsLd5+3/URMIhPtns0qwHHtw9tTfVWANlVdoJqDcgTGzcOrNgB36lkE6BsyldXJV+PSOiZAwPlELjwLsfwlENCgGAYuBdnEdDIMzIg/oqX6w+D5fXMEiEyAN/1k0u6+ofnzXWc/VrzS3n4kRpzhvcVx0+01nyQe1yJFfClwpt98O2sDsRNj0a+yd4vdda6hbBEdLgb33F2ZYnN7u3vuS4Fnnxx/T/Tlgc5nU/777/MbUOq0YGoxTIEAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVSUlIdHR3R0dGdnZ0AAAABAQH+/v4AAAACAgIUFBR7e3sAAADq6uoAAAC2traBgYEPhGbEAAAAEHRSTlP+5///PoD/Afz8/kn/tP7+6SIKFgAAAlxJREFUeNqVlLFrE1Ecxz/37nK5FoW0Sluc2i6FEmsWpdao6aBDdQgoiNJiin+AKQ7VOnhDURDFdHOMWkQHIXRxEDSlqIhLSmuogzSoi0VppFAvuSTn8F5ySRXEW+7d+9z7/X7f7/1+p03z90vwT3BssqOj6+sfwJhcyYC7vyvWCoyJDJ39/X24eUUMeZvIdJ62AevIer75xGimO2wDOEtT7l4fGDkxkJYvlq/0VmMNMKGNp+vVlN+E8gB6FIz12R++gMro5+GCBMcLvc3SVubC2zJUzmwVnajKHCaJVmCSAAHvg3YrcJLPQEBu904Dl6sgqCbb5ePMwmBOrh4Ecwiqmqyp7UnSGVN2hHIIgpoU986Zf2ilpMhQEkFM+Vi4ORJN3pHrmIEeXdxTBKic2uxh38Z3ABZ3lQR2CACNItz/KU9oFoJMSBWZBq9NARcB8boToHnShAAIyADgYcNb5Y7b1CWG7WAWffUGxLMA9G08LV9Vu82hOJy6dmNBiXXBIP5SnR17vjXkSOAFMLCH6lEHcD259BwECcvPeEvVYpsIshX/00Vm5SJbQVBSomby46+nZIFmMYUepd0rAJzY/hK+XZaOBJ0egZ7aBmB4Trt+Vka6WIpgQGQLgJN8uqRyHXgBAg6WdnSJlToDAsqkW0GZtDQxUm4FaV11+5L1uHn/gh1W3V47330562fQqh/q8/HIm2+0rzlSHGwMTiVS+6iIebegZ/0ZfBX/tmoDWEfvBWQHadP+OIfw1gkMynR6FIDa6rm1X5ubxcZ+HVDLHRpZI7CsF1QR2n//fX4DArC2/C68DFMAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVWVlbQ0NAkJCSioqIAAAABAQH9/f0AAAACAgJ7e3sTExMAAAAAAADs7Oy2traBgYEi8HYYAAAAEHRSTlP+/+j/PoD/Afz+/Em0//7+izvCTQAAAjtJREFUeNqFlD9oE1Ecxz/37jU5VGzOVpQibTpoS9tAEBGHqCedKgTi4qQYHHVJVciawU2KcXTywMFJCHRw0h7qVv9EJFJbwbMKImiTgpbkepc4JJdLrmJvedzvc7/fe7/v/b5PyfPvR7ArOHNB1w9+675Kf01bgJuQ01ZfhkxbjOv6AdyK0ZeRtsZPFwBtZqPSm3HOmkgUAOrvb7jDAZBlZaLY/rBxM+YZXZAWl4v+aRof4hUANQXy++1fQQPu3Oopuw3O2vHe1pbvzWy1S5Uj/U1nvfYeA2T7QYQMCHgVLfSDeu4pCLBHwwKuN0HgZX+Ewd1IGUFTGEHo8UIOkHEbNSW1J7D94NbIV1DPL7c+gadP1gXGACDMqzbw9v7aagnISARmHVBfXgTI/VFLNaDgIMjFu2pqKxmOm4CIIrBq3a2VQdhaA1ougp6+N393UiMgwNw5Is7/xye7MxouNbgPaPqljFgXtDZhz1FAkQiKdqD3ZIk3WaDZQJDVgtrFvV4mBhQiqKkvkSpEx4akvnR4ZHbomAQ2t+oCR8lBY17XdRvvzvVJIBozUfLe8P5y6LTq2FJSoJqHwm3MO0kExNfDYFSAgBON0JRoxVkQsB2W0aHUFjHp9ANT7aj/QnvUG79WmOk4yjXEpWAbbUVavj8Wmw9zfjw6ZU93jeMmWx87JLpQUy3fOGDPvXauWICWeCZ/tgcjH9i5hrKBb/TOP3cXDT5Xq0G8UwqaKyenbOQ7aYeuDHgOcGT32+cvyTKpuZ1JbS8AAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUjIyOKiorPz89NTU0AAAABAQH+/v4AAAACAgJ7e3sAAAATExMAAAC1tbXs7OxcXFw2Pq3tAAAAEHRSTlPp/v/+PoD/Afz+Sfy0/v//Cgn+JQAAAgVJREFUeNqVlEFrE0EUx3+Z2XRX0JKlDSghNMSDldJlIwoeIkQ8iGJDil8kt5yERa8eIn4B/QCloT16cKuXgoUuLUXxFKmBQiyVKrixO6mH3SS7SVU6l4H3m/fevDfvP6kGZy/Bf4G1bJrZ/Qkgl/ddCKysnQSy6lIyzRmCTkS0cKu6pXwT0K3DTtyj5F5fbAL0dl8GMyMg26lbTnjQf5zp20NQlUvO4Db+nt0ZAOmuN0cF9BYCG5BlsLtT8dLebeR+hR5tmSza7oeh0tSSIE0NZJntK2+SQL3O/kaAe2e8gbsByLJ6+ONgDGzMbl4WBLI27pG2XWQ5baxC8PzS1c+wsvXoGAgu3PYFtgacus88IN+9CEBFkmp8sdoAau4roBc/Aoj8saAePoAC4Gf0PDoa7nQsbRiJfoAAZ3ISfP4CjH+Pz7lDVQpnxNHQaFqTQPUQ1PSYJSqwnkbgBYBRnJ8qtrhxrVd8BbgKgS8c8F+YppnhrmmaGTAKDqmGmp32xlLIube2QDrz47mf+jYCKu/HwaIGAm7q9aRdr98DASe0kuCEVtjEgkoCT0RDvZP+FLc/qeUjoCpLsSz6nuYN9LGm1octNha83FA4qnD6ISLGynfhEekDDh5sifubgG4tat8ASDVGcm4jDtFyXlznaq3C9tHRyD4cBrWar4C20x00NHXu3+cPG9yT5O5f4HQAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEXOzs4kJCRRUVEAAAABAQGioqL9/f0AAAACAgJ7e3sTExMAAAAAAADr6+u2traCgoLFf1P4AAAAEHRSTlP/6v4+gP//Afz+/Em0//7+/LJENAAAAk5JREFUeNqFlM1r1FAUxX95SSdTLO1EWsQP2umq0A8cBDcyg7F0U2Sg/QOkXXUlkupiwIWEuhPELF0WxE03be2mYJGULiqCMKCtCkJj3ShIZ6RSkphmXGRmMglCs3l597x77zv3nvukCv//BGcCpVlNG/jY3iqttWwDQUkZsxMeStlmWNPOE+zpCY+yPVwygez40V6nxy17ZMIEcD/cD/pjQKlKI1Z00HuQO9XbQFncsVq38fbze60civ3ya0zAHXV0G+Qi3Dzs66T2bv3KSRSqqiRJ66dRji7mk0CGGRCwpZpJwDW2QIAzmC7gYQiCwPiZBp6pNoJQ6G2Lf/wcQMk7CNSGBf7ryRvgb159sgJ4dQOB3gV0mUsOdFcezT40gBkFubh+uQ7S90t9x3hz7u5aZRO2z/kCMw9AA8hYUCgAIovAridutGwAjQBBind+BsiAXOz+9AMgzB0DyJOvgEbOTcunNhjLpzNU49pCVEYELHcAj0/mAXwQ6LnY7i8vACApCEwnBlYyUQdCF4GRjR1630Y/popc/JapgTrUr2gH6u2Lmraah98nrsCTDPAWNU1b66lomlYANWchVYKB3mqKjDy0qgsU60K6g4uejoD8YRoYFCBgykupJGtNgYC/Ce6Az1qkxEKQBGy5qfadzG6n/e78OJGow+ncPTvOkP2z35qPjfCF0bKro85Ye3CCQuNLE1Gf1mWbZihwpt/7czaQnXij/IoqX4nHuY50RGvQmz0PNnQOarXY3gwF4efrow7Kdo+TejJgB2D87NfnH8VrsK5pa4zQAAAAAElFTkSuQmCC',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUlJSXQ0NBQUFCdnZ0AAAABAQH9/f0AAAACAgJ7e3sUFBQAAADr6+sAAACCgoK2traigDTfAAAAEHRSTlPp//7/PoD/Afz+/En/tP7+Pk/OYQAAAjtJREFUeNqVlEtoE1EUhr+587BB0IyEINpHqihYtQRBFxp04l4YcGtk0oWuhODCrCqhK0GQgEtBg10L405xkUCpCm5ihFgEMU1VVKQJgm3MTFIXySQzaUG8m4H/m3PuPefc/0pZdl6Cf4LzaV2Pft4GlPQ7G5yTUSMIlJTNtK7vw6n2idL7pOzpSxkgdHy96o9I2kcnMgCblTknMgRKWdpf6P3YXgh3jAFIiRsF7zTt97GqBxT7cWZYwOYBxwDkBFyo7/WXVnk6vtGLKCvBoo1OL5VGJgh2YYGAN9oI2LSegIDS5GgD6y4IOrkfo+DRWBmBK+ID5fnKvAXIsRJSVtI/glO882cZbRwOLgGnGk2BoQEit1ADHtw7p+YBS0HKrs7WANypL73y1g0QE78EuRgA3f42NQAxhsBuBk4UA9hyEGD69dTNJqCCANunX1yeMwFn2/VJjt2yBqP1p5qvRq0dU0HlmpfKDAfAxm9AUhHkagHw7AjQbSGwQgOx88JK5fNAXkNOrGoN0KYiil48lFxd290Gvm+0BC3JgnZa1/Va6276+mFAC+eQsp3InvLIoOSpYlwg56KjE0y34ggw6qNgUgEBp9v5oB4qXAY5QSf0Ktj5bvh1r4lxNxhRkvuXekl76devWCf6wDWv+nYJfVVLnj8Wu/ctT9eO1WYGxnHjW9/6RLvdlEtDDxbND2t5gNDsQ/UnAFJ2aOcm0jrqTMnvc3fR5FOjMdSRE/2iymfOrqC+lb2xSf/9+vwFJbKrQ3NwCkkAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUlJSXPz89SUlKenp4AAAABAQH9/f0AAAACAgJ7e3sTExMAAAAAAADs7OyDg4O2tramUjP3AAAAEHRSTlPp//7/PoD/Afz+/Em0//7+DpVzfAAAAjJJREFUeNqFlM9rE0EUxz87O80mBGpXqhYsNO1BamskBxHBoqvehED9A4QoeFNYL/YkBL2JhwWlRyl48SSV3gTpoFB/4CESUksPmkoPHqQtSky3maQedpPdLEL3Muz77Pu+fTPvO8Yc/38EB4IL12z7yGbvVXbXogJ0Xk6rvgxZVIzb9mF0zenLKKrxogtkprdq8YxL6kTeBWhWb+rhCMiKMekFH/oPh9pODxTFHa/7N/7XXK0LpHruRg00p7QDmDNw8ceheGufXo3+DTIqsr9ppx1IDeD2A4tZEPA5lQDN0hsQoMaSG/hbgznTvqp/JsDH4Q8jAi2cZIbMKQTpfQ9ary+fB+DpJODvlBE4KUCUH9QBrJctgJJEsNAEzJVzADQMANw9BG4OgA4A84+CrbWQqMFY2RcFAPY1AmajuN7IAjAAAhYjMH+rAUArGoZQaSUbG5/ZmBKNgVBKxqXurY74W/lqKOV8i6ZvHdLbgCGReKd74DGkj28CHR9BKRMvH9TwUgjUHmBNTFoTFSDbAljQCHYNF/wbtm3XgT9HAWuojDHXHh6sJM7DHFsuCMzyseRB3d0tIMDZSIJBCQLO7Hn98czCFRDQIgF8FoNJLOh+oMxwqN+l3sfjt0unQqCd6zGxzKpUXX8sdZ70ptQ6WZ/uGUcX9tdCYt3fMVXkwWVnveoBZPLP5C8AjLnIzjsYW3SNHvpcLzl8396O4pgzwdpZOztVR36R9cSVAW8BRg++ff4BjdKisJ56mhUAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUnJyfOzs5RUVEAAAABAQGenp79/f0AAAACAgJ7e3sUFBQAAAAAAADs7OyDg4O2trZKpI4aAAAAEHRSTlPt//4+gP//Afz+/Em0//7+6tB+DQAAAjFJREFUeNqFlM9rE0EUxz87O2kSlJiVViUtNC0i2rQQBE+2uJZeA/VUFITUs8J6yqmwKuhJDHiXoH+ALT2pBVd6EDxIpEaLoEYtiCDNomCSZpN42CT7Q6FzGfZ99n2Z9+Z9Rynw/yXYF8xd0LSRt4NP2d9zFuDMyYwVyJA5iwlNO4xT0QMZOWsiZwDxzG7Fn3HeOjFjANS3rjjDHpBl5WTR/bF5K9nWByAnrhX7p2m+T1f6QFqPDK+A+pSjA+osnPt6yF/aq7WxP25GWQaL1tuuVAQjCKIsgoCNoRCo5zdAQHk83MBfbRA45o8wuBezELSFHgYyXUYQ6xah9XT+LPBwcvI40LRNBPoQIM2bVQBNGwbIS9TZtVEblG+p5G94c+T7DsCTA3sCMw1AJ3CvMSRW4t8L7zoIWPRF5sdsgAhIWPXiqRvdSztAyxsGdy3Quv3J7N+gX4pIMu1KiYAUsFhypQR6MgAMAEUiMKsBkDSBTgOBEfeO/8xYL9lAMYpSULSPEB0FXh9LwZ0l4HTNFjQUA5rLmqZZjbvLF5eAaNJEKTgjiXKoI+r4Y10gzaPhVl1v6AjIfgmDhAoCFvaKwXi8tAACWoRAk1V3ErNOEFhqb6g3h17641fz0z3g6Jd9YvF30ur7Y71zfzCl0VPVzMA4Tra73SPRFVu1PA8+1z9sFQHiMw/kTwCUgmdnG2WXvtF7PnfWdT7Xal4cddbdO9tnpqrIFweroScDNgGm9399/gJZ3p/2Do8Y3gAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUmJibQ0NBVVVWdnZ0AAAABAQH9/f0AAAACAgJ7e3sTExMAAAAAAADs7Oy3t7eDg4M4Kd/1AAAAEHRSTlPt//7/PoD/Afz+/Em0//7+2qQ/+wAAAlhJREFUeNqFlM1LFHEYxz/zm9mdCax2wlDKfDmI4EsMEtFhq7FOFgv2B4ReIgKJtQ573VPUoVioS5cIwo5heOikTXWopMAoRaFwMgUPokuKzO7OjB1mdmZ3Efpdhnk+83yfed5+Uo6Dj+C/4MI1XT++Fr0q1WfGAtwBpc+q81AyFl26fgx3wazzyFhd5/OA1r+1UOsxZPUM5AGc73fc5hgo81JPIfiwdDflmRHIiOuF6t+UFjsXqjEUa/JnnIDTa5sWyGm4uHq0NrW51217gdS8Up+06QUxEozVgyQjIOCLmq8HTnYGBFjtjQVcdUFOe1fcjQbwuflTq8AVZmyqPF4ClE4LOZ3Q3kBl5saJP6C+c7o7NvD0c46cHtraBEbvte3AzcOP5lZa4daPPSn3+7QN4Hasw+AzI6jgqb+CbCcAPqBuGGHNVQRWMQq9d8h7OgWw7yKoybuJyQfjWSAJAp5HYGc/ufxyBCjHwxAeLXGpZb3awVhKdUZwxAFSZQFqUyAlMFMR8H0o7QKSgqBgRyBxfwrNB/wSgjEtjm07ldlJIJ9Eykn6L1BPAq8Mr5vyGjC4XRQ4UhZKE7qu28hXW54AaiqPlPOaj8w3NErueGsI5HxLY2snHAMB5mojaFdAwJlSw5RohcsgoFKTe1AApoJJNNx6YMnhtH9Ifqy1j4/1Ewy1P5y6bcURtN3F6n5M+y+yUel77b5ocVxjfzkk6sOibBFKgT38tTxqAdrArLIJgJSL17mItEV10cM9d6dNVra3Y3soBf7S2V4b5ZtiN1wZ8B6g7f+3zz/DLLodgYCy2QAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUlJSXQ0NBQUFAAAAABAQGbm5v9/f0AAAACAgJ7e3sTExMAAAAAAADs7Oy2traAgIBXOu3IAAAAEHRSTlPq//4+gP//Afz+/Em0//7+FymGeAAAAi9JREFUeNqFlE1rE0Ecxn+ZnXQXqTUjiiClpvXQ0hfNRfDQ6gq99BCIH0AsgjeRVA/1OAiCFzEfoSDeKz3UQ5XRHgRBiGiLguBSkShIG7HIJtkkHjYvu2uhexl2fjvPf5//y6SWOfgRHArmrip18mPvVXbXvAGCOTllYidk3jCq1HGCLTd2Im9G5zTgTO9uRU9cMeMzGsD/cCc40QeynBovhR/W7maabg/kxbVS929q29mtbgxpnn7pG/AnPdeANQuXd45Frb19Nvw3lCrLuGm3GcZIsxgHAxRAwIat48AvboCA8kgygTtNEAT6ZxI8dgyCpnCTQGbLWLNpZx0aL26e/kb7rFLqvEdTXfQFbhqQ+r4HgVJqRQMFSWr5/SUPIDjzHYDX5zIghv8IdBaAVijfuKEB4SAxQ9G4Q34JaAcI4r5/t0PvCFiJgocPAOr/t49b6LdPVMpe1AdL+fVST8rNREBjEICURKC9CHh+LzTlIyg6EaCr4WIjMA3AHpuwx6rY1TANqwECP1WE2pJSyrB/tABgZzTWLEcqP2C9UqlMYHVrVs0KpD6VLNSS7yIgt5MEIxYImK8lusQpzYOARjyNUGc1TGIuiANjdbp9c+BNdP/W4jRhU7cWMrdNP4Kzv92dj7XWk2Iv8ZPeVG9wglz7c4fYj6qWoSMF3sK7+nUDODMv5a8w88v9ca6S2qU76J2aB2suX/f2+vsdKWh9ujDpIV8NeokrAzYBpg+/ff4BHSioTqzWS94AAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUnJyeLi4tVVVXJyckAAAABAQH9/f0AAAACAgJ7e3sTExMAAAAAAAC2trbr6+vV1dUfy7qlAAAAEHRSTlPv/v7/PoD/Afz+/Em0/v//iyGqkAAAAmFJREFUeNqFlD9oE1Ecxz/37tJLS0lzkkKqlaYFsRhTM4hUiXoiglWCFZwcpIuTS3AJiEN0cHCQ6OAuCjoIViqCdPDaLulk1MQ/KDRoBYXSllLapHmXOuSSy4VC3/J4v8/7fe9+/56SZucl2BWcumwYvYvNo9bYkxYgY1rU8nhoSYtBw9iDLJoej6Q1GMsCemy52Opxxuo7mQWoFB7JkAu0vHIuU79YvhK0zSZIimSm8TflYqTYAJr1LOsGUDkhTUBNwOlfgdbQZl/3b9Q98po3aNOuS/kY9wIf46Am+NA37QX2k94tBFix9gR+kqAm7AvVv21gJpQLC6Ro+cSNaBbwRSzUhM//CjrfXh/+CfdfyLk1kMZoWWBqwFrmbgEIP/9xLw6YGmpiJrQK6u+9+5ewL/aImYUSzHdXBKkIADWgS8DNEiB0NCw3H6IGDwITsC0R0Ewsm+F5O5gHyqCkjUAeYOvIV6geZN8coA6seNvn3a0uO98srStlpxYLoztJqeE/yOh3R8oM1q+vQ8XZUTQE2VIddMO2AjUB1CoIJvSmR6DjuJ17CqQ6EFgS8A8N+4YmN8//O3DVAiyJoKxkoPzQMIwIj8c632TAH8ygpO1QIN9WKHXgfVygZsLtpb1TjiPA/NwORjQQcFRPee166iwIqDLpBVUm650Yl15gqU5Tz3XkWu23Jw47TV0b67nmIl1Z/9KYj6naVDP3/mgp2hwcGd+edoj/5apq4UhBaaywdikH6LERbQkAJe2O8yrKMo1Bd2oup0wWVlZcuyMFtW/HDpXQPmqlticDZgH6d399/gNFrcHRbPSX6wAAAABJRU5ErkJggg==',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEUlJSXPz89TU1OioqIAAAABAQH9/f0AAAACAgJ7e3sTExMAAADq6uoAAAC2traDg4O2j7qzAAAAEHRSTlPt//7/PoD/Afz+/En/tP7+6n6C5gAAAkdJREFUeNqVlM9r02AYxz9588OMoS5SpgxHt4MIY5aCOMRVjf9BQfAgVrKDeN126cFL2EGYhzE8iQcdzIuiUG+CjAbUXQSJE8oEwc5NURnbFDZim7Qe0jZpFMRcXng+yfd5nx/fSEX+/gj+Cc5NGEb/xh9AmXhXgvqJfrMbKIUSw4ZxiHqlRZTwKJSGz9qAPrpViX9xoXR80AbwVqbrqQgornR4IXyxNt0XmB1QEIWF9m1qlaFKO4dSevAhKsAbqJoOyDk4/+lgvLSVp0f3QilX6S7aDMIcGlY30LBAwOt9djfwJp+AAGcw2cAVHwSB/T0J7usuAl9ko9DsHQB5yEHOqXoZ6kvXBtbhUc+rWychME57AlMFhD1TBbzU+KwF5BWk4lqmCuCnPxOkN7h9zwUx+FNgDwHQAJoSuJOA0BGUdqLcvbBwA2jWEcTr3gVrP6CBgE7HkZqQ3QVqifXpuTkWzEfLEEnV9M1jdxuhlBKX4tJ1sdobSink38TEijxbNkFSEdjVrgb2OUDDQ2DpUXTJenzZBmwNObembYOWTilG+cjL4XHjK/BjzxN4kgW1KcMwqjyfeugCWp+NVAxSB9zEoOR0OSuQ7f7kBCe8LALM9STIKCDg1K/ElujzF0FALV47tAICyPrdwJFb2/5CW47Hr1ijLeDnr8ay6F9Up+2PxcZip/faSHWkYxw/2/zWItrcjuxEHizn36/bAHpmTt0Mx1yM7LyDtIU64sR97i/m+bi9HcWRc+HZcMfOrKK+ldtjk/777/Mb0K+w2JDnGmkAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwBAMAAAClLOS0AAAAMFBMVEVWVlaioqLT09MWFhYAAAABAQH9/f0AAAACAgJ7e3sTExMAAADr6+sAAAC2traCgoJ6pGEKAAAAEHRSTlP+///bPoD/Afz+/En/tP7+y1nInwAAAmBJREFUeNqVlE1oE0EYhp+d/XFRabtaqpfSFKSWUEMUFH9qjZ48BvWkBpKbvWjsJfUiC4LHokdPLhRUBGvwJHjogkdB1hZDq5WmtoiKNmmRku5uGg+bdJMoiHMZmGfmm+9753tHyvH3IfgnGMkYRs/KH0DJzObBO9STaAVKKk+/YezBK9SJEkypfP9pE9CHVgvNJ87mD/aaAJWZMa87BIoj7bOCje5YVzWxDVIiZTWycQuRAoA8DMrinZ9hAf6Jz8eLAThTjDSXNnt/aCMI5WitRaerwR0a6VagkQYBb3aYraCSfQYCyr3tAs7UQFBNfm8HD1UHhZqIO3Dt8N5LwCvnvQVypIyUk4xP4A5Ch4Pcx8BL4EipLEiogH5r5MomPH86/8EGkgpSbilWBF/BH1zg3O3Ei9U0iN51gRkJ1FembH0uwQULEDqCfLmeS9aSOmFjAah5CBp1ex+ttXWgBmggoK746K6wELepS7Trenv7BKF+nXeaZQxDPbkLnR2AFIRSSL4FcMe/QG0Ndh5YAUlFYBYbB6gM2kylga0KgrQOyOM2QHa3l40ApoY8vKSVILOyZBg37Oip7gEfWNuoCDwpDY9vGoaRoPpgdD+gdeWRctXuDqftoeS+6bhAzve0v2DGiyOga7kdxCQQcHSzrUv0exdBgIvVClysQMS42wosud7tr/VHzeuXzaG6o/ykuBpeo39V7YY/Jrcmt9tXixaj28bx47VvdaJNlGU79OB0cn7ZBNBjE+oPAKRcaOcy0ipq1G72uT+ZZLFUCteRh4N5yzl2cg71nVysJyH99+/zG+9mvSaC2S6SAAAAAElFTkSuQmCC',
];

const COMPANY_LOGO_B64 = {
  aceken: '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',
  chemmettle: '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',
  metryscape: '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',
};

const RICHMENU_SPEC = {"size": {"width": 1250, "height": 843}, "areas": [{"bounds": {"x": 30, "y": 30, "width": 584, "height": 456}, "action": {"type": "message", "text": "เริ่ม"}}, {"bounds": {"x": 636, "y": 30, "width": 584, "height": 456}, "action": {"type": "message", "text": "punch list"}}, {"bounds": {"x": 30, "y": 508, "width": 281, "height": 304}, "action": {"type": "message", "text": "ย้อนกลับ"}}, {"bounds": {"x": 333, "y": 508, "width": 281, "height": 304}, "action": {"type": "message", "text": "สถานะ"}}, {"bounds": {"x": 636, "y": 508, "width": 281, "height": 304}, "action": {"type": "message", "text": "ส่ง"}}, {"bounds": {"x": 939, "y": 508, "width": 281, "height": 304}, "action": {"type": "message", "text": "โครงการ"}}]};

const RICHMENU_JPG_B64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEBAQFBQQFBwsHBwYGBw4KCggLEA4RERAOEA8SFBoWEhMYEw8QFh8XGBsbHR0dERYgIh8cIhocHRz/2wBDAQUFBQcGBw0HBw0cEhASHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBz/wAARCANLBOIDASIAAhEBAxEB/8QAHQABAAIDAAMBAAAAAAAAAAAAAAcIBAUGAQMJAv/EAGMQAAEDAgIEAw8OCwcCBAYBBQABAgMEBQYRBxIhMQhBURMUFRciMjdWYXGBkbGz0hY0NTZUVXJzdHWUpLLRGEJSg4SSk5WhwcMjJDNTYoLhQ7RjZNPwJSY4ZaLiZkZ2o8Lx/8QAHAEBAAIDAQEBAAAAAAAAAAAAAAMEAQIFBgcI/8QAShEAAgECAgYEDAUEAAQGAAcAAAECAxEEEgUTITFBUQYycZEUFSI0UlNhcoGxwdEWM5Kh8DVCsuEHFyPxJENUYnPiJURFgoOiwv/aAAwDAQACEQMRAD8AvIADYiAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABj1tfS22mdU1tTDTUzOulnkRjE8K7AYbSV2ZAOEq9MuBqOXmT8QQSO5YY5JG+Nrcj0dPDAnv59Vm9Ek1NT0X3FN6SwadnWj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7jHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgR708MCe/n1Wb0R08MCe/n1Wb0RqKnovuHjPBeuj+pfckIEe9PDAnv59Vm9EdPDAnv59Vm9Eaip6L7h4zwXro/qX3JCBHvTwwJ7+fVZvRHTwwJ7+fVZvRGoqei+4eM8F66P6l9yQgczZdIeFsQyRxW6+0U08mWrC5/M5FVc9mq7Jc9m46Y0lFxdmrFqnVp1Y5qck17HcAAwSAAAAA0uIcXWDCULZr7eaC2sciq3nqZGOcib8m718CKLXBugRXLwkNGMUr41xOxysVW6zKSdzVy40VGZKndPx+Epow7ZvqVR6Btq5cjGaPMlcEUfhKaMO2b6lUegPwlNGHbN9SqPQGrlyMZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6A/CU0Yds31Ko9AauXIZo8yVwRR+Epow7ZvqVR6B5bwktGL3Nb6pkTNUTNaOdETvrqDVy5DNHmSsDQ4cxrhzF7XLYb5b7krUzcymnRz2pnlmreuRM05DfGrVt5sAAAAAAAAAAAAADHr62C20NTW1L9SmponTSO5GtRVX+CAw2krs4jSfpPpdHtDExkTaq8VSKsFM5VRqNRcle9U/Fz2IibVXwqVOxFia7Yrr3Vt3rZaqZV2I5cmMTka1NjU7wxNiKrxXfa271rlWaqerkbxMbuaxO4iZIak7mHw8aUfafLNMaYq4+q0namty+r9vyAALBxQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABvy7hKWjjTRdMITRUNzkluFjVUarHu1padOVirvT/SuzkyItBrOnGosskWMLi62EqKrRlZ/zfzL/UFdT3Oip62kmbNS1MbZYpG7ntVM0UyCvXBwxfIstdhiplziRq1dIi/irn/aNTubUd4ywpwq1J0puLPrGjcdHHYaNeOy+9cnx/nIAEdacMeSaPNHNzudJLzO6Tq2jonZZ6sz8+q77Wo523jahGld2RebsrkX6eOEbLhiuq8LYRezotD/AGdZcVTWSlfszjjRdjnom9y7G55JmqbKhV1dVXOrlrK2pmqquVdZ888ive9eVXLtU9DnOe5znOVznKqq5y5qqrvVV5TwdCEFBWRTlJye0ZgA3NQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD209TNR1EdTTTSQVEa6zJYnqx7F5Ucm1C1ugvhJ1NwrqLC+M5kkmnckNHdnbHOeq5Njmy2bdyP5eu35lTRlmmS7lNZwU1Zm0ZOLuj6tbu+CJuDrj6bHmjqmdXTrNdrVJzjUvd1z0REWN691WKmfdapLJzpRyuzLad1cAAwZAAAAAABwmmWrko9GeIHxZaz4mRKvcfI1q/wU7sj3Th2ML5+Z88wko/mR7UUtJNrB1mvRl8mU7AB6A+PAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHc6HaqSk0l4ddH/1Z1hdn+S5jkUuYm5Clmifsk4Y+WN+y4umm5Dk6Q/MXYfQuiDfgk1/7vojyVb4Z1dKy34PoUy5hJNUzu35q5rWNTubnqWkKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWg4GVdKl3xfQbOYPpqeo480cj3N72538ELdFPOBn7acWfN8PnlLhlCv12WqXVQABESAAAAAAAj3Th2ML5+Z88wkIj3Th2ML5+Z88wko/mR7UUdJ+ZVvdl8mU7AB6A+PgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWX4GftpxZ83w+eUuGU84GftpxZ83w+eUuGUK/XZapdVAAERIAAAAAACPdOHYwvn5nzzCQiPdOHYwvn5nzzCSj+ZHtRR0n5lW92XyZTsAHoD4+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADPtlluN5dK230UtSsLdeRWJsY3lVV2IYC7NqkoR3mtw1o5ZT0VGkNQrObVCpnrPc7frdxENJycdx0tGYKOKnJ1HaMVdkf3CxXK1wunqqN7KduWcqORzU7+S5ondU15IWErpU3yjrGV/MpUYqN1msyRyOzzavEuX8yPpadaOqq6TVcnO0z40R2/JF2fwVBCTbsyXH4GjTpRxGHbcZczwBkvIoNzkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAN65Ez6N9AdxxQ2OuvCvoqBVzSPc96d1eLvbwaykoq7IZa1zlVGoqqm3JEzU2dHhu8XCNZKW11s8afjRwOVPIXDZhTCOBYUp6O3RyVqNXYzqVRF/Kdv8GZyGIMTW3DlMtTcalIkdtZE3a+TuNbx9/cZW0g17bskVxTB+IlVESw3PNVyT+7O+40z2Oje5jkVrmqrVRUyVFTehImJdLt1uivhtaLbqVdmsjs5nJ3Xbk8BHnVSv8AxnPcvfVVXyqCaLk+sfk3dowhfb7qLb7XVTseqokiMVGZp/qXYTzoo0GUlPRR37FTG62SSMp5MtWNO7xKv/8Awk+sxQykTney08dNA1NVJdXql73J4THYRTr22RKnV+inGNtp1nqLHUJGmzqHNeq95EXNTk6qlnop3wVMMkMzFydHI1WuTwKW3ut7WOCSrudw1IGbXSTyZNT/AN9wgvSLpBt+I4Ft9DQsmjY5FStnb1aZL/003oi93xGWjNOrKT3EbAAwTgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFl+Bn7acWfN8PnlLhlPOBn7acWfN8PnlLhlCv12WqXVQABESAAAAAAAj3Th2ML5+Z88wkIj3Th2ML5+Z88wko/mR7UUdJ+ZVvdl8mU7AB6A+PgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHsp4kqKiCFznNSV6M1m70zN4tmt67VpGeFzvvNNQ+yND8e07C2sbJcKJj2o5j5o2uRdyorkPEdKMRVhiIQhNpW4O3Fn1//AId4LDVcDVq1aalLNa7SexJO23tMaPBUkrGvjsFW9jkzRzaaZUVO4qGysuAaKorWRXGg50a5yIiTo+PZyqirnkXciY1sbGtTJqIiIibETYQFpgbNS4tdNNT1PO80LOZSthe9jss80zRFyVOTuk2B0fKNZSqVXJLhd/c6uksTQ1DVOhGLfGy2fsYNDo7wRQrG5kVOsrFz1lm2KveVVQ262DDLmq1ZI1aqZKizoqKnIRtz5F/lVH0WT0Rz5F/lVH0WT0T0WV8zy8VGOyKSJKhw/heCNGRJSsYm3JsiNTxIYdZgzBVwc51TS0cj3JkrllyVU76KcDz5F/lVH0WT0Rz5F/lVH0WT0RlfMPK1Z2OU0iaPrZbX1dRZc1ZB1TmMkcrVbx5bd6fxMeDBE74Inep+tdrNRc+dptuw6e61Cz22qggo62onmjdFHFHSyKrnOTJE63lUt7ZIZYbNbop0ckzKeNr0cu1HI1M8/CcfSeCdVxlCo487P/Z3ND16MFKE6MZLZa6X2KJTYfpKaV0U1v5lK3rmSI9rk76KuaGkutLFQTwpA1WRvVE1EXNNvHtJ50/Ma3HUKo1EV1DGqqib11npmpBmIv8AHpfhN8qnncFXr0dIRp6xtZkt72ne0vo/BYjRNao6MU8jasldNK6s7GCAgPpJ+eQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADstE/ZJwx8sb9lxdNNyFLNE/ZJwx8sb9lxdNNyHJ0h112H0Loh5rP3vojyVS4aG/BX6Z/SLWlUuGhvwV+mf0itQ66PU1OqyqQAL5UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB7IIJamaOGGN8k0jkaxjEzc5V4kQ9ZPmi3DNuobHS3ViMmuNU3WdLvWFF/ETkXl5czKVyOpNQVzpNEegiO2pBfcSsatSia8VM7LVj7qrxr3fESte8Ww0cS0lr1VeiavNWp1LE/wBPKpxclXUTMRkk8r2J+K56qniPSMvMpyk5O7OY0gYtmwtZ+fI4+bVlTKsUbn7Wtdlmrncve4yudwuNVdaqSqraiSeok66SRc173cTuFob9Y6XEVrnt1Y3+ylTY/jjdxOTuoVeuNDNbK+poqhqtmp5HRuReVFMssULW9pjHV6OYYJcV0L6mHm0cTkVrc0yR6rk1VTkRc18CHKHTYKnSluSVC/8ASkjeveRwiruxnEzcKbki1N0vlVdGRxSascESIjYo0ybs4zR3KpdRW6sqWM13wQvkRv5SoirkZKKjkzRc0XaeFajkVHIitVMlRUzzQzaxUKs33ElzxJU88XGpdKqdZHuZH3Gt3Iao3mLcOVGGL1PRTNcsSqr4JVTZJGq7FTyL3TBoLVPXLrImpDxyOTycpqk3sL0qkIRzN2RggkexaLnXpWSK6enpV3zyOREXuo3Lb5CPaqJKeqnha7WbHI5iO5URVTP+Blxsa0q0aqvE9QANSYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA99D7I0Px7TsrT7J0Hx8f2kONofZGh+PadlafZOg+Pj+0h4PpV53T936s+0f8N/6bW99/4xLys61O8eVRF35HhnWJ3jkKiyYqdPK6K/xtiVyq1qxbkz2JuOulctN2Ov1W8iDVbyIcZ0Cxd2wxfsv+B0Cxd2wxfsv+DNvaa3fI7PVbyINVvIhxnQLF3bDF+y/4HQLF3bDF+y/4FvaLvkdnqtTiQ/RxXQLF3bDF+y/4OntFPWUtBFFXVKVNUmetKjcs9uww17TKd+BW/hAe3mD5BH9t5BeIv8el+E3yqTpwgPbzB8gj+28gvEX+PS/Cb5VPMUv6oveXzO/jv6LV/wDjl/izBQBAfTD83gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADcYbwxc8WXJlvtdOss7t6rsaxOVV4jUJlmma5JxrlnkTvo1xtSYMWmgZRxxRN2rOmarIqp1z+PbypuNlFvcV69eNKyfE4rFehXFmEaDn+po21NK3JHupVV6x91UyzyPZhO8VeHIaV0WaIkaJLC9djkz3L3e6W7ixfaLha3SvnYnNI1zhXqldmnFxKhXbG2FY6Zr7nQs1Ys85ok3Nz/GT+ZtS37SjipznFNcDt7Xc6e70cdVTOzY7YqcbV40XumYQzhLFDLRcUynY+mldqSxtcir30TlQkTEmMrdh1rYpJGy18rNaKmau1ycSr+ShirKNOLlJ7Eb4bNXahFeVyNhe73S2GhfVVLkXYupEi5Old+Sn38RWO83Ga73Wtr6lqNnqZXSPaiZIirxHWXW7Vd6q3VVZKr5F3ImxrU5ETiQx6zDnP9uZUQplWIirl/mJxJ3zhx0zF1bSVov8Am09StByhRzRd58fsv5tONNrh+dIq5Y13Tt1c+PNNqfzMOht1Vcq2KipIHy1crtRkTU2qv8suPkJptmiWmoLWz+9qt2cn9pNvj+C1N+ScvGduD2pnAxf5bhbazqcG3ht1s8THO/vFMiRyJxqnEvhQ6EhuKS5YPu2bmakreuau1krf5oSXZsT2+8sTmUzY58uqhkXJyd7lJJR4o59GrdZZb0ZN4sdvv9MlPcaWOojaqq3WTaxeVF4lNVbcDWq3zc1VslQ5vWpMqK1vgQ6XJeQx7hX01qpX1VbOynpmddJIuSf8r3ENb2JnBSaujW4ru8Vhw5cK1+XURLHG3drPcmq1P4/wKu+HPunZY/xw/Ftc2Ona6O10yrzFjtjnrxvdyKvEnEhxpo2XqUMq2gAGCUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA99D7I0Px7TsrT7J0Hx8f2kONofZGh+PadlafZOg+Pj+0h4PpV53T936s+0f8N/6bW99/4xLys6xO8clPjtIppI0s9wcjHK3WSNduXgOtZ1qd4/K1ELVVFlYipxK5Drqxad+ByHq//wDstw/U/wCB6v8A/wCy3D9T/g67nmD/ADo/1kHPMH+dH+shm65GtnzOR9X/AP8AZbh+p/wPV/8A/Zbh+p/wddzzB/nR/rIOeYP86P8AWQXXIWfM5H1f/wD2a4fqf8HTWm4pdaGOqSCWDXzTmcrcnJkuRkc8wf50f6yHsa5HoitVFReNFMO3Iyr8ysXCA9vMHyCP7byC8Rf49L8JvlUnThAe3mD5BH9t5BeIv8el+E3yqeYpf1Re8vmd/Hf0Wr/8cv8AFmCgCA+mH5vAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOy0T9knDHyxv2XF003IUs0T9knDHyxv2XF003IcnSHXXYfQuiHms/e+iPJVLhob8Ffpn9ItaVS4aG/BX6Z/SK1Dro9TU6rKpAAvlQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHR2G480YlJI5Ndqf2a/lJyd9DnAi5KioqoqbUVN6G0ZZXcgr0VWhlZNOD8UOtU7aOpeq0Mq5Iqr/hKvH3iUJYY6qJ0MrUfFKmo5q7UVF2FZqC/tVEjrM0XdzVE2L30/mddcdKk0GHqa3W16urdVWSVa7mM4kbyuy4+Ikk09qKFClVjLVyRHt3omW67V1GxyubTTyRNcu9Ua5UMVZHq7XV7tfZ1WsuezdtPDnK9yucqq5VzVV4zwQtX2M6y2bTpLTOtyVsWzm+eSpyp+UdxGxI42sb1rUyQi62PqWV0LqP1w1c05MuPPucpJ8MqTRNemW1NqJxLyHk9K4F0JayC8h/s+R6vRWkIV/wDpTflr91zNvhmro7PcpqmSmiR9SiMknRvVonf5OUkprke1HNVFa5M0VOMiIzH4luVrslZDRt5rJqLzJM+qZy5eDiJtFaT1dqFZ7OD5f6+RU01ojWp4igvK4rn2e359pg6UsVU/PkVJTask9OjkVeLWXf4Ey8KkYx3iviXNKlyqq59WiO8XJ4DFmlknlfJK5XSOXNVXees9Q5PgeWp4WCTzq7ZvmY0v8UepFc5o2caN408Jqamuqq1c6mpmm25pzR6uRO8imODDbZLGlCO2KAAMEgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABZfgZ+2nFnzfD55S4ZTzgZ+2nFnzfD55S4ZQr9dlql1UAAREgAAAAAAI904djC+fmfPMJCI904djC+fmfPMJKP5ke1FHSfmVb3ZfJlOwAegPj4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB76H2Rofj2nZWn2ToPj4/tIcbQ+yND8e07K0+ydB8fH9pDwfSrzun7v1Z9o/4b/wBNre+/8Yl5WdYneOWm0e2eaWSVyVGs9yuXKXjVTqWdYneOSnnxkk0nMqWhWLWXVzfxZ7DrxvwLMrcUfrpc2X/zP7X/AIHS5sv/AJn9r/wenm+NfclB+uOb419yUH65tt5mvk8j3dLmy/8Amf2v/A6XNl/8z+1/4PTzfGvuSg/XHN8a+5KD9cbeY8nke7pc2X/zP7X/AIOhtdsgs9FHSU2vzFmapruzXauZzHN8a+5KD9c6W0Or30Ma3KOJlXt1mxLm3fs/gYd+LMxtwRW/hAe3mD5BH9t5BeIv8el+E3yqTpwgPbzB8gj+28gvEX+PS/Cb5VPL0v6oveXzPQY7+i1f/jl/izBQBAfTD83gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADc4awzXYpuKUdExNia0krusibyqvkTjM3BuCrhjGuSKma5lKxyJLOrc0bn+KifjO7ha7DWjy04KsLOemrFC3quYtXq5X5b3u43LycQIalXLsW8je16NLDbKTmKQyyyuRNeZ0io5y8uXF3jj7xaJ8M3Dmb830sm1kmXXJ96Exyua6R7mM1GK5Va3PPVTkOU0hVFPSYUrJp0RdVW6nLrZ8XdyzNpwjUg6c1dMpKU6c1WpO01tTOIa5HNRzVzRdynk4S04olp65y1SqtLKuStT/pJxKn8zumuR7Uc1Uc1UzRU3Kh4XHYOWFqZXue5n0rR+NWLpKb2S4rk/sclibDmtr11EzN3XSxN4+VyJ5UOP3kvZ5bjjsTYdRmvXUjepXqpYmpu/1J/NDq6K0na1Cs+x/Q5eldGXvXortX1OSAB6M84AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWX4GftpxZ83w+eUuGU84GftpxZ83w+eUuGUK/XZapdVAAERIAAAAAACPdOHYwvn5nzzCQiPdOHYwvn5nzzCSj+ZHtRR0n5lW92XyZTsAHoD4+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAe+h9kaH49p2Vp9k6D4+P7SHG0PsjQ/HtOytPsnQfHx/aQ8H0q87p+79WfaP+G/9Nre+/wDGJeVnWJ3jn5cc2KKR8bq5NZiq1eodvTwHQM61O8YbrPb3uc51DTq5y5qqxptU66txLTvwNT6vbB7uT9R33D1e2D3cn6jvuNr0FtvuCm/ZIOgtt9wU37JDPkmvlGq9Xtg93J+o77h6vbB7uT9R33G16CW33BTfs0HQS2+4Kb9mg8keUar1e2D3cn6jvuN1brjTXWlZVUkqSQPVUR2SpuXJd56uglt9wU37NDMhhjp42xxRtjjbua1MkQw7cDKvxKycID28wfII/tvILxF/j0vwm+VSdOEB7eYPkEf23kF4i/x6X4TfKp5il/VF7y+Z38d/Rav/AMcv8WYKAID6Yfm8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAd7o80ZXDGlXFI+OSK3a2WsidVN3GdzlduQ3eA9FqVcUVzvsTkidk+GjXYr04lfxoi/k71LIWm9WXDlEyGhppJZdVEc5GJGidxORO4hnaV6la2yJmYfwzaNH9mjXUjZzFuqxGJuXkbyqvG7epzF4vE95qVllXVY3YyNNzE+8/F1u1Rd6lZp3bE2MYm5iciGCqoiKqqiInGpmMeLK1z01VVDQ001TUytip4Wq+SR67GtTjUrnjnGU+Lbmqo5zLdAqpTw9z8tf9S/wTYbjSXjpMQVK2ygevQynfm56f9d6cfwU4vGR6Gy1Sp28pg6vCt+WNzLfUuTma7IXr+Kv5K9zkOUBVxWGhiabpz/7F/C4meGqKpD/ALkvA5zDF+59jSjqX/3pidQ53/Ub96HRnia9CdCo6c96Pb0K8K9NVIbmcRiXDy0rn1tK3+7rtkYn/T7qdzyHMEvKiLsVEVF4l4zhMR4dWhc6qpGf3RV6pibeZL6PkO9ovSea1Cs9vB/Q4GldGZb16K2cV9TnAAegPPgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFl+Bn7acWfN8PnlLhlPOBn7acWfN8PnlLhlCv12WqXVQABESAAAAAAAj3Th2ML5+Z88wkIj3Th2ML5+Z88wko/mR7UUdJ+ZVvdl8mU7AB6A+PgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHvofZGh+PadlafZOg+Pj+0hxtD7I0Px7TrKSfnapp59XW5lI1+ry5Ki5Hg+lWzF0/d+rPtH/Db+m1vff+MS9bOsTvHJT4QuUs0j24irGtc5XI3Ldmu7ea6l0z4Mlp43vu7YXuairHJE5HNXkXYe3pyYJ9/Iv2b/uL6xlBbprvR0nhKz3wfczI9Rl07ZKzxf8AJ7qXCVygqYZX4hq3tY9HKxU2ORF3bzB6cmCffyL9m/7h05ME+/kX7N/3GfDaPprvRr4FV9B9zO7BwnTkwT7+Rfs3/cOnJgn38i/Zv+418Loemu9G3gtf0H3M7sHCdOTBPv5F+zf9w6cmCvfyL9m/7h4XQ9Nd6Hgtf0H3MhzhAe3mD5BH9t5BeIv8el+E3yqS3pbxRb8WYt59tkjpaSKmZAkityR6orlVUTk6oiTEX+PS/Cb5VPP0JKWk4yi7rMvmdjSEXHQ1aMlZ6uX+LMFAEB9OPzaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdlon7JOGPljfsuLppuQpZon7JOGPljfsuLppuQ5OkOuuw+hdEPNZ+99EeSqXDQ34K/TP6Ra0qlw0N+Cv0z+kVqHXR6mp1WVSABfKgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJH0SYXhu9znudZFzSnoNXmbHtza6VdqZ8uqm3LuoRwS1oVvTWS3CzyORHS5VMSZbXKiZOTxZLl3zK3kdVtRdjvcbYvjwja21Kxc3qp36kMauyRVyzVzl35J/E5vBGlGTEl2ZbK6iigmnz5i+nV2qqomeSoqryLtN9jzB/qvtkUUUzIauner4nvTNrs02tXLi/mcrgLRhW2W7xXS7SQtfT5rFBE7XzcqZZuXdlku7fmbbbleOTI77yVc9mZFmlbG/OcT7Db5sqiRP73I3exq/iZ8q8fc2cZ0uPMaRYSt2rC5j7pUNXmEa7dVP8xU5E4uVSutRUS1c8k88jpZpXK973rmrlXeqmGzNGnfymesAGpbAAAP1HK+GRskblbIxc2uTeikj2K8tu9Lm7VbUxplIxPtJ3FI2MihrZbfVR1EDtV7F8CpxovcU5+kMCsVT2dZbvsdDR+OeFqbeq9/3JWPDmo9qtciK1yZKi7lQxbbcYbpStqIF2Lsc1d7HcimWeMlGUJOMtjR7OMozipRd0yP8RWBbZJzeBqrRvX9mvIvc5FNCStX8y5xqubavMuZO1tbduXL+ORFDc9Vue/Laet0Ri54im4z3x48zyWl8JDD1FKnulw5HkAHWOSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWX4GftpxZ83w+eUuGU84GftpxZ83w+eUuGUK/XZapdVAAERIAAAAAACPdOHYwvn5nzzCQiPdOHYwvn5nzzCSj+ZHtRR0n5lW92XyZTsAHoD4+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAeWSvp5GTRta6SNyPajtyqhtExJSoiZpqrl1rnIip30NUMjj6U0NT0hKM5Ss1s+B63o30sraDhOkqanGTva9rPdvsza+qak/KT9dB6pqT8pP10NTknIMk5Dk/hOn6x93+z03/M6f/pV+r/6m29U1J+Un66D1TUn5SfroanJOQZJyD8J0/WPu/wBj/mdP/wBKv1f/AFNt6pqT8pP10HqmpPyk/XQ1OScgyTkH4Tp+sfd/sf8AM6f/AKVfq/8Aqbb1TUn5SfroPVNSflJ+uhqck5BknIPwnT9Y+7/Y/wCZ0/8A0q/V/wDU23qlpOVP10NZXViXKVkjHMVrHtyajs8kTM/GSch5LGF6NUsPVjVzt2d93+ynpH/iJVxeFqYaNBRzpq+a9k9j2WQAB6Y+cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD3UtVNRVMVTTyuinhcj2SMXJWqm5T0gAmmw6ZqKSmjjvVNNFVIiI6WnajmPX8rLPNve2nvu+ma108DktlLPVVO5ObN1I07q7c172zvkHgzci1ML3My63SrvVfNXV0yzVMy5ucuzvIicSJyGGAYJAAAZAAAAAANjZrvJZ6rmjW68T9kkee9OVO6h3i362pS88c+RrH+Tn1f6u8jIHNxejKWJmpt2fs4nSwmk6uGg4JXXt4G3vd+mu0qtTOOlavUx8vdd3fIagAvUaMKMFCmrJFKtWnWm51HdgAEhEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWX4GftpxZ83w+eUuGU84GftpxZ83w+eUuGUK/XZapdVAAERIAAAAAACPdOHYwvn5nzzCQiPdOHYwvn5nzzCSj+ZHtRR0n5lW92XyZTsAHoD4+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdlon7JOGPljfsuLppuQpZon7JOGPljfsuLppuQ5OkOuuw+hdEPNZ+99EeSqXDQ34K/TP6Ra0qlw0N+Cv0z+kVqHXR6mp1WVSABfKgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABZfgZ+2nFnzfD55S4ZTzgZ+2nFnzfD55S4ZQr9dlql1UAAREgAAAAAAI904djC+fmfPMJCI904djC+fmfPMJKP5ke1FHSfmVb3ZfJlOwAegPj4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB2Wifsk4Y+WN+y4umm5Clmifsk4Y+WN+y4umm5Dk6Q667D6F0Q81n730R5KpcNDfgr9M/pFrSqXDQ34K/TP6RWoddHqanVZVIAF8qAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFl+Bn7acWfN8PnlLhlPOBn7acWfN8PnlLhlCv12WqXVQABESAAAAAAAj3Th2ML5+Z88wkIj3Th2ML5+Z88wko/mR7UUdJ+ZVvdl8mU7AB6A+PgAAAAAAAAAAAAAAHXYB0dXTSLW1lJa56OGSkjbK9apzmoqKuSZarV2ne/gv4v98bJ+1l/9M2PBZ9seIPkcXnFLH4lxBTYWsVfeKxkr6aijWWRsKIr1RORFVEz28pzcRiakKuSB7bQ+g8FicCsTiL32328mVfXgwYvRPZGyr+dl/wDTNFetAOObNE+Ztuhr42bV5ymR7v1VyVfAikzJwoMIK7Jbfek7vMI//UJBwZpFw9j2GV1mrdeaFEWWnlarJY04lVq8XdTNDV4jEw2yjsJ6ehtC4p6uhV8r2Pb+6KGzQyU8r4Zo3xyxqrXse1WuaqcSou1FPwXD036LKXF1kqLxQU7WX+hjWRHMTJaljUzVjuVcutXl2blKeb9peoV1WjdHltLaLqaNraubunufP/YABMcsAAA2NisdfiW70lqtkCz1tU7VjZnkm7NVVeJERFVV7hLdfwZMUUtufUQXC21VUxustMxXtV3ca5UyVe/kcTomxZR4Lxzb7rcEdzkjXwyvamaxo9MtbLjyXLPuZltK7S5gqgtrq52I6CWNG6yRwSpJK7uIxNuffRClia1aE0qa2HqdB6O0dicPOeKnaSfO1lbeUWnjfA6VkjHMlj1mua5Mla5N6KnLmXIs2gzAVXZ6ComsWtLLTxve7nqZM1VqKq9f3SouIbml6vN2uSR8yStnmqOZ/k67ldl/Ev8AYd9r9r+SxfYQ0x05RjFp2LHRXC0K1WsqkVNK1rpPnzKL6QrVSWPG9+ttBFzGipap0cUesrtVqImzNdq+E5o7HSx2ScU/Ln+RDji9Td4JvkeXxkVHEVIxVkpP5gAGxWAAAARM1ROVcgeW9e3vp5QCak4MGLlRFS42Xb/4sv8A6Y/Bfxf742T9rL/6ZbNnWN7yEX4u084cwZiGsslfRXSSqpdTXfBExWLrNRyZKr0Xc5OI5EMXXm7R2n0bE9H9E4WCnXbins2shWq4M+M4GK6Oe0VDk/FZUPaq/rMQjvE+CMQYNmbHe7XPSI9cmSrk6N68iPTNF728txhHThhLGNxit1NPUUldMuUUVZFqc0Xka5FVFXuZncXuy0GIbXU225U7KijqWq2SN6fxTkVN6LxKbrGVacrVUV5dGsBi6Tngam3tur8nxPneDc4tsEmFsTXWzSOV60M7omvX8du9rvC1UU0x1E01dHg5wlTk4S3rYAADUAAAAAAAAAAAAAAAAAAAAAAHc6HrLQYh0jWa3XOlZVUU3NVfDJnqu1YnuTPLuoimJyyxcnwJcPRderCjHfJpd7scTFFJOrkijfIrGq52o1XaqJvVctyH4L042s1usmjfE8Ftoaajh6GzpqU8TY0/w15EKLIQ4evrk2lax0tL6JejZQhKeZyV91gACc5AAAAAAAAAAAAAAAB2Wifsk4Y+WN+y4umm5Clmifsk4Y+WN+y4umm5Dk6Q667D6F0Q81n730R5KpcNDfgr9M/pFrSqXDQ34K/TP6RWoddHqanVZVIAF8qAAAAAAAAAAAAAAAAAAA8Odqtc5dzUVTyfib/Bl+AvkMgsLb+B/ji5UFLWRXTD7YqmJsrUdPNmiORFTP8As9+0yfwMsd++2Hf283/pF0cJ+1ey/IoPNtI10icJDC2jTE0uH7rQXiasjhjmV9LDG5mq/PLa56Lns5Ciq1STsi26VNK7K11/A+0h0kSvglslY5PxIatzVX9diJ/EiHFmBsR4FrW0eIrPVW6Z+eosrc2SZb9R6Ztd4FL54F4S+BMd3eC0U1RWW+4VC6kEVwhSNJncTWua5zdZeJFVM+IkTF2EbRjiwVdlvVIypoaluSoqdUx3E9q/iuTeiobKvOLtNGNTGSvBnyoBv8b4VqcEYtvGHqt2vNbqh0PNMsuaN3sfl3Wqi+E0BbTvtKrVgAAAAAAAAAAAAAAAAADym9C72h7QBo8xVoywxebth9Ki5VtG2Webnuduu5VXbk16IngQpCm9D6U8H3sMYL+b2eVSDESairMmoJOTuUn4QmELNgfSdXWaw0fOdtipoJGw80c/Jzmqrlzcqr/Ei0m3hYdmi5fI6X7CkJEtN3irkc1aTAANjUAAAlfRlwf8S6VrFUXmzV1qgpoKl1K5tZJI16va1rlVEaxUyyenHyjSbwf8S6KbFT3m811qnpp6ltK1tHJI56Pc1zkVUcxEyyYvHyFkeBj2Mbr88S+ZhHDO7GNq+eIvMzFbWy1mXgWNXHV5ii4ALJXBMOi/g44p0n2fo1T1FHbLS9zmQz1aOc6dUXJVaxv4qKipmqptRcsyHk2KXj4OemvB8Oju0Ydu14o7TdLTGsDmVsiRMlajlVr2uXYuaLtTPPNF7hHWlKMbxJKUYylaRV/SnoaxFolrKWO7871FFWZpT1tKqrG9ybVaqKiK1yJtyXfxKu0jwtNwr9LmGsX2u1Ybw/XQ3J9PVc91FVTrrRR5Mc1rEducq66quWxMkKsmabk43kYqJKVogAG5oADpNHttpbxj3C1uroWz0VZc6aCeJyqiPY6RqOauW3aihuyuErnPQQy1MzYYI3yzO3RxtVzl8CbT8H1RtWD7BhK2TQ2OzUFuYkTk/usDWKuzjVEzXwqfK929e+RUqusvsJKlPJY8AAlIwAAAAAAAAAAAAAAAAAAAACy/Az9tOLPm+HzylwynnAz9tOLPm+HzylwyhX67LVLqoAAiJAAAAAAAR7pw7GF8/M+eYSER7pw7GF8/M+eYSUfzI9qKOk/Mq3uy+TKdgA9AfHwAAAAAAAAAAAAAACfOCz7Y8QfI4vOKTXpk7GGJ/kbvKhCnBZ9seIPkcXnFJr0ydjDE/wAjd5UORiPOV8D6Pob+hy7J/Uoyu9TqNHOIZsL42slxierWNqGRTIi9dE9Ua5F8C599EOXXep+oXK2aJzeuR7VTxnWlFSTTPnlGpKlUjUjvTT7j6OcRQTSDZ2WDHGILbE3VigrJEjanExy6zU8TkL9N2sTPjQpPp0TmWle/qxVaqOhciouSovMWLmcrR78tr2H0DpjTTwtOpxUrd6f2N3gTg9X7FMEVddJUs9vkRHMSRmtPInKjNmqnwtvcJao+DRg2CJGzy3Spk43uqUZ/BrUI/p+ExcqXB1LRtoWz4kZnFJVz7YlYibJNVNqvXjTYmaZ8eRHNdphxvXzumlxRWxOVc9WB7Ymp/taiE7hiaje3Kjk08ToPB04pU3Uk1tb/AN7O5fEnK/cF+x1EDnWW6VtHU5dS2pVJo1XkXYjk8alc8V4TumC7xLarvT8yqWJrNc1c2SsXc9q8aL/wpZfg+6TLrjKG52u81CVdVQtZLFU5Ij3scqoqOy2KqKibe6evhPWaCpwfb7rqJz1RVjY0flt1JEVFTxo1fAaUq1SnV1VR3LGkNGYLF6P8YYKOVrbbs37PZ7CuGCLJT4lxdZrRVvlZTV1S2GR0Soj0Rc9yqipns5CxN14NWFKG11tVHcLyskML5Go6aPJVRqqmfUdwgjRP2ScLfLmeRS7mIva/dPksv2FM4yrOE4qLsadG9H4bE4WrOtBSaey/YfPBVziVeVmf8D6H4d9r9r+SxfYQ+d//AEP9n8j6IYd9r9r+SxfYQaR3R+Jv0M69bsX1KR6WOyTinLfz8/yITFhng8YWxPh+23ilvV15jWwNlRP7PqVVNret4lzTwEO6WOyTin5c/wAiE38GHFfPVpuWG535yUT+eqdF/wAt65ORO87b/vJK7nGhGUHa1ijounhq2lKtDEwUlJyt2pt/urkI6UMD9L/Fs9pjllmpFiZNTyyoiOexybc8tmxyOTwHMWq3TXe50Vvp01p6uZkDE/1OciJ5SzHCgw1z1Y7Xf4mf2lDKtPMqf5cm5V7zkT9YjTg8Ye6NaQ4Kt7NaC1Quqlz3a69Qz+LlX/ab0696Gse9FbG6JyaV8EgrRk1bsf229xKCcFvD2W29XXP836JWnEFLQ0V8uNLbJpZqCCd8UMsuWtI1q5ay5bNuSqXZ0s4o9SOArvXxv1ap8fO9Py80f1KKnezVfAUU3EeCnUmnKbuW+k+HwmFnChh4KL3v6fUHlvXt76eU8HlvXt76eUvHlUfR1nWN7yFKNPXZYv8A+Y8ywuuzrG95CIMbaAbfjXE9dfZ7zWU0tXqZxRxMVrdViN2Ku38XM4eDqxpTcpcj6n0iwFfHYWNKgrtST5bLP7lSrZzx0Souddbnrm8fMtXfr6yauXhyPoqnW7d/GRXgnQHhvB1zhujpaq418C60LqlWoyJ35SNam/urnkb3SLpOtGj62SvnnjmurmrzvQtdm97uJXInWt5VXwZqSYmqsRJRpq5V0HgZaHoVK2Mko3tx3Wv+7vuRVjTfPHU6U8RPiVFa2SONcvymxMRf4oYejvRnd9I1wfFRatPQwKnPFbKiqyPP8VE/Gd3PGqHKVtZVXi41FXUOWatrJXSPd+W9y5+VS+WA8K0+C8KW20QMRHQxosz03ySrte5e+v8ABELleq8PTjFbzzmidHx0vjalapshdt/FuyODs/BvwZb4WJXNrLjNl1T5p1jaq9xrMsvGp7rpwdMD18Lm0tLV0Eipskp6lzsl7z9ZFI60v6c71BiKsseG6vnKkoHrDNUsaiySyJ1yIqouq1F2bNqqi7TT6OtPmIrdfaOlxBWrcbTUyNikdM1qSQ6y5a6OREzRF3ouezkK6pYlx1mb4HYljtBwreCOirXtmsrX7d/xOV0l6KLro4qo3TPSstM7lbDWMbq7fyXp+K7LwLxchpMAWCkxTjKz2aufNHS1sqxvdCqI9OpVUyVUVN6JxF38Y4apsX4auNnqmtVlVErWuX8R+9rk7qORFKZ6J45KfSjhuKRNWSOu1HJyKiORf4k9DEOpSlfejlaU0NTwWPoqCvTm1sfarr9yYcXcHCw2jDNzrrTUXmpuUEKvp4XPY9JH8TckYirn3z1YP4MUDqWOoxTcJ0qHpmtHRORqR9x0ioua95ETuqWJlmZTQPmlcjY42q5zl4kRM1UptjXTvijEV0nda7jParW1ypBDTKjXq3ic929VXfkmxCtQqV6ycYv4nZ0rhNE6OlGtVp3vsUVu9rf8+BMlx4MuEqmnc2jqbnRz/iyc2SVEXutcm3xoV30g6Obto6ujKS4I2WmnRXU9XGi6kyJv7zk408qEqaEdMl7q8S02H7/XPrqavzZBPNkskUuWaIruNFyVNu5ciY9LuFYsW4Cu1MrEWpp4lqqZ2W1sjEVUy76Zt8JvGtVoVFCo7pkFXR2A0rgpYnBQyTjfZ7Vts1u28GUZJh0c6AbrjGkiud1qHWu1Sojok1NaeZv5SIuxrV4lXfyHN6G8Iw40x3b6Oqj5pQU7Vq6hi7nsZlk1e4rlai9zMuXifEFJhHDtfeKtF52oYlerG7Fcu5rU7qqqJ4SXF4iUGqdPezndH9DUcTTli8X1I8Odtrb9iI6peDfgenjRskVwqHIm18lW5FXwNRENZe+DFhqsgctqrq+gqPxdd6TR+FFyXxKQXiHTHjLEFwkqVvdXQxOdmymoZVijjTiTZtXvqqkkaFdNd3nv9Lh7EdW6tp653M6eqly5pHLxNcv4yO3bdqLkRypYmEc+YvUcfoXE1VhnQsnsTsl8tqIixxgG84AuiUV2hbqSZrBUxZrFM1N6tXlTjRdqGBhK1U99xTZbXVOkbTV1XFTyOjVEcjXORFVFVF27S7Gk7B0GNsHXG3PjRaprFmpX5bWTNRVbl3+tXuKpTLR77fsLbMl6J02zk/tGk9DEOrTbe9HJ0roiOAxtOEdsJtWv27UWCvXBqwtb7PcKuC4XhZ6enklYj5o1armtVUz6jdmhH2jLQFcMZUEF3u9S+22qdqPhYxqLNO38pM9jWrxKuarycZbiop4qunlgmYj4ZWqx7V3OaqZKniIh0saZabR22OyWWnhnvHM06l3+FSsy6nNE3rlubs2bV4s6VLEVp+RF3bPUaQ0PozDtYmslGEVuXF8P59Dn8a6BMJYewrVVtItwWqifC1sklTn10rGLsyy3OU7DCGgfDmDcQ0d7oK26SVVLr6jJ5WKxdZqtXNEYi7lXjKyXjSzjK/Mljrr7O+CRzXLCxjGR5o5HJsROJURfASDoe0nYuxDpFs9tud8qKmhn5tzSF7GIjsonqm5qLvRFJ6lGuqbvLnc5WE0joqeMiqdBq7io7Fsd3t3+1dxZ2+WiC/2avtdS6RlPWwPgkdGqI5GuTJVRVRdu0iH8F/CHvjev28f/AKZJuO6+pteC8QVtHKsNVTUM0sUjUTNjkYqou3ulOunRj3tlqv1I/RK+Fp1ZJ6uVjr6dxmj6FSCxlJzbWzd90c1im1w2TE15tlO57qehrJaeN0iorlax6oirlx5IakyK6tqLlW1NbVyrLVVMjpZZHb3vcuaqvfVTHOwr22nzao4ubcVZX2AAGTQAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAfib/Bl+AvkP2fib/Bl+AvkMg+r+E/avZfkUHm2lE+Fp2Zqz5BS+RxezCftXsvyKDzbSsWn7QDjXSFpHqb5Y6agkt8lJBCjp6tI3azUdn1OS8qHPoSUZ3ZdrJuGwqEyaSme2aFzmTRKkjHNXJUcm1FTu5oh9Y7LUS1dnt9ROmU81PG96ZfjK1FX+KlOdHvBAxC+/UlVi+ooKa008jZJaammWaSoRFz1M8kRrVyyVc1XLcnGXQmmipKeSWV7IoImq5z3KjWsaiZqqrxIiG2InGVkjWhBxu2fPrhZtZDpluz2Ims6ipnv+FzNU8iITfZOB9gi5Wa31st0xAktTTxyuRs8SIiuairl/Z7tpVnTHjGPHukHEt+gcrqOplVlMqplnCxqMYuXdRufhPpThT2rWX5FB5tpvVlKEIpGtNRnKTZ8ytI2HKXCGPMQ2GikmkpLbVugifOqK9zURNrlRETPbyHMtTWc1OVUQ77Tj2X8a/OUnkacFH/iM+EnlLMdqRXlvZeRnAywI5jV6K4i2p7oh/8ASKh1+G6Kj0lVGHOaTrborytv11cnNOZJPzPPPLLWy7mWfEfUeL/DZ3kPmXiRctNdzX/+Su/7srUJyle7LFaEY2si0VfwN8EwUFVLDdcQLNHG9zEdPEqayIuWf9nuzIh0N8F+5aQrbT32/Vklpsc6a0DI2ItRUt/KTPYxq8SqiqvJlkpfB7GyxvY9qOY5FRUXjRSpem3hM3DCd9nwlgaOkpWWrKnnrXxJJqvamSxxsXqURu5VVF2pkibM10p1KkvJRtOEI7Wdw7geaOlp1ja+9tkyy5slbm7Ply1dX+BW3TboAuWiV8Nwp6p1yw7UP5myqVmrJC9dzJETZtyXJybFy3Iu+TNBXCYxRe8b2/DuLKiCvpLq/mENS2BsUkMuSq1F1ERHNVUy3ZoqptLL6UMNwYu0e4js87NZKmik1P8ATI1usxfA5qKZzzpytJjLCpG8UfLkmDRDwecQ6VY0uKyttWHkcrefpmK50youSpEzZrZflKqJ39xw2jbCT8e43sGH0VzGXCoa2Zzd7IkRXSKndRrXeE+nTGW3CdgyjZHR2m10yqjWpkyGKNufiREJa1Vw2R3kVGmpbXuINt3A5wBSwNZWVN6rZ8uqkdVJGir3GsamX8TWYj4GOFqymethvNzt1UiLq88ubURKvIqZI7xKQXpA4TONsW3meW0Xapsdma9UpqajVGP1OJ0j8s1cqbVTNETdlxm80UcKbE2HLxTUmLa+S8WCZ6Mllmai1FMi/jtciZuRONq5rlu279MlZK9zfNSbtYinSFo3v+jG/dCr7Tta56K+CoiXWhqGIuWsx3lRclTj4i/nB97DGC/m9nlUp3p605S6WbpDRUNMlPhy3yq+mSRic2mdllzRy/ioqbmp4c13XE4PvYYwX83s8qmK7bprNvFFJTeUiTSXwfLzpY0zXW4yVKWvD0VNTRrVuZrvmcjNrY27lyzTNy7E7u06Sl4HmjyGnbHNLeqiXLbK6s1VVeVEa1EPVwltOlfo3jorBh10cd9r4lnkqntR/OsOatRWtXYr3Ki5Z7ERFXLahWCwcIXSNYbxDcXYmrrgxj0dJSVr0khmbxtVMupz5W5KghGrKKadjMnTjJpq5J2lnglVOGLZU3rB9bU3KlpmrJNb6lEWdrE2q5jmoiPy/JyReTPcVi3n1fw1fqbFOHrXeqPPna400dTGi70RzUXJe6meXgPnPp5wtBg/SziW20kbY6N0zaqFjUyRjZWo/VTuIquTwG9Co5NxkaVqaj5USOAAWCAvRwMexjdfniXzMI4Z3YxtXzxF5mYcDHsY3X54l8zCOGd2MbV88ReZmKX/AJ/xLn/klFwAXSmCzegjg64X0oYES+3euu8NWtXNBqUksbWarFTJcnMVc9vKVkL88EDsQN+cqnytIa8nGN0S0YqUrMrTwh9E9m0S32yUNlqa+eGupZJpFrHtc5HNejURNVrdmSnJaMNF170q4gW12hGRRQtSSqrJkXmdOxVyRVy3qu3Jqb8l3IiqTTw2PbdhT5BN51p3XAqSj9RGIlj1ef8AomnNuXU5kzUz7nX/AMTXWNUs3EzkTqZeBtbHwO8CW+mY251N1ulVl1cjqjmDFXuMYmxO+qnqxFwOcFXClelmrbnaqzLqHLNzxHn3Wu25d5yGz4T8ukOmw7a58EyXCOijfItyW2Z88ImSai7Oq1Ouz1e5nsKx4F4SWPMF3LXrLpUXyh2tlornKr1zy4pFzcxUXvp3COCqTWZSJJOnF5WjjtJejW/aLL1JbL1C1dZjpKaqizWGpYn4zVXjTjau1PEq27wJwWMH26XDeJYrle3V1MtPXtjdPFzNZE1XoipzPPVz7u7jKfY+0hYg0lXh9zxBWrO/JWxQM6mGnYv4rG8Scq7141UkTRnpu0gVmNsIWefE9W+2zXGlpXwKyPVdEsjWq3rc8stm8mnGbirMig4KW4+gksaSxPjdnk9FauXdK7LwMsCLmvRbEX0iH/0iw1U9zKWZzVyc1jlReRcj5vu4Q2k7Nf8A5vrf2cXoFajGbvldixVlFWzI1emLBlBo+0jXnDlsmqJqKi5jzN9S5HSLrxMeuaoiJvcvEcKbPEOIrpiu71F3vNZJWXKo1eazyIiOdqtRqbkRNiIieA1heimkrlN2vsAAMmAAAAAAAAAAAAAAAAAACy/Az9tOLPm+HzylwynnAz9tOLPm+HzylwyhX67LVLqoAAiJAAAAAAAR7pw7GF8/M+eYSER7pw7GF8/M+eYSUfzI9qKOk/Mq3uy+TKdgA9AfHwAAAAAAAAAAAAAACfOCz7Y8QfI4vOKTXpk7GGJ/kbvKhCnBZ9seIPkcXnFJ10o22rvGj/EFDQU76isqKVzI4o+ueuabEORiXbEr4H0jQqctCNLfaf1KHrvU2WHLe+7YgtNBG1XPqquKJETuvRPIdG3RDjp78kwxcEVV40aiePWJp0MaDq/Dl3jxDiRsUdVTovOtGx6PVjlTLXeqbM0RVyRM9+Z0KuIhCLdzx2A0PisRXjB02lfa2mklx3lgOIozpYnfedKWIkp2rLI6sSmjazarnNRrERO7mmRcvF+JqTB+HLheKxyJHSxq5rVXbI/c1id1VyQpdo6rUq9J+HqyvcjnT3Nksjnble5yqi/rKhRwMWs1Tkj1XSurGo6GDvtlK79nD6vuJ/wBwdrJaaGGqxNElzuj2o58DnLzCFfyUROvVONV2ciHX3G56NsIy85VbsO0EzNiwcziR7e+1EzTwna3FtS63VTaRUSrWJ6RKvE/VXV/jkfPO4UtdSXCeC4xTx3BHrzZkyKkmvntzz2quZrQjLEtuciTSlejoOnThhqKd+L9nN7232l68J4lwhfKmojw3V26eeNiOlSkYjVRueSZ5ImzM4vhJ9jd3y6Dyqc9wasFXWzxXW+XKmlpYq2OOGnjlarXvaiq5X5LtRNqInLtOh4SfY3d8ug8qmkYRhiVGLvtRaqYiriNDVKtWGVuL2fIrfon7JOFvlzPIpdzEXtfunyWX7ClI9E/ZJwt8uZ5FLuYi9r90+Sy/YUlx/5kTn9E/Mq3b9EfO/8A6H+z+R9EMO+1+1/JYvsIfO//AKH+z+R9D8OKi4etaptRaSL7CEmkd0fiVuhn5lbsX1KSaWOyTin5c/yIfjRlipcG43tN0c5W0yScxqe7E/qXeLY7/ae/S5DJDpMxMyRjmvfWOe1qpkrkVEVFROPM4tzVRVa5FRU2KipkpdhFSpqL4o8xiKs6GOnVhvjNvuZ9AcZ2CPFmE7taHZKlbTuYx3Ej8s2O8DkRSL+DRhl9pwrcbpURKypuFUseSptRkWbcv19fxHU6EcWeqvR/b3yya9bQf3OfNdqqxE1XeFuqvfzO8ZFS2ukfqNjp6aPXkdkmTW5qrnL41VTiSlKnGVF8z6dSoUcZVo6Rjwi/3+23vK1cKHFHPFztOHIX5spWLVzoi/ju6liL3mo5f9xX03uNMRSYsxVdry9VyrJ3PjRfxY02MTwNRDRHaoU9XTUT5lpXF+GYupW4N7OxbEDy3r299PKeDy3r299PKSnPR9HWdY3vIQNpE0+3LBWM7jY4LNR1MFJzPKWSZ7XO1o2u3ImX4xPLOsb3kKUaeuyxf/zHmWHEwVONSbUlfYfUekuMr4TCRqUJZXmS+FnzLN6LdKNJpLttTKylWjr6NzWz0yv10RF61zVyTNFyXi2Khx3CKwDS3XDcuJaSna26W7VWd7EyWaDPJdbl1c0VF4kzIZ0EYp9TOkKhZI/VpLmnOUua7EVy5sX9ZET/AHKXNrqOG40VRSVLEfT1EbopGL+M1yZKniU2qx8GrJx3EWj63jvRkqdfbLam/bwf89p8/cLsY/E1lZJ/huroEdnyc0afQlNx8+8R2aqwZimutr1Xni21OTHL+MjVRzHeFNVfCXvwzfabE+H7dd6VyOgrIWypl+Kqptb30XNPAS6QV1GS3HP6Hy1cq9CeySts7Lp9xx9ToPwBV1E1RNZEfNM90j3LVzZq5VzVev5VPWmgjR41UVLE1FRc0/vc3pkD6XNEl9sWJLhcLZQVNZZayV08b6ZrnrCrlzcxzU2pkqrku7LI4azYBxViCqZT0FkuMj3LlrPidGxvdc52SIhtClKUcyq7P57SPEaQp0a7oy0enK/JbfavI4l+NZiIiayZJ3SmWF42w6fYI2Jk1t8mRMvhSG8xdweLxh7CtPdKOrdcK+Bivr6aPPJqb84uN2qm9F2rvTkOH0RrnpMwuu/OsT7LjNClGMJyhK+w00rj69fFYelXo6tqSe+97texfEurif2s3j5HN5tT56s6xnwU8h9GK2kZX0NRSyZ8znjdG7Lfk5Ml8pQbGGDrnge8TWy6QPjWNypFMqZRzs4nNXcuaeLcpro6S8qPEk6ZUZvVVUvJV1fuPbo+c9mPMMOjz10uVPll8YhfeqY2SmmY/rHMci97Ip9oCwTWYhxpRXd0D0tVqfzd86pk18iJ1DGrxrmua5bkTuoWjx/fosM4MvVzldq8wpnoz/VI5NVieFyoaY55qsYreWOisHQwNWvU2Rbv8EtrK+cFtjExVf12a7aJqN73NNvkQkzhHSSM0Z1CMVdV9XA1+X5Otn5UQgnQDiWLDekKkZUyIynuUTqJz13I9VRWL4XNRP8AcWsx9hVmNcI3Syq9sclTH/ZSOTYyRqo5ir3M0TPuZmcT5GJU5btg0KvCdC1KFPreUvi9q7yghssPSSRYgtL4lVJW1kKty3580bkeL5Yblhu4S0F1opqSriXJWSNVEXutXc5ORUJJ0HaNrhiXFFBeKmlkislulSdZpGqjZpG7Wsbn123JVXciJ3To1KkYwcm9h4rB4StWxMaEIvNfu7ewuLxeEohhZrWaVbO1mWo2+Ro3Lk542F0saYkgwjhe6Xid6NSlhc5iL+PIuxjU7quVEKQ4Ac5+P8MOeub3XSnVy8qrK3M52Bi8k5Hs+lNWLxGGpcU797X2ZfqRyMY5y7mpmp88r9d579e7jdKlyunrJ3zOVe6uxPAmSeA+hNV62m+A7yHzlXevfNtHLrPsIumc3ajHh5X0BI+gXssWD8/5l5HBIeguZkGlXDznqiI50rEz5VheiF+t+XLsZ5PRjtjaPvR+aLaaSux9ij5un+wpQhD6C4xtk17wne7dTpnPV0U0MaLxucxUT+J8/wCppaihqJKaqgkgqYl1XxSNVrmqm9FRSlo5rLJHpemUJa6lK2yz+Z6gfqSN8T1ZIxzHpva5FRU8Cn5OieMAAAAAAAAAAAAAAAOy0T9knDHyxv2XF003IUs0T9knDHyxv2XF003IcnSHXXYfQuiHms/e+iPJVLhob8Ffpn9ItaVS4aG/BX6Z/SK1Dro9TU6rKpAAvlQAAAAAAAAAAAAAAAAAAH4m/wAGX4C+Q/Z+Jv8ABl+AvkMg+r+E/avZfkUHm2nB464QeDNHeIZLFe5q9tfHEyZUgpHSN1X55dUneO8wn7V7L8ig820onwtOzNWfIKXyOOdSgpysy9Um4xuif7hwxsAU0DnUlNe6ybLqWNpUjRV7qvcmRX3S3wlsQ6S6Oa0UdO2zWCXZJTxya8tQnJI/Z1P+lEyXjVSEgW40YRd0VZVZSVmfib/Bl+AvkPq9hT2rWX5FB5tp8o3N1mub+UiofUXRVeosRaNsK3GF2s2e3QI7uPaxGuTwOaqEWK3Ikw+9nz6049l/GvzlJ5GnBxIrpY2omaq5ERPCT/wmdE+ILbpEueIKC1VlZZrw5s6T0sLpUil1Ua9j0aiqi5tzTiVF7imLoJ0A4gxZim3XW92upt+HKCVtRI6rjWN1UrVzbGxrslVFVEzduRM+NSaNSKgncjcG5tF+Y0yjai8iHzLxL2a7n/8A3K7/ALs+m3EfMnEqZaa7mn/8ld/3ZWw29k9fgfTbi8J8n8SSvnxHeZZHK6R9dUOc5d6qsrj6wcXhPk5f/Z67fLJ/OONsLvZjEbkb/RS5W6UMFqi5L0YpPOtPp7XIi0VSi7ljd5FPmDoq7J+C/nik880+n9b6zqPi3eRTGK6yGH3M+f8AwUGMdpqtquRM2UdU5nf1ETyKpb/T7NLBobxm+FVR/Q97c05FVEX+CqUP0N4uiwNpPw7eql+pRxVCw1D13NikRWOcve1s/AfSPENlpcU4duVoql1qS5U0lO9zdvUvaqZp480FfZNSYobYNHyhXep4Onx1gC+6Or5UWm+UcsT43KkVRqLzKoZxPY7cqLyb03KbzRVofv8ApTvcFNRU01PaGvTnu5vjXmULOPVVdj38jU8OSFvMkr32FbK72I9Teh9KeD72GMF/N7PKpRPSlomvuim+85XONZqCZyrR3CNq8yqGp9l6cbV8GabS9nB97DGC/m9nlUr4hpwTRPQTUmmVE4WT3O0z17VVVRlFSo1ORNVV/mQim9CbOFh2aLl8jpfsKQmm9Can1ERVOsz6VcH9VdoZwWqrmvQ9nlUqDwsOzRcvkdL9hS3vB97DGC/m9nlUqFwsOzRcvkdL9hStR/NZPV/LRCQALhVL0cDHsY3X54l8zCOGd2MbV88ReZmHAx7GN1+eJfMwm54VOEr5jHR/bqGwWuouVZHdI5nQ06IrkYkUqK7aqbM3InhKN7VtvMub6R8/gSH0iNJXaVdv1WekOkRpK7Srt+qz0i5njzKmWXIjwvzwQOxA35yqfK0pTijAGKMFR00mIbHWWxlU5zYXVCNRJFRM1RMlXdmhdbggdiBvzlU+VpDiGnDYTUFae0iXhse27CnyCbzrSGtFelS86J8Qrc7XqT087Ujq6KVVSOoYi5pt/Fcm3J3Fmu9FVCZeGx7bsKfIJvOtIZ0baJsS6UrktNZKTVpI1RKivnRWwQd934zv9KZr3t5tTtqlm3Gs76x2LyaPuENgfSBHDDFcm2y6vTJaC4OSJ+tyNd1r/AufcQ3GO9C+C9IscjrxZ4UrnJsr6VOZVDV5ddOu7zs0PnbjXAl+wDd5rXf7dLTSscqMkc1Vimbnscx+5yL4048lLYcDqtxfV2m8pdJayXDESRtoHVauVEkzXXSJXbVZllnlsRd3GQzpKCzwZNCpmeSSK+6adCty0Q3aBr5+frLXK7nStRuquabVjenE5E27NiptTcqJzmirsn4L+eKTzzS3/DImpmaLKOKVW88yXWHmKLvzRj1cqf7c/GU70aVEdJpGwhUTORsUV2pHOcvEnNmk1OTnTuyGcVGdkfUSt9Z1HxbvIp8k3b1759b5o+bQyR55I9qtz758pcTYduOE75XWi60stNW0kro3Mkaqa2Srk5vK1U2oqb0Uiwr3kmJW41IP3JDJDq80jezXbrN12qmsnKme9O6fgtlYAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAmPg9Yqs2FL5ep71cYKGKemjZG6ZVRHOR6qqJ4CwnTjwJ2z279dfuKMZ5HnNeVSpVwcasszZ6HR/SOvgaCoQgmlfffj8S8i6Y8BtTNcTW/wOVf5GgvnCLwVa4n851NTc5kTqWU0LmtVe65+SeUp1mvKp4NFo+mt7ZaqdL8ZJWjGK+D+53WkfSnd9I9YxapG0ttgcroKKJ2bWr+U5fxnZcfFxIcPHI+KRkkbnMkYqOa5q5K1U2oqH5BcjCMFlith5qviKuIqOrVleT4lsdHfCGst1t0FJiaobbrrG1Gune1eYTqn42adaq8aLs5FO8rtJGBaZiVdRiKzOVqZo5szJHp3kbmpRIbipLAU27p2PR0OlmLp01CcVJri7/v8AxFqmcI+0VmNaKiiVaXDSNkSeuqGKjnv1eoVG72tzTj2rmm5DG006RcH4swBXUFsv1NUV7ZYpYoWteivVr0zRM0y3Kq+Aq8M1Nlg6cZKUeBXn0lxdWjUo1Ump357Lq1lt4HUaObjS2jHeH66unZBSU9W2SWV69SxqIu1S2F70u4IqbNcIYsS290slPIxrUeuaqrVRE3FJzzmvKpvWw0aslJvcQaN03W0fSlSpxTUtu2/Kx+Wp1DUVOJEVPAWp0Q6b7G/DtDZcQ1zKC4UMbYGTT7Ip2N2NXW3I5EyRUXkzKrg3rUY1o5ZFbRuk62jqutpbb7GnuZee66R8A0Strqq+2aWWNOpfG9k0id7VzUpxji52+9YvvVytTJWUFZUumjSVuq7qtq7OLN2a+E01DSrW1tNStcjFnlZEjlTYms5Ez/iTfDwW8Quq0bLerW2kz2ysbI5+XcYqImf+4rwp0sK7ylvOtisXjtOxUaVFWi+HN822bDgrtuPRHELmp/8ACVijSRV/zs11cv8AbrZ+AkvT3ij1N6Pa6KKTVq7oqUUeS7cnbXr+oip4UOuwbhC24Ew/Babc1eYx5vklflryvXrnuXlX+CIicRVXTvpAixriptLQSpJabUjoontXNssir1b07mxGp3Ez4ytBeEYjOlsR3cTJ6H0OqE5eXJNL477di/ftIqAB1j52Dy3Y5vfQ8AAu+3TdgBGtRcS027/Lk9EqxpfvdvxHpEvFztdS2qoZ+Y8zmYiojsomNXft3oqHD5rygrUcLCjLNFnc0np6vpGkqNWKSTvsvya4t8z9RyPikbJG5WSMVHNcm9qptRfGXMw9p3wbV2O3zXO+QUtxfAxaiBzH5sky6pNjct+ZTEZqbV8PGtbNwINF6Xr6NlJ0knm339nY0S7p8vGGMTX2gvWHrpBWTSxLBVsja5FRW9Y5c0TiVU8CGFon0xVmjuR9FVRPrLFM/XdC1erhcu9zM9m3jau/uLvi/MGyoR1ere1EctKVvC3jafkyfLd7d99/EvLZ9MmB71C18WIKSB6pmsdW7mD29xUdl/BT33LS1gm0xLJPiW3PyTPVgl5s5e8jM1KJjcVfF8L72d1dMcVls6cb89vyv9Sc9KPCBmxPRz2bDsU1JbZk1JqqXqZpm8bWonWNXj41TkOA0R9kzC/yxPsuOLO00R9kzC/yxPsuLDpRp0pRiuDOPHHV8bjqVWvK7zR7Ft4F3rtWvt1orqyNrXPpoHyta7cqtaq5L4iP8N6ZMEY1t8KVtZSUVU5qLJR3HVbquy4nO6lyd1PEh2+J/azePkc3m1Pnq3rGp/pTyHNwuHjWi770e10/pito6rTUEnGSd0/gXyr9I+C8P0aOlxBao4WJ1MdPM1695GMzX+BWPTDpfk0hTx2+3xyU9hpn67WybH1D9yPcnEibck7ua9yKkRE3Iid4F+jg4Unm3s8ppHpHicbT1NlGL324/HkeUVUVFRVRU3KhY/RvwjoIKOC24vSXmkSIxlyiar9dE3c0am3P/UmefGhW8E1WjCqrSObgNJYjAVNZQe/euD7S90OkjAt2ha/1RWaRibUSedjVTwPyVDX3rTZgaxQOVb3BVyNTqYaFObOd3Ey2J4VQpCu3eCotHwvtbPQS6YYpx8mnFPnt+5IulLS1cNI9VHDzNaOzUztaGlR2audu13rxuy3JuT+Jy2CqyC3Yyw9WVUrYaWnr4JZZH7mMbIiqq9xENGC5GnGMckdx5urjKtav4RVeaV79xeOo0w4FfBK1MT27NWqidWvJ3iji71POa8qngjoYeNG+V7y7pXTFXSWTWxSy33X42+wMq23GptFxpLhRyLHV0krZon/kuauaGKCfeclNxd1vLmYM09YVxHQQ9Ea6G03PJElgqnarNbjVj12KnfyU6Gv0i4Fpv7xUYhsrnNTY5s7JHJ3ss1KJBNm4ovR8G7ptHq6fS7FRgozhGT57TrdJ98osSY9vd0tsyzUNTK1YpFardZEY1ueS7d6KckAXYxypRXA8vWqutUlVlvk2+8AAyRgAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAD8yoqxSIm1VaqJ4j9AA+i+HNPOjejw/aqefGNqZNDSxMexZFza5GIipu5UKhcJHE9oxfpRqrpY7hBX299HTxpPAubVc1HZp4M0ImzXlU8byKFFQd0STquSswACUjBYjg68IOm0cwPw3iTmq4fllWWnqY2q91I93XIrU2qxV27NqLnsXPZXcGsoqSszMZOLuj6dU+mfR7VUiVUeM7HzJUz6qsYx36qqi/wACFNM3Crs1PZa2zYGqXV10qo3RLcmtVsNMipkqsVdr38mWxN+a7imHHnxgijh4p3ZLKvJqx9EsK6f9HUeGLKysxdbYattFCk0Uki6zHpG3Wauzei5oUoxfdLbU6Y7pdaKsimtMt+57ZVMXNjo1ma9XZ8mSr4jhc15VPBtCkoNtGs6rkkmfSn8IHRll7dLTv/zV+4+cd5mjqLxcpono+KSqmexybnNV7lRfEph5ryqeDNOkqe4TqOe86XR3cKW06QMK19bOyno6S6U000z16mNjZGq5y9xETMv/AFWn/RnJTTMbjS06zmORP7ReTvHzbPOa8qmKlJTd2IVHBWQdtVeQs3oR4Uy4SttNh3GMdRVWynRI6W4QprywMTcx7d72pxKm1E2ZKVjBvOCmrM1jJxd0fTGj0zaNcQ0qObi2xviXbqVU7YlTvtkyVF8Brr/whtGmFqVyriOjq3xp1FNbP7d7u4mr1KeFUQ+b67d+0EPg0eZL4RLkStpq04XLS7c4GcxWgsFE5XU1FraznOXZzSRU2K7LYiJsairlnmqlmdC+mjAOHdFuFbXdMVW2kuFJRNjmglkVHRuzXYuwogec15VN5UYyiomkarTzErcI3E1oxdpTrrpY7hBX2+Slp2NngXNqua1UVPARSm9DxvBJFZVY0bu7l79C+mjAOHdFuFbXdMVW2kuFJRNjmglkVHRuzXYuwrPwjcTWjF2lOuuljuEFfb5KWnY2eBc2q5rVRU8BFOa8qnjeaRpKMnJG8qjlHKAASEZbrgtaUMH4JwBcaDEGIaG3Vkt0kmbDUPVHKxYokR27dm1U8BN/4QOjFf8A+tLT+1X7j5rZqnGec15VIJYeMndsmjXcVY+lH4QGjHtztH7RfuH4QGjHtztH7RfuPmvmvKozXlU18FjzM+ES5FnOFjpEwtjm34Vjw5e6O5PpJ53TNp3Kqxo5rURV2ceSnVcGbStgvBujNttv2I6C31/P08vMJ3qjtVypku7jyKcZqp5RV4syR0U4ZDRVXmzE/cK3G+HscYlw7U4du9LcoKajljlfTuVUY5ZEVEXZyGNoD4Qr9FjJbJeaaWsw3PKsrVhyWWkevXK1F65q71bvz2pvVCClz4z86zVXLWTWTiz2m2rWXIzGsebMj6W23TbozxNSNc3FVm5muTlirpEhc1e62TLaYWI+ETo2wtSvcuI6WulYnUU1s/vD3dxNXqU8Koh84F7oIvBo8yTwiXIknTLphuWl2/xVU0S0dpokcyiotbW1EXrnuXjeuSZ5bEREROVY3a5zHI5jla5q5o5q5Ki8SoeATpKKsiFtt3ZevRLwpsNX+y0lDi6vjtN+gYkck06KkFSqbNdH7mqu9Wrlt3ZoSZcNKujdImz1eLMOStYmaKtXFIqd5EVVPmQN24geGi3dEyrySsyXuEljSx460jpcsP1qVlvioYqbmzWOY1Xtc9VRusiZp1SbdxEIBPGOVWRDJ5ndgAGTAAAAAAAAAAAAAAAAAABZfgZ+2nFnzfD55S4ZTzgZ+2nFnzfD55S4ZQr9dlql1UAAREgAAAAAAI904djC+fmfPMJCI904djC+fmfPMJKP5ke1FHSfmVb3ZfJlOwAegPj4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB76OpdRVlPUsajnwSslRHblVrkXJfEWBg4VdS2HKbC8Tpfyo61Ub4lYq/xK7gjqUYVOurl7B6SxWCv4PPLffsT+aZJ+N9O2JsZ0slA1YrZbZE1ZIaVV15E5HPXbl3Eyz4yMADaFOMFaKsQ4nFVsVPWV5OT9oABsVwAAAAAAeVRU3oqd9D32/1/SfHR/aQmjhLIiX2wZIif3SXcn/iEcqlpxhbfcuUcJrMNUxGbqW2c7sg8AEhTAAAB2OiiaOn0j4allkZHEyrRXPe5Goiart6qccFRF2Kmad0xKOaLjzJaFXU1Y1LXytPuL8Ykv8AapMOXZjLnROe6jmRESoYqquovdKbYL0d1+L6KpuHPlHbbTSZMlrq5+rGjsk6lOVdqeNDj9Rv5Df1UJVwlWWXFGjybB1xvMFlroK7n2nnqf8ABmRU2tcvKm3+ClSFF4eLyvf7Nx6HEaShpivHXQtlTss1sz4K+yxy2M8A3DBnOc009LW26tRVp66jfrRSZb07inKEnY8uNms+CbLgy1XWO7zUlS+sqKyFP7JrnIuTGr/uXxd0jEsUpOUbyOLj6VOlWy0t1ldXvZ22q/GzAAJCmSLhzRZFc7DRXi84jobJT3F6x0TKhqudOqLlnvTJMzk8U4ZrcIX2rs9fqLUU6p1ca5te1Uza5O4qEh4Qxdg6+WCz2HG8M0a2Z7uc6uNXajmKueo/V2p4slyTcbvFjdHl+xTUYjvWMG1sDkYjLbQU7s1Y1MkYrt/f3b+IqqrOM2pJ27O6x354HDVsNGVCUVLZduVnu8rMnus91t6OEuujuO06N7Xiua4SJU3CRrWUaxIiaqq7JdbPPrW57uM4M7nSTpEfjmspYaWm5yslvbqUlLszTZlrOy2Z5IiIibk8JwxNSzZbz3nMx2oVXLhuqklfm+L282AASFMAAAAAAAAAAAAAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAASfoUwpbcS3LEM9daXXyotFsfW0lmbIrOfpUciaq5bVREXPJN+aEYHc6KZ8M0WKWV+Kb1c7VR0jeaROtrXpLM/PLU12dUxuW9U37thie5mVvOw004Jtlmwrg7EtNh5cMXO8JLHWWbXcrY1ZtR6I7a3NMs0/1JszO5vej+e2cFugZcLRG+/JUxVECJDlURJNPkxqqm1ztV+Wqv5fKiH5xzpy0c11/pr/AE9mumJLtQRpHQRXD+xoqRUXPWRi5uc5VyVVVFXYm7I0+EeFPX0L7/Pie2uu1VWytqKNIntZDSvY3JkaMXc3WyXWRdbPNdqkPltLZuN9lyScB6EcNYYwHdqW+0FuueLGUT6us5sxJFoldE9Y428mWqq58aoq7silkSqsUartVWp5C23B2vtfibD+lW73SodUXCtzllkXjVaeXYicSImSInEiIVIi/wAGP4KeQ2p3u0zWW5WP2ACU1AAAAAAAAAAAAAAAAAAAAAAAAAAALL8DP204s+b4fPKXDKecDP204s+b4fPKXDKFfrstUuqgACIkAAAAAABHunDsYXz8z55hIRHunDsYXz8z55hJR/Mj2oo6T8yre7L5Mp2AD0B8fAAAAAAAAAAAAAAAAAAAAAMigoZ7nXU1FTM16mpkbFG3lc5ck8pNd0wDo0wRzta8TXi4SXmWNJHvp1dqsz49VrVyTflnmqkO2G8z4evNDdaZkT6iilSZjZUVWKqcqIqEsN06W69ZR4owbb65ipk6SLJXoneei/aQr1lUbWXd7N52dGTwcYS11s73Zk3G3w4v9jzS6PdGcbpbnLjdKm0xxuVaXXayfPLZlxqvc1dqke4NwdNjvE/Qu2udBTKrpXzTdUsMKLvXLLN21Ey41UkHFuAcK33BNTjPB75qWGlzdNSS56uxURzURc1a5M0XYqopGuFcZXjBVVUVNmqI4J52JG9z4myZtRc+PdtMU3KUW4vb7eBJjIUaVenGvTShvvBt5k+Tb3bN2y20lG4Yc0QYbrX2i43G6VFfCupNNE9ytjdxouqmSKnGiZ5HMaS9GMGEaOivVmr1r7BXKiRyOyV0aqmbdqbHNVEXJdm7JSOppn1E8k0rtaSV6vc7lVVzVfGpOt/XW4N1kVdqpLAiZ/GvMNSpSi8zd3Zm9KdHHU60dVGOSLlFrY9nB7dpxOjnR/SYktt5v94lqWWW0MVz46VE5rO5G6ytRV3IiZeNNx5xHhbD9ZgePF2G219JAysSjnpK6RJM1VNjmPTfxZ/8HZaCb+stgv2GaStjo73M51TQySsRzXLqIi7F35aqZpyKvIajSDYNJddZpJ7/AE1LHZbZnMsdG6KOJvFr6jVzVdv8TGeWtabtt/YkWFo+L41KdNybi7tK9pX4u91ZcLWaNbgjR7a8SYBxLfquarbWWxJVibE9qMXVi101kVFVdvdIyTcTzoo7DuOvg1H/AG5E2GsE3rFtNcp7TS83ZbokklTWyc7Pc1qcblRFXLuG9Op5U8z2JlLF4ROjh9TC8pRbdt7s39DrMPYTwra8GUmKMXS3GWK4zvgpaWgVGqiMzzc5V7y7M08JrdJuCKTB9dbZrZUy1FoutOlTTOmTKRibM2ry7FRc+6MJ6TK3DVqdZam12+7WvmvNY6evj1kheq7VTw8SpvzO94SyJzzhlERERYJkyTiTNhrecayT3O5ZdPC1dHTqU0s0FHhtu3Z3fFPhyNVhnRZYbfhSDFGOLlNSUdSiOgpYF1XOR3W5qiKquVNqNTcm9TY2/R9o70gRVNNhK611HdYWK9sVXmqOTlVrkzVueWatXNM9xF+Icc3zFNBQUFzqo5KWg/wGMiazV6lG8W/Yh02ghVTSTQZLlnBUIv6gnCooublt/YzhsRhKlenhadFODsm2vKbe93vs2mlwlgOpxBjhuGauRaSSGSRKp6bVjbH12XKvJ38zsJMD4KxXYr9NhCoukdxskazPbWqisqWJntTkz1Vy3bcs02moxfiOtwjpkvd3t6s54pq5/UvTNr2q1Ec1e4qKStgXEVsxPgzGdbb8PUlmkSKRs6U7tbmzlhc7WVcky49ndNas5pKa3bP4ybAYbCznPCySck5707tJbLPcmmm3zKwouaIqblJLl0eWxmiCLGCT1fRJ70ases3mWXNlZuyz3Jy7yM29Y3vIT1Uf/TPT/Gp/3LiavJxy25o5mi6MKqr51e1OTXsattONwnhLDdPg+XFmLJq59C+q5zp6WhyR73omaqqr4eTcY2kjBNtw5T2S8WOpnmsl6iWWFtQn9pGqIi5KvGmS/wAFMTCOkitwnbau2SW+gutondzZ1HXM1mNeidcniTZ3CS+ELIk2HMHSNjZEkiOekbEyazOJi5InImeRG3ONVJ7ncuQp4ato+c4JZoKN9m27dm78U1w4EE2/1/SfHR/aQmnhL+ztg+SS+cIWt/r+k+Oj+0hNPCYTO+WBOWjlT/8AyG1T86HxIMJ/TcT2w+bMGxaOMK2LCFFiPHNfVQtuOS09NTqrVRFTNu5FVXKm3iREVD9xYB0Z36Vktpxs6jYjkV9PXaqO1eNEV+rl/E9Fu09VCUFNb7xhq13GjgjbG1uStXJqI3c7WTPJDobZhvAGmCnq2WOhmsV8hZrrGxMmbVyRVai6rm57FyyVCGTqRvKba7LNdx0qUMHXUaWFjCTtukpRk3x8q9vgRdf7FaLljltlwa+WejnlZTwyTSayPkXrlR2SdQnL3FU7Cs0N2l01bZrXitlXiqhhWWWhdTqxj9VM1a13Lt7vdyIzt1fV4Wv9PWQKxK221Os3Pa1XMcqKneXJU8JPtm0o6PK6qqrzU0stkxBWQrFPUpA6RyZpkqtc1FTiTarUXYmZJVdSFsl2vr7Sno6GDxDn4RljJvc20lH/ANu2178+BDejfCDMb4qp7TM+aKmWOSWWSFE1mI1uzfs65UTwnpxBhZKbHNZhuyOlrVZVc6wK/LWkdsRc8tm/PxEkLpGwbo9tdXTYEpKipulU3VdcKtq5N5Fzdkrst6NRETPeRHab/cbJd2XehqXMuTHOek7mo9dZyKjlycioqrmvjN4OcpOVrLgmVcRTwtCnCi5KUr3lKO2y5Lg+faS/PotwRgakp3Y0xBPJcJm6yU1Gqon+1ERXKn+pckFBo80c46SWlwrfq2lujWK5sNWiu1kTj1XIiqnLqrmnIY9z0XXPFNfHJfMX29MZXCBszLbKzJytRvUtVUyRFyTiTLfv2qcbovhmotKGH4JWujmiruZSN40VEcjk8qEKu4uSm7ruOnPJTrwoyw0VTk7K/W4b2nse29jm7xh+vsd8qLLVQ/3+CVIVYzbrKuWrq8qLmip3yXpdGWCsBWyklxzdKqW5VTc0paNVRG8qIjUzVE3K5VRM9xz2mesltmleoraZWtqKdtNNGqtRURzWIqKqLv2ohxOJ8V3XGNwZX3iobPUsjSJrmxoxEaiquWSd1VJbTqxi72Vtpz28NgataDhnknaN9qsntb5slCv0W4XxXhysvOA7lUyS0aKslFUqqquSZ6u1EVrskVU3opGeDsJV2Nr5Darfqte9FfJK/rYo03uXxps41VEJa4NS/wB4xOnFzGHZ4XkU4VxreME1dXUWaaGKWoakb3SQtk6lHZoiZ7tpiDmnOCd7Wtf2k2IhhZRw+KqQyqebMo/+18E3suSdcMHaKcH1C2293q5VlzjySbndVyjXuoxqo3vZqpqsY6J7bHhh2KcH3V9xtEaK+WKRc3sai5KqLki7ONqoipvIonnkqp5Z5nq+WV6yPcu9zlXNV8ak8aFXLJo2xzE9daNEeqNXdtp1z8iGtRTpRU8zZJhKmHx9SWGdGMU07NXurK6u77facBgHCFoulrveIcRVFTHZLQjGvipcuazSP3NReJN3j4jLxvgqxQ4Tt2LsLz1nQqqmWnlpqzJZIn7ePvtVF38SoppMC47lwgytpZrfT3O0XKNrKqiqFya/LcqLtyXbyEs6Saqkr9B1jq6G3w26kqJ4JGUkK5tiRVfsRePlz7pmcpxqLk38DXC0sNXwU0ks0YtvY8177Hfda2yxXpqZuROVciSdLuj22YBms7LbPVypWxyPk55c12StVuWWSJykbN69vfQnbhK+usMfEzeVhJOTVWCXG5TwtGE8DiKkltjks+V3tIIABMcsAAAAAAAAAAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAAAAWDwzogwPhnAFtxfpMulbTtu+qtJRUjla5GuTNu5Fc5yt6pdyIioV7cms1UXcqZE/2jhRVbbZR2rEGDrJdrdSxMha3JWrqtajUXJ6PbnkncNJ5v7TaNuJkw6LNDeKJoprFpIfbokcjpaW5arX6ue1EV6MVFy49pF2N7Jh6p0gPsuAFqa23Syx01M6WXmnNpnLkuo7JOozVERV5FXcTnZcH6K9P9JXxYattRhjE1NGkjomNyj2rkjlYiqx7dbJF1dVUzK22y53HBuJYa6jkjjulpqXLG9Wo9rZGKrc8l2Kmee81g229veGWCuOiLRVoqoqKHSDfLhW3yqj5otNb1ciNTcqta1M9XPNNZypnlsQ1WKdCWEsQ4GrcY6M7xVVdNQNc+poKpVc9EambkRVRHNejduquaKm5SF8XYvu+Ob1JeL5UtqK+SNkSvbGjE1Wpk1EamxCw/BZVVwLpIau1vM88uL1vKYkpRWa+0yrN2sQfos0fz6TcZUdihqOdoHNdPUVCN1liiblmqJxquaIndUk3pZ6PsU1eMsO4bjxDQ3/DNPNPz3XzNkgqViXJyOYiIrM13buXiyOX4NmMrfgzSNRTXSVsNDcKV1C6Z/WxucrVYqrxIrmomfFmTHpDwrpwutRerPbXW6rsde9WrV0jYKaephVepZK5cnZoi6q8uW/JROTUrXsIpWIO0F4AtekzGbrPdpauKkSikqUdSvRr9ZqtyTNUVMuqXiOSxbZI7LjG92WhSaWKjuE1JAjuqkejZFa3PJNrl2bk3ku8FKnkpNLdZTyt1ZYbfUxvbnnk5r2IqeNDiMQX5mFtN15vb6RlY223+oqed3u1UkVsrlRFXJctuS7uI2TedoxbYSNS6EMF6PbLR3LSpiGenr6xuvHaaBeranGiq1Fc5U3KqZNRdmamfadGGhvShza34Lv10tt9axXxw1qudrom9dR6dUiceq7NN+Ru9MdJhS+YFo8Y44tVXY8WXSBGUEFFVrPK5EbrMR7XIjUbkqK5MkVNbeqrkVz0b1s9v0gYVqYHrHNHcqfJzV5ZERU7yoqp4TSN5K99pl2TtYwcWYYuOC8QV9ju0SR1tE/Vfqrm1yZZo9q8bVRUVO+TjYdCODsIYNocUaULvVU3P6NdBbqRytcmsms1q5IrnP1dqomSN41MLhdQxw6T6J7GojpLXErl5VSSRE/giIRfjbSXiTSGlvTEFbHUNt7XNgbHA2JGI7LPY1NvWp4jdZppNbDGxNk1UWh3RjpUttf0uL3cKW9UbNfnS4K5UdnsTWa5NZGquzWaq5LvQgzCmCrlivGdHhaFqQXCeodBIsibINTPmjnfBRru/kSnwSXKmlOdEVcltk+fd6qM5iuxvXaOtNmKL9bKelnqoblXRNjqWqrNV8jkXcqLnkYWZNxQdtjJGvuj/QThK5SYavOI722+U6I2oqY3Oc2N6oi5ORrFa1dqLltyz2qaus0X6I8P2K8Xqox/0bgWBUoKSjljjqObcSKiZq7PYm1qIiZqpls4RWEsVv5njnRxbqlJF6uqo0a96d3JyI7xPNXph0S4XtuC7fpAwRVzdAq6SNjqWdVdqo9VRrmK7qkyc1UVrs8uJTVXTSk2jOzgQMma5cpNliwJo+wvgTDuJdIFReZ5sSK91JTWxUa2CJq5K9y8a7UXLPjyRF2kf4a0bYkxdYL1fLRQLU0NnRFn1XdW5V2qjG73KjeqVOTlXYdjo400XCy0FowrcLJZ79aY6yPnRLjFrupFfIiKrF7msqpnu5ciSd3uML2mm0z6N4NGWKYqKirJKu1V1K2tpJZUykSNVVFa7LeqKm/JM0VNhI1h0I4Owhg2hxRpQu9VTc/o10FupHK1yayazWrkiuc/V2qiZI3jU/fDFTUx1YET8W3OTxTOIfxtpLxJpDS3piCtjqG29rmwNjgbEjEdlnsam3rU8RrHNKK2mXZNk1UWh3RjpUttf0uL3cKW9UbNfnS4K5UdnsTWa5NZGquzWaq5LvQinRdo29XGNqiyXSokt9JbYZqm4PaiLJGyJcnNbxZ57M9uW1dp23BJcqaU50RVyW2T593qozmazHVx0c6bMUXu2Mhkey51kMtPMn9nPE6V2sx2XeTbxKiBZk3FMbNjZ0l10daP8X4AxDiXR9UXmCpw6iPqaa5qjkniXbrN5M0RVTbxKiohBaJtyLi4cxFZcU6AdIdxsuF6LDsSx1MUtPSO1klekTXa6rkn5WWXFkU6Tehmm27pmJLcTFifRNZbLoOw7jmnqa912uToElike1YW66vz1URuf4qcanp0A6LLPpUvV6orxU10EVDSxzRrRva1Vc6TVXPWauzIkLH/AP8ASTgj4VL5ZTF4G3tpxV83w+eNczyNmbLMkVwr4m0tXVxMVVbDJIxqrvVGuVEz8RL+lzRLZcBYHwdfLbU18tXekas7Kl7XMbnA2TqURqKm1eNV2ER3j2RuXx8323FmeEn2JtGPeZ/2jDeTacTCWxlccOYeuGK75Q2W1QLPcK2RI4mZ5JyqqrxIiIqqvEiE+V2i7RFoxSKhx1iS4XK/KxHy0ttRzUiz/wBLUVUTk1nIq78kIw0MY0qMDY4p66isiXm4VUa0NPTc15muvI5qZouS7dmXhJK4SOHsE2V0U6Q1NFj645VlVSU1QtRT9UvVLI5+WSrt1VblnluyNZN5lHgFuuZLtB+AtJVjra/RffqlblSJm63V7lXNV3NXWRHMzyyR21uZW+eCWlnlgnjdFPE9Y5I3pk5jkXJUVOVFTImPgt1k1Npco4o3q2OpoqmORqLsciM1kz7ytRTlNNkMdPpcxnHG1GsS4yLknKqIq/xVTMW1JxbD2q5M/BY9o+kj4pP+3lKtQNV0cTWtVzla1ERN6rluLS8Fj2j6SPik/wC3lKw2uqWhqKCqRqPWnfFMjV/G1VR2XhyEetIPciztv4O2GMGYThvWPfVBW1L4+aTwWaBzo6NMs1RytRVXLjXNE37MkzOaxxoVwvV6P58d6O7zU1tqpUV1RS1XVOa1FRHZLkjkc3NFVrk3bUXlkxmNcLzY96Z79JcLbCtDk/Djnu5sjuZ5LFzLPJeq6rrc9bjy2nO3qVming6VVBVR8xvGM55poqNd9PHMrVVFT/REjUX/AFORCJSldbTZpEeQ6JrLJoBqMfrU1/RmORWJCj28wy54SPdq57l5d5DZaCl/+jWs+PX/AL1pV9Sam2735msluAANzUAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAAAAAAAG6wpha4YxvUNqtrWLPIivc+RcmRsTe5y8ifzNKddo4xhDgvETq2rpn1FDU076SpjjXJ/M35Zq3upkhrNyUXl3k+FjSlWgqztG+3sJmiw9HhjQdiq3x3Whueq2Z7p6J+sxFVWZtXupkVsXepKl3xnhKw4KumG8HxXKVbu9HVM9ciN5mxMupRONcky3cq5qRVvIcPGSzOXFnR0xWpVHShSt5MbbHdLa+PHYE3oTzfv/ptsnxsPnXkDJvJLuekO2VmiS3YRjgq0uNM+NzpHNbzJdV7nLkuee5ycRtWi5ONuDI9GVqdKNdTds0Gl7Xs2HXaBI2UWGMY3iGNq3GnZqxyK3NURInPRO9rZL3ckIhrcZ4jusE0VbfblUQ1Cf2sUlQ5WPRduStzyy7hvdG2keq0fXCoclOlXbqxESop1dqquW5zV3Zpmqbdiop2E940M3OV1XNaLtSSvXWdBC1zWZ95rsk8GRHZwqSk43uXFKGKwdKjTrKDhdNNtJ3e/kzY6KUVNDmOVXcqVG39HQiPB+Lrjgq8w3O3P6tvUyxOXqJmcbXfyXiXad7i/SzbJMMSYWwhaHW20yorZZZMke9qrmqIiKu/jcqqqkSm1KDeZzW/gQY/FRg6EMPO7prrLne+wm3HGELdj6z+rnB8ecirrXG3tTq2vTa5yNT8ZN6onXJ1ScZlcJX11hj4ibysIxwHjm4YDvTK6kVZKeTJtTTKuTZmfycnEvF3szf6WtItBpBqLVJQ0lVTJRska5KjV6rWVFTLJe4aKnONSK3pXLVTG4argq0l5NSeW64Np7128VzI3JI0E9km3/ET/YUjc63Rriijwdi2lu9dHPJTRRysVsCIr83NyTYqohYqpuDS5HI0dUjTxVKc3ZKSb7z2aV+yRib5Y77LSStCXY7x13nf9u4iPG17p8SYtvF3pWSspq2oWWNsqIj0RURNuSqmew7nRPpLsmB7NeKG7UlXUc/StejIY2ua5qMVqo7WVN5BVhJ0VFLbsOlgMRSjpOdWckotz29t7HOYK0V4ixqkMtLS87W52WdbUorY8v8ASm9/g2d0lvSDaY7foiWwYbqKe5UtpkZ0Qkjna6SNGuVznK1ONXrmqcSJxnD0una9Li6kudW1UskGtGlrp11WNjVMv9zkTJUVdmzZkKvF+CsNWG/02EYLpLX32JYJXVqI1lPGqqqonKu1ct/fNZqrKacl/PaWMNUwFGhUjSltaabex2tsyrbsb38eZEz+sf8ABXyE+afUVcKYJVE2amWf5lhAnc4iXsPaY7fNh2DD+MrEl2oadrWRzMVFfqtTJubVy2omzWRUUlrRlmjOKvY5+ja1LVVsPVllzpWb3XTvttzIqtyKtwo0RFVVnjTL/chNHCX9nrB8kl84emix7otw9UNr7RhCtkr411olnVMmO4lRXPdkvdRCOccY1rsd3t1zrWMiRrEihgjVVbExFzyzXeuaqqrxmqzVKilayV95LN0cJgqlBVFOU3Hq3sktu9pHPQQS1U8UELHSTSuRjGN3ucq5IieEsxob0ez4HxFVur7vbZrjNSsbJQU8mtLB1aOzd3O6VutVwktN0orhC1rpaSZk7EduVWuRURfETTFpMwLbr7XYzoaK7uxNVxOTnOTLmDJHIiKutybE5e4iDEqclljxN9Bzw1Gpr6zSlFre7bLO7XN+wjK3WVmItIEdpklWGOtuT4XSJvaiyOzy7uSbO6S/Pg/CN2xDeMGU+FKi3SUFM6SO9c1cqq5rUVHOz2K1c+NduS7iAFrZ+fVrWyOZVLKsySMXJWv1tbNOTaTDauEVdI6DnS9WeluiK3UfIkixLIn+puStXPjyRBWhUdnD52MaMxODjmjidl3e7jmuvR4tc7o0WhLBzcUYr5vW0UdVZ6KJ6z81bnE56pkxvdXNc/Bmcnjea3T4uvL7PDFBbEqHMp2QpkxGt2Zp31RV8J2GJtNt1vFqfabTb6Sx26Rqteyk69zV3prZIjUXjyTNeUjA3pxm5Oc9nsKuLq4eFCOGw7zWd3K1rvdZcbL28SfMD6S7LifFuH33XDrfVQqNpG3Rk3UbGqiOVnLxdzPYppW27oZwi4oUbqsfdUmancexX/8A+ykU2m5TWe6UVxp8ub0czJmZ7lVqouS+InZdKOjivvdNiustdzjxFTsREY1quajkRUTbrI1VRFVEVciGpTdNvIm01Y6WExkcXTisROMZQmpXey647ltfbtZwunbsk3D4iD7CEbnQY2xRJjLE9feXw8wSociRxZ56jGoiNRV41yTb3VOfLNKLjBJ8jiY+rGtialSG5ybXeTvwavXWJ/iYfK8gl3Xu76kk6ItIVswDNeH3KCrlStjjZHzs1rslars881TlI2cublXlXM0pxaqTb42LWKrU54HD04vbHPdcrtWNnh7D9dii8UtptsaSVdS5Uajlya1ETNXKvEiJtLF4Ewk3B+CcZUfRm3XOWSKR0nOT9bmLkhcitdyKQPo/xb6icU0d3dAtRDGj45Ymrk5zHJkuS8vH4DuH43wVhKxX6HCEF1luN7iWF7q1EaynYuexOXLWXLf3yPERnN5Vu2fMuaHq4bDxdebWZZr3e1K2yy43d0+RD8e5neQnvF7VfwesKNaiuc59OiIiZqq5ybCBU2ZciE42XTbabBgK1WuC2T1V6t0DWxLOxvMGyoq9XnnnsR3EiL3jaupPK4q9mV9EVKMVWhWnlUotX+KNNgrQpc690V1xIrbRZIVSWRKhyNlkam3LJesReV2XeNrwh31Nxq7HcoEgmsKwuip6uCVJGvkVc3IuW7YiZcuSmmselVl4gvlqx1LW1tsu6MXmtNkjqZzVzTVZuRu7YnGm3M1uN8W2KfDVswrhiGs6E0U7qqSorckklkcipuTcm1eTvGijUdVSlw7rFydXBRwE6VB2zWvd+U5J7E1a1rbdjI9ABbPNgAAAAAAAAAAAAAAAAAAAAHZaJ+yThj5Y37Li6abkKWaJ+yThj5Y37Li6abkOTpDrrsPoXRDzWfvfRHkqlw0N+Cv0z+kWtKpcNDfgr9M/pFah10epqdVlUgAXyoAAAAAAAAAAAAAAAAAAAAAD20tNNW1MNNTxulqJ3tjjjamavc5ckRO+qnqM+x3aaw3q3XWna109BUR1LGv3OcxyORF7mwAuBwe9E9Vo1xbXuul+s892qKJjJrVSza89N/aNdm7lTizRCoWIvbFefl1R51xYiDTJoytGKLlpEttuv7sZ18DmrQTavO0crmojna/J1KcuzciKVqqqiSsqZ6mVUWWeR0r1RMkVzlVV/iqkVNSu2zeVrWR6i0fBY9o+kj4pP+3lKuEzaF9LVl0dYcxbbbpTV8094ZqwOpWNc1v9k9nVZuTLa5N2ZtUTcbIxF2Zi8GC20ty0s2dKqJkraaknqY0emaJIyNNV2XKmaqndPfpj0m4yh0nYmpKfEl1o6WirHU8FPS1L4WRsbllsaqbePNdq5kcYJxZccB4itt9tis58ol6yRM2SNVNVzHdxUVU/iTzdtJ2hfSPM254uwzdbfenNRJpqPN3NMkyTNzHJrd9zc8jWStLNa4W6xo+Ca6SbStVSvVz3uttQ9712qqq9maqvdVSMdJOS6SsW8nRip884mmDTho90a2ysh0aYYqeilU3VdXXBFREy3K7NyuciLt1U1UzK5VFXNWVktXUyOlqJpFlkkdve5XZqq99VUzFNycrB7rFl+GNsrMFtTrUpqjJP90ZAGBfbvhr5ypvOtJE0+aWLNpTqcPyWemr4G26KWOXnxjWq5XK1U1dVy/kqRhhu5RWfEdouM7XugoquGoe1iZuVrHo5UTPjyQU01CzEn5VybOF/2TLd81R+elK/koad9I9q0n4vpLxaKesgpoaJtM5tWxrXq5JHuzya5UyycnGReZppqKTMSd2TtwSuynN82T/aYRnpN7I+L/naq8646DQdpCtmjTGkl6u0FXNSuo5KdG0jWufrOVqouTlRMupXjOPxhd4MQYtv12pmyMprhXTVMbZERHo171ciLkqpnkoSedscDcaOtG910kXOqpqCalpKWhi54q66sfqw07OVV41XJdncXdkWD0o2aLDvBctVrhudHdI6SqpmJW0TtaGb+1eubV8OXgIV0S4+s2FYsSWPE1HVVGHMSUraaqdRr/bQq1V1XNTjTql2d7fuNxpB0i4UTR5QYAwPBcn2iOr59qay5IjZJX5qqIjU7q5quSJsRETeprJSclyNlZI4/RlpKu2jDEcd1tzlkp35Mq6NzsmVMee5eRyb2u4l7iqTFjjRpasVyWbSZo+ak1pqa2CS40ETcn0z+at13oxN2S9e3i65NilaiQtEeli5aK79zzCj6m0VSo2todbJJETc9vEj04l49y7DacX1o7zCfBkmcMj292L5uf55xXElLTppPt2lPEFruNtoqukipKRadzarV1nLrq7NNVV2ZKRaKaaikzEndk7cErspzfNk/wBphGek3sj4v+dqrzrjoNB2kK2aNMaSXq7QVc1K6jkp0bSNa5+s5Wqi5OVEy6leM4/GF3gxBi2/XambIymuFdNUxtkREejXvVyIuSqmeShJ52xwLDaIdnBk0jfDq/MREY6OtAeLdIKwVTaZbXZX5KtwrGq1HN5Y2dc/+Cd06vQvpswzo8wJdbFe7ZXV89VVyVCRRRMdDI1Y2IjXK53KzbsXZymNZeEvfpscrdMS80qMO1EEtJJaaNdRkMT0y1mJ+M9Mt7lzVM8sjTy05WRts2XJB08W6KLQtZ7RhGekumHcPzxx11TBVMlkh1Gq1usjeVz1Vy8WzZltOe4G66uKMVqu5LfD545a9450f4WwHiDDOj+C8zy4jWNtZU3REakMTFzRjU413pnlx5qq7DndC+kml0cYhr5bnSS1Vmu1I6irGQL/AGjWKuaObtTPLbszTYvKhjK8jQusyZkaSdDtwwtaKnE9JebTfbJJVPimqLZLr87SOcqo16eHLNF35cqFgtJuAOmLo60d2yO/Wq01ccMT4GXCRW89OdTMajGIm1V8CkIYrxxgWy6OrjgrAMF3mgvFVHU1tXdERqtazLVYxP8AaiZ5bs96qdBR6UtHeLbHhB+OKW9xX3CkbY4Ut7UdFVozVVue3ZmrGqu7bntyUPM7PkZVtxxui/D9fhfT3hqy3WBIa+huzYpo880zRrlRUXjRUyVF5FM7hPKq6Ybrmu6lpfNIa9mlSCv040+kG40c0VG24NqXU0GT5GxNZqNamaoiuyRM9qJvNXpixrQaQse1t+tkNTDRzwwxtZUtRr0VjEauaIqpv7puk8yb5Guy1jpODF2YbV8mqvNKc/py7MGNPnF32Wnr0O41oNHuPaK/XOGpmo4IZo3Mpmo56q9itTJFVE3901ekfElLjDHmIb9QxzR0lxqnTxMnREe1qoidUiKqZ7OUzZ57+wX8mxYDgnQpU4R0gwOlZEkupGski5NZrQyJrKvEiZ5qQxj3RBcsBWe33hl1tl8sNW7mDLjbJNeNJETrXcm5clzXcu43WhjSDYcN2/FOGMU89RWLElOkUlXSt1nwORHNzyTaqKjuLPJU3KiqZOOsWYNs2jaDAOC66uu0E1wS41lxq4eZJrImSNY3JORM9mWzjVTXapv2mdjREtta19yomuRFa6eNFReNNdCxnDJc5MS4UjRV5mlBOqN4kXmqJ/JCtTXK1Uc1Va5FzRU3ovKWVqNM2jbSbYrXBpJstxZeLczVSqoEVUeqomsrVa5FRHZIqtVFRF3KZmnmUrGFuaMml/8Ao1rPj1/71pWBScdKemWwXfBdHgXA9pnoMOQPa+SSoTVfIjVVyNRuarkrl1lc5c1Ug4zTTSbfESAANzUAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACy/Az9tOLPm+HzylwynnAz9tOLPm+HzylwyhX67LVLqoAAiJAAAAAAAR7pw7GF8/M+eYSER7pw7GF8/M+eYSUfzI9qKOk/Mq3uy+TKdgA9AfHwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADstE/ZJwx8sb9lxdNNyFLNE/ZJwx8sb9lxdNNyHJ0h112H0Loh5rP3vojyVS4aG/BX6Z/SLWlUuGhvwV+mf0itQ66PU1OqyqQAL5UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALL8DP204s+b4fPKXDKecDP204s+b4fPKXDKFfrstUuqgACIkAAAAAABHunDsYXz8z55hIRHunDsYXz8z55hJR/Mj2oo6T8yre7L5Mp2AD0B8fAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOy0T9knDHyxv2XF003IUs0T9knDHyxv2XF003IcnSHXXYfQuiHms/e+iPJVLhob8Ffpn9ItaVS4aG/BX6Z/SK1Dro9TU6rKpAAvlQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACy/Az9tOLPm+HzylwynnAz9tOLPm+HzylwyhX67LVLqoAAiJAAAAAAAR7pw7GF8/M+eYSER7pw7GF8/M+eYSUfzI9qKOk/Mq3uy+TKdgA9AfHwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADstE/ZJwx8sb9lxdNNyFLNE/ZJwx8sb9lxdNNyHJ0h112H0Loh5rP3vojyVS4aG/BX6Z/SLWlUuGhvwV+mf0itQ66PU1OqyqQAL5UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALL8DP204s+b4fPKXDKecDP204s+b4fPKXDKFfrstUuqgACIkAAAAAABHunDsYXz8z55hIRHunDsYXz8z55hJR/Mj2oo6T8yre7L5Mp2AD0B8fAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOy0T9knDHyxv2XF003IUs0T9knDHyxv2XF003IcnSHXXYfQuiHms/e+iPJVLhob8Ffpn9ItaVS4aG/BX6Z/SK1Dro9TU6rKpAAvlQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAsvwM/bTiz5vh88pcMp5wM/bTiz5vh88pcMoV+uy1S6qAAIiQAAAAAAEe6cOxhfPzPnmEhEe6cOxhfPzPnmElH8yPaijpPzKt7svkynYAPQHx8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7LRP2ScMfLG/ZcXTTchSzRP2ScMfLG/ZcXTTchydIdddh9C6Ieaz976I8lUuGhvwV+mf0i1pVLhob8Ffpn9IrUOuj1NTqsqkAC+VAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACy/Az9tOLPm+HzylwynnAz9tOLPm+HzylwyhX67LVLqoAAiJAAAAAAAcrpKs779gO/0MbFkmfSukjaiKqq9mT0RETjzadUDMZZWpLgR1qSq05U5bpJrvPnzv2gkfTBo8kwTf31FNGq2W4PdJTuRNkTl2uiVeJU4uVveUjg9DCanFSifHMVhqmFqyo1VZoAA2IAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAeWtVzka1FVyrkiImaqoBJGgq0Pumka3S6iuht7JKp65Lk1UarW7fhOTxFvU2IRjoW0evwXYH1dezVu9zRr5WLvhjTa2Ne7tzXu7OIk44mLqqpU2bkfUuj2BlhMGlUVpSd38d37IFcOGHh99bg6xXqONXdDK10UrkRV1Y5W5Iq8SJrMamfdQseaXF2GKHGeGrnYbijuc7hCsT3N65i72vTutciKndQghLLJM7cldNHy/B0GNsG3TAWJa2w3ePVqqZ3UyNRdSeNetkYq72qn8c04jnzpJ32opbgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAbbDGGrli+/UNktFOs9fWyIyNuS6rU43uVNzWptVeJBuBaDga4ffFQYpv8kSoyeSGhheqKmsjEV78uJdrmeItIczo/wXR6PsI2zD1E7mkdIxeaTKmSzSuXN7177lXwZIdMc6pLNJsuQWVWAANDYAAAAAAAAAwrvZ6G/W+a33KliqqOZMnxSpmi8i9xU4lTahXfF/BzudJNLUYaqY62lVc20tS9GTN7iOXqXd9clLKglpV50uqznY/RWGx6tWjtW5rY/wCdpSGs0b4voZuZTYaumvln1FO56eNuacRj+oTFPa3ePocn3F5twLfjCXonBfQ+hfZUf7FGfUJintbvH0OT7h6hMU9rd4+hyfcXmA8YS9Ex+D6HrX3Ioz6hMU9rd4+hyfcPUJintbvH0OT7i8wHjCXoj8H0PWvuRRn1CYp7W7x9Dk+4eoTFPa3ePocn3F5gPGEvRH4PoetfcijPqExT2t3j6HJ9w9QmKe1u8fQ5PuLzAeMJeiPwfQ9a+5FGfUJintbvH0OT7h6hMU9rd4+hyfcXmA8YS9Efg+h619yKM+oTFPa3ePocn3D1CYp7W7x9Dk+4vMB4wl6I/B9D1r7kUZ9QmKe1u8fQ5PuHqExT2t3j6HJ9xeYDxhL0R+D6HrX3Ioz6hMU9rd4+hyfcPUJintbvH0OT7i8wHjCXoj8H0PWvuRRn1CYp7W7x9Dk+4eoTFPa3ePocn3F5gPGEvRH4PoetfcijPqExT2t3j6HJ9w9QmKe1u8fQ5PuLzAeMJeiPwfQ9a+5FGfUJintbvH0OT7h6hMU9rd4+hyfcXmA8YS9Efg+h619yKM+oTFPa3ePocn3D1CYp7W7x9Dk+4vMB4wl6I/B9D1r7kUZ9QmKe1u8fQ5PuHqExT2t3j6HJ9xeYDxhL0R+D6HrX3Ioz6hMU9rd4+hyfcPUJintbvH0OT7i8wHjCXoj8H0PWvuRRn1CYp7W7x9Dk+4eoTFPa3ePocn3F5gPGEvRH4PoetfcijPqExT2t3j6HJ9w9QmKe1u8fQ5PuLzAeMJeiPwfQ9a+5FGfUJintbvH0OT7h6hMU9rd4+hyfcXmA8YS9Efg+h619yKM+oTFPa3ePocn3D1CYp7W7x9Dk+4vMB4wl6I/B9D1r7kUZ9QmKe1u8fQ5PuHqExT2t3j6HJ9xeYDxhL0R+D6HrX3Ioz6hMU9rd4+hyfcPUJintbvH0OT7i8wHjCXoj8H0PWvuRRn1CYp7W7x9Dk+4eoTFPa3ePocn3F5gPGEvRH4PoetfcijPqExT2t3j6HJ9w9QmKe1u8fQ5PuLzAeMJeiPwfQ9a+5FGfUJintbvH0OT7h6hMU9rd4+hyfcXmA8YS9Efg+h619yKM+oTFPa3ePocn3D1CYp7W7x9Dk+4vMB4wl6I/B9D1r7kUZ9QmKe1u8fQ5PuHqExT2t3j6HJ9xeYDxhL0R+D6HrX3Ioz6hMU9rd4+hyfcPUJintbvH0OT7i8wHjCXoj8H0PWvuRRn1CYp7W7x9Dk+4eoTFPa3ePocn3F5gPGEvRH4PoetfcijPqExT2t3j6HJ9w9QmKe1u8fQ5PuLzAeMJeiPwfQ9a+5FGfUJintbvH0OT7h6hMU9rd4+hyfcXmA8YS9Efg+h619yKM+oTFPa3ePocn3D1CYp7W7x9Dk+4vMB4wl6I/B9D1r7kUZ9QmKe1u8fQ5PuHqExT2t3j6HJ9xeYDxhL0R+D6HrX3Ioz6hMU9rd4+hyfcPUJintbvH0OT7i8wHjCXoj8H0PWvuRRn1CYp7W7x9Dk+4eoTFPa3ePocn3F5gPGEvRH4Po+tfcimtl0NY0vT49WzS0cL8s5q1Uia1OXJeq4uJMyd9HWhS2YNkjuNwkZcryzJzJFblFTrysau93+pfAiEpghq4upUVtyOlgejuDwclUs5SXF8Oxf9wACqd4AAA43SJoww9pOtSUV6pl5vEi87VsOST0yrv1VXiXLa1c0Xv7So+L+CvjnD8r32mKC/0SZq19I5I5kT/VE9U2/BVxeobySFWUNxpKClvPmlLosxzBK+J+Dr+j2OVrkSgkcmad1EyXwH46WON+0/EH7ul9E+mAzXlUl8JfI01K5nzP6WON+0/EH7ul9EdLHG/afiD93S+ifTDNeVRmvKo8JfIalcz5n9LHG/afiD93S+iOljjftPxB+7pfRPphmvKozXlUeEvkNSuZ8z+ljjftPxB+7pfRHSxxv2n4g/d0von0wzXlUZryqPCXyGpXM+Z/Sxxv2n4g/d0vojpY437T8Qfu6X0T6YZryqM15VHhL5DUrmfM/pY437T8Qfu6X0R0scb9p+IP3dL6J9MM15VGa8qjwl8hqVzPmf0scb9p+IP3dL6I6WON+0/EH7ul9E+mGa8qjNeVR4S+Q1K5nzP6WON+0/EH7ul9EdLHG/afiD93S+ifTDNeVRmvKo8JfIalcz5n9LHG/afiD93S+iOljjftPxB+7pfRPphmvKozXlUeEvkNSuZ8z+ljjftPxB+7pfRHSxxv2n4g/d0von0wzXlUZryqPCXyGpXM+Z/Sxxv2n4g/d0vojpY437T8Qfu6X0T6YZryqM15VHhL5DUrmfM/pY437T8Qfu6X0R0scb9p+IP3dL6J9MM15VGa8qjwl8hqVzPmf0scb9p+IP3dL6I6WON+0/EH7ul9E+mGa8qjNeVR4S+Q1K5nzP6WON+0/EH7ul9EdLHG/afiD93S+ifTDNeVRmvKo8JfIalcz5n9LHG/afiD93S+iOljjftPxB+7pfRPphmvKozXlUeEvkNSuZ8z+ljjftPxB+7pfRHSxxv2n4g/d0von0wzXlUZryqPCXyGpXM+Z/Sxxv2n4g/d0vojpY437T8Qfu6X0T6YZryqM15VHhL5DUrmfM/pY437T8Qfu6X0R0scb9p+IP3dL6J9MM15VGa8qjwl8hqVzPmf0scb9p+IP3dL6I6WON+0/EH7ul9E+mGa8qjNeVR4S+Q1K5nzP6WON+0/EH7ul9EdLHG/afiD93S+ifTDNeVRmvKo8JfIalcz5n9LHG/afiD93S+iOljjftPxB+7pfRPphmvKozXlUeEvkNSuZ8z+ljjftPxB+7pfRHSxxv2n4g/d0von0wzXlUZryqPCXyGpXM+Z/Sxxv2n4g/d0vojpY437T8Qfu6X0T6YZryqM15VHhL5DUrmfM/pY437T8Qfu6X0R0scb9p+IP3dL6J9MM15VGa8qjwl8hqVzPmf0scb9p+IP3dL6I6WON+0/EH7ul9E+mGa8qjNeVR4S+Q1K5nzP6WON+0/EH7ul9EdLHG/afiD93S+ifTDNeVRmvKo8JfIalcz5n9LHG/afiD93S+iOljjftPxB+7pfRPphmvKozXlUeEvkNSuZ8z+ljjftPxB+7pfRHSxxv2n4g/d0von0wzXlUZryqPCXyGpXM+Z/Sxxv2n4g/d0vojpY437T8Qfu6X0T6YZryqM15VHhL5DUrmfM/pY437T8Qfu6X0R0scb9p+IP3dL6J9MM15VGa8qjwl8hqVzPmf0scb9p+IP3dL6I6WON+0/EH7ul9E+mGa8qjNeVR4S+Q1K5nzP6WON+0/EH7ul9EdLHG/afiD93S+ifTDNeVRmvKo8JfIalcz5n9LHG/afiD93S+iOljjftPxB+7pfRPphmvKozXlUeEvkNSuZ8z+ljjftPxB+7pfRP03Rfjh7mtbg+/5uVETO3yp/I+l2a8qjNeVR4S+Q1K5lDsKcF3H2IZmrcKSGxUn40te9HSZZ5LlExVVV49uqm7aW00ZaI8PaLbe6K1xLPcZ2o2puM6Jzabj1dmxrM9zU8Kqu073LIEU6sp7GbxpqO4AAjNwAAAAAAAAAAAAAemerhp/8R6IvIm1QG7HuBgdE0dtjgle3lRB0Rd7lm8QszXOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYKXSJFRJGSRr/qQzI5GSt1mORycqCxlST3H6AAMgAAAAx562CnXJ7+q5E2qA3beZAMDonrbW08zm8qIOiLvcs3iFma50Z4MDoi73LN4h0Rd7lm8QsxnRngwOiLvcs3iHRF3uWbxCzGdGeDA6Iu9yzeIdEXe5ZvELMZ0Z4MDoi73LN4h0Rd7lm8QsxnRngwOiLvcs3iHRF3uWbxCzGdGeDA6Iu9yzeIdEXe5ZvELMZ0Z4MDoi73LN4h0Rd7lm8QsxnRngwOiLvcs3iHRF3uWbxCzGdGeDA6Iu9yzeIdEXe5ZvELMZ0Z4MDoi73LN4h0Rd7lm8QsxnRngwOiLvcs3iHRF3uWbxCzGdGeDA6Iu9yzeIdEXe5ZvELMZ0Z4MDoi73LN4h0Rd7lm8QsxnRngwOiLvcs3iHRF3uWbxCzGdGeDCZdIVdqvR8bv9SGY17XtRzXI5q8aAymnuPIABkAAAAGLNcIIVyV+s7kbtAbS3mUDA6JKu1KaZU4lyHRF3uWbxCzNc6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBhx3OB7snK5i/6kMtFRURUVFReNAZTT3HkAAyAAAAFXJM13GHLc6eNckcr1/0pmDDaW8zAYHRJ3uWbxDoi73LN4hZmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDoi73LN4hZjOjPBgdEXe5ZvEOiLvcs3iFmM6M8GB0Rd7lm8Q6Iu9yzeIWYzozwYHRF3uWbxDokvHSzZd4WYzozwYkVyp5Vy1tReRyZGWDKae4AAGQAAAAAAAAAAfiWRIo3vXc1MwDHqJ5HzMpaZM5371/JQ2VFZKemRHyok0+9XO2pn3EPTh+l1ad1U9M5Z1Vc+4bkN8BCN/KZ4RERMk2HkA1JQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD8SRMmarZGNe1eJyZmkrbM6mVaihXVVEzdFvRe8b4GU7GsoqW856lqW1USPTYu5U5FPeY1bDzjdmuamUVSm7i1v8A35TJMka5MAHorJuYU8j03omSd8GW7Hqe+atqFpKVURUTq5PyTb0dopqNEVGI+VN73pmv/B+bLRpS0TFVP7STq3L5P4GxMNmYR4sAAwSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHqmp4qhmrLG17f9SGirbbJbFdU0iqsCbXxLxIdEFTNMlMp2NZQUjQwzNnja9q7F/geww0i5wuc1MiZRSJrsTk/97TMMkad94AMS4yrHTq1vXyLqpkA3ZXPyxs12ndDA7Up2dfJy943lJbKaiROZxJrJ+O7aqn6t9I2ipY4kRM0TNy8q8ZkmGzaMOL3gAGCQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9FRRwVTcpomv7qptTwmhqqOWzO5pG5ZKRV2tXe06U/MkbZY3MeiOa5MlReNDKZpKCfaaVj2yNRzVRWqmaKh+jBo2upp6ikd/03Zt73/vIzjJondA8OcjUVVXJE2qp5MG4a0qw00a9XM7Lwf+/IA3ZXP1T00t5eq6yx0bVy2b3G+pqGnpG5QxNb3ctq+E9kELKeFkUaZMYmSIeww2bxhba94ABg3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMWqt9NWIqSxNVfyk2KnhNFNFNZ5WskdzSkeuTXcbe+dOemrpm1dPJC9M0cmXeXiUymaShfat5q0XNM03Awra93Mnwv6+FytUzTJondXAABkAAAAAAGLclVKKXLueUyjEufrKTweUIxLczeW5qNoKZETJOZt8hkmPb/WNN8W3yGQaksdyAABkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0eI9iUbk65JNin6PziTrKT4w/RtwIf7mDAu6/wB2anEr0zM81939bs+Gn8wjE+qzqWojWoiJkiJkh5CbkBqTgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGgvOy60SpsVUVFXwntPVevZSh7y+U9qG3Ah4sGFVprVtA1drVkTNPChmmFVev7f8YnlQIxLcdOADUnAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOcq+pvzstmtGmfd2GSY1Z7PL8UnkMk2IVx7QYsaa19pUXaiNVU7+SmUYsPs9TfAXyKA+B0gANSYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQDmY+pu1e1Nia2eRmGGz2Xr++ZhsyCO4AAGwAAAAAAMS5+spPB5TLMS5+spPB5QjEtzN7b/WNN8W3yGQY9v9Y03xbfIZBqSx3IAAGQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADR4k6yk+MP0fnEnWUnxh+jbgQ/3MGvu/rdnw0/mbA1939bs+Gn8wjE+qzqk3IAm5Aak4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABoL17KUPeXyntQ9V69lKHvL5T2obcCHiwYVV6/t/wAYnlQzTCqvX9v+MTyoEYluOnABqTgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHOVns8vxSeQyTGrPZ5fik8hkmzIVx7QYsPs9TfAXyKZRiw+z1N8BfIoD4HSAA1JgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAUA5lnsvX98zDDZ7L1/fMw2ZBEAAGwAAAAAAMS5+spPB5TLMS5+spPB5QjEtzN7b/WNN8W3yGQY9v9Y03xbfIZBqSx3IAAGQAAAAAAAAAAAADR4tvy4bsdRXsiSWVuTWNVdmsq8fc4yIWaU8TSP1WSUzlXciU+a+UlhSlNXRDUrwpuzJ6BByaQ8YOTY2n8MCJ/M9M+k7FVM5EldTMVdqZwJ95t4PIj8LhyZO4ID6a+JP86l+jp946a+JP86l+jp95nwaZjwyn7SfAQH018Sf51L9HT7x018Sf51L9HT7x4NMeGU/aT4CA+mviT/Opf2CfeaCp084lwziShW586Vtlqf8SNkHM5WJmiKqORdqpnmmabd3dHg0x4bTW8s2Dwi5oipxnkrlsAAAAAAAAAAAAAAA0eJOspPjD9H5xJ1lJ8Yfo24EP9zBr7v63Z8NP5mwNfd/W7Php/MIxPqs6pNyAJuQGpOAAAAAAAAAAAAAAAAc1iq61tvntcNHK2JaqXmbnOYjss1anH3zJ6HXz36i+iJ95mxi/A3gNH0Ovnv1F9ET7x0Ovnv1F9ET7xYXN4DR9Dr579RfRE+8dDr579RfRE+8WFzeA0fQ6+e/UX0RPvHQ6+e/UX0RPvFhc3gNH0Ovnv1F9ET7zGq+jFsdSSy3OKeJ9RFE5iUyNzRzkRdufdFhc6UAGDIAAAAAAAAAAAAAABoL17KUPeXyntQ9V69lKHvL5T2obcCHiwYVV6/t/wAYnlQzTCqvX9v+MTyoEYluOnABqTgAAAAAAAAAAAAAAAAAAAAAHMY7xtQYEsM1zrFR8nWQU6OydNJxNTucarxIaDRTpTg0h0EsdQyKmvVNtmp2L1LmZ7Hsz25cS8i99CJ16aqKk3tZdjo7Ezw0sZGD1adm/wCfMkYAEpSAAAAAAAAAAAAAAAAAAAAAOcrPZ5fik8hkmNWezy/FJ5DJNmQrj2gxYfZ6m+AvkUyjFh9nqb4C+RQHwOkABqTAAAAAAAAAAAAAAAAGNX10Fto5qupfqQxN1nLvOGq9KtKxHJTW+WRyOyTmr0aipy7M/EVMTjsPhba6aV/5uLFHC1q/5UbkhAiOr0n3SZHtghp4E1s2uRquVE5FzXI7vBl6nvllbUVSsWdj1Y5Wpki5ZKi5cWxSvhNL4XF1XSou7tfc0S4jR9fDw1lRWW7edCBmYFTe7bR6vN66mj11ybrSomZ0pSUVeTsU0m3ZGeDlqnSFYadubap8yo7VVIo3Kqd3blsNNVaVKViPSmoJZHI7JOaPRqKnLszKNXSuDpdequ+/yLUMDianVg/l8yQgRJV6ULlKkjYIKaBFXqHZK5yd/NclJBwrd5b3ZaerqGNZO7WRzU2Z5OVM8u7ka4TSuGxlR06ErtK+5r5mcRgK+Hgp1VZM3QAOiUwAAAAAAAAAAAAFAUA5lnsvX98zDDZ7L1/fMw2ZBEAAGwAAAAAAMS5+spPB5TLMS5+spPB5QjEtzN7b/WNN8W3yGQY9v9Y03xbfIZBqSx3IAAGQAAAAAAAAAAADjdKPtPqvhs8pD9hiRsEkuXVOdq59xCYNKPtPqvhs8pDdFUJT2aV6KiPRzkTvruLtD8v4nOxP5vwPdXXhlO50cKI+RNiqu5F/maOoqpap+vK/WVN3Ih6Qu5SwkkU3Js6mh0d4guFJDVQ0kaRTNR7OaTNaqou5clMjpX4l9y0/0lpLmGbhSTYetasqoXatNG1f7RNio1EVF7uaG256p/dEP7Rv3lN4iadrHQjhabSdyDelfiX3LT/SWmtumCr7Z4nS1Nvk5i3fJEqSNTv5biwnPVP7oh/aN+89iKipmm5eNOMLEz4oy8HB7mVYOA0j+uLX3n/aQsdpKwVDSROvNuiSONF/vMTU2Jn+OicW3enhK46R/XFr7z/tIXKU1NXRzcRTdO8WXvj6xveQ/R+Y+sb3kP0co7wAAAAAAAAAAAAAABo8SdZSfGH6PziTrKT4w/RtwIf7mDX3f1uz4afzNga+7+t2fDT+YRifVZ1SbkATcgNScAAAAAAAAAAAAAAA4zHEjYq6wyPcjWMqEc5y7kRHM2m+9Uto98ab9dDR409kcP8AylPtsOv5mz8lviNuCNFe7NZ6pbR740366D1S2j3xpv10NnzNn5LfEOZs/Jb4jGw22ms9Uto98ab9dB6pbR740366Gz5mz8lviHM2fkt8Q2Daaz1S2j3xpv10NZVaSMI0U74KjEdsimZscx9Q1Fb30Om5mz8lviKI6UuyNij5fL5TtaE0XT0jVlTnJqyvs7Tg6f0vU0XRjUhFSbdtvYXQoMc4bujHvor3QVDWLk5YpkdkvdyPRebzb65lDFT1kMsq1kCo1js169CFuCs1FTFGaIu2n3/7ydsRNalPRZNRP77T7k/8RCrpPBxwWKlh4u6Vv3SZb0VjZ47BwxM1Zyvs7G0boAHOOoAAAAAAAAAAAAAAAaC9eylD3l8p7UPVevZSh7y+U9qG3Ah4sGFVev7f8YnlQzTCqvX9v+MTyoEYluOnABqTgAAAAAAAAAAAAAAAAAA119vlDhy1VNzuM7YaSmbrPev8ERONVXYiGxXYVJ0xYzvOObutFSW+4MsdFIqQs52kRZnpsWRyZd9ETiTuqVcXidRDNa74HY0Jop6SxKpuWWK2yfs9ntfA4/SDjuux9fpLhU5x0zM2U1PnmkMee7uuXeq/yRDS2C+12GrvS3S3TLFV0ztZruJeVFTjRU2KhrnNcxytc1WuauSoqZKing8nKrOU9Y3tPt1LB0KeHWGhFZLWtwt/vjzL0aP8c0OPbBFcaVUZUNyZU0+eboZOTvLvReNPCdUUiwBf8QYGvkN0obfWy070Rs8KQP1Z4l25Z5b+NF/lmXRtVyiu9tpa+BsrYamNsjWysVj0RUzyVq7UU9RgcU68PKVpLf8Ac+NdItDLRuI/6TvTlu27vY+z918TMABePPAAAAAAAAAAAAAAAAAAHOVns8vxSeQyTGrPZ5fik8hkmzIVx7QYsPs9TfAXyKZRiw+z1N8BfIoD4HSAA1JgAAAAAAAAAAAAAADitIl6o4LRNbllR1ZKrFSNN6NRyLmvJuIgOkx4ipiu4rxK5nm2HNnzXTuKliMZJSVsnkr4NntdFUI0sOmn1toNnbL3c7YySCgqZo2zrtZHt1lyy2ci941h0uCI87rNNq5rBTve135LtiIv8VOZh5zhNOEnF80W8TlVNuaulwZ5Wz4nuSsfOlWuqio19TNlki99T9w4HqU/x66khbntaxVev8EyOqcquXNyqq8q7TwJ4hTd5Jyftd/t8zmLEVErQtHsRpIsHW2PbNW1My8kbEYn8c1M6KxWaDrbesq8s8rnfwTIzQaa5rqpL4X+dyOVWpLfJ/L5WPMKQ03rekpYfgQtz8am0sc0kt5jWR6uXmEibe+w1RucORKtasmrmjWObrcmat2fw/gdXQdWc8fSTezb8mUsYlqmzqQAfSzhgAAAAAAAAAAAAKAoBzLPZev75mGGz2Xr++ZhsyCIAANgAAAAAAYlz9ZSeDymWYlz9ZSeDyhGJbmb23+sab4tvkMgx7f6xpvi2+QyDUljuQAAMgAAAAAAAAAAAHG6UfafVfDZ5Sv5YDSj7T6r4bPKV/L+G6hy8Z+Z8AZFJQVVe9zKSmmne1NZzYmK5UTlXIyrFYqzENwZR0bM3rtc9etjbxuVeTyk/wCG8OUeGaBtLSpm9cllmVOqldyr3OROI2q1VDtNKFB1dvArcqZKqKm3j2DJORDZYh2X+6/Kpftqa0lTurkDVnYeBCQ9F+JqimurLRPK59JVIvM2uXPmciJns5EXJdneI8Op0dUMtbi63qxF1adVmevI1E/mqohpVScHckotqorE81lJHX0k9LK1HRTsWNyLyKmRSLSdEtPXW+F3XRrIxe+jkT+ReNFRuSruTapSDSrI2a60sretfJM5O8r0Ugwe9ljSS8lMvPH1je8h+j8x9Y3vIfopnSAAAAAAAAAAAAAAANHiTrKT4w/R+cSdZSfGH6NuBD/cwa+7+t2fDT+ZsDX3f1uz4afzCMT6rOqTcgCbkBqTgAAAAAAAAAAAAAAHGY4R61tiSNyNkWoTVc5M0RdZmS5cZvOdb1740n0VfTNHjiRsVdYZHuRrGVCOc5dyIjmbTdVOJbYlPMrLhBroxdXJ/HkbN2VzTZd3P1zrevfGk+ir6Y51vXvjSfRV9Mg71RXhdq3SszXf/bOJVwZiWnXD9N0RuTFqs3IqzP6rLWXLPwHLwWlI4upq4xtsuQ060ZuxvOdb1740n0VfTHOt698aT6Kvpn79Ulp98Kf9ceqS0++FP+udTaT7OZ+Fpb1740n0VfTKR6TUkbpBxKkr2vkSuk1nNbkirnycRd5cSWn3wp/1ykOk2Vk+kLE0kbkdG+ukVrk3KmZ63oh5xU936o8X02t4LT976MlrgxxVkjcS86VEMKotPrc0iV+fX91MicbxBco20K1NXTyxc+QZtZArF69OPWUg7gw3Kkt6Yl56qI4ddYNXXXLPLXJyvN5oK1lDFT1cMsq1sCo1rs169Dm9Ib+Mqnw/xR1OjNvFVL4/5M6cAHCPRAAAAAAAAAAAAAAAGgvXspQ95fKe1D1Xr2Uoe8vlPahtwIeLBhVXr+3/ABieVDNMKq9f2/4xPKgRiW46cAGpOAAAAAAAAAAAAAAADUX2/wANihbJKzW1s12uRqNam9VVdiG3KrcLnGvQ/C0tqhkymusqUaJ/4TOqlXwrk3wlXF1pU4JQ60mkvr+1yxhqSqT8rciaemzZv8+i+nxfeE0sWVVROeKL6fF958tdRn5DP1UCxsyXqGbvyUILYj1n/wDX/Za1NL0f3LF4jmbUYgu0zFRWy1cz0VHZoqK9V38e81a9aveNVa7lQstlE1aymarYWIqLK1MupTumYl1oM0/vtN+1b955qcJZndH3LDV6KowWZblxXIuThzSdaKHDtopZJ6PmkFJDG7OuiRc0YiLsVdhs+mzZv8+i+nxfefL64JG+vq3NaxzXSvVFREXPqlMbUZ+Qz9VD0cViLL/qft/s+JVqNHWS2cXxPrRh/F9JiCTVgRqtciqySOVsjHZb0zbxnRFDeCPjNbZdbnYXvyRVbcKdu7NW9TK1O+1Wr4FL4Me2RjXtXNrkzReVCfCVpycqdR3cX+z3FHE0owacdzP0AC4VgAAAAAAAAAAAAAADnKz2eX4pPIZJjVns8vxSeQyTZkK49oMWH2epvgL5FMoxYfZ6m+AvkUB8DpAAakwAAAAAAAAAAAAAABDGMqSSuxlWQRZa73N37k/s27VPZFgmBv8Aj3PPuQwqv8VU2d7iamPZ3Im1Y9Ze/qNQzj5bpSajja11fynzPVUq840KcYO2xGriwvZoeujqp1/1yo1PEifzNnBHBRwOgpKaOnicubkZmqu76rtU8goOtK1ls7F/GaylKXWbYABEagAAA3mGJ/7xUQ6u5jX5591U/kaM2+GEXolUrkurzBu3/c47XR5X0hT+PyZVxr/6LOrAB9MOGAAAAAAAAAAAAAoCgHMs9l6/vmYYbPZev75mGzIIgAA2AAAAAABiXP1lJ4PKZZiXP1lJ4PKEYluZvbf6xpvi2+QyDHt/rGm+Lb5DINSWO5AAAyAAAAAAAAAAAAcbpR9p9V8NnlIQsdkq8QXGKho2osj9rnO61jU3uXuITfpR9p9V8NnlIWw1iCow1dY66BrX7FZJG7c9i5Zpnxbk2l2hfVu285uKtrVm3E84cw5R4at7aWlbm5dsszk6qV3Kvc5E4jcGvst6o7/QR1tFJrRO2K1euY7ja5OJTYFOV77d50IWyrLuOBuOim33Cvqavn+rjWokdIrEaxURVXNclXumL0nbf751n6jPuN1W6SrBQ1c9LLLULLA9Y3asKqmaLkuSno6amHf8yr/YL95OnWtsKzjh77bGtTQ9bs9tzrP1Gfcddh3C9vwxTviomOV8i5ySyLm9/Jt5O4aPpqYd/Lq/2C/eaq6aX6OOJzbZRTSyqmx9RkxqeBM1X+Aaqz2MypUKflKxvdIOJGWGxyxMenPtY1YompvRF2Od3kT+KlRdI/8Aj2rvO8qEmXW61d6rZKytmdLO/jXcicSInEncIz0j+uLX3n/aQt0KeRWOdi6utu+Be+PrG95D9H5j6xveQ/RzDtgAAAAAAAAAAAAAAGjxJ1lJ8Yfo/OJOspPjD9G3Ah/uYNfd/W7Php/M2Br7v63Z8NP5hGJ9VnVJuQBNyA1JwAAAAAAAAAAAAAADjsa7bjh/5Sn22HUVsbOc6jqW/wCG7i7inK44R7q6wpG5GvWoTVcqZoi6zMly4zbVdJd0pZ1dcqZW6js0517nwhPqmnFkAt61O8Tdo6Y12FKTNqL1cm9P9SkIt61O8TBgOnuMmGqV1NWwxRaz8mPp9dU6pePWQ8noLzh9n1RRwvXM/HOO7Po/oqWqusU72VMixRtp4ke7NEzXPNU2ZHJWjT9hK83Sjt0NNcmTVcrYWOkp2o1HOXJM8nLszOU4SUNdFYrGtXVxTtWqfkjIdTJdTvqQdgtHuxfYEjcjZFrodVypmiLrpty4zpYvHVaWI1UbW2H1HQvRvBYzRfhdVPP5XHlexfLmbPyG+IolpS2aRsUfL5fKXZWjvO3/AOJ030T/APcpHpNbI3SDiVJXo+RK6TWcjckVc+TiPpPRDzip7v1R8J6bea0/e+jJj4K7UcmKM0RdtPvT4ZO2ImNbT0So1EXn2n3J/wCIhAHBiirJW4l50qYoMlg1teLXz6/upkTjeKe4xtoXVNbDNFz5BmxkGovXpx6ynN6Rf1Kp8P8AFHV6M/0ql8f8mdQADhHoQAAAAAAAAAAAAAADQXr2Uoe8vlPah6r17KUPeXyntQ24EPFgwqr1/b/jE8qGaYVV6/t/xieVAjEtx04ANScAAAAAAAAAAAAAAAxLnWJQUE9QqZqxubU5V4k8Z85OEFiKTF2k51rgk14bW1tE1c805oq60rvGuX+0vzjmv5lTQ0rJWMkkzkzeuzZ1vfTNc/AUwtnB2xDFe57nX36yzzSufIrmvfmr3rmq7U7qnExmLpwxDUn1Fs7X/r5nYwOGlKmnbZJ/siI/UG/3ez9mv3j1Bv8AdzP2a/eTViDRderBbpLgslLWUsO2V1M9VWNOVUVNxxJSjj6kleMvkdlYOg+H7s4r1Bv93M/Zf8j1BP8AdzP2X/J2oNvDK3P5DwKj6PzOL9Qb/dzP2a/ePUG/3cz9mv3naHUYVwDdsWxSz0vMYKOJ2q6oqHarVdyJxqayx1WKu5fIPB0Fw/dkT4Wuc2jbSBZ7ksiuipZmOkc1MteF3UvTxKviPpvhOvbXWiJEej+ZdQjkXPWblm1e9kqeIpLiTg7Xm9JTuhvNmZJHmiq+R+StXi3cpZ3Q1FW4es1pslzrqerroqRsEksDupc5meqqZ7et2Z9ws4bG05VqclLbLY/mn/OZysbhmoSsti2r6/z2EtAA75wwAAAAAAAAAAAAAADnKz2eX4pPIZJjVns8vxSeQyTZkK49oMWH2epvgL5FMoxYfZ6m+AvkUB8DpAAakwAAAAAAAAAAAAAABG97icmN6hzkyRadHIvKmTU+89x7b+3/AObHryUjU/8AyPUfKtL+e1e1npKf5UOxAAHONgAAAAAAdFhmJUSeXPYqI3Lwqv8AM51Nu5MzocLc0VtW5dsKuajF4s8tp3ejcW8fFrgn8injmtU0dCAD6ScUAAAAAAAAAAAABQFAOZZ7L1/fMww2ey9f3zMNmQRAABsAAAAAADEufrKTweUyzEufrKTweUIxLcze2/1jTfFt8hkGPb/WNN8W3yGQaksdyAABkAAAAAAAAAAAA43Sj7T6r4bPKV/J70sVMVNg6odM9GNfLGxFXdmrskIF1Xfkr4i/huocvGfmfA3OGcTVmGK9KimXWidkksLl6mRv8l5FJ+st6o79QRVtFJrRO2K1euY7jaqcSlaNV35K+I2FqvVzsj5H2+qmp1lTJ+pud4FM1aKntW81oYh09j3HnEOzEF1+VS/bU1p+3rJI9z367nuVVc5c1VVXjPzqu/JXxEyVkQN3dzwDzqu/JXxDVd+SviBg8HAaR/XFr7z/ALSEgarvyV8RHWkSpikuFBAx6LJC1Veifi5qmSL4jaO8jqdUvpH1je8h+j8x9Y3vIfo456IAAAAAAAAAAAAAAA0eJOspPjD9H5xJ1lJ8Yfo24EP9zBr7v63Z8NP5mwNfd/W7Php/MIxPqs6pNyAJuQGpOAAAAAAAAAAAAAAAcZjiRsVdYZHuRrGVCOc5dyIjmbTcVeI7S+lna24U6uVjkRNfuGpxp7I4f+Up9th1FaxvOdR1Kf4buLuKJ2y7TTiytrdyEw4CvVvosM0sNRWQxSo56q1zslTqlIeb1qd4m7Ry1FwpSZoi9XJxf6lPJ6C84fZ9UUcL1yKeEndaK4WKxtpaqKZzap6qjHZ5JqEG4LkZDjCwSSORrGV0Kucu5E10J94TzUSwWHJET+9v3fFqQJgf254e+XwfbQm0h553fQ+4dGP6D8J/Nl3vVLaNv/xGm/XKQ6TZWT6QsSyRuR8b66RWuTcqZl8dRv5KeIojpS7I2KPl8vlPqvRDzip7v1R+a+m1/BafvfRkr8GK5UlvTEvPVRHDrrT6uuuWfXk5Xm9W+uZQw09ZDLKtZAqNY7Nf8RCF+CsiKmKM0RdtPv8A95OuImtSnoskRP77T8X/AIiHN6Rf1Kp8P8UdTozfxVS+P+TN0ADhHoQAAAAAAAAAAAAAADQXr2Uoe8vlPah6r17KUPeXyntQ24EPFgwqr1/b/jE8qGaYVV6/t/xieVAjEtx04ANScAAAAAAAAAAAAAAAiXTH64tnwH+VCL8k5EJR0xeuLZ8B/lQi48Ppnzyfw+SPe6E8yh8fmzNtlclDK9JI0lppmqyWJU2OapzFdoosVXUPmoMQc6U71zSCaLWWPuZ5ps75ugc+FSUOqy9UoRm825nO9J+39tUP0f8A/YdJ+39tUP0f/wDY6IEnhNTmR+CL0n+xz8eiG1Nkas2KWOiRc3JHAiOVO5tU62eSjo7fS2m1xLFbqVOpRd73flL3ePwmEDSdWc9kmb08PGDzXuMk5EOy0YJ/8203wH/ZU407LRh7bab4D/sqWNH+dU+1EOkvNKnYyeAAe/PnYAAAAAAAAAAAAAABzlZ7PL8UnkMkxqz2eX4pPIZJsyFce0GLD7PU3wF8imUYsPs9TfAXyKA+B0gANSYAAAAAAAAAAAAAAA4G9vV+LKtuSZR0sWXLtc77j1nsvOSYpr1zTPnaHZntyTXPMNNPUZcxglkRclza3ZkvHmuSKfMdKYerVx9WNKLe3grnfpVIxpRzPgj1A2kOHq6VOr5lCm1OqdrKnIuSb08KGwgwxE1UdNUSPVFRcmojU7qcaqiklDo7jqu+OVe1/a7I542lHc7nNuVGtVy7GpvVdiIfuGGSodqxRveuequq1VRFyz2rxHYwWehp8tSmYqoit1n9UuSrnlmuZnImSZJuOxQ6JLfWqdy+r+xWnpF/2xONhsdwnRF5i2JFai/2r8uPaiomZsYcMJn/AG1S5UzXZG3V2Kmzaue1OVMjoQdih0fwFH+zM/bt/bd+xWni6suJrYbFQQ5KsCSO2dVKquzVNy5Lsz7xsWtRiZNREROJDyDrU6UKSy04pL2KxXcm97AAJDAAAAAAAAAAAAACgKAcyz2Xr++Zhhs9l6/vmYbMgiAADYAAAAAAGJc/WUng8plmJc/WUng8oRiW5m9t/rGm+Lb5DIMe3+sab4tvkMg1JY7kAADIAAAAAAAAAAABzePMHU2O8L1tkqZnwtqERWSsTNY3tXNq5caZptTkK3y8GfGkT1ZFeqF7E3OSolb/AAyLaAlp1p01aJXrYanVd5LaVI/Brxx770X0qT7h+DXjj33ovpUn3Ftwb+FVCLxfR9veVI/Brxx770X0qT7h+DXjj33ovpUn3FtwPCqg8X0fb3lSPwa8ce+9F9Kk+4fg144996L6VJ9xbcDwqoPF9H295Uj8GvHHvvRfSpPuNlhvguXZbvTz3+50fQ9kiPmjp3OfJKibcs1RETPjXeWlAeJqPiZWAop3sETJMk3AArlwAAAAAAAAAAAAAAA0eJOspPjD9H5xJ1lJ8Yfo24EP9zBr7v63Z8NP5mwNfd/W7Php/MIxPqs6pNyAJuQGpOAAAAAAAAAAAAAAAcxi6019xfbpaBjHyU0iydW5ERFRWqnf3GDI7Gcsb2Op6HVeitXqk4/CdqDN9ljVxIZTRrd0/wChH+3adLaLdiyyUEdFS09HzFiqqa70Vdq57yQQQUsNRpPNTgk+w0jSjF3REuNcD37H1JS012ghSOmkWRnMJkYuaplt3nLWzQPPabjSV9PC/m9LK2aPXqmqms1c0zTLdsLBgzOhSnLPKCbOnR0njaFLUUq0lHkns27zjOa409z0P6yfeRhfNBNRiC8V10q4X89VsrppOZ1LUbrLvyTLcWCBew+MrYZuVGWVvkcbE4GhioqNeOZLmQ7gbR3etHvP3QeCNefdTmnPEyP63PLLdl1ynXc74prqikZXQUiU0dRHK9Y3Jnk1yLynaA0rYipWm6lV3k+JJQw1OhBUqStFcEAAQk4AAAAAAAAAAAAAABoL17KUPeXyntQ9V69lKHvL5T2obcCHiwYVV6/t/wAYnlQzTCqvX9v+MTyoEYluOnABqTgAAAAAAAAAAAAAAHBaRcJ3DEbqF9A2JyxI5r0kfq5Z5ZHC9K3Ef+TS/t0+4ncHMxOiaGIqOrO92dXC6YxGGpqlBKy/nMgjpW4j/wAml/bp9w6VuI/8ml/bp9xO4IPEOG5vv/0WPxDiuS7n9yCOlbiP/Jpf26fcOlbiP/Jpf26fcTuB4hw3N9/+h+IcVyXc/uQR0rcR/wCTS/t0+4dK3Ef+TS/t0+4ncDxDhub7/wDQ/EOK5Luf3II6VuI/8ml/bp9x0mBsCXex3+KsrWQNhYx3WS6yqqpllll3SUwSUdDYelNVIt3Xt/0RV9N4mtTdOSVn7P8AYAB1jjgAAAAAAAAAAAAAAHOVns8vxSeQyTGrPZ5fik8hkmzIVx7QYsPs9TfAXyKZRiw+z1N8BfIoD4HSAA1JgAAAAAAAAAAAAAAD1rTxOlSVYmLK1MkerUzTwnsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUBQDmWey9f3zMMNnsvX98zDZkEQAAbAAAAAAAxLn6yk8HlMsxLn6yk8HlCMS3M3tv8AWNN8W3yGQY9v9Y03xbfIZBqSx3IAAGQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADR4k6yk+MP0fnEnWUnxh+jbgQ/wBzBr7v63Z8NP5mwNfd/W7Php/MIxPqs6pNyAJuQGpOAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAaC9eylD3l8p7UPVevZSh7y+U9qG3Ah4sGFVev7f8YnlQzTCqvX9v+MTyoEYluOnABqTgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHOVns8vxSeQyTGrPZ5fik8hkmzIVx7QYsPs9TfAXyKZRiw+z1N8BfIoD4HSAA1JgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAUA5lnsvX98zDDZ7L1/fMw2ZBEAAGwAAAAAAMS5+spPB5TLMS5+spPB5QjEtzN7b/WNN8W3yGQY9v8AWNN8W3yGQaksdyAABkAAA0mLMV2zBdknu92lcyliVG5MbrPe5dzWpxqpH2F+EBY8QXyltVVbrha5a1UbTS1bU1JVXrUzRdme5F2pnxm90xYJlx1gyWhp6mGnqaaVtXE6d2rGqtRUVHLxJk5dvLkVsueN7hjfGOHocS11qpqSyTJr1dLsj1Gua57kcirrKuoiIjdme5C7h6EKkHff8uR5jTGlMTg8RGMXaLtbZslt23d9lkWrxxju1aP7VFcrsk7oZZkgYynYjnq5UVdyqmzJqnuwXjKgx1ZG3e2xVMdK6R8SJUMRrlVq5KuSKuzMrFjnE11064yo7Th+klW3UqqkCSJllmvVTyfkpllknJ3VyLR4Qw1TYPw3brLSqroqOJGK9UyV7l2ucvfcqr4TSrRjSprN1mWtH6RrY7F1HT/JjsTtvfs9m/8AbmbsAFU7oAAAAAAAAAAAAAAB+XvbGxz3uRrWpmqquSIh6qWtpq1ivpqiKZqLkqxvRyIvgIE4R9xnW54Us9XVzUeHayVzqyWPPbk9qKq8uq1VXLu58RylDDZMGaXsMU2ALvJV0VYrI65jJ+ax6qu6pFcmxep6r/SqFqGGzQzX2u/7e04GI03qcS6OS8YuKe3beXKNtqXaWpnnjpoJJpnoyKJqve5dzURM1U5/D+PsNYqq30lmvNLW1LI+aujhcqqjM0TPdyqnjOD006VrXYMN11nt9bDU3uvidAkcL0fzBrkyc9ypuXLPJN+anNcGLB9TRUtyxLVRujjrGNpqRHJ17EXNz+8qoiJ8FTCoWpOpPZyJKmlZS0hDB4dKSs3J8v59UWFABWO2AAAAAAAAAaPEnWUnxh+j84k6yk+MP0bcCH+5g1939bs+Gn8zYGvu/rdnw0/mEYn1WdUm5AE3IDUnAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABzOP8W+obCldfedOe+dVYnMeaamtrPRvXZLlvz3GYxcmkuJHVqxowlUm7JK77EdMCLdFmmPpl3G4UfQbnDnOFsuvzzzXWzdlllqpkSkbTpypvLLeR4XFUsXTVai7xfb9QADQsAAAAAAAAAGgvXspQ95fKe1D1Xr2Uoe8vlPahtwIeLBhVXr+3/GJ5UM0wqr1/b/jE8qBGJbjpwAak4AAAPCqib1RO+eSE+FAqpgK3ZKqf/E493xchJShrJqHMqY7FeCYede18qvbcTWiou5UXvHkhPgvqq4CuOaqv/wATk3/Fxk2CrDVzceQwOK8Lw8K9rZle28AAjLYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABzlZ7PL8UnkMkxqz2eX4pPIZJsyFce0GLD7PU3wF8imUYsPs9TfAXyKA+B0gANSYAAA9dRPFSwSzzSNjhiar3vcuSNaiZqqryZFZcWcJ24PuEsOGqClZQsdqsqKxrnvm7qNRURqLyLmveJ10j2S5YjwTeLTaXRtr6yJImLK9WtyVyayKqIv4uaFUVsGNtC11jvM1pgRuXM21MkbamDau7WTaxVy37FL2Ep05JuW18EeV6RYzGUZQhRvGG+Ukr2/naiQ8NcKSRqOjxHZkeqJsmtzslz5FY9f4o7wHYaItL950j3uvo6mz0sFFSxLKtRC93UqrsmMVFzTNUz4/xVNLgrEWCdNtQ6hxDhqigxDGxZM48283am9Wvbk7ZxtVV8JM2HMLWfCVCtFZbfDR0yu1nNjRc3O5XKu1V76mK7pRTjktI20XHHV5Qq+EqdJeyzfsezZ33NwACkeoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUBQDmWey9f3zMMNnsvX98zDZkEQAAbAAAAAAAxLn6yk8HlMsxLn6yk8HlCMS3M3tv9Y03xbfIZBj2/1jTfFt8hkGpLHcgAAZABE2nrSDXYIw5SQWqTmNxukjo2zomaxMaiK5yf6tqInJmqm9ODqSUVxK2MxUMJRlXqbonXaQsExaQLB0Hmrqiii5s2Vz4ERVdqovUqi7FTb/AAI6tvBhwxTSI+tuNzrET8TXZE1e/qpn/EjNbReLVo5pNIFPjyv6KySNVaZahXIqq/VVm1y5uTeqKmWWewmq+4puNz0F1GIGySUdyntbZ+aQOVjmPXLNWqm1OVO+W8tSklGEtjdvieeVXB46cq2JoeXGGZXd7x4btnwaO6w7hWzYTouc7NboKOBVzckbdr15XOXa5e6qm4KwcHjFd+vmOa2mud6uFbTtoJHpFU1DpGo5JGJnkq79q+MkPTRpefgCKC2WqOOW91bFkR0iZsp488kcqcaqqLkncVV7sVTDz1urvdl7C6Yw3gPheXJBbLfZIlzMZlLrbQ6U9JqOrqaou9XTK5U5s+q53gz40btai+BD8XCXSdoqqIJqyrulFG92THPqOeKeRd+S5q5ufcXJSXwLblzq/Io/idqOteHnq/S/mz9y6gzI30P6T00jWWdamJkF3oVaypZH1j0d1r2ou5FyXZxKneIoghxNpuxjiWJmJZbPQ2iRWQUsbnImWs5repa5M+szc5c8s0IY4d5pKbtbedOrpenqqU8PFzdTqpbN2+7e6xZ8Fe+D1jy83G73XC93rn17KSJ00E8j9dzdR6Mc3WXa5q5oqZ8hOd+kfDZLlJG9zJGU0rmuauSoqMXJUU0q0nTnkZYwOkIYzD+EQVt+z2o2IKfaFcZ4juukiw0ldf7pVUsvNNeGere9jsoXKmaKuS7UzLK6Q8eUWj3Dsl0q2rNM53MqenauSzSKmxM+JEyVVXiRDerh5U5qG9srYDTNHF4aeKayxi7O/sSf1OsGZTb1Y6UNKddOlqmuCwtXbDbV5hBEi7kV+af/AJOVTEuVXpS0aTQ1FwrbzRse7Jj5ajm8L3b8l2ubn3FJlgnuclfkc6XSiFtZGhN0/Sts+37l1ARdob0sJpFoJ6WujjgvdE1HStj2MmYuxJGpxbdipxLlyn70yaU10dWunhoYo5rzX63MUk2siam97k49qoiJxr3itqJ6zV22nZ8aYbwTw3N5H8Vu2+w7DFuD7Rja1Ott4pubQZ6zHNXVfE78prk3KQtWcFejfMrqLE1TDFnsbNSte5E+Ejm+QjG3O0n6UZZp6Oqu1bE1yo57ajneBi8ibWt8CHtulm0p6N4kuNRUXelpWKmtNFWc3ibyayayoid9Mi/Tozp+RGok+R5TF6RwuN/8RWwcpRX921bO1fcmXDPBow1Z6hlRdKqpuzmLmkUjUihVe61u1e8q5E0RRR08TIoo2xxRtRrWMbkjUTciIm5CINCel+bHjKi03hsbb1Sx81SWNNVtRHnkq6vE5FVM0TZtzQ5PFdViHSfpXuOD6S/S2a12yNVyiVyLKrUbmuTVRXqqv2JnkiJmV506tSbjVe47GHxeBwmFhVwNO+sdklsbfJt8ixwK06JMWX/Dek2qwLc7q+6UXNJoGvker+ZyMarkc1VzVEVEVFbnsXvFliCtSdKVntOpo7Hxx1J1IqzTaafBoApdiLG2JodJt0pIsQ3ZlKy8vibC2rkRiM5vlqomeWWWzIuihtWoOkk295Do3SsMfKpGMWsjt8/sAAQHVAAANHiTrKT4w/R+cSdZSfGH6NuBD/cwa+7+t2fDT+ZsDX3f1uz4afzCMT6rOqTcgCbkBqTgAAAAAAAAAA5vHeMqPAeG6q81jVk5nkyKFq5LNIvWtReLlVeJEVTMYuTsiOrVhSg6lR2S2s6QFK6jF+kLS5eX0dDPWSa3VJR0L1hgiZnvcuabO65TKrtEekzDtO+4xx1TliTXctDXq+Vvd1UVFXwZl3wNLZOaTPNfiWdS88PhpTguP8T+ZcoFYdDunO6LeaSwYmqVrKarekMFZL/ixSLsaj1/Gaq7M12oq8m6ddIWNqbAOGKm8VEazPaqRQQouXNZXbm58SbFVV5EUgqYecJqD4nVwel8NisNLExdlHffejqTxn3/ABFLH4z0kaUbrJT2+quErl6paW3OWGGJvFmqKmSd1ymFiO2Y90cy0k1zulZQz1GaxNjumu9ct6q1HLs7q7CwsC75XJX5HHl0pWV1adCTpr+7h9v3LS3fTPgixXKrt1fe0irKR6xyxpTyu1XJvTNGqi+A7alqYq2lhqYHK6GZjZGOVFTNqpmmxdqbFKN6NLbb8W6Q7bTYhqZXRVk7pHq7atTL1yMcvEjlzzXwceZanS7j52jzCTqqjbGtyqXpT0jXJm1rlRVVypxo1Ezy5cjSvhlCUacNrZY0XpqpiaFXF4i0YR3W3/Hb2W5skHMFJcP2zSRpGkqrnbKy51joX5PndX8yRHb9VubkTdlsRMkNleK3TDFROsNwZiGSCZUaqJBzRz+4krUVVT/cbPBbbZ1chj0nvDWPDzyvc7bH/PiXIPGaZ5Z7SBamrxdo10I1dXdLjVS4gqZWMjWeXmrqJj1RqIirn1SJmu9clXuEZ37AlbhnAllx7Bimqkuda+J7kbIqORZEVU1X55q5uW3Pu8hpDDKX93Gy9paxGnJ0UrUW2o5pJtLKvq/YXHI00/diq+d+DzzDd6LcS1OLsB2a7VqotZNG5kzkTJHOY5WK7Lu6ufhNJp+7FV878HnmEdKLjWUXwf1LmOrRraNqVYbpQbXxiRNwWfbHiD5HF5xS0hVvgs+2PEHyOLzilpCTHfnMpdF/6dDtfzYABUPQgAAAAAAAAGgvXspQ95fKe1D1Xr2Uoe8vlPahtwIeLBhVXr+3/GJ5UM0wqr1/b/jE8qBGJbjpwAak4AK2aZNOlzoL1V4ew1MlK2jdzKprUaiyOkTe1mexqJuVd+eeWWW2WjRlVlliUNI6Ro6Ppa2t8Et7ZZLMjjTZaLDeMIwNxFeJbVb4ayORJ4ouaKr9VzUbq5L+Uq+Ar1SYH0qYlpFur3XbmDm805tW3FYc25Z62TnoqJltzyRDgrliG9V9Mltr7vV1lJBIr2xS1KysRyZprNzVeLPamzaXaWDtK8Z7uR5jH9JM1Bwq4ZpTWzNufy2djLX6DqjCNut1fYcNX6a7PbKtbK6WmdErEcjWZbWon4vfJbIf4OljtFDgVlyoJFmrrg9efJHNyVj2KqJGiciZ593Wz7iSxXVSUVHUVKtVyQxukVqb1yRVy/gU8RbWtI9HohtYGnKaS2Xsr2S4b2+BkZgqXaLfizS1aL/i6bF0lCtvc9YqNkj2sZqs18upciMbkuSLkqqqLmSZwd8fXTF9luVDd6h9VU2x0epUSbXvjei5I5eNUVq7e6SVMM4Rcr3tvK2D05HE1oUnTcVNNxbttt7OBNB4zK6cIDSxc7RdEwxY6t9G6ONslZUxLlJm5M2sa78VMslVU27UTlODtODNLdNQwXu2reEZM1JW6leiyOau1FWNX7c+RU8BmGEbgpSklchxPSGNPESoUaUqmXe1w/nwLkAp3A3S5jXEVBTzy3ymq6ZdRtQ+N1LHTtVU1nOVqNRd3dVcsibNLekybRlh+30NG9Ku+1UepHNOmeq1qIjpXJxqq7k3ZqvIYnhWpKCabZNh9O06lKpiKlOUIQ4vj7EuZLGYKV2lNKekbm1db6y9VsTHKjpW1fMIkdxtb1TW59xD3WbSrjvRzfVo7vUVtQ2nciVFvuTleqt/0uXNU2bUVFVO+SPAvcpJvkUY9KaatOpRlGD3Sts/nY2XOGZpY8TUU+FfVHE5XW9aNa1F49TU1su/lsKw4Sq73pvxdXtuuKqu1QxwrUQ09NKrUameSNY3NE6lNqquaqQU6Dmm27JHVxulY4eVOnTjnlU3K6Xxuy3AIO0DYqu9ZccTYcuNyddqe0SZU9c5yuVzddzMtZdqouqipmq5bSJNJ+OMTW/SJiGlpMQ3WnpoatWxxRVb2sYmTdiIi5IhJHCSlUdO+4qV+kFKjhIYtwbUna2zY1e/yLmA9cCqsMaquaq1PIRVp+xtc8HYUpm2mV1PV3Go5hzy3romI1XLqrxKuSJnxbSvTg6klFcTr4vFQwtCVee6KJZzBUbF9qxdoeWx3uDGM1dPXqqvjWR7mK5ERyoqOcqSMXPfsLLw4upGYJhxRWf2NItC2ukam1WorEdqpyrtyQkqUMiUou6ZSwWlVXnUpVYZJQSbTaex8bo6IZlMr1pUx3pHvqUVnnraZs7lSC325ysVGp+U5MlXZvVVRO8ei7JpS0c8wrbhWXqiikcjWyOq+bxK7fqu6pzc9m5SdYF7nJJ8jly6U09s6dGUoLfK2z+drRdQZkXaFtKMukOz1UVwZGy8W5WpMsaZNmY7PVeicS7FRU5e+RNaKTFOm+txFdlxTJaoLc/KCka97WMRc1aio1yaqZJtcuaqufIQxw7vJTdrHRqaZpunSnh4ubqXsti3b735FqgQPwc9IN2xJFc7Ld6mSsfQsZNBUSu1n6iqrVa5342Soioq7dveJYx1UTUmCsR1FPK+GeK31D45I3K1zHJG5UVFTcqKaVKThPVstYTSFPFYXwuC2WezsOgBU7QLi7EF40iUlLcb5c6ymdTTOWKoqnyMVUamS5KuRbEzXoujLK2aaL0lHSNHXQjbbbaAAQnSOcrPZ5fik8hkmNWezy/FJ5DJNmQrj2gxYfZ6m+AvkUyjFh9nqb4C+RQHwOkABqTAAAA0+LKWGswxeIKiJksMlJKjmPTNFTUU3BrMR+wF0+Sy/YUzHeiOsk6ck+TKbaBXKmlPDqoq5qkufd/sXl3CkWgbspYc/O+ZeXd4i9pD8xdh5fof5lP3n8og8ZlYNK2n25y3aqs2FZ+daOnesMlaxqOlnei5LqKvWtz2ZptXuHLUmjzSziKFK9WXdUkTWa6ruKxPd/tc9FTwohpHBvKpTko3LFbpHDWujhaUqrW+276lyQUrhxzpG0XXdlLcKuvY9uTlo7i5ZopG9xVVdndapazR/jakx9hmmvFKxYnOVY54FXNYpU3tz496Ki8ioR1sNKks17ot6N03Rx03RyuE1vTOoGZUbSzpXv2KMV1FisNZU09tgn50ijpHqx9VIjtVVVybVRXbETPLjPXDhbTLg1iVdKl31FTWVkFU2qTwx6zvISLBvKnKSTZTn0kjrZQo0ZTjHY2lf+d6Legqvo4tmkrFmO4brcqy9UVIyRrq2eVHQMkY3/pNZkiLnu2JszVS1BDWpap2vc6mjce8dTdTVuCvZX4+0Ar1pEueIMc6V2YDt96ks9vghR73xKqLKvM0eqrkqK7YqIjc0TYqmmwBiPEGANLPqKr7zJdrdLNzuqyPV6Nc5muxzdZVVq7kVueW8kWGbje+217ewpy05CNfVum8mbJm2dblbfb2lngcnpDx5RaPsOyXWqYssznJFT07VyWaRUzRM+JEyVVXiRCsXqx0oaU66dLVNcFhau2G2rzCCJF3Ir80/wDycqmtHDSqLNey5kukNNUcHNUVFzm+C3lycwUruVXpS0aTQ1FwrbzRse7Jj5ajm8L3b8l2ubn3FLB6G9LCaRaCelro44L3RNR0rY9jJmLsSRqcW3YqcS5cptVwsoRzp3RFgNPUsTW8GqQdOfJ/z6EojMiDTdpanwDT01stCRreq1iyc0kbrNp488tbV43KuaJns2KqkF2mj0qY+hkudBVXysp0cqc2585ixVTejUVzUXLuIKeFc455NJGuN0/Tw9d4alTlUmt6XD+dhdMFNsM6YsZYBvi0d8nrKymgk1Kqir1V0rE49Vy7UXLam1UX+JbG5YlobZhmoxA+TWt8VKtWjk/HZq6yZd1dnjNa2HlSaW+5Y0dpmhjoTkrxcN6fA3GYzKTTYnx5pcxM+Chqat8z9aSOipqhYYYGJ4UTZmiZrtVTePbpowNC6HO9rTqmrm3VrWN7y9Urf4EzwTWxyV+RzY9J4zvOFCbgv7kv58y3oII0AYcxjSy1t0xBV3OG3SMVsFFWSOzke5c3SKx21qcm7PNSdyrVgqcsqdzu4DFSxVBVpQcL8GAARlwBQFAOZZ7L1/fMww2ey9f3zMNmQRAABsAAAAAADEufrKTweUyzEufrKTweUIxLcze2/wBY03xbfIZBj2/1jTfFt8hkGpLHcgAAZBCfCSwhX4gw5brnb4H1Elpke6WKNqudzJ6Jm5ETfkrUz7ma8RNhCfCWxDX2jCdvo6KofAy41KxzujcrXOY1irq5pxKuWfeJ8NfWxynJ04qbwFXW7rcOd9n72IJwC7R0yFZMXtu7quKXNsdPtglZsyzRqayLvRdu1MiwOKMX2XGWhfFNTYWyNoKSndSox8KxaqtRioiN5ERUI00IaJMP48w/X3K8LVPkiqlp42Qzcza1EY12ezeq638CT8YYItOAtD2LrfZ2zNppoXzuSaVZF1l1U3r3GoXa84Oqld3TXYeb0Rh8VTwM6jjFU5QltXWex2uRLwZOyDX/ADbJ5yMmLS7YsDWy21eKsR2NLhWIjII2pM9jpXbmMTJ2ScaquW5FXaQ7wZOyDX/NsnnIyS+FAuWArd85x+bkMVk3ikr2vY20bKMNBTm4qWVtq6TV+dmchZ9N+K7FZaC4eoqmhwdEraeF0DZGo1idSiNkVVRV2ZZqmSrxkg6ZLnRYj0J191pMpKapjpqiFzk2pnKzLvLtVPGQ7g71e6SsDtwhbI6BuH6SVkM1XKqNexqKj2sXbmqJsXY3PZlmS7pUsMOF9A1bZoHrJHQ09NCj3bFflNHmvhXNTFSMI1YpbHfhy9vtN8JXxFbA13JuVPVvbJJeVZ3Ubb0RzwWVX1SX9M9i0ca5fnFOi0xaHaGipb9jK1XKpoJ2xOnqKWNOomcq9VkqKitzzzVNqZ8RznBZ9st/+RR+cJt0ydjDE/yN3lQxWnKGJ8l77G2jcLSxGhP+rG+XM17GrkA8GNMtIFcnJbZPORlpMR+wF0+Sy/YUqnwcq+ltmNbrWVtRFT0sFsldJLK5GtYnNI9qqp2mkrhF2+e3VtpwvE+ofOx0L7hM3Uja1UVFVjV2uXJdirknfM4mlOpX8lcjXQukMPg9FXrSs25WXF9iIt0DdlLDn53zLyddPWj274zgoK6luFvpbfaopZJkrJXRoirlm7PJUyRG8ZC2gCW1Uuki3y3KqWnlax8dG1W5tklemqjVXi2KuXKuRPHCMqJYNGdU2N6tbNVQRvRPxm62eXjRDeu2sTHKVtE06ctCV9btV27J8krX5bUQ3oc0jYstVyosMWihprpb1mVXQsi1XNarurk5omWzbnm7PiTkLH6UbfBctHmJYqiNHsZQyytzTc5jVc1e+itQhjgpwRuqMVTqxFmY2mYjuNGqsiqnjRPETjpC9oWKPmyp804gxLSrpJWtY6mg6c3omUqknJSUrJ8ErqxVzg4zPZpLp2tcqNlo52uRONMmr5UQshpDw3gyqoZb/i2ghnht0KpzWRzs2tzz1URqpmqquxONVK2cHTsm0XySf7KEw8J2Z8Wj+jY1yo2W5RNenKiMkXyohLiIuWJik7XKOhqkaWhatScVLK27Par2Vv3Iwl0/3G3RQ2jBliorXaYVVtPC9jp5VRVVd2eWaqqrlt74q9PWI6mzXSy4mtMMkVwpJYGyNhdBIxzmKiO1XbHIiqnIazQtpFw/o+q62W7W2eaoqnNYysha16wMRFzTJVz2qua5ciFj9ItLZ8XaMbxWIkNZS9D5KylnRM8nNYrmvau9F2J/FDarkpzUXDZzIMCsVjcNKtDFWkk/ItsS5W3WtyWwrjwdFVNJtIme+knRe71KE16UtDVBiWqqcTUdxqLXdoYXPlfCmbZtRuxd6K12SZZou7iIU4Oi56TqNf8Ays/2ULb4j9gLp8ll+wpHi5yhXTi+Bb6P4WlidFyhWjdZm/jZFN9BLlfpVw85VVVcsyqq92F5dtCkWgbspYc/O+ZeXdNdIfmLsLHQ/wAyn7z+USiOJuyvd/n1/wD3Be5CiOJuyvd/n1//AHBe5DOO3Q7PsR9FvzMT7y+oABzz2AAABo8SdZSfGH6PziTrKT4w/RtwIf7mDX3f1uz4afzNga+7+t2fDT+YRifVZ1SbkATcgNScAAAAAAAAAEEcKSGd2E7NK3Pndlfk9OLNY3avkUncj7TbZW3vRnfWauclLElXGvIsa6y/wRyeEmw8stWLObpii62BqwW+z/bb9CEtFeM4sB6KMWXmlp45rtHWxRIj02dU1EYrstuSdWuR2CY3x5gitwrXYnuVvulpxBIyN0EEKMfT6yNVFaqImtkjk5U2KnIpD+jHENitVJiq34la+Wz3ChavMI16uWZj01EZyO6pVRdyZHd6GNGVbii40WJbutUzD1ufr22lqpVkWRUXNuWeSajVRNqIiOVNiZHRrQhFylNf72bkeM0dicRVhRo4aTvbcnZRtJ3lJbmmuZGekmNlu0mYhSlakTYri57EbsRq5o7Z4VLo4mwjZMZUENLfaNtXTQv5s1rpHMRHZKmfUqnEqlMdLHZNxN8ud5GluNKtZNQaNcST071ZK2heiOTemaZL/BVI8TdqlZ7f+xe0HkjLHZ43ine3DY5EM3LTDhTRu24WjR9Y4nrI9VlrZJXLCsiJlmmaq56J30Tk35kYWHHNN6r+j+MbY/EEkr2qqzS6qMyXejMtVyJxNXJDE0d3+yYXxNFcr5a33KlgYvM4Waq6j80yeqO2LkmeScqpyFx7VW4Y0oYWbPDTwV1qqEWJ0M0SI6NybFaqfiuTudxUUkquOH/tbvvdylgYVtL7VWjBw2xhlVl7bbv2bKb4SqI59Jdknp0VkUl4ifGmWWTVmRUTLi2KWr0t6LZ9JkNqjhurKFKB0rlR8KyI9XI1E3KmWWqvjKqYVpmUekuzU0aqrILzFE1V35NnRE8hfUjxs3CcZR5FzozhoYrDV6NdXTkrrd7eBU+4cG3GFoRZ7Tc6Kqe3c2KV9PIvez2fxNFY9LeOdHN3fb7rPU1TKV+pPb7ius5E5Gv3ouS5ouapu3lr8YYvteCLJLdrtK5lOxyMayNus+R67mtTjXYviUpLpHxTBjXGNzvlNTy08FWkerFKqK5EbG1u3LZt1TfDTniLqqrrmVdNYaholxlgajjUv1b8Nu3v57y7FXQ2vSFhBsVVE59ru9MyVGquq5rXIjmqi8Tk2L30Ki6XNHvS4uNut0V2qK6kqY3zxslbq8yydkqZIuWa570RC22j32hYX+bKbzTSv/Cm9seH/kcvnEIMHJxq5E9m06vSOhTq6PWKnHy0o7e1olnQD2KrH35/PPGn7sVXzvweeYeNAPYqsffn888afuxVfO/B55hF/wDmf/3fUv8A/wCif/xf/wCSJ+Cz7Y8QfI4vOKWkKt8Fn2x4g+RxecUtIZx35zNOi/8ATodr+bAAKh6EAAAAAAAAA0F69lKHvL5T2oeq9eylD3l8p7UNuBDxYMKq9f2/4xPKhmmFVev7f8YnlQIxLcdOADUnBDOkDD+jDALkv93syS3OonWeGJksjpJ5dbWVdVXauWa5qq7NvgJmKe8JGrmn0jrDI9VipqKFsbV3NRdZy/xLWEg51Mt7I4PSLERw2E1rgpSvZXSdm+Jg6RdNt7x9E63wxdDbQ7r6aF6vfN8N2SZp3ETLlzOfv+JLBcsI2q2Wywpba+kqHSVEySc154RWZZq9eqzz/F3JxE3aD9JGDqeltmF4re+3XWRjWOqJWNVtXMqberTbmq7kXuIavhO4btdAyy3elo4oK2pmkhmfE1G81RG6yK5E3qi8e/aXoTjGoqWW3I8picLWrYOekNeqjaSkrbtq2J8LexK50vBjnbDgC6ySyNZDFcJHOc9cmtRIo1VVXiQ7XCGlnDmOL1crRb515vTKvMuaoiJVRonVPZyoi57F25ZLu3cTwY4o58A3aKVjXxSXCRrmPTNHIsUeaKnGhHmlvRbW6N7vHifDLporUkqSNdEvV0EmexM/yFXcq95eLOvKnCpWnGTs+B2qOMxWD0bh69KOaCXlLjb2fz9rmfpk0O0OCbTXX+z3Kphoqidkb7cqdR1btyORUzai7kVF75suCntlxX3qb+oa7GelSm0iaH54qjUgv1JVU3PMCbEkTWy5oxOReNOJfAbLgp/4uKu9Tf1CWefwaSqb1/ooYZYV6aoTwnUkm/jaV+zsNtjvg81+LMT3S9w3+CN1bJrpDLTOXURGoiJrI7bu5COrzof0hYAhluNvq5JqenRZHy2uqe1zGpvVWLkvizLhEYaV9LNkwXTy2idk9Vc6yndlBBl/ZtcitRzlVdmfEm1dhXo4ms2oLadbSWhNHU4TxM24Pfe73vv48iONDOnC9XK/0WHcQSJXRVqrHBVq1ElY/JVRHZbHIuWWe9O6Sjj7Q7Z9It1prjcq24QyQQJA1lO9iN1dZXZ7Wrt2/wACq+iFMtJWFU5Ktqf/AIuL2JuQ2xa1NVOns2EXR6T0jgZU8Z5aUuPYmabCeGaPB+H6Ky0LpHU1I1WtfLlruzVVVVyREzzUrHwnWNZpBt6taiK62xqqpx/2kiFtipfCe7IFt+bI/OyGuCbda79pN0npxp6NyQVknFImrRvbUvehS1W1ztVK22Pp1cvEjkc3P+JU6nsVLhzFaWvGdNcKamgcrKhKXJJU2dS9uaKjmqu3ZvRdhbXRdVOodDlkqmIivgtzpERdyq3WX+RVvBFA/SZpFt1NfqypmW5SPkqJUf1bkRjn6qKu5NmWzcm4sYZtSqN7jj6apxnSwUYq82klfdw3/H6k/wCifGOjm31UGGsKR1zauvc5yyVMDtaVzWqubnryIi5Ju8ZX/S32TsTfLV+y0tJhrQlhXCV6pbzboqxtbS6yxrJUue3qmq1c0XfsVSrelvsnYm+Wr9lpnCyhKq3C+7iY07SxFLR9OniFFNT2KO61vvcuBjLHVqwBh5Llc3qrnNRsFOxU5pO/LrWov8V3Ihr7lbsN6bMERaszpKKdUkimjVElppU2bUXc5M1RUXei91FM/GmBbZj/AA50NuDNWRGo6nqWp1cD8uuTucqcaFYcO3/EOgXGs9vuML5KGRyc8U7V6ioj3NmjVeP/AJavcq0aSnG8H5aO7pPHVMLWUcVBPDzVr8n7f52bTmtJuEpMD4mdZHXKW4MggjfHLI1W6rXZrqoma5ImXEWts2GabGOh+y2Ssmnhpqy2UrXvgVEeiI1jtmaKnFyFatOd4osQY56J26oZUUVVQU745GrvTJ2xeRU40XahbDRx7QML/NtP5tCfFSlqoSe85WgaFF4/FUYq8LW57L/Y0WANDlk0eXOpuNvqa2oqJ4eYLzy5io1usirlk1N+SHp0+sa7RTfVVqKrVgVFVNy82YSURtp87E9//MeeYU6c5TrRcntuj0eMw1LDaOrU6MbRyy2fBkRcFn2y39OLnKPzhstMehuhw5ar5iyz3KppI3K101vanUPWSRGqiORUVG5uz1VRUNbwWfbLf/kUfnCXdPnYnv8A+Y88wuVZyjirJ77HncDhaVfQTlUjdxU2vY9pEXBZ9st++RR+cLBaQvaFij5sqfNOK48G660Nku+Ja+41UVLRw0Mavmmdqtb/AGnL/I3OlPhCUd4tNfYsN08joauN0M1fOmoisXY5GM37U2Zrlv3GK9KdTEeSuRtozSGHwmh0q0rN5rLi9r4fxHHcHTsm0XySf7KFyioHBvltMGPXOrqtYa99O6GiiVvUyOdtd1XEuq3YnHmvIW/Isf8Am/AvdElbAb/7n9AACkenOcrPZ5fik8hkmNWezy/FJ5DJNmQrj2gxYfZ6m+AvkUyjFh9nqb4C+RQHwOkABqTAAAA1mI/YC6fJZfsKbM1mI/YC6fJZfsKZjvRHV6kuwproG7KWHPzvmXl0bpzZbZWc75835i/meW/W1Vy/iUR0c4ohwZi61Xyop5aiKkR6uiiVEc7WjVuzPZs1sy6OBsf2bSDa311pkkzicjJoJU1ZInZZoipuyXiVNinRx8JZ1O2w8f0RxFLweeGcrTbbtxtZFPdEXOTdI1gkueolLDI+V6yda1zI3ORV7ypn4CY6XSzj7SBcrnJge10LbVbslXnpEWSVFz1c83J1Tkaq6qbuUhHSPZkwzjzEFvjzZHDVPfHlxMf1aJ4nZEyYV0GYhp8OW64WPFs9pqbrSMdXQaiq1UcmaIitVNyOy27c89u0nr6t2qS4rZfccfRXhkZTwdFO0ZNyytKT4JXfJr5mm0oYxj0i6JbHf5qNlPcqa6uo5UZta13M1V2rntyVNRcl/kdZwWXuXD+IWay6qVjFRORVjT7kNLpgwPSaPtEVms9LM+dUuqSzTvTJZJHRvzXLiTJERE5ENzwV/YPEXyuPzZFUcXhpZN1/qdLCRrR01TWI6+Tb25TR1/Bbur3yS0+JKSWR7ld/bUz2Zqq570cpxt8whpG0TRpXtraqGhY5G89UNW58SKq5IjmruRe63IucV608aWbJU2i84NpGT1Fe5WMlnZkkULmSNcrVVdqqmrkuSZIvGaUMTVqSUWrosaW0No/BUJV4SdOW21m9r4LibzQbpdr8dS1dmvTI3XKlh5uyqibqpKzWRq6zdyORVTdsXPcmR1eJdL+G8LYoobBW1K88TrlNK1UWOkz63mi8Wf8ABNq5IQRwX/b9cfmx/nYyTNNmhxmLqeS+2SFrb9C3+1ibsSsaibvhom5ePcvFlrVpUo18stiZLgcbj6uiVXo+XOL472l83/N5udI2hq3Y+r4LzT3Ge2XaJiN55gbrJI1OtzTNFzTPYqKmwrJopc5+k7DTnuc5617VVzlzVVydtVSUdCOmF9tdHhLEkzmQovMaOpnXJYXbuYvVdyZ7EVd25eLKLdFGzSbhn5enkcWaUZwjOE9yWz9zi4+vhcVXw2Kw6tKUvKXtTjv+/EsHp60e3fGdPb66luFvpbfaoZZJkrJXRoirlm7PJUyRG8ZFehzSNiy1XKiwxaKGmulvWZVdCyLVc1qu6uTmiZbNuebs+JOQmPhF1EsGjKpbG9WtmqYI3on4zdbPLxohwnBTgjdUYqnViLMxtMxHcaNVZFVPGieIhpy/8K3JXS3fz4nSxtL/APHKcKEnGUleTvvst1uyJM+lG3wXLR5iWKojR7GUMsrc03OY1XNXvorUKzcHGZ7NJdO1rlRstHO1yJxpk1fKiFo9IXtCxR82VPmnFWeDp2TaL5JP9lDXDfkVESaaSWlsI1v2fMn7HGhKyY9vq3e4V9yiqFiZCjIHsRiI3PLe1V41O5w7YqXDNjoLRR6y01FC2Fivy1lRONcuNd6982YKUqkpRUW9iPT0sFQpVZVqcUpS3vmU14RbUbpNrFRERXUlOq91dVU/khYCmwxJjTQpabHHWJSPrbXSt5urNfVREY5dmaZ5omW/jIA4RnZMqvkcHkcWi0ce0DC/zbT+bQvV5ONGm0eW0VSjV0njKc1sd0/iyv8AXcF3EFMiyW++0E727USRj4VXwprHJVd20j6ILnDTVVdW0yPzdHHLLzxTzNTflmqpxpuyVM+IudV1UNDSzVVTI2KngYskkjlyRrUTNVXuIhT3TfpPtekWqtcdqgqWQW50yc2nRGpLr6mSo3enW8e3buN8NWqVpZZq6K+mtG4PRtLW4abhU4JN7dqv7f3LJaLMedMTCkd1kp209VHK6nqI2LmzmjURc257clRyLt3bjtiEuC97Qbj85yebjJtKFeKjUlFbj1eia86+DpVaju2toABEdABQFAOZZ7L1/fMww2ey9f3zMNmQRAABsAAAAAADEufrKTweUyzEufrKTweUIxLcze2/1jTfFt8hkGPb/WNN8W3yGQaksdyAABkEe6YtHsukLCyUtG9jLlRy88U3NFya9clRWKvFmi7+VEJCBtCbhJSXAgxOHhiaUqNRXUikVmvePdEFXUwRUtVQtlVFlgqqZZIXqmxHIu7wtU92INJuO9I9GtoeySWlmcmvTW+jcnNVRc0RypmqpntyzyLrZIoRqJuTLvF3wyLeZwVzzX4arRg6MMVJU+VuHf8AQg/QForuWD1rL5e4+d6+riSCGlVUV0UeaOVXZblVUTZxIndO50sYGk0gYPntlPIyOtikbUUyv2NWRuexeRFRVTPizO4BWlXlKprOJ26Oi6FHCeBJXi00+bvxKQWi6480P3CqjipaqgWbJJoqim5pDLluVF3L32qe7EOkPHWk6njtUkMtRTuejudbfSORJHJu1ss1XLkzyLsZIoRETcmXeLPhsW8zgr8zifhmrGDowxMlT9G3+7fsQ5oF0YV+CKGuud5YkVyuLWMbTo5FWGNua9UqbNZVXdxZJ3Tr9LsEtTo2xLFDG+WV9I5GsjarnOXNNyJvO1BVlWlKprJbzu0dH06GEeDpbFZrv4lDsJ6OMRYtvUdspqGppmydVLPUwvZHGxF2quaJnxZJxrl3ySNIWhvpdw4fvVmo57zBRSo+4pK3W5oqOa5qqxNzFyVq5Z5ZpnmWpyyBZljpuSdtnI4tHophqdGUHK83ulbd2L58yqtbearTdjrDC2fDs1ugtkjX1NU5M1axHtcus5ERMk1cmpvVXEn8I2GSbRvI2ON8jufIFyY1VXevEhLSIibkyPJE8R5UWlZR4F+GiGqNaFSpmlV3uyXCy2IrnwV6eaBcV81hkj1udstditz/AMXlJp0gNV+BMTtaiucttqURETNVXmbjowaVKueprLFjBaP8Fwawma9k1e3Nt7viU74PFHUQ6S6N0lPMxqUs/VPjcidanGqE8adcI1+MMCvp7ZEs9ZR1DKtsDeulRqOa5qd3JyqiceRJgN6mJc6iqJWsVsHoWGHwU8FOWZSvttbf38inUGPJKjRumj6LCE8l3d/ZJI2Jc9bXz19TV1uacX8+InW24ar8OaCaqzVbFdcIrRUo+JnVKjnte7UTLeqa2WzkJPyTPPLbynkVMRm2JW23+JjB6HdBuVSpmeXItiVo/De/aVB4PtnuNFpJo5am31kESUs6K+WB7G56qcapkW4qqZlZTTU8qKsczHMcicipkvlPdkDWvWdWWa1izorRkdH0HQUsybvuKS4i0c4w0X39lbR09W+Kkk16W5Ucavblxa2SLqrlsVHJlv3obSThA6QJ4FpWS0zJlTV5pHQ/2ngTamfgLjHjVTPPJM+Un8MUrayCbOQujU6MpeCYiVOL4fxr7lOtGmibEmLsS0l1ulJVUtsjqG1VRVVbVY+dUdrZNRdqq5U2ruTb3i4yAEFevKs7s62itFUtHU3CDbb2tviAAQHUAAANHiTrKT4w/R+cSdZSfGH6NuBD/cwa+7+t2fDT+ZsDX3f1uz4afzCMT6rOqTcgCbkBqTgAAAAAAAAA5zSBBLU4GxJDDG+WaS3ztYxjVc5yrGuSIib1OjBmLs0yOrDWQlDmmikujLRnX4ixnbaK82qvp7WiulqHTU742ua1M9TNUTrlyTvZl1ooY6eFkMTGxxRtRrGMTJGoiZIiJxIR/jrHl3tOIbbhjDNrgrr9XQuqVWrl1IYYmqqZrltVc0Xj4u6afRxpaumIMWXHCeJbXT0V5pEeqOpXKsblYqazVRVXbkqKioqoqFyu6ldZ7bEt31PO6Lp4PRc3hYyblJ2zW2Xt1b7v+5AmlDDF8q9I2Ip6ezXGaCStVzJI6V7muTJu1FRMlLaY3sEuKMGXizwuRk9ZSvjjV27WyzTPuZohFelLTjecCYwks1FbaCeBsMUnNJ1frZuzz3LlxE7NXNqLyoYr1J5acmrW3fsZ0VhcMq2LpU5uTk7SVrWvm3c+JT/BGOJ9F1uvmHrxg6WouFZIuSSsyVy6qN1HZouszZmmrnvUmHg84SumGcIVUt0hkppLjUpPHTyJk5jEajUVU4lXLPJduWRL+Sch5NauJzppK195YwGhXhakJzqZlBNRVkrX33a3lHrFZrk3Sjb5XW6tSJL21yvWnfqonPGeeeWWXdLwnjI8mlevrrbLWJ9FaKWjlNKWbM77rEP8InCdzxLhClmtkElTJbqjm8lPGms5zFarVVETflmmxOLMhbG2JKvS/U4ftNkwpJSVtFG6JzWMz2qjUyzRE1Y25Z9Vuz8dnNI+OqfR7hma7zQOqJFe2GCBF1eaSOzyRV4kyRVXvER3LThjnB9XQTYqwlSU1urk12JE5zZFamWeS6yprIip1LkTwFnDSnlVo3te223b2nF03Rw2vnrKripKOdKObYn5O3+0nbDlrWx4ftVsc9HuoqWKnVybnKxiNz/gRhp30XV+OqKhuNn1ZLnb2vYtO5yN5tG5UXJFXYjkVOPfmpLNur4Lpb6Wupna1PVRNmjdllm1yIqL4lMkpwqSpzzreejxGCo4vDeDz6rS3fsUmsWK9ImjGOS3U8FfR0+srlpquiV7Ecu9W5psz7i5KL7izSJpOjjt1RBXVdPrI5KakolYxXJuV2Sbcu6uSF2chkWvDI3zZFc4P4aq5NT4VLV8vZy32/Yh7QRoursCUVdcLxqsudwRjed2uR3MY25qiKqbFcqrty3ZITCAVKlR1JOUj0ODwlPB0Y0KW5AAGhaAAAAAAAAANBevZSh7y+U9qHqvXspQ95fKe1DbgQ8WDCqvX9v+MTyoZphVXr+3/GJ5UCMS3HTgA1JwVn0+YVuduxtbcYQW1bja2Nh5vHqK9rXROz1XomeTXJlt3byzAJaNV0pZkUNJYCOOoamTttTT5NfMqtWXes0345wxJZsOzW2ntcjX1NY5EXVaj2uXNyIiZJq5NTequXcdfwnqGqrbJh9tLTTzubVyK5IY3PVE5nx5IpPKIibkyPOWZL4TaUZRWyPAo+JXKhWp1al5VLXdkt1rbEQtwZ6OoosE3JlTTzQPW4vVGyxuYqpzOPbkqEx1dJBX0s1LUxMmp5mKySORubXtVMlRU40PduBDUqZ5ufM6WCwiwuHjh73UVYpvpa0NVuDLpz3aKaoq7FVOXmXM2LI+nd/luyzXLkd4F27+94Ltvq6GXFHPVJUQa6U2rzaJzNb/ABN2aJmWLGWRPPFynS1cl8TkYfo7Rw2NWMoyslfybc01v+IK4aRmV+j/AEwx43qLNLdLNPC1qOjTPmL0jRipnkqNcmWaZ7FRV2ljxlmQ0qmrbdr32HU0hgvC6cYqWVxakna9mvZxKo6NLNcMfaXXYtgtL7dZoal1W5VbkxF1VRrEXJEc5VXNcu6WuTYgRETcDNatrWna1jTRmjlgaco5szk22921+zgCqHCapZ58e250UE0jUtrEVWRq5M+ayciFrwKFXVTzWuY0ro9aQw+ocsu1O9r7u44LRJSpLorw9TVEao19HqPY5FRclVyKhWrFei/FujK/pX2yCrmpKaXmlJcaNivVicWuiIqtXLYuaZKXSBvTxMqcnJLY+BWxug6WLoU6UpNSppJSXw+3+ynbuEFpAfDzsklKk+WXNG0P9pn3t2fgMfAmifE2P8Qx3G701VBbpJ+b1dbWNVj59uao1F2uV27PLJP4Fy9VM88kz5TyS+GKKapwSuUl0blVnGWMxEqijw3fVnhEyRETchxukjR1btIlkdR1OUNdDm6lq0bm6F/82rxp/NEOzBTjJxeaO89HXoU69N0qqvF70fP69YJv9hudVbqy01fPFO7VcsUD3sdyOa5EyVFTaXc0eRviwHhqORjmSNt1OjmuRUVF5mmxUXcdJkeSxXxTrRSa3HH0ToKGjas6kJ3UtlrbgRzp4jfLoqvzI2Oe9eY5Naiqq/2zOJCRgV4SySUuR1sVR19GdG9sya71Yq9wXqaeDEl+WWCWNFo2IivYrc/7TuoS7p0ppqvRbfYaeGSaZ3MdVkTFc5f7Zm5E2kiAmnXz1VVty/Y5+F0UsPgJYHPe6avbnfhf2lFsE6L8QYzvLbdHS1FDToiST1NTC9jI2ou/JUTWdt2J5EzO/wAd6L00VXjDV/tNsqLvaaNWurWzdWrpWuzzciJk1qouzZkitTPu2qyBLLHTlK9tnI51Horh6VFwUrzvdStut7N3bzKvW+4VemLSxh282ywTW632lzH1NS9OuRjtbqnIiJmvWoiZrtXiLQnhERNyZHkr1ausskrJHY0fgXhVNznmlN3btb9kAARHQOcrPZ5fik8hkmNWezy/FJ5DJNmQrj2gxYfZ6m+AvkUyjFh9nqb4C+RQHwOkABqTAAAAxrhSJX0NTSq7VSeN0aqnFrIqfzMkAw0mrMp7gu81mgzEN3pL9hmWrknYkMcrUyVUaq5KxyoqKxyLty27E7xJfB9w7c467EuJqy3utlFdpE52pFarUy13OVUauS6qayIi5bdpOyoi70PJaqYrPFq217zg4LQXg1SDdRuEG3FWStfm97KX6crRcarSdiGWC31ksTuZar46d7mr/Ys3KiZFvsPNVlhtjXIrXJTRIqKmSp1CGxyPJrVr6yEY23FnAaKWDxFaupX1jva27a39SFuExR1Fbgm2spqead6XFiq2KNz1ROZybckQ1/BhoaqismIG1VNPA51XGrUmjcxVTmfFmiE87xlkNf8A9LVWMPRSekFj821K1rey28KVTp7vV6FMZYsS8Ybfc4bs5zqapVOpe1XOciayoqKi62Tk35t3FrDwqIu9MzWlVyXTV0ybSGAeKcJ055Jwbs7X3qz2MrhwasG3SjudzxLWUclJRzU601O2RisWTWejlVqLt1U1UTPjz7hZAAxWqurPMzfRuAhgMOqEHe3Hm2QPpx0Mpfo58SYfp06KsTWqqVieukT8Zqflp/8Aknd3wvoqs1yg0jYZllt1bHGysarnvp3tREyXeqpsLwHjLv8AjJqeMlGDg1c5eK6OUK2KjioSytNNq2xtO/wvxIl4RkUk2jd7Y43vdz5AuTGqq714kOO4K9PNAuK+awyR63O2WuxW5/4vKWMBoq9qTpW3lupopT0hDH5+qrWt7Gt9/byOc0gNV+BMTtaiucttqURETNVXmbir3B4o6iHSXRukp5mNSln6p8bkTrU41QuIBTr5IShbeMbopYrFUsVntq+Ft+2/MAArnXKecIijqJtJVS6Onme1aSBNZkbnJuXjRCzujtrmYCwy1zVa5LdToqKmSp/ZodMCxUr56cYW3HIwWilhcXVxWe+fhbdtvzOdx3ZKjEmDr3aqR6NqqylfFGqrkiuVNiKvIu7wlU5sW1Ft0c1GjyqwnPHeFnXOd0S62fNNbW1cs1f+Kipsy8Rc48ZJnnltFGvq1Zq+2/xMaS0U8ZPWQqZHlcXsTvF9u7tIz0E4Sr8IYFZBc4XQVlZUPq3QO66JHI1rUXkXJqKqcWZJoBFObnJyfE6GFw0cNRjQhuirAAGhYAUBQDmWey9f3zMMNnsvX98zDZkEQAAbAAAAAAAxLn6yk8HlMsxLn6yk8HlCMS3M3tv9Y03xbfIZBj2/1jTfFt8hkGpLHcgAAZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANHiTrKT4w/R+cSdZSfGH6NuBD/cwa+7+t2fDT+ZsDX3f1uz4afzCMT6rOqTcgCbkBqTgAAAAAAAAAAAEfaQ9FseN66gulJd6uzXqhascdZTbVVirnqqiKi71XJUVN6ldMC3am0baX612IaqoWKlfU0stU+NznuVV2SOTauS5Z8e8uYcviXR1hfF8zZ7zZqaqqGpqpNtZJlyazVRVQtUcRli4T2o4GktDOtVjicLaNSLT23s+230RUnS3iOhxzpCkrbI6Wop5WQU8TljVqyuTZsau3aq5IXdYmTGp3Dk8PaMMI4Wqm1dqsdLBVN62Z2tI9vec5VVPAdaYxFaNRRjBbESaI0bWws6tbESTlUd3a9lv59oABWO2AAAchpKwLDpDwvNaH1C00zXtngm1dZGSNzyzTjRUVUXvlW9MluxjZqm0UGLL3Fc9SB7qXmKrkxqKjVVepbm5dm1c12by6ZxWNtFuH8f1dLU3iOpdLTRujj5jOsaZKua55b9paw2I1bSluOBpvQ/htOUqOybst7SaT4rjbgbHR77QsL/NlN5pp0hh2q2wWa10VupUclNRwsgjRztZdVqIiZrx7EMwryd5NnaoQcKcYPekkAAakoAAAAAAAAAAAAAABoL17KUPeXyntQ9V69lKHvL5T2obcCHiwYVV6/t/xieVDNMKq9f2/4xPKgRiW46cAGpOAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAc5Wezy/FJ5DJMas9nl+KTyGSbMhXHtBiw+z1N8BfIplGLD7PU3wF8igPgdIADUmAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUBQDmWey9f3zMMNnsvX98zDZkEQAAbAAAAAAAxLn6yk8HlMsxLn6yk8HlCMS3M3tv9Y03xbfIZBj2/1jTfFt8hkGpLHcgAAZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANHiTrKT4w/R+cSdZSfGH6NuBD/cwa+7+t2fDT+ZsDX3f1uz4afzCMT6rOqTcgCbkBqTgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGgvXspQ95fKe1D1Xr2Uoe8vlPahtwIeLBhVXr+3/ABieVDNMKq9f2/4xPKgRiW46cAGpOAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAc5Wezy/FJ5DJMas9nl+KTyGSbMhXHtBiw+z1N8BfIplGLD7PU3wF8igPgdIADUmAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUBQDmWey9f3zMMNnsvX98zDZkEQAAbAAAAAAAxLn6yk8HlMsxLn6yk8HlCMS3M3tv9Y03xbfIZBj2/1jTfFt8hkGpLHcgAAZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANHiTrKT4w/R+cSdZSfGH6NuBD/cwa+7+t2fDT+ZsDX3f1uz4afzCMT6rOqTcgCbkBqTgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGgvXspQ95fKe1D1Xr2Uoe8vlPahtwIeLBhVXr+3/GJ5UM0wqr1/b/jE8qBGJbjpwAak4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABzlZ7PL8UnkMkxqz2eX4pPIZJsyFce0GLD7PU3wF8imUYsPs9TfAXyKA+B0gANSYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQFAOZZ7L1/fMww2ey9f3zMNmQRAABsAAAAAADEufrKTweUyz1VMfNoJGJvcmzvgw9qNvb/WNN8W3yGQayw1CT29jfxouoVPIbM1ZJF3SAABsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAaPEnWUnxh+j03eTnm500Cboerd/78H8T3G3Ah/ubBr7v63Z8NP5mwMW4xLLSSIm9Oq8QRiSumdIm5AYltqUqqKGRN+rkvfTYplmpMndXAABkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0F69lKHvL5T2oY1VJz3enKnWU7dXPu/+1/gZJsQra2wYVV6/t/xieVDNMG5tVImSt3xPRwRiW46gHrgmbUQslZ1r0RyHsNScAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA5yt9nl+KTyGSYUUnPdyqqlOsz1G/wDvwGabMhjxYMWH2epvgL5FMowax/O1VS1WXUxuyd3v/eYRiXM6gHhFRyIqLmi8Z5NScAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQfmR6Rsc9y5Namar3ADm2+y9d3zMMG3qszqipVMubPVUM42ZBHcAADYAAAAAAAAAwtd9rq+eY2q6B+yRieU6GmqoqyJJIXo5q+NO+aveYT7fqP5pTSuhf/pXYN5hNx3HTg5xKm7R7OaRP7qog58u3LB4kMWNtZ7GdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGa65XWKharGrr1Cp1LE4u+at77nUJlJUtjau9GJtP1TUUdOusmbpF3vdvM2MObe48UdO6PXllVVnlXNyqZQACVtgG8AAw6eodZqhyqirRyrty/FU6OGaOeNJI3o5i7lQ07mo5qtciKi70Uw+cXwPV9JO6JeTPYN5hNx3bjpwc5z3dm7NeF3dVEHPl25YPEhixtrPYzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz7duWDxILDWLkzozU3S7NhRaemXXqnbOp26v8AyYEiXCqTKaqRjF3tjTI9lPSR0qdQnVLvcu9TNjDk3sWw8UdMlNFku17trl5VMgABK2wHh7Ue1WuTNqpkqHkAGLQVq2mVaedVWmcubH/knRse2RqOa5HNXaiouaKaSSNsrVa9qOavEpiMpJ6V2tSVLmJ+S7ag3mE3HZvR04Oc58uybNaFcuPJNo58u3LB4kMWNtYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPl25YPEgsNYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPl25YPEgsNYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPl25YPEgsNYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPl25YPEgsNYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPl25YPEgsNYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPl25YPEgsNYuTOjBznPl25YPEg58u3LB4kFhrFyZ0YOc58u3LB4kHPt25YPEgsNYuTOjNFdLpzfOjo11pHbHvTcice0xpIq2r2VNUup+SzYe+Cnjpmasbck4141M2sYcnLYtgp4G08TY28W9eVT2gAA9c0TZ43Ru3OPYAD1Wy5c5KlHVrqon+HIu7LkN+i5pmm40M0DJ2akjc08hjR09XSetapUZ+S/agtcwpOOzedODnOfbtyweJBz5duWDxIYsbaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLtyweJBYaxcmdGDnOfLtyweJBz5duWDxILDWLkzowc5z5duWDxIOfLsvHCngQWGsXJnROcjUVVVERN6qc9cbgtyfzpSqvMs/wC0k4lTuHqfTVNWv97qnOb+S3YhlRRMhYjGNRrUM7jVty2bkeY42xMaxqZNamSH6ABkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9k=';

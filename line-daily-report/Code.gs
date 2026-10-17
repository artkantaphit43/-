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
    // ไม่ตอบกลับทุกรูป เพื่อไม่ให้แชตรก (ส่งทีละหลายรูปได้)
    withSession_(event.source, session => addPhoto_(session, msg.id));
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
  if (CMD_ADD_PROJECT.test(text)) return reply_(token, ...addProjectFromText_(text));
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
    const section = s.section;
    const before = s[section].items.length;
    const group = s[section].group;
    applyText_(s, expandShortAnswer_(s, text));
    if (s.section === section) {
      added = s[section].items.length - before;
      if (s[section].group !== group) newGroup = s[section].group;
    }
    advance_(s);
  });

  if (!session.project.name && session.project.code && session.awaiting !== 'project') {
    return reply_(token, projectPicker_(`⚠️ ยังไม่มีข้อมูล ${session.project.code} ในระบบ กด "➕ เพิ่มโครงการ" ได้เลย 👇`));
  }
  const sec = session[session.section];
  if (added) {
    const it = sec.items[sec.items.length - 1];
    return reply_(token, withPrefix_(workPrompt_(session, sec, true),
      `📝 ${it.group ? it.group + ' • ' : ''}${it.title}${it.progress ? ' ' + it.progress : ''}`));
  }
  if (newGroup) return reply_(token, withPrefix_(workPrompt_(session, sec, true), `📁 ${newGroup}\nพิมพ์งานของโครงการนี้ได้เลย`));
  reply_(token, withPrefix_(question_(session, session.awaiting), '✅ บันทึกแล้ว'));
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
  { aliases: ['ปัญหา', 'ปัญหาอุปสรรค'], set: (s, v, sec) => { lastItem_(sec).problem = v; } },
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
    const blob = fileId && imageBlob_(fileId, 400);
    if (!blob) {
      sheet.getRange(signRow, col).setNumberFormat('@').setValue(name.split(' ')[0]);
      return;
    }
    // วางลายเซ็นให้ฐานอยู่บนเส้นประของช่อง ความสูงไม่เกิน 2 แถว
    const colW = sheet.getColumnWidth(col);
    const rowH = sheet.getRowHeight(signRow);
    const prevH = sheet.getRowHeight(signRow - 1);
    const img = sheet.insertImage(blob, col, signRow - 1);
    const scale = Math.min((colW - 10) / img.getWidth(), (rowH + prevH - 4) / img.getHeight());
    const w = Math.round(img.getWidth() * scale);
    const h = Math.round(img.getHeight() * scale);
    img.setWidth(w).setHeight(h)
      .setAnchorCellXOffset(Math.round((colW - w) / 2))
      .setAnchorCellYOffset(Math.max(0, prevH + rowH - h - 2));
  });
}

// ===== ภาพถ่ายหน้างาน =====

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
    const blob = imageBlob_(id, 1000);
    if (blob) images[id] = sheet.insertImage(blob, 1, firstRow);
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

/** รูปจาก Drive ขนาดย่อ (Google Sheets รับรูปไม่เกิน ~1 ล้านพิกเซล) ถ้าไม่มีภาพย่อใช้ไฟล์จริง */
function imageBlob_(fileId, size) {
  try {
    const res = UrlFetchApp.fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?fields=thumbnailLink`, {
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
      muteHttpExceptions: true,
    });
    const link = JSON.parse(res.getContentText()).thumbnailLink;
    if (link) return UrlFetchApp.fetch(link.replace(/=s\d+$/, '=s' + size)).getBlob();
  } catch (err) {
    console.warn('ย่อรูปไม่สำเร็จ ' + fileId + ': ' + err.message);
  }
  try {
    const blob = DriveApp.getFileById(fileId).getBlob();
    return blob.getBytes().length < 2e6 ? blob : null;
  } catch (err) {
    console.warn('เปิดรูปไม่ได้ ' + fileId + ': ' + err.message);
    return null;
  }
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

const TIME_PRESETS = ['08.00-17.00', '08.00-18.00', '08.00-19.00', '08.00-20.00', '08.00-21.00',
  '09.00-17.00', '09.00-18.00'];
const RAIN_PRESETS = ['08.00-10.00', '10.00-12.00', '13.00-15.00', '15.00-17.00', 'ทั้งวัน'];
const BRAND = '#0A9A9A';

const numbers_ = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);
const isPlan_ = s => s.section === 'plan';

/** ขั้นตอนการกรอก: done = กรอกแล้วหรือยัง, ask = คำถามพร้อมปุ่ม */
const STEPS = {
  reporter: { done: s => !!s.reporter, ask: () => reporterPicker_('👤 ใครเป็นผู้เขียนรายงาน?') },
  project: { done: s => !!s.project.code, ask: () => projectPicker_('📁 วันนี้ทำโครงการไหน?') },
  time: {
    done: s => !!(s.start || s.end),
    ask: () => quickReply_('⏰ เวลาทำงาน?\n(หรือพิมพ์เอง เช่น 8-21)',
      TIME_PRESETS.map(t => ({ label: t, text: 'เวลา: ' + t }))),
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
  notes: { done: () => true, ask: () => quickReply_('🗒️ พิมพ์หมายเหตุได้เลย', [{ label: 'ไม่มี', text: 'หมายเหตุ: -' }]) },
  work: { done: () => false, ask: (s, sec) => workPrompt_(s, sec, false) },
};

const FLOW = {
  today: ['reporter', 'project', 'time', 'manpower', 'weather', 'rain', 'temp', 'machines', 'impact', 'accident', 'work'],
  plan: ['manpower', 'machines', 'work'],
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
  if (step === 'time' && /^\d.*(-|ถึง)/.test(t)) return 'เวลา: ' + t;
  if (step === 'rain' && /^\d/.test(t)) return 'ฝนตกช่วง: ' + t;
  if (step === 'notes' && !/[:：]/.test(t)) return 'หมายเหตุ: ' + t;
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

/** ขั้นกรอกงาน: ปุ่มถ่ายรูป, เลือก PJ, ดูสรุป, แผนพรุ่งนี้, ส่ง */
function workPrompt_(s, sec, short) {
  const plan = isPlan_(s);
  let text;
  if (short) text = plan ? 'พิมพ์งานข้อถัดไปได้เลย' : 'ส่งรูปของงานนี้ หรือพิมพ์งานข้อถัดไป';
  else if (plan) text = '🗓️ พิมพ์งานพรุ่งนี้ทีละข้อ\nเช่น  1. ขุดดินวางท่อ';
  else text = '📝 พิมพ์งานทีละข้อ แล้วส่งรูปของงานนั้นตาม\nเช่น  1. ขุดดินวางท่อ 60%\n\nทำหลายโครงการ: กดปุ่ม PJ ก่อนพิมพ์งานของโครงการนั้น';

  const options = plan ? [] : [{ label: '📷 ถ่ายรูป', camera: true }, { label: '🖼️ เลือกรูป', cameraRoll: true }];
  const codes = [s.project.code].concat(Object.keys(getProjects_())).filter((c, i, a) => c && a.indexOf(c) === i);
  codes.slice(0, plan ? 5 : 3).forEach(code => options.push({ label: code, text: code }));
  options.push({ label: '📋 ดูสรุป', data: 'summary' });
  options.push(plan ? { label: '↩️ งานวันนี้', text: 'วันนี้' } : { label: '🗓️ แผนพรุ่งนี้', text: 'แผนพรุ่งนี้' });
  options.push({ label: '✅ ส่งรายงาน', text: 'ส่ง' });
  return quickReply_(text, options);
}

function editMenu_() {
  return quickReply_('✏️ ต้องการแก้ข้อไหน?', [
    { label: '👤 ผู้เขียนรายงาน', data: 'ask=reporter' },
    { label: '📁 โครงการ', data: 'ask=project' },
    { label: '⏰ เวลา', data: 'ask=time' },
    { label: '👷 คนงาน', data: 'ask=manpower' },
    { label: '🌤️ อากาศ', data: 'ask=weather' },
    { label: '🌡️ อุณหภูมิ', data: 'ask=temp' },
    { label: '🚗 เครื่องจักร', data: 'ask=machines' },
    { label: '⛈️ ผลกระทบ', data: 'ask=impact' },
    { label: '🦺 อุบัติเหตุ', data: 'ask=accident' },
    { label: '🗒️ หมายเหตุ', data: 'ask=notes' },
    { label: '🗓️ แผนพรุ่งนี้', text: 'แผนพรุ่งนี้' },
    { label: '🗑️ เริ่มใหม่', text: 'ยกเลิก' },
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
        text: `${i + 1}. ${it.title}${withProgress && it.progress ? '  ' + it.progress : ''}`,
      }));
    });
    return lines.length ? lines : [{ type: 'text', text: 'ยังไม่มี', size: 'sm', color: '#8C8C8C' }];
  };
  const time = `${s.start || CONFIG.DEFAULT_START} - ${s.end || CONFIG.DEFAULT_END}`;
  const weather = [s.weather, s.rainTime && `ฝน ${s.rainTime}`, s.temp && `${s.temp}°C`].filter(Boolean).join(' • ');

  const body = [
    row('ผู้รายงาน', s.reporter),
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
  if (o.data) return { type: 'postback', label: label, data: o.data };
  return { type: 'message', label: label, text: o.text };
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

// ===== รันครั้งแรกจากหน้า Editor เพื่อขอสิทธิ์และสร้างโฟลเดอร์/ชีต/แม่แบบ =====

function setup() {
  token_();
  const folder = getRootFolder_();
  const sheet = getSheet_();
  UrlFetchApp.fetch('https://api.line.me/v2/bot/info', {
    headers: { Authorization: 'Bearer ' + token_() },
  });
  const templateId = getTemplateId_();
  console.log('โฟลเดอร์: ' + folder.getUrl());
  console.log('ชีตบันทึก: ' + sheet.getParent().getUrl());
  console.log('แม่แบบฟอร์ม: https://docs.google.com/spreadsheets/d/' + templateId);
  console.log('พร้อมใช้งาน ✅ ต่อไปให้ Deploy เป็น Web app');
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

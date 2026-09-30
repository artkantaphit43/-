'use strict';

// แปลงข้อความที่พิมพ์ในไลน์ให้เป็นคำสั่ง หรือรายการ punch

const COMMANDS = [
  { type: 'help', re: /^(help|วิธีใช้|ช่วยด้วย|\?)$/i },
  { type: 'list', re: /^(list|รายการ|ค้าง|งานค้าง)$/i },
  { type: 'listAll', re: /^(list all|ทั้งหมด|รายการทั้งหมด)$/i },
  { type: 'report', re: /^(report|รายงาน|สรุป|pdf)$/i },
  { type: 'cancel', re: /^(ยกเลิก|cancel)$/i },
  { type: 'done', re: /^(ปิด|เสร็จ|done|close)\s*#?(\d+)\s*(.*)$/is },
  { type: 'reopen', re: /^(เปิด|เปิดใหม่|reopen)\s*#?(\d+)\s*(.*)$/is },
  { type: 'delete', re: /^(ลบ|delete)\s*#?(\d+)$/i },
  { type: 'note', re: /^#(\d+)\s+(.+)$/s },
  { type: 'setTitle', re: /^(ตั้งชื่อ|ชื่อโครงการ|project)\s+(.+)$/is },
];

const HIGH_PRIORITY = /(^|\s)(ด่วน(มาก)?|urgent|!!)(?=\s|$)/i;
const ITEM_PREFIX = /^(\+|punch\b|แจ้ง\b)\s*/i;

function parseCommand(text) {
  const t = (text || '').trim();
  for (const { type, re } of COMMANDS) {
    const m = t.match(re);
    if (!m) continue;
    switch (type) {
      case 'done':
      case 'reopen':
        return { type, no: Number(m[2]), note: m[3].trim() };
      case 'delete':
        return { type, no: Number(m[2]) };
      case 'note':
        return { type, no: Number(m[1]), note: m[2].trim() };
      case 'setTitle':
        return { type, title: m[2].trim() };
      default:
        return { type };
    }
  }
  return null;
}

// ข้อความขึ้นต้นด้วย "+" / "แจ้ง" / "punch" = ตั้งใจสร้างรายการแม้ไม่มีรูป
function hasItemPrefix(text) {
  return ITEM_PREFIX.test((text || '').trim());
}

/**
 * รูปแบบที่รองรับ (ทุกส่วนไม่บังคับ ยกเว้นรายละเอียด):
 *   ตำแหน่ง / รายละเอียด @ผู้รับผิดชอบ ด่วน
 * ตัวอย่าง:
 *   ชั้น 3 ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน
 *   ห้องน้ำ 2 | ยาแนวหลุด
 *   ประตูหน้าปิดไม่สนิท
 */
function parseItem(text) {
  let t = (text || '').trim().replace(ITEM_PREFIX, '');

  let priority = 'normal';
  if (HIGH_PRIORITY.test(t)) {
    priority = 'high';
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

  const clean = (s) =>
    s
      .split('\n')
      .map((l) => l.replace(/[ \t]+/g, ' ').trim())
      .filter(Boolean)
      .join('\n');

  return {
    location: clean(location),
    description: clean(t),
    assignee: assignees.join(', '),
    priority,
  };
}

module.exports = { parseCommand, parseItem, hasItemPrefix };

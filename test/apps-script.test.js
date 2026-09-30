'use strict';

// ทดสอบ apps-script/Code.gs ด้วย mock ของ Google Apps Script (SpreadsheetApp, DriveApp, ...)

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const CODE = fs.readFileSync(path.join(__dirname, '..', 'apps-script', 'Code.gs'), 'utf8');

// คืน object ที่เรียก method อะไรก็ได้ แล้วคืนตัวเอง (ใช้กับคำสั่งจัดรูปแบบ)
function chain() {
  const p = new Proxy(function () {}, { get: () => () => p, apply: () => p });
  return p;
}

function makeEnv() {
  let idSeq = 0;
  const newId = (pfx) => `${pfx}${++idSeq}`;
  const files = {};
  const sent = [];
  const props = {};

  function makeSheet() {
    const grid = [];
    const cell = (r, c) => (grid[r - 1] || [])[c - 1] ?? '';
    const put = (r, c, v) => {
      while (grid.length < r) grid.push([]);
      grid[r - 1][c - 1] = v;
    };
    const sheet = {
      grid,
      rich: {},
      getSheetId: () => 0,
      setName: () => sheet,
      getLastRow: () => {
        for (let r = grid.length; r > 0; r--) if ((grid[r - 1] || []).some((v) => v !== '' && v != null)) return r;
        return 0;
      },
      appendRow: (row) => row.forEach((v, i) => put(sheet.getLastRow() + (i === 0 ? 1 : 0), i + 1, v)),
      deleteRow: (r) => grid.splice(r - 1, 1),
      getRange: (r, c, nr = 1, nc = 1) => {
        if (typeof r === 'string') return chain();
        const range = {
          setValue: (v) => (put(r, c, v), range),
          setFormula: (v) => (put(r, c, v), range),
          setValues: (vals) => (vals.forEach((row, i) => row.forEach((v, j) => put(r + i, c + j, v))), range),
          getValues: () => Array.from({ length: nr }, (_, i) => Array.from({ length: nc }, (_, j) => cell(r + i, c + j))),
          setRichTextValue: (rt) => ((sheet.rich[`${r},${c}`] = rt), put(r, c, rt.text), range),
          setNumberFormat: () => range,
          setFontSize: () => range,
          setFontWeight: () => range,
          setBackground: () => range,
          setVerticalAlignment: () => range,
          setHorizontalAlignment: () => range,
        };
        return range;
      },
    };
    for (const m of ['setFrozenRows', 'setColumnWidth', 'hideColumns', 'setRowHeight', 'setConditionalFormatRules']) {
      sheet[m] = () => sheet;
    }
    return sheet;
  }

  function makeSpreadsheet(name) {
    const id = newId('ss');
    const ss = { id, name, sheets: [makeSheet()] };
    Object.assign(ss, {
      getId: () => id,
      getUrl: () => `https://docs.google.com/spreadsheets/d/${id}`,
      getSheets: () => ss.sheets,
      setSpreadsheetTimeZone: () => {},
      rename: (n) => (ss.name = n),
    });
    files[id] = ss;
    return ss;
  }

  function makeFile(name, extra = {}) {
    const id = newId('f');
    const f = {
      id, name, trashed: false, sharing: null, ...extra,
      getId: () => id,
      getUrl: () => `https://drive.google.com/file/d/${id}/view`,
      setSharing: (a) => (f.sharing = a),
      setTrashed: (t) => (f.trashed = t),
      moveTo: (folder) => (f.parent = folder.id),
      setName: (n) => (f.name = n),
    };
    files[id] = f;
    return f;
  }

  function makeFolder(name) {
    const folder = makeFile(name, { children: [] });
    folder.createFolder = (n) => {
      const c = makeFolder(n);
      c.parent = folder.id;
      return c;
    };
    folder.createFile = (blob) => {
      const f = makeFile(blob.name, { blob });
      f.parent = folder.id;
      return f;
    };
    return folder;
  }

  const index = makeSpreadsheet('Index');

  const blob = (name) => ({ name, setName(n) { this.name = n; return this; } });

  const ctx = {
    console: { log() {}, error() {} },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: (k) => props[k] ?? null,
        setProperty: (k, v) => (props[k] = String(v)),
        deleteProperty: (k) => delete props[k],
        getProperties: () => ({ ...props }),
      }),
    },
    LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
    Utilities: {
      getUuid: () => '1234-5678-abcd',
      formatDate: (d) => new Date(d).toISOString().slice(0, 16),
    },
    ContentService: { createTextOutput: (s) => ({ s }) },
    HtmlService: { createHtmlOutput: (h) => ({ h, setTitle() { return this; } }) },
    ScriptApp: {
      triggers: [],
      getService: () => ({ getUrl: () => 'https://script.google.com/macros/s/X/exec' }),
      getProjectTriggers: () => ctx.ScriptApp.triggers,
      newTrigger: (fn) => {
        ctx.ScriptApp.triggers.push({ getHandlerFunction: () => fn });
        return chain();
      },
      WeekDay: { MONDAY: 'MONDAY' },
      getOAuthToken: () => 'oauth',
    },
    DriveApp: {
      Access: { ANYONE_WITH_LINK: 'ANYONE_WITH_LINK' },
      Permission: { VIEW: 'VIEW' },
      createFolder: (n) => makeFolder(n),
      getFolderById: (id) => files[id],
      getFileById: (id) => {
        if (files[id] && files[id].sheets) {
          const ss = files[id];
          return { moveTo: (f) => (ss.parent = f.id), setSharing: (a) => (ss.sharing = a) };
        }
        return files[id];
      },
    },
    SpreadsheetApp: {
      getActiveSpreadsheet: () => index,
      flush: () => {},
      create: (n) => makeSpreadsheet(n),
      openById: (id) => files[id],
      newConditionalFormatRule: () => chain(),
      newRichTextValue: () => {
        const rt = { links: [] };
        const b = {
          setText: (t) => ((rt.text = t), b),
          setLinkUrl: (s, e, u) => (rt.links.push([rt.text.slice(s, e), u]), b),
          build: () => rt,
        };
        return b;
      },
    },
    UrlFetchApp: {
      fetch: (url, opts = {}) => {
        const res = (code, body, b) => ({
          getResponseCode: () => code,
          getContentText: () => (typeof body === 'string' ? body : JSON.stringify(body)),
          getBlob: () => b,
        });
        if (/\/message\/(reply|push)$/.test(url)) {
          sent.push({ kind: RegExp.$1, ...JSON.parse(opts.payload) });
          return res(200, {});
        }
        if (/\/content$/.test(url)) return res(200, '', blob('img.jpg'));
        if (/\/summary$/.test(url)) return res(200, { groupName: 'คอนโด ABC' });
        if (/\/member\/|\/profile\//.test(url)) return res(200, { displayName: 'สมชาย' });
        if (/export\?format=pdf/.test(url)) {
          // เก็บหัวกระดาษ ณ ตอน export ไว้ตรวจ
          const ss = files[url.match(/\/d\/([^/]+)\//)[1]];
          ctx.exportedHeader = ss.sheets[0].grid[0].slice();
          return res(200, '', blob('r.pdf'));
        }
        return res(404, 'not found');
      },
    },
  };
  vm.createContext(ctx);
  const api = vm.runInContext(
    CODE + '\n;({ doGet, doPost, weeklyReport, parseItem, parseCommand, readItems, projectSheet })',
    ctx
  );
  return { api, ctx, props, files, sent, index };
}

function walkNoEmptyText(node) {
  if (Array.isArray(node)) return node.forEach(walkNoEmptyText);
  if (node && typeof node === 'object') {
    if (node.type === 'text') assert.ok(node.text && String(node.text).length, 'Flex text ห้ามว่าง');
    Object.values(node).forEach(walkNoEmptyText);
  }
}

test('Apps Script: ตั้งค่า → รูป → ข้อความ → ปิดงาน → PDF', () => {
  const { api, ctx, props, files, sent, index } = makeEnv();

  // เปิด URL web app ครั้งแรก → ได้ webhook URL พร้อม key
  const page = api.doGet();
  assert.match(page.h, /\?key=12345678abcd/);

  const post = (events, key = props.KEY) =>
    api.doPost({ parameter: { key }, postData: { contents: JSON.stringify({ events }) } });
  const source = { type: 'group', groupId: 'G1', userId: 'U1' };
  const img = (id, imageSet) => ({ type: 'message', replyToken: 'r', source, message: { type: 'image', id, imageSet } });
  const txt = (t) => ({ type: 'message', replyToken: 'r', source, message: { type: 'text', text: t } });

  assert.strictEqual(post([txt('+ x')], 'wrong').s, 'forbidden');
  assert.strictEqual(sent.length, 0);

  post([]); // LINE กด Verify
  assert.match(api.doGet().h, /เชื่อมกับ LINE แล้ว/);

  post([txt('คุยกันทั่วไป')]);
  assert.strictEqual(sent.length, 0, 'ข้อความทั่วไปไม่ควรตอบ');

  post([img('m1', { id: 's', index: 1, total: 2 }), img('m2', { id: 's', index: 2, total: 2 })]);
  assert.strictEqual(sent.length, 1, 'ตอบแค่รูปแรก');

  post([txt('ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน')]);
  const project = JSON.parse(props['chat:G1']);
  assert.strictEqual(project.title, 'คอนโด ABC', 'ตั้งชื่อตามชื่อกลุ่มไลน์');
  const sh = api.projectSheet(project);
  let items = api.readItems(sh);
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].no, 1);
  assert.strictEqual(items[0].location, 'ห้อง 301');
  assert.strictEqual(items[0].priority, 'ด่วน');
  assert.strictEqual(items[0].reporter, 'สมชาย');
  assert.strictEqual(items[0].photoIds.length, 2);
  assert.match(sh.grid[2][1], /^=IMAGE\("https:\/\/drive\.google\.com\/thumbnail\?id=f\d+/);
  assert.deepStrictEqual(sh.rich['3,12'].links.map((l) => l[0]), ['รูป 1', 'รูป 2']);
  const card = sent.at(-1).messages[0];
  assert.strictEqual(card.type, 'flex');
  walkNoEmptyText(card);

  post([txt('+ ห้องน้ำ 2 / ยาแนวหลุด')]);
  post([txt('#2 ลูกค้าขอเปลี่ยนสียาแนวเป็นสีเทา')]);
  post([img('m3'), txt('เสร็จ 1 ทาใหม่แล้ว')]);
  items = api.readItems(sh);
  assert.strictEqual(items[0].status, 'เสร็จแล้ว');
  assert.strictEqual(items[0].photoIds.length, 3, 'รูปหลังแก้ถูกแนบ');
  assert.match(items[0].notes, /สมชาย: ปิดงาน — ทาใหม่แล้ว/);
  assert.match(items[1].notes, /ลูกค้าขอเปลี่ยนสียาแนว/);

  post([txt('รายการ')]);
  const list = sent.at(-1).messages[0];
  assert.match(list.altText, /ค้าง 1/);
  walkNoEmptyText(list);

  // ภาพรวม: 1 แถวต่อโครงการ
  const idx = index.sheets[0].grid;
  assert.strictEqual(idx.length, 2);
  assert.deepStrictEqual(idx[1].slice(0, 4), ['คอนโด ABC', 1, 1, 2]);

  post([txt('รายงาน')]);
  assert.match(sent.at(-1).messages[0].text, /📄 PDF คอนโด ABC/);
  const pdfs = Object.values(files).filter((f) => f.parent === project.pdfFolderId);
  assert.strictEqual(pdfs.length, 1);
  assert.ok(ctx.exportedHeader.some((v) => /^สถานะ ณ วันที่ .+ น\.$/.test(v)), 'PDF มีวันที่บนหน้า');
  assert.ok(!sh.grid[0].some((v) => /สถานะ ณ/.test(v)), 'ลบวันที่ออกจาก Sheet หลัง export');

  post([txt('ตั้งชื่อ คอนโด ABC เฟส 2')]);
  assert.strictEqual(files[project.sheetId].name, 'Punch List - คอนโด ABC เฟส 2');
  assert.strictEqual(index.sheets[0].grid.length, 2, 'ไม่สร้างแถวภาพรวมซ้ำ');

  post([txt('ลบ 2'), txt('+ ประตูหน้าปิดไม่สนิท')]);
  items = api.readItems(sh);
  assert.deepStrictEqual(items.map((i) => i.no), [1, 3], 'เลขที่ไม่ซ้ำหลังลบ');

  // สรุปรายสัปดาห์: push เข้ากลุ่ม + PDF ใหม่
  api.weeklyReport();
  const pushed = sent.filter((m) => m.kind === 'push');
  assert.strictEqual(pushed.length, 1);
  assert.strictEqual(pushed[0].to, 'G1');
  assert.match(pushed[0].messages[0].text, /ค้าง 1 · เสร็จ 1/);
});

test('Apps Script: แต่ละกลุ่มได้ไฟล์ Sheet แยกกัน', () => {
  const { api, props } = makeEnv();
  api.doGet();
  const post = (groupId, t) =>
    api.doPost({
      parameter: { key: props.KEY },
      postData: { contents: JSON.stringify({ events: [{ type: 'message', replyToken: 'r', source: { type: 'group', groupId, userId: 'U' }, message: { type: 'text', text: t } }] }) },
    });
  post('G1', '+ งาน A');
  post('G2', '+ งาน B');
  const a = JSON.parse(props['chat:G1']);
  const b = JSON.parse(props['chat:G2']);
  assert.notStrictEqual(a.sheetId, b.sheetId);
  assert.strictEqual(api.readItems(api.projectSheet(b))[0].description, 'งาน B');
});

test('Apps Script parser ตรงกับเวอร์ชัน Node', () => {
  const { api } = makeEnv();
  const node = require('../src/parser');
  for (const t of ['ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน', 'ท่อ 1/2 นิ้ว รั่ว', '+ ห้องน้ำ 2|ยาแนวหลุด']) {
    const a = api.parseItem(t);
    const b = node.parseItem(t);
    assert.deepStrictEqual({ ...a, priority: a.priority === 'ด่วน' }, { ...b, priority: b.priority === 'high' });
  }
  assert.deepStrictEqual({ ...api.parseCommand('เสร็จ 3 ok') }, { type: 'done', no: 3, note: 'ok' });
});

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { parseCommand, parseItem } = require('../src/parser');
const { Store } = require('../src/store');
const { createHandler } = require('../src/handlers');
const { renderReport, renderCsv } = require('../src/report');
const { verifySignature } = require('../src/line');

test('parseItem: ตำแหน่ง / รายละเอียด @คน ด่วน', () => {
  assert.deepStrictEqual(parseItem('ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน'), {
    location: 'ห้อง 301',
    description: 'สีผนังไม่เรียบ',
    assignee: 'ทีมสี',
    priority: 'high',
  });
});

test('parseItem: ไม่ตัด 1/2 และรองรับ | และ +', () => {
  assert.strictEqual(parseItem('ท่อ 1/2 นิ้ว รั่ว').description, 'ท่อ 1/2 นิ้ว รั่ว');
  assert.deepStrictEqual(parseItem('+ ห้องน้ำ 2|ยาแนวหลุด'), {
    location: 'ห้องน้ำ 2',
    description: 'ยาแนวหลุด',
    assignee: '',
    priority: 'normal',
  });
});

test('parseCommand', () => {
  assert.deepStrictEqual(parseCommand('เสร็จ 3'), { type: 'done', no: 3, note: '' });
  assert.deepStrictEqual(parseCommand('ปิด #12 ทาสีใหม่แล้ว'), { type: 'done', no: 12, note: 'ทาสีใหม่แล้ว' });
  assert.deepStrictEqual(parseCommand('#4 รอของ'), { type: 'note', no: 4, note: 'รอของ' });
  assert.deepStrictEqual(parseCommand('ตั้งชื่อ คอนโด ABC'), { type: 'setTitle', title: 'คอนโด ABC' });
  assert.strictEqual(parseCommand('รายการ').type, 'list');
  assert.strictEqual(parseCommand('ห้อง 301 / ผนังร้าว'), null);
});

test('verifySignature', () => {
  const body = Buffer.from('{"events":[]}');
  const sig = crypto.createHmac('sha256', 's3cret').update(body).digest('base64');
  assert.ok(verifySignature(body, sig, 's3cret'));
  assert.ok(!verifySignature(body, sig, 'wrong'));
  assert.ok(!verifySignature(body, undefined, 's3cret'));
});

function setup() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'punch-'));
  const store = new Store(dir);
  const replies = [];
  const line = {
    reply: async (_t, msgs) => replies.push(msgs),
    getContent: async () => ({ buffer: Buffer.from('img'), contentType: 'image/jpeg' }),
    displayName: async () => 'สมชาย',
  };
  const { handleEvent } = createHandler({ store, line, baseUrl: 'https://bot.example.com' });
  const source = { type: 'group', groupId: 'G1', userId: 'U1' };
  const img = (id) => ({ type: 'message', replyToken: 'r', source, message: { type: 'image', id } });
  const txt = (t) => ({ type: 'message', replyToken: 'r', source, message: { type: 'text', text: t } });
  return { store, replies, handleEvent, img, txt, dir };
}

test('flow: รูป → ข้อความ → ปิดงาน → รายงาน', async () => {
  const { store, replies, handleEvent, img, txt } = setup();

  await handleEvent(txt('คุยกันทั่วไป'));
  assert.strictEqual(replies.length, 0, 'ข้อความทั่วไปไม่ควรสร้างรายการ');

  await handleEvent(img('m1'));
  await handleEvent(img('m2'));
  assert.strictEqual(replies.length, 1, 'ตอบแค่รูปแรก');

  await handleEvent(txt('ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน'));
  const chat = store.chat('G1');
  assert.strictEqual(chat.items.length, 1);
  const item = chat.items[0];
  assert.deepStrictEqual(item.photos, ['m1.jpg', 'm2.jpg']);
  assert.strictEqual(item.reporter, 'สมชาย');
  const flex = replies.at(-1)[0];
  assert.strictEqual(flex.type, 'flex');
  assert.match(flex.contents.hero.url, /^https:\/\/bot\.example\.com\/r\/[a-f0-9]{32}\/img\/m1\.jpg$/);

  await handleEvent(txt('+ ห้องน้ำ 2 / ยาแนวหลุด'));
  assert.strictEqual(chat.items.length, 2);
  assert.deepStrictEqual(chat.items[1].photos, []);

  await handleEvent(img('m3'));
  await handleEvent(txt('เสร็จ 1 ทาใหม่แล้ว'));
  assert.strictEqual(chat.items[0].status, 'done');
  assert.deepStrictEqual(chat.items[0].photos, ['m1.jpg', 'm2.jpg', 'm3.jpg']);

  await handleEvent(txt('รายการ'));
  assert.match(replies.at(-1)[0].altText, /ค้าง 1/);

  const html = renderReport(chat, { imgBase: '/img' });
  assert.match(html, /สีผนังไม่เรียบ/);
  assert.match(html, /ห้อง 301/);
  assert.match(html, /ปิดงาน: ทาใหม่แล้ว/);
  const csv = renderCsv(chat, { status: 'open', imgBase: '/img' });
  assert.strictEqual(csv.split('\r\n').length, 2);

  await handleEvent(txt('ลบ 2'));
  assert.strictEqual(chat.items.length, 1);

  // ข้อมูลยังอยู่หลังโหลดใหม่
  const reloaded = new Store(store.dataDir);
  assert.strictEqual(reloaded.chat('G1').items[0].description, 'สีผนังไม่เรียบ');
});

test('report escapes HTML', () => {
  const html = renderReport(
    { title: '<b>x</b>', items: [{ no: 1, location: '', description: '<script>', assignee: '', priority: 'normal', status: 'open', photos: [], reporter: '', createdAt: new Date().toISOString(), notes: [] }] },
    { imgBase: '/img' }
  );
  assert.ok(!html.includes('<script>'));
  assert.ok(html.includes('&lt;script&gt;'));
});

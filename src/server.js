'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { Store } = require('./store');
const { LineClient, verifySignature } = require('./line');
const { createHandler } = require('./handlers');
const { renderReport, renderCsv } = require('./report');

// โหลด .env แบบง่าย (ไม่ต้องติดตั้ง dotenv)
const envFile = path.join(__dirname, '..', '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2];
  }
}

const {
  LINE_CHANNEL_SECRET,
  LINE_CHANNEL_ACCESS_TOKEN,
  PORT = 3000,
  DATA_DIR = path.join(__dirname, '..', 'data'),
} = process.env;
const BASE_URL = (process.env.BASE_URL || '').replace(/\/+$/, '');

if (!LINE_CHANNEL_SECRET || !LINE_CHANNEL_ACCESS_TOKEN) {
  console.error('ต้องตั้งค่า LINE_CHANNEL_SECRET และ LINE_CHANNEL_ACCESS_TOKEN (ดู .env.example)');
  process.exit(1);
}

const store = new Store(DATA_DIR);
const line = new LineClient(LINE_CHANNEL_ACCESS_TOKEN);
const { handleEvent } = createHandler({ store, line, baseUrl: BASE_URL });

const MIME = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

function send(res, status, body, type = 'text/plain; charset=utf-8', extra = {}) {
  res.writeHead(status, { 'Content-Type': type, ...extra });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// ประมวลผลทีละ event ต่อแชท เพื่อให้ "รูป → ข้อความ" เรียงลำดับถูก
const queues = new Map();
function enqueue(key, fn) {
  const prev = queues.get(key) || Promise.resolve();
  const next = prev.then(fn, fn);
  queues.set(key, next.catch(() => {}));
  return next;
}

async function onWebhook(req, res) {
  const raw = await readBody(req);
  if (!verifySignature(raw, req.headers['x-line-signature'], LINE_CHANNEL_SECRET)) {
    return send(res, 401, 'bad signature');
  }
  send(res, 200, 'ok'); // ตอบไลน์ทันที แล้วค่อยประมวลผล
  const { events = [] } = JSON.parse(raw.toString('utf8'));
  for (const ev of events) {
    const key = ev.source?.groupId || ev.source?.roomId || ev.source?.userId || 'x';
    enqueue(key, () => handleEvent(ev)).catch((err) => console.error('event error:', err));
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');

    if (req.method === 'POST' && url.pathname === '/webhook') return await onWebhook(req, res);
    if (url.pathname === '/') return send(res, 200, 'Punch List bot is running');

    // /r/:token/  /r/:token/csv  /r/:token/img/:file
    const m = url.pathname.match(/^\/r\/([a-f0-9]{32})\/(csv|img\/([\w.-]+))?$/);
    if (req.method === 'GET' && m) {
      const found = store.chatByToken(m[1]);
      if (!found) return send(res, 404, 'not found');
      const imgBase = `${BASE_URL}/r/${m[1]}/img`;
      const status = url.searchParams.get('status') || 'all';

      if (!m[2]) return send(res, 200, renderReport(found.chat, { status, imgBase }), 'text/html; charset=utf-8');
      if (m[2] === 'csv') {
        const name = `punch-list-${new Date().toISOString().slice(0, 10)}.csv`;
        return send(res, 200, renderCsv(found.chat, { status, imgBase }), 'text/csv; charset=utf-8', {
          'Content-Disposition': `attachment; filename="${name}"`,
        });
      }
      // รูป: ต้องเป็นรูปของแชทนี้เท่านั้น
      const file = m[3];
      const owns =
        found.chat.items.some((i) => i.photos.includes(file)) ||
        Object.values(found.chat.pending).some((p) => p.photos.includes(file));
      const p = store.imagePath(file);
      if (!owns || !fs.existsSync(p)) return send(res, 404, 'not found');
      return send(res, 200, fs.readFileSync(p), MIME[path.extname(file).slice(1)] || 'application/octet-stream', {
        'Cache-Control': 'private, max-age=86400',
      });
    }

    send(res, 404, 'not found');
  } catch (err) {
    console.error(err);
    if (!res.headersSent) send(res, 500, 'error');
  }
});

server.listen(PORT, () => {
  console.log(`Punch List bot listening on :${PORT}`);
  if (!BASE_URL) console.warn('⚠ ยังไม่ได้ตั้ง BASE_URL: จะไม่มีลิงก์รายงานและรูปใน Flex message');
});

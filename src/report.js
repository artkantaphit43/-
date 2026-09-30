'use strict';

// หน้ารายงาน punch list (HTML พร้อมพิมพ์ / Save as PDF ขนาด A4) และ CSV

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const fmtDate = (iso) =>
  iso
    ? new Date(iso).toLocaleString('th-TH', {
        timeZone: 'Asia/Bangkok',
        day: 'numeric',
        month: 'short',
        year: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

function filterItems(items, status) {
  return status === 'open' || status === 'done' ? items.filter((i) => i.status === status) : items;
}

function renderReport(chat, { status = 'all', imgBase }) {
  const items = filterItems(chat.items, status);
  const totals = {
    all: chat.items.length,
    open: chat.items.filter((i) => i.status === 'open').length,
    done: chat.items.filter((i) => i.status === 'done').length,
  };
  const title = chat.title || 'Punch List';
  const printedAt = fmtDate(new Date().toISOString());

  // จัดกลุ่มตามตำแหน่ง เรียงตามเลขรายการ
  const groups = new Map();
  for (const i of items) {
    const key = i.location || 'ไม่ระบุตำแหน่ง';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(i);
  }

  const rowHtml = (i) => `
      <tr class="${i.status}">
        <td class="no">${i.no}</td>
        <td class="photos">${
          i.photos.length
            ? i.photos.map((p) => `<a href="${imgBase}/${esc(p)}" target="_blank"><img src="${imgBase}/${esc(p)}" loading="lazy" alt=""></a>`).join('')
            : '<span class="muted">—</span>'
        }</td>
        <td class="desc">
          <div>${esc(i.description).replace(/\n/g, '<br>')}</div>
          ${i.notes.map((n) => `<div class="note">• ${esc(n.text)} <span class="muted">(${esc(n.by)} ${fmtDate(n.at)})</span></div>`).join('')}
        </td>
        <td>${esc(i.assignee) || '<span class="muted">—</span>'}</td>
        <td>${i.priority === 'high' ? '<span class="tag high">ด่วน</span>' : 'ปกติ'}</td>
        <td><span class="tag ${i.status}">${i.status === 'done' ? 'เสร็จแล้ว' : 'ค้าง'}</span>${
          i.closedAt ? `<div class="muted small">${fmtDate(i.closedAt)}</div>` : ''
        }</td>
        <td class="small">${esc(i.reporter)}<div class="muted">${fmtDate(i.createdAt)}</div></td>
      </tr>`;

  const sections = [...groups.entries()]
    .map(
      ([loc, list]) => `
    <tbody>
      <tr class="group"><th colspan="7">${esc(loc)} <span class="muted">(${list.length})</span></th></tr>
      ${list.map(rowHtml).join('')}
    </tbody>`
    )
    .join('');

  const tab = (s, label) => `<a class="${status === s ? 'active' : ''}" href="?status=${s}">${label}</a>`;

  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@400;600;700&display=swap" rel="stylesheet">
<style>
  :root { --text:#1f2328; --muted:#6b7280; --line:#d8dce2; --open:#c2410c; --done:#15803d; --high:#b91c1c; --bg:#fff; }
  * { box-sizing: border-box; }
  body { margin:0; background:#f3f4f6; color:var(--text); font:14px/1.5 'Sarabun', system-ui, sans-serif; }
  .page { max-width:1100px; margin:0 auto; padding:16px; background:var(--bg); min-height:100vh; }
  header { display:flex; flex-wrap:wrap; justify-content:space-between; gap:12px; align-items:flex-end; border-bottom:2px solid var(--text); padding-bottom:12px; }
  h1 { margin:0; font-size:22px; }
  .meta { color:var(--muted); font-size:13px; }
  .stats { display:flex; gap:8px; }
  .stat { border:1px solid var(--line); border-radius:8px; padding:6px 12px; text-align:center; min-width:72px; }
  .stat b { display:block; font-size:20px; }
  .stat.open b { color:var(--open); } .stat.done b { color:var(--done); }
  .toolbar { display:flex; flex-wrap:wrap; gap:8px; margin:12px 0; align-items:center; }
  .toolbar a, .toolbar button { font:inherit; font-size:13px; padding:6px 12px; border-radius:999px; border:1px solid var(--line); background:#fff; color:var(--text); text-decoration:none; cursor:pointer; }
  .toolbar a.active { background:var(--text); color:#fff; border-color:var(--text); }
  .toolbar .spacer { flex:1; }
  .table-wrap { overflow-x:auto; }
  table { width:100%; border-collapse:collapse; min-width:760px; }
  th, td { border:1px solid var(--line); padding:6px 8px; vertical-align:top; text-align:left; }
  thead th { background:#f9fafb; font-size:12px; white-space:nowrap; }
  tr.group th { background:#eef2f7; font-size:14px; }
  td.no { width:40px; text-align:center; font-weight:700; }
  td.photos { width:210px; }
  td.photos img { width:88px; height:66px; object-fit:cover; border-radius:4px; margin:0 4px 4px 0; border:1px solid var(--line); }
  td.desc { min-width:220px; }
  tr.done td.desc > div:first-child { text-decoration:line-through; color:var(--muted); }
  .note { font-size:12px; margin-top:4px; }
  .tag { display:inline-block; font-size:12px; font-weight:600; padding:1px 8px; border-radius:999px; white-space:nowrap; }
  .tag.open { background:#fff1e6; color:var(--open); } .tag.done { background:#e7f7ee; color:var(--done); } .tag.high { background:#fde8e8; color:var(--high); }
  .muted { color:var(--muted); } .small { font-size:12px; }
  .empty { padding:40px; text-align:center; color:var(--muted); }
  .sign { display:grid; grid-template-columns:repeat(auto-fit, minmax(220px, 1fr)); gap:24px; margin-top:40px; }
  .sign div { text-align:center; padding-top:40px; border-top:0; }
  .sign span { display:block; border-top:1px dotted var(--text); padding-top:4px; }
  @media print {
    @page { size:A4 landscape; margin:10mm; }
    body { background:#fff; }
    .page { padding:0; max-width:none; }
    .toolbar { display:none; }
    table { min-width:0; font-size:12px; }
    tr { break-inside:avoid; }
    td.photos img { width:80px; height:60px; }
  }
</style>
</head>
<body>
<div class="page">
  <header>
    <div>
      <h1>${esc(title)}</h1>
      <div class="meta">รายงาน Punch List · พิมพ์เมื่อ ${esc(printedAt)}</div>
    </div>
    <div class="stats">
      <div class="stat"><b>${totals.all}</b>ทั้งหมด</div>
      <div class="stat open"><b>${totals.open}</b>ค้าง</div>
      <div class="stat done"><b>${totals.done}</b>เสร็จ</div>
    </div>
  </header>
  <div class="toolbar">
    ${tab('all', 'ทั้งหมด')}${tab('open', 'ค้าง')}${tab('done', 'เสร็จแล้ว')}
    <span class="spacer"></span>
    <a href="csv?status=${esc(status)}">ดาวน์โหลด Excel (CSV)</a>
    <button onclick="window.print()">พิมพ์ / บันทึก PDF</button>
  </div>
  ${
    items.length
      ? `<div class="table-wrap"><table>
    <thead><tr><th>#</th><th>รูป</th><th>รายละเอียด</th><th>ผู้รับผิดชอบ</th><th>ความสำคัญ</th><th>สถานะ</th><th>ผู้แจ้ง / วันที่</th></tr></thead>
    ${sections}
  </table></div>`
      : '<div class="empty">ยังไม่มีรายการ</div>'
  }
  <div class="sign">
    <div><span>ผู้ตรวจสอบ</span></div>
    <div><span>ผู้รับเหมา</span></div>
    <div><span>เจ้าของโครงการ</span></div>
  </div>
</div>
</body>
</html>`;
}

function renderCsv(chat, { status = 'all', imgBase }) {
  const cell = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const header = ['No', 'ตำแหน่ง', 'รายละเอียด', 'ผู้รับผิดชอบ', 'ความสำคัญ', 'สถานะ', 'ผู้แจ้ง', 'วันที่แจ้ง', 'วันที่ปิด', 'หมายเหตุ', 'รูป'];
  const lines = filterItems(chat.items, status).map((i) =>
    [
      i.no,
      i.location,
      i.description,
      i.assignee,
      i.priority === 'high' ? 'ด่วน' : 'ปกติ',
      i.status === 'done' ? 'เสร็จแล้ว' : 'ค้าง',
      i.reporter,
      fmtDate(i.createdAt),
      fmtDate(i.closedAt),
      i.notes.map((n) => n.text).join(' / '),
      i.photos.map((p) => `${imgBase}/${p}`).join(' '),
    ]
      .map(cell)
      .join(',')
  );
  // BOM ให้ Excel อ่านภาษาไทยถูก
  return '﻿' + [header.map(cell).join(','), ...lines].join('\r\n');
}

module.exports = { renderReport, renderCsv };

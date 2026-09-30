'use strict';

// สร้าง Flex Message สำหรับตอบกลับในไลน์

const COLORS = {
  open: '#E0752D',
  done: '#2E9E5B',
  high: '#D93025',
  muted: '#8A8F98',
  text: '#1F2328',
};

const STATUS_TH = { open: 'ค้าง', done: 'เสร็จแล้ว' };

function trunc(s, n) {
  s = String(s || '');
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function row(label, value, color) {
  return {
    type: 'box',
    layout: 'baseline',
    spacing: 'sm',
    contents: [
      { type: 'text', text: label, size: 'sm', color: COLORS.muted, flex: 2 },
      { type: 'text', text: value || '-', size: 'sm', color: color || COLORS.text, flex: 5, wrap: true },
    ],
  };
}

function itemBubble(item, { imageUrl, reportUrl, heading } = {}) {
  const statusColor = item.status === 'done' ? COLORS.done : COLORS.open;
  const bubble = {
    type: 'bubble',
    body: {
      type: 'box',
      layout: 'vertical',
      spacing: 'md',
      contents: [
        {
          type: 'box',
          layout: 'horizontal',
          contents: [
            { type: 'text', text: heading || 'PUNCH LIST', size: 'xs', color: COLORS.muted, weight: 'bold' },
            { type: 'text', text: STATUS_TH[item.status], size: 'xs', color: statusColor, weight: 'bold', align: 'end' },
          ],
        },
        {
          type: 'text',
          text: `#${item.no} ${trunc(item.description, 120)}`,
          weight: 'bold',
          size: 'lg',
          wrap: true,
        },
        {
          type: 'box',
          layout: 'vertical',
          spacing: 'xs',
          contents: [
            row('ตำแหน่ง', item.location),
            row('ผู้รับผิดชอบ', item.assignee),
            row('ความสำคัญ', item.priority === 'high' ? 'ด่วน' : 'ปกติ', item.priority === 'high' ? COLORS.high : undefined),
            row('รูป', `${item.photos.length} รูป`),
            row('ผู้แจ้ง', item.reporter),
          ],
        },
      ],
    },
  };
  if (imageUrl) {
    bubble.hero = {
      type: 'image',
      url: imageUrl,
      size: 'full',
      aspectRatio: '4:3',
      aspectMode: 'cover',
      ...(reportUrl ? { action: { type: 'uri', uri: reportUrl } } : {}),
    };
  }
  if (reportUrl) {
    bubble.footer = {
      type: 'box',
      layout: 'vertical',
      contents: [
        { type: 'button', style: 'link', height: 'sm', action: { type: 'uri', label: 'ดูรายงานทั้งหมด', uri: reportUrl } },
      ],
    };
  }
  return { type: 'flex', altText: `Punch #${item.no}: ${trunc(item.description, 80)}`, contents: bubble };
}

const MAX_ROWS = 25;

function listBubble(title, items, { reportUrl, totals }) {
  const rows = items.slice(0, MAX_ROWS).map((i) => ({
    type: 'box',
    layout: 'horizontal',
    spacing: 'sm',
    contents: [
      { type: 'text', text: `#${i.no}`, size: 'sm', color: COLORS.muted, flex: 1 },
      {
        type: 'text',
        text: trunc([i.location, i.description].filter(Boolean).join(' · '), 60),
        size: 'sm',
        flex: 6,
        wrap: true,
        color: i.status === 'done' ? COLORS.muted : COLORS.text,
        decoration: i.status === 'done' ? 'line-through' : 'none',
      },
      {
        type: 'text',
        text: i.status === 'done' ? '✓' : i.priority === 'high' ? 'ด่วน' : ' ',
        size: 'xs',
        flex: 1,
        align: 'end',
        color: i.status === 'done' ? COLORS.done : COLORS.high,
      },
    ],
  }));
  if (items.length > MAX_ROWS) {
    rows.push({ type: 'text', text: `…และอีก ${items.length - MAX_ROWS} รายการ`, size: 'xs', color: COLORS.muted });
  }
  if (!rows.length) {
    rows.push({ type: 'text', text: 'ไม่มีรายการ 🎉', size: 'sm', color: COLORS.muted });
  }

  const bubble = {
    type: 'bubble',
    size: 'giga',
    body: {
      type: 'box',
      layout: 'vertical',
      spacing: 'md',
      contents: [
        { type: 'text', text: trunc(title, 60), weight: 'bold', size: 'lg', wrap: true },
        {
          type: 'text',
          text: `ค้าง ${totals.open} · เสร็จ ${totals.done} · ทั้งหมด ${totals.all}`,
          size: 'sm',
          color: COLORS.muted,
        },
        { type: 'separator' },
        { type: 'box', layout: 'vertical', spacing: 'sm', contents: rows },
      ],
    },
  };
  if (reportUrl) {
    bubble.footer = {
      type: 'box',
      layout: 'vertical',
      contents: [
        { type: 'button', style: 'primary', height: 'sm', action: { type: 'uri', label: 'เปิดรายงาน / พิมพ์ PDF', uri: reportUrl } },
      ],
    };
  }
  return { type: 'flex', altText: `${title}: ค้าง ${totals.open} รายการ`, contents: bubble };
}

module.exports = { itemBubble, listBubble };

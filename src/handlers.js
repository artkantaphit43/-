'use strict';

// Logic หลัก: รับ event จากไลน์ → บันทึก / ตอบกลับ

const fs = require('fs');
const { parseCommand, parseItem, hasItemPrefix } = require('./parser');
const { itemBubble, listBubble } = require('./flex');

const HELP = `📋 วิธีใช้ Punch List Bot

➊ ส่งรูปหน้างาน (กี่รูปก็ได้)
➋ พิมพ์รายละเอียดตามหลังรูป
   ตำแหน่ง / รายละเอียด @ผู้รับผิดชอบ ด่วน
   เช่น: ห้อง 301 / สีผนังไม่เรียบ @ทีมสี ด่วน
→ บอทจะสร้างรายการ พร้อมเลขที่ให้

ไม่มีรูป: ขึ้นต้นด้วย + เช่น "+ ห้องน้ำ 2 / ยาแนวหลุด"

คำสั่ง
• รายการ — ดูงานค้าง
• ทั้งหมด — ดูทุกรายการ
• รายงาน — ลิงก์รายงานพร้อมรูป (พิมพ์ PDF / Excel)
• เสร็จ 3 — ปิดรายการ #3 (ส่งรูปก่อนได้ = รูปหลังแก้)
• เปิด 3 — เปิดรายการ #3 ใหม่
• #3 ข้อความ — เพิ่มหมายเหตุ
• ลบ 3 — ลบรายการ #3
• ตั้งชื่อ ชื่อโครงการ — ตั้งชื่อหัวรายงาน
• ยกเลิก — ล้างรูปที่ส่งค้างไว้`;

function chatIdOf(source) {
  return source.groupId || source.roomId || source.userId;
}

function extFor(contentType) {
  if (/png/.test(contentType)) return 'png';
  if (/webp/.test(contentType)) return 'webp';
  return 'jpg';
}

function createHandler({ store, line, baseUrl }) {
  const reportUrl = (chat) => (baseUrl ? `${baseUrl}/r/${chat.token}/` : '');
  const imageUrl = (chat, file) =>
    baseUrl && baseUrl.startsWith('https://') && file ? `${baseUrl}/r/${chat.token}/img/${file}` : undefined;

  const text = (t) => ({ type: 'text', text: t });

  function totals(chat) {
    const open = chat.items.filter((i) => i.status === 'open').length;
    return { all: chat.items.length, open, done: chat.items.length - open };
  }

  async function onImage(event) {
    const chatId = chatIdOf(event.source);
    const userId = event.source.userId || 'unknown';
    const { buffer, contentType } = await line.getContent(event.message.id);
    const file = `${event.message.id}.${extFor(contentType)}`;
    fs.writeFileSync(store.imagePath(file), buffer);
    const count = store.addPendingPhoto(chatId, userId, file);

    // ส่งหลายรูปพร้อมกัน ไลน์จะส่ง imageSet มา ตอบครั้งเดียวที่รูปแรก
    const set = event.message.imageSet;
    const isFirst = set ? set.index === 1 : count === 1;
    if (isFirst) {
      return [text('📷 รับรูปแล้ว พิมพ์รายละเอียดต่อได้เลย\nเช่น: ห้อง 301 / สีผนังไม่เรียบ @ทีมสี')];
    }
    return null;
  }

  async function onText(event) {
    const chatId = chatIdOf(event.source);
    const userId = event.source.userId || 'unknown';
    const chat = store.chat(chatId);
    const msg = event.message.text;
    const cmd = parseCommand(msg);

    if (cmd) {
      switch (cmd.type) {
        case 'help':
          return [text(HELP)];

        case 'list':
        case 'listAll': {
          const items = cmd.type === 'list' ? chat.items.filter((i) => i.status === 'open') : chat.items;
          const title = `${chat.title || 'Punch List'} — ${cmd.type === 'list' ? 'งานค้าง' : 'ทั้งหมด'}`;
          return [listBubble(title, items, { reportUrl: reportUrl(chat), totals: totals(chat) })];
        }

        case 'report':
          if (!baseUrl) return [text('ยังไม่ได้ตั้งค่า BASE_URL ที่เซิร์ฟเวอร์ จึงสร้างลิงก์รายงานไม่ได้')];
          return [text(`📄 รายงาน ${chat.title || 'Punch List'}\n${reportUrl(chat)}\n\nเปิดแล้วกด "พิมพ์ / บันทึก PDF" ได้เลย`)];

        case 'cancel': {
          const n = store.pendingPhotos(chatId, userId).length;
          store.clearPending(chatId, userId);
          return [text(n ? `ล้างรูปที่ค้างไว้ ${n} รูปแล้ว` : 'ไม่มีรูปค้างอยู่')];
        }

        case 'done':
        case 'reopen': {
          const by = await line.displayName(event.source);
          const after = store.pendingPhotos(chatId, userId);
          const item = store.updateItem(chatId, cmd.no, (i) => {
            i.status = cmd.type === 'done' ? 'done' : 'open';
            i.closedAt = cmd.type === 'done' ? new Date().toISOString() : null;
            const label = cmd.type === 'done' ? 'ปิดงาน' : 'เปิดใหม่';
            i.notes.push({ text: cmd.note ? `${label}: ${cmd.note}` : label, by, at: new Date().toISOString() });
            // รูปที่ส่งมาก่อนพิมพ์ "เสร็จ N" = รูปหลังแก้
            if (cmd.type === 'done' && after.length) i.photos.push(...after);
          });
          if (!item) return [text(`ไม่พบรายการ #${cmd.no}`)];
          if (cmd.type === 'done' && after.length) store.clearPending(chatId, userId);
          const heading = cmd.type === 'done' ? '✅ ปิดงานแล้ว' : '↩️ เปิดใหม่';
          return [itemBubble(item, { imageUrl: imageUrl(chat, item.photos.at(-1)), reportUrl: reportUrl(chat), heading })];
        }

        case 'delete': {
          const item = store.deleteItem(chatId, cmd.no);
          return [text(item ? `🗑 ลบรายการ #${cmd.no} แล้ว` : `ไม่พบรายการ #${cmd.no}`)];
        }

        case 'note': {
          const by = await line.displayName(event.source);
          const item = store.updateItem(chatId, cmd.no, (i) => {
            i.notes.push({ text: cmd.note, by, at: new Date().toISOString() });
          });
          return [text(item ? `📝 เพิ่มหมายเหตุใน #${cmd.no} แล้ว` : `ไม่พบรายการ #${cmd.no}`)];
        }

        case 'setTitle':
          store.setTitle(chatId, cmd.title);
          return [text(`ตั้งชื่อโครงการเป็น "${cmd.title}" แล้ว`)];
      }
    }

    // ไม่ใช่คำสั่ง: สร้างรายการเมื่อมีรูปค้างอยู่ หรือขึ้นต้นด้วย "+"
    // (ข้อความคุยกันทั่วไปในกลุ่มจะถูกข้าม)
    const photos = store.pendingPhotos(chatId, userId);
    if (!photos.length && !hasItemPrefix(msg)) return null;

    const fields = parseItem(msg);
    if (!fields.description) return [text('กรุณาพิมพ์รายละเอียดด้วย เช่น: ห้อง 301 / สีผนังไม่เรียบ')];

    const reporter = await line.displayName(event.source);
    const item = store.addItem(chatId, { ...fields, photos, reporter });
    store.clearPending(chatId, userId);
    return [
      itemBubble(item, {
        imageUrl: imageUrl(chat, photos[0]),
        reportUrl: reportUrl(chat),
        heading: '🆕 บันทึกแล้ว',
      }),
    ];
  }

  async function handleEvent(event) {
    let messages = null;
    if (event.type === 'message' && event.message.type === 'image') messages = await onImage(event);
    else if (event.type === 'message' && event.message.type === 'text') messages = await onText(event);
    else if (event.type === 'join' || event.type === 'follow') messages = [text(HELP)];

    if (messages && event.replyToken) await line.reply(event.replyToken, messages);
  }

  return { handleEvent, HELP };
}

module.exports = { createHandler };

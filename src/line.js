'use strict';

// เรียก LINE Messaging API ด้วย fetch (Node 18+) ไม่ต้องใช้ SDK

const crypto = require('crypto');

const API = 'https://api.line.me/v2/bot';
const DATA_API = 'https://api-data.line.me/v2/bot';

function verifySignature(rawBody, signature, secret) {
  if (!signature || !secret) return false;
  const expected = crypto.createHmac('sha256', secret).update(rawBody).digest();
  const given = Buffer.from(signature, 'base64');
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

class LineClient {
  constructor(accessToken) {
    this.accessToken = accessToken;
  }

  headers(extra = {}) {
    return { Authorization: `Bearer ${this.accessToken}`, ...extra };
  }

  async reply(replyToken, messages) {
    const res = await fetch(`${API}/message/reply`, {
      method: 'POST',
      headers: this.headers({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ replyToken, messages: [].concat(messages).slice(0, 5) }),
    });
    if (!res.ok) throw new Error(`LINE reply ${res.status}: ${await res.text()}`);
  }

  // ดาวน์โหลดรูปที่ผู้ใช้ส่งมา คืนค่า { buffer, contentType }
  async getContent(messageId) {
    const res = await fetch(`${DATA_API}/message/${messageId}/content`, {
      headers: this.headers(),
    });
    if (!res.ok) throw new Error(`LINE content ${res.status}: ${await res.text()}`);
    return {
      buffer: Buffer.from(await res.arrayBuffer()),
      contentType: res.headers.get('content-type') || 'image/jpeg',
    };
  }

  // ชื่อผู้ส่ง (ในกลุ่มต้องใช้ endpoint ของกลุ่ม) ถ้าหาไม่ได้คืน ''
  async displayName(source) {
    const { type, userId, groupId, roomId } = source;
    if (!userId) return '';
    const url =
      type === 'group'
        ? `${API}/group/${groupId}/member/${userId}`
        : type === 'room'
          ? `${API}/room/${roomId}/member/${userId}`
          : `${API}/profile/${userId}`;
    try {
      const res = await fetch(url, { headers: this.headers() });
      if (!res.ok) return '';
      return (await res.json()).displayName || '';
    } catch {
      return '';
    }
  }
}

module.exports = { LineClient, verifySignature };

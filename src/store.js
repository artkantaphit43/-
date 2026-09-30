'use strict';

// เก็บข้อมูลเป็นไฟล์ JSON ไฟล์เดียว (พอสำหรับทีมหน้างานทั่วไป)
// โครงสร้าง: { chats: { [chatId]: Chat } }
// Chat: { token, title, seq, items: Item[], pending: { [userId]: { photos: string[], at } } }

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PENDING_TTL_MS = 30 * 60 * 1000;

class Store {
  constructor(dataDir) {
    this.dataDir = dataDir;
    this.imageDir = path.join(dataDir, 'images');
    this.file = path.join(dataDir, 'db.json');
    fs.mkdirSync(this.imageDir, { recursive: true });
    this.db = fs.existsSync(this.file)
      ? JSON.parse(fs.readFileSync(this.file, 'utf8'))
      : { chats: {} };
  }

  save() {
    const tmp = this.file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.db, null, 2));
    fs.renameSync(tmp, this.file);
  }

  chat(chatId) {
    if (!this.db.chats[chatId]) {
      this.db.chats[chatId] = {
        token: crypto.randomBytes(16).toString('hex'),
        title: '',
        seq: 0,
        items: [],
        pending: {},
      };
    }
    return this.db.chats[chatId];
  }

  chatByToken(token) {
    for (const [chatId, chat] of Object.entries(this.db.chats)) {
      if (chat.token === token) return { chatId, chat };
    }
    return null;
  }

  addPendingPhoto(chatId, userId, file) {
    const chat = this.chat(chatId);
    const p = this.pendingPhotos(chatId, userId);
    p.push(file);
    chat.pending[userId] = { photos: p, at: Date.now() };
    this.save();
    return p.length;
  }

  pendingPhotos(chatId, userId) {
    const p = this.chat(chatId).pending[userId];
    if (!p || Date.now() - p.at > PENDING_TTL_MS) return [];
    return p.photos.slice();
  }

  clearPending(chatId, userId) {
    delete this.chat(chatId).pending[userId];
    this.save();
  }

  addItem(chatId, fields) {
    const chat = this.chat(chatId);
    const item = {
      no: ++chat.seq,
      location: fields.location || '',
      description: fields.description || '',
      assignee: fields.assignee || '',
      priority: fields.priority || 'normal',
      status: 'open',
      photos: fields.photos || [],
      reporter: fields.reporter || '',
      createdAt: new Date().toISOString(),
      closedAt: null,
      notes: [],
    };
    chat.items.push(item);
    this.save();
    return item;
  }

  getItem(chatId, no) {
    return this.chat(chatId).items.find((i) => i.no === no) || null;
  }

  updateItem(chatId, no, fn) {
    const item = this.getItem(chatId, no);
    if (!item) return null;
    fn(item);
    this.save();
    return item;
  }

  deleteItem(chatId, no) {
    const chat = this.chat(chatId);
    const idx = chat.items.findIndex((i) => i.no === no);
    if (idx < 0) return null;
    const [item] = chat.items.splice(idx, 1);
    this.save();
    for (const f of item.photos) fs.rm(this.imagePath(f), { force: true }, () => {});
    return item;
  }

  setTitle(chatId, title) {
    this.chat(chatId).title = title;
    this.save();
  }

  imagePath(file) {
    return path.join(this.imageDir, path.basename(file));
  }
}

module.exports = { Store };

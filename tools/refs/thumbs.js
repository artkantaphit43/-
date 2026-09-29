// Renders library previews: node thumbs.js <scene dir> <png dir> (needs playwright)
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [src, dst] = process.argv.slice(2);
  fs.mkdirSync(dst, { recursive: true });
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 160, height: 160 } });
  await p.setContent('<body style="margin:0"><canvas id=c width=320 height=320></canvas></body>');
  for (const f of fs.readdirSync(src).filter(x => x.endsWith('.json'))) {
    const scene = JSON.parse(fs.readFileSync(path.join(src, f), 'utf8'));
    const url = await p.evaluate((sc) => {
      const W = 320, cv = document.getElementById('c'), ctx = cv.getContext('2d');
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, W);
      const az = -0.62, el = 0.5;
      const view = q => { const x = q[0]*Math.cos(az) - q[1]*Math.sin(az), y = q[0]*Math.sin(az) + q[1]*Math.cos(az);
        return [x, y*Math.sin(el) + q[2]*Math.cos(el), y*Math.cos(el) - q[2]*Math.sin(el)]; };
      const V = sc.v.map(view);
      let mn = [1e9, 1e9], mx = [-1e9, -1e9];
      V.forEach(v => { mn[0] = Math.min(mn[0], v[0]); mn[1] = Math.min(mn[1], v[1]); mx[0] = Math.max(mx[0], v[0]); mx[1] = Math.max(mx[1], v[1]); });
      const s = Math.min((W - 24) / (mx[0] - mn[0] || 1), (W - 24) / (mx[1] - mn[1] || 1));
      const P = v => [12 + (v[0] - mn[0]) * s + ((W - 24) - (mx[0] - mn[0]) * s) / 2, W - 12 - (v[1] - mn[1]) * s - ((W - 24) - (mx[1] - mn[1]) * s) / 2];
      const nrm = a => { const l = Math.hypot(...a) || 1; return a.map(x => x / l); };
      const fs2 = sc.f.map(f => {
        const o = f.l[0].map(i => V[i]); let n = [0, 0, 0];
        for (let i = 0; i < o.length; i++) { const a = o[i], c = o[(i + 1) % o.length];
          n[0] += (a[1] - c[1]) * (a[2] + c[2]); n[1] += (a[2] - c[2]) * (a[0] + c[0]); n[2] += (a[0] - c[0]) * (a[1] + c[1]); }
        return { f, n: nrm(n), d: o.reduce((a, v) => a + v[2], 0) / o.length * 0.7 + Math.max(...o.map(v => v[2])) * 0.3 };
      }).sort((a, c) => c.d - a.d);
      const L = nrm([0.3, 0.7, -0.65]);
      ctx.lineJoin = 'round';
      fs2.forEach(({ f, n }) => {
        const sh = 0.6 + 0.4 * Math.abs(n[0]*L[0] + n[1]*L[1] + n[2]*L[2]);
        ctx.beginPath();
        f.l.forEach(l => { l.forEach((i, k) => { const q = P(V[i]); k ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]); }); ctx.closePath(); });
        ctx.fillStyle = `rgb(${f.c.map(x => Math.round(x * sh)).join(',')})`; ctx.fill('evenodd');
        ctx.strokeStyle = 'rgba(0,0,0,.8)'; ctx.lineWidth = 0.9; ctx.beginPath();
        f.l.forEach((l, li) => l.forEach((i, k) => { if (!f.h[li][k]) return; const a = P(V[i]), c = P(V[l[(k + 1) % l.length]]); ctx.moveTo(a[0], a[1]); ctx.lineTo(c[0], c[1]); }));
        ctx.stroke();
      });
      const t = document.createElement('canvas'); t.width = t.height = 128;
      t.getContext('2d').drawImage(cv, 0, 0, 128, 128);
      return t.toDataURL('image/jpeg', 0.8);
    }, scene);
    fs.writeFileSync(path.join(dst, f.replace(/\.json$/, '.jpg')), Buffer.from(url.split(',')[1], 'base64'));
  }
  await b.close();
})();

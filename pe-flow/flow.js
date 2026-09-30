// Draws orthogonal connector arrows between flow nodes after layout.
// Each .flow holds <script type="application/json" class="edges">[[from,to,"b-t",label,cls,{opts}], ...]</script>
(function () {
  const NS = 'http://www.w3.org/2000/svg';
  const COLORS = { '': '#6b7385', no: '#cf2f2f', yes: '#12825a', loop: '#8a92a3', dim: '#aab1bf' };

  function anchor(r, side, frac) {
    const f = frac == null ? 0.5 : frac;
    switch (side) {
      case 't': return { x: r.left + r.width * f, y: r.top };
      case 'b': return { x: r.left + r.width * f, y: r.bottom };
      case 'l': return { x: r.left, y: r.top + r.height * f };
      case 'r': return { x: r.right, y: r.top + r.height * f };
    }
  }

  function route(p1, fs, p2, ts, o) {
    const V = s => s === 't' || s === 'b';
    const off = o.off != null ? o.off : 14;
    if (V(fs) && V(ts)) {
      if (fs !== ts) {
        if (Math.abs(p1.x - p2.x) < 1.5) return [p1, { x: p1.x, y: p2.y }];
        const my = o.my != null ? p1.y + o.my : (p1.y + p2.y) / 2;
        return [p1, { x: p1.x, y: my }, { x: p2.x, y: my }, p2];
      }
      const y = fs === 'b' ? Math.max(p1.y, p2.y) + off : Math.min(p1.y, p2.y) - off;
      return [p1, { x: p1.x, y }, { x: p2.x, y }, p2];
    }
    if (!V(fs) && !V(ts)) {
      if (fs !== ts) {
        if (Math.abs(p1.y - p2.y) < 1.5) return [p1, { x: p2.x, y: p1.y }];
        const mx = o.mx != null ? p1.x + o.mx : (p1.x + p2.x) / 2;
        return [p1, { x: mx, y: p1.y }, { x: mx, y: p2.y }, p2];
      }
      const x = fs === 'r' ? Math.max(p1.x, p2.x) + off : Math.min(p1.x, p2.x) - off;
      return [p1, { x, y: p1.y }, { x, y: p2.y }, p2];
    }
    if (V(fs)) return [p1, { x: p1.x, y: p2.y }, p2];
    return [p1, { x: p2.x, y: p1.y }, p2];
  }

  function pathD(pts, rad) {
    let d = `M${pts[0].x},${pts[0].y}`;
    for (let i = 1; i < pts.length - 1; i++) {
      const a = pts[i - 1], b = pts[i], c = pts[i + 1];
      const l1 = Math.hypot(b.x - a.x, b.y - a.y), l2 = Math.hypot(c.x - b.x, c.y - b.y);
      const r = Math.min(rad, l1 / 2, l2 / 2);
      const p = { x: b.x + (a.x - b.x) * r / l1, y: b.y + (a.y - b.y) * r / l1 };
      const q = { x: b.x + (c.x - b.x) * r / l2, y: b.y + (c.y - b.y) * r / l2 };
      d += ` L${p.x},${p.y} Q${b.x},${b.y} ${q.x},${q.y}`;
    }
    const e = pts[pts.length - 1];
    return d + ` L${e.x},${e.y}`;
  }

  function draw(flow) {
    const spec = flow.querySelector('script.edges');
    if (!spec) return;
    const edges = JSON.parse(spec.textContent);
    const fr = flow.getBoundingClientRect();
    const svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('class', 'wires');
    svg.setAttribute('width', fr.width);
    svg.setAttribute('height', fr.height);
    const defs = document.createElementNS(NS, 'defs');
    Object.entries(COLORS).forEach(([k, c]) => {
      const m = document.createElementNS(NS, 'marker');
      m.setAttribute('id', 'ah-' + (k || 'd') + '-' + flow.dataset.k);
      m.setAttribute('viewBox', '0 0 10 10');
      m.setAttribute('refX', '9'); m.setAttribute('refY', '5');
      m.setAttribute('markerWidth', '7'); m.setAttribute('markerHeight', '7');
      m.setAttribute('markerUnits', 'userSpaceOnUse');
      m.setAttribute('orient', 'auto');
      const p = document.createElementNS(NS, 'path');
      p.setAttribute('d', 'M0,0.8 L10,5 L0,9.2 Z');
      p.setAttribute('fill', c);
      m.appendChild(p); defs.appendChild(m);
    });
    svg.appendChild(defs);
    flow.prepend(svg);

    edges.forEach(e => {
      const [fromId, toId, sides = 'b-t', label = '', cls = '', o = {}] = e;
      const A = document.getElementById(fromId), B = document.getElementById(toId);
      if (!A || !B) { console.warn('missing node', fromId, toId); return; }
      const ra = rel(A.getBoundingClientRect(), fr), rb = rel(B.getBoundingClientRect(), fr);
      const [fs, ts] = sides.split('-');
      const p1 = anchor(ra, fs, o.fa), p2 = anchor(rb, ts, o.ta);
      const pts = route(p1, fs, p2, ts, o);
      const path = document.createElementNS(NS, 'path');
      path.setAttribute('d', pathD(pts, 5));
      path.setAttribute('fill', 'none');
      const col = COLORS[cls] || COLORS[''];
      path.setAttribute('stroke', col);
      path.setAttribute('stroke-width', cls === 'loop' || cls === 'dim' ? '0.9' : '1.1');
      if (cls === 'no' || cls === 'loop' || cls === 'dim' || o.dash) path.setAttribute('stroke-dasharray', '3.2 2.2');
      if (!o.noArrow) path.setAttribute('marker-end', `url(#ah-${cls || 'd'}-${flow.dataset.k})`);
      svg.appendChild(path);
      if (label) {
        const L = document.createElement('div');
        L.className = 'lbl ' + cls;
        L.textContent = label;
        flow.appendChild(L);
        const w = L.offsetWidth, h = L.offsetHeight;
        let x, y;
        if (o.lend) {
          if (ts === 'r') { x = p2.x + 4; y = p2.y - h - 1; }
          else if (ts === 'l') { x = p2.x - w - 4; y = p2.y - h - 1; }
          else if (ts === 't') { x = p2.x + 3; y = p2.y - h - 2; }
          else { x = p2.x + 3; y = p2.y + 2; }
        }
        else if (o.lx != null) { x = p1.x + o.lx; y = p1.y + (o.ly || 0); }
        else if (fs === 'b') { x = p1.x + 3; y = p1.y + 1.5; }
        else if (fs === 't') { x = p1.x + 3; y = p1.y - h - 1.5; }
        else if (fs === 'r') { x = p1.x + 3; y = p1.y - h - 0.5; }
        else { x = p1.x - w - 3; y = p1.y - h - 0.5; }
        L.style.left = x + 'px'; L.style.top = y + 'px';
      }
    });
  }

  function rel(r, fr) {
    return { left: r.left - fr.left, top: r.top - fr.top, right: r.right - fr.left, bottom: r.bottom - fr.top, width: r.width, height: r.height };
  }

  function checkOverflow() {
    const report = [];
    document.querySelectorAll('.page').forEach((pg, i) => {
      const pr = pg.getBoundingClientRect();
      const limit = pr.bottom - 11 * 3.7795; // above footer zone
      let worst = 0;
      pg.querySelectorAll('.n, .box, table, .blk').forEach(el => {
        const b = el.getBoundingClientRect().bottom;
        if (b - limit > worst) worst = b - limit;
      });
      const room = limit - Math.max(...[...pg.querySelectorAll('.n, .box, table, .blk')].map(el => el.getBoundingClientRect().bottom), pr.top);
      report.push({ page: i + 1, overflowPx: Math.round(worst), spareMm: Math.round(room / 3.7795 * 10) / 10 });
    });
    return report;
  }

  function run() {
    const pages = document.querySelectorAll('.page');
    pages.forEach((pg, i) => { const el = pg.querySelector('.pf .pg'); if (el) el.textContent = `หน้า ${i + 1} / ${pages.length}`; });
    document.querySelectorAll('.flow').forEach((f, i) => { f.dataset.k = i; draw(f); });
    window.__overflow = checkOverflow();
    window.__done = true;
  }
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => requestAnimationFrame(run));
})();

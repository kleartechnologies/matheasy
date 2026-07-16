// Final Matheasy "M" mark: a clean, constructed, bold-italic M whose proportions
// are measured from the supplied logo artwork. Emits both an SVG preview and the
// Dart Path source.
const fs = require('fs');

const H = 100;      // cap height (the mark's native grid)
const W = 104;      // upright width before the italic shear
const S = 31;       // stem width
const a = 34;       // apex top width
const Vd = 42;      // outer V notch depth
const Vi = 76;      // inner V vertex depth
const Vt = 58;      // inner apex (where the inner diagonal meets the stem)
const SLANT = 21;   // italic, degrees (measured ~22 on the artwork)

// per-vertex corner radius: generous on the outer silhouette, crisp at the V
const RO = 7;   // outer corners
const RV = 3.5; // the two V vertices stay sharp -- the artwork's V is a point

const pts = [
  { p: [0, 0], r: RO },        // 0 top-left apex
  { p: [a, 0], r: RO },        // 1 top of left apex
  { p: [W / 2, Vd], r: RV },   // 2 outer V notch  <- crisp
  { p: [W - a, 0], r: RO },    // 3 top of right apex
  { p: [W, 0], r: RO },        // 4 top-right
  { p: [W, H], r: RO },        // 5 bottom-right
  { p: [W - S, H], r: RO },    // 6 bottom of right stem
  { p: [W - S, Vt], r: RV },   // 7 right inner apex <- crisp
  { p: [W / 2, Vi], r: RV },   // 8 inner V vertex   <- crisp
  { p: [S, Vt], r: RV },       // 9 left inner apex  <- crisp
  { p: [S, H], r: RO },        // 10 bottom of left stem inner
  { p: [0, H], r: RO },        // 11 bottom-left
];

const sh = Math.tan((SLANT * Math.PI) / 180);
// shear about the baseline so the bottom edge stays on y=H
const sheared = pts.map((v) => ({ p: [v.p[0] + sh * (H - v.p[1]), v.p[1]], r: v.r }));

const dist = (A, B) => Math.hypot(B[0] - A[0], B[1] - A[1]);
const lerp = (A, B, t) => [A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t];

function build(list) {
  const n = list.length;
  const segs = [];
  for (let i = 0; i < n; i++) {
    const prev = list[(i - 1 + n) % n].p, cur = list[i].p, next = list[(i + 1) % n].p;
    const rr = Math.min(list[i].r, dist(prev, cur) / 2.2, dist(cur, next) / 2.2);
    segs.push({
      in: lerp(cur, prev, rr / dist(cur, prev)),
      c: cur,
      out: lerp(cur, next, rr / dist(cur, next)),
    });
  }
  return segs;
}
const segs = build(sheared);

// ---- SVG ----
const f = (n) => n.toFixed(2);
let d = `M ${f(segs[0].in[0])} ${f(segs[0].in[1])} `;
for (let i = 0; i < segs.length; i++) {
  const s = segs[i];
  if (i > 0) d += `L ${f(s.in[0])} ${f(s.in[1])} `;
  d += `Q ${f(s.c[0])} ${f(s.c[1])} ${f(s.out[0])} ${f(s.out[1])} `;
}
d += 'Z';

const minX = Math.min(...sheared.map((v) => v.p[0]));
const maxX = Math.max(...sheared.map((v) => v.p[0]));
console.log('sheared bbox width =', (maxX - minX).toFixed(2), ' height =', H);
console.log('aspect (w/h) =', ((maxX - minX) / H).toFixed(3));

const pad = 14;
const vbW = maxX - minX + pad * 2, vbH = H + pad * 2;
fs.writeFileSync(
  'm-final.svg',
  `<svg xmlns="http://www.w3.org/2000/svg" width="${(vbW * 5).toFixed(0)}" height="${(vbH * 5).toFixed(0)}" viewBox="${minX - pad} ${-pad} ${vbW} ${vbH}">` +
    `<rect x="${minX - pad}" y="${-pad}" width="${vbW}" height="${vbH}" fill="#06AC60"/>` +
    `<path d="${d}" fill="#fff"/></svg>`
);

// ---- Dart ----
// normalise so the mark sits in a 100-wide x 100-tall box, centred
const scale = 100 / Math.max(maxX - minX, H);
const ox = -minX, oy = 0;
const N = (p) => [(p[0] + ox) * scale + (100 - (maxX - minX) * scale) / 2, (p[1] + oy) * scale + (100 - H * scale) / 2];
let dart = '    final p = Path()\n';
dart += `      ..moveTo(${N(segs[0].in).map(f).join(', ')})\n`;
for (let i = 0; i < segs.length; i++) {
  const s = segs[i];
  if (i > 0) dart += `      ..lineTo(${N(s.in).map(f).join(', ')})\n`;
  dart += `      ..quadraticBezierTo(${N(s.c).map(f).join(', ')}, ${N(s.out).map(f).join(', ')})\n`;
}
dart += '      ..close();';
fs.writeFileSync('m-path.dart.txt', dart);
console.log('\n--- Dart path (100x100 grid) ---\n');
console.log(dart);

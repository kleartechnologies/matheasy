// Derive + VERIFY the Matheasy token system from the logo's measured tones.
// Logo anchors (k-means over the artwork):
//   #06AC60 hsl(153,93%,35%)  56.7%  tile / identity
//   #058446 hsl(151,93%,27%)   9.7%  mid shadow
//   #046934 hsl(148,93%,21%)   7.1%  deep shadow
//   #024221 hsl(150,94%,13%)  13.4%  outline
//   #FCFCFC                   13.2%  letterform
const lin = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
const L = (c) => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
const h2r = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const cr = (a, b) => { const l1 = L(h2r(a)), l2 = L(h2r(b)); const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1]; return (hi + 0.05) / (lo + 0.05); };
const hsl = (h, s, l) => { s /= 100; l /= 100; const k = (n) => (n + h / 30) % 12; const a = s * Math.min(l, 1 - l);
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return '#' + [f(0), f(8), f(4)].map((v) => Math.round(255 * v).toString(16).padStart(2, '0')).join('').toUpperCase(); };

const WHITE = '#FFFFFF';
const INK = '#0A1F16';   // brand ink, derived: the logo's hue at very low L (was #0F172A, a blue-grey - off-brand)

// ---- Brand emerald ramp: 4 steps are MEASURED from the logo, rest interpolated
//      along the same hue(153->148)/sat(93) signature.
const RAMP = {
  50:  hsl(154, 76, 96),
  100: hsl(154, 80, 90),
  200: hsl(153, 82, 80),
  300: hsl(153, 84, 66),
  400: hsl(153, 90, 47),
  500: '#06AC60', // LOGO tile
  600: '#058446', // LOGO mid shadow
  700: '#046934', // LOGO deep shadow
  800: hsl(149, 93, 17),
  900: '#024221', // LOGO outline
};

console.log('=== BRAND EMERALD RAMP (4 steps measured from the logo) ===');
console.log('step  hex       vs #FFF   vs ink    source');
for (const [k, v] of Object.entries(RAMP)) {
  const src = ['500', '600', '700', '900'].includes(k) ? 'LOGO (measured)' : 'derived';
  console.log(String(k).padEnd(5), v, String(cr(v, WHITE).toFixed(2)).padStart(6), String(cr(v, INK).toFixed(2)).padStart(8), '  ' + src);
}

// ---- Semantic roles ----
const T = {
  primary:       RAMP[500],  // identity fill - large shapes only
  primaryAction: RAMP[600],  // fills BEHIND WHITE LABEL TEXT (>=4.5:1)
  primaryDark:   RAMP[700],  // pressed depth + emerald TEXT on white
  primaryDeep:   RAMP[900],  // text on primaryContainer
  primaryLight:  RAMP[400],  // dark-mode mark / accents on dark
  primaryTint:   RAMP[300],
};

console.log('\n=== CRITICAL CONTRAST GATES ===');
const gates = [
  ['white TEXT on primaryAction', WHITE, T.primaryAction, 4.5, 'AA text'],
  ['white ICON on primary (FAB)', WHITE, T.primary, 3.0, 'AA non-text'],
  ['primaryDark TEXT on white', T.primaryDark, WHITE, 4.5, 'AA text'],
  ['primary on white (non-text)', T.primary, WHITE, 3.0, 'AA non-text'],
  ['ink on primary', INK, T.primary, 4.5, 'AA text'],
  ['primaryDeep on emerald50', T.primaryDeep, RAMP[50], 4.5, 'AA text'],
  ['primaryTint on emerald900 (dark)', T.primaryTint, RAMP[900], 4.5, 'AA text'],
];
let fails = 0;
for (const [name, fg, bg, min, label] of gates) {
  const r = cr(fg, bg);
  const ok = r >= min;
  if (!ok) fails++;
  console.log((ok ? 'PASS' : 'FAIL').padEnd(5), name.padEnd(34), r.toFixed(2).padStart(6), ' need ' + min + ' (' + label + ')');
}

// ---- Semantic hues: the logo is monochrome green, so warning/error/info CANNOT
//      be derived by hue. They are derived by TONAL SIGNATURE: the logo's own
//      saturation/lightness discipline (S~93, L~35 at the 500 step) at semantic hues.
console.log('\n=== SEMANTIC HUES (logo tonal signature S~90 L~35-42 at other hues) ===');
const SEM = {
  'error/500':   hsl(4, 74, 43),
  'error/deep':  hsl(4, 76, 33),
  'warning/500': hsl(28, 88, 38),
  'warning/deep':hsl(26, 90, 29),
  'info/500':    hsl(206, 82, 38),
  'info/deep':   hsl(208, 84, 29),
};
for (const [k, v] of Object.entries(SEM)) {
  console.log(k.padEnd(14), v, 'white-on:', cr(v, WHITE).toFixed(2).padStart(5), ' on-white:', cr(v, WHITE).toFixed(2).padStart(5));
}

console.log('\n=== INK / TEXT (derived: the logo hue at very low lightness) ===');
for (const [k, v] of [['ink', INK], ['inkDeep', '#06140E'], ['textSecondary(light)', hsl(155, 12, 38)], ['textMuted(light)', hsl(155, 9, 48)]]) {
  console.log(k.padEnd(22), v, 'on #FFF:', cr(v, WHITE).toFixed(2).padStart(6), 'on #F4F7F5:', cr(v, '#F4F7F5').toFixed(2).padStart(6));
}
console.log('\nfails:', fails);

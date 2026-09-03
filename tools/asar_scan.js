// Minimal asar reader: parse header JSON, locate files containing a needle, print context.
const fs = require('fs');
const path = require('path');
const ASAR = '/Applications/Typeless.app/Contents/Resources/app.asar';
const fd = fs.openSync(ASAR, 'r');
const head = Buffer.alloc(16);
fs.readSync(fd, head, 0, 16, 0);
const headerPickleSize = head.readUInt32LE(4);
const jsonLen = head.readUInt32LE(12);
const jsonBuf = Buffer.alloc(jsonLen);
fs.readSync(fd, jsonBuf, 0, jsonLen, 16);
const header = JSON.parse(jsonBuf.toString('utf8'));
const base = 8 + headerPickleSize;

const files = [];
(function walk(node, prefix) {
  for (const [name, v] of Object.entries(node.files || {})) {
    const p = prefix + '/' + name;
    if (v.files) walk(v, p);
    else files.push({ p, size: v.size, offset: v.offset !== undefined ? Number(v.offset) : null, unpacked: !!v.unpacked });
  }
})(header, '');

console.log('TOTAL FILES', files.length);
// top-level dirs by size
const byDir = {};
for (const f of files) { const d = f.p.split('/').slice(1, 3).join('/'); byDir[d] = (byDir[d] || 0) + f.size; }
console.log('=== biggest top-level entries (MB) ===');
Object.entries(byDir).sort((a, b) => b[1] - a[1]).slice(0, 15).forEach(([d, s]) => console.log((s / 1048576).toFixed(1).padStart(8), d));

const needles = ['Upgrade for enhanced accuracy', 'enhanced accuracy', 'busier than usual', 'Upgrade to Typeless Pro'];
console.log('=== scanning text files for needles ===');
const hits = [];
for (const f of files) {
  if (f.unpacked || f.offset === null) continue;
  if (!/\.(js|mjs|cjs|html|json|ts|tsx|jsx|css)$/.test(f.p)) continue;
  if (f.size > 60 * 1048576) continue;
  const buf = Buffer.alloc(f.size);
  fs.readSync(fd, buf, 0, f.size, base + f.offset);
  const s = buf.toString('utf8');
  for (const n of needles) {
    let i = -1;
    while ((i = s.indexOf(n, i + 1)) !== -1) {
      hits.push({ file: f.p, size: f.size, needle: n, idx: i, ctx: s.slice(Math.max(0, i - 700), i + 700) });
      if (hits.length > 40) break;
    }
  }
}
console.log('HITS', hits.length);
const seen = new Set();
for (const h of hits) {
  const key = h.file + ':' + h.needle;
  console.log(`\n##### ${h.file} (${(h.size/1024).toFixed(0)} KB) needle="${h.needle}" idx=${h.idx}`);
  if (seen.has(key)) { console.log('(dup file/needle, ctx omitted)'); continue; }
  seen.add(key);
  console.log(h.ctx.replace(/\n/g, '⏎'));
}
fs.writeFileSync('asar_files.txt', files.map(f => `${f.size}\t${f.unpacked ? 'U' : ' '}\t${f.p}`).join('\n'));

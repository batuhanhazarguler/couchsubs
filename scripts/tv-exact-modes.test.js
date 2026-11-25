// SPDX-License-Identifier: AGPL-3.0-only
// Çizim kipleri (TV uygulaması 0.9.108, app.js exactMode / exactInput / exactTwins / placeExact) gerçek Chromium'da:
//  - beside (Sinan Bey: "SELAMLA  GREET"): kutu yok, özgün yazı açık kalır; Türkçe hemen solunda, aynı satır ve aynı
//    yazı boyunda, özgüne yaslı, okunurluk konturuyla.
//  - twin (#1296): özgün panel örtülmez; aynı zemin, yuvarlak köşe, kuyruk ve kişi resmiyle küçük ikiz panel hemen
//    üstte, sol kenarı özgünle hizalı, genişliği içeriğe göre; yazı scale katında.
//  - Alanları eksik/eski gönderi örtme kipinde çizilir (eski bilgisayar bozulmaz).
// node --test scripts/tv-exact-modes.test.js — tarayıcı yolu: COUCHSUBS_TEST_BROWSER.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const root = path.join(__dirname, '..', 'tv-webos');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const browser = [process.env.COUCHSUBS_TEST_BROWSER, process.env.CHROME_BIN,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].find(p => p && fs.existsSync(p));

function slice(from, to) {
  const start = app.indexOf(from);
  const end = app.indexOf(to, start);
  assert.ok(start > 0 && end > start, 'TV işlevi bulunamadı: ' + from);
  return app.slice(start, end);
}

const W = 1920, H = 1080;
const px = (l, t, r, b) => ({ left: l / W, top: t / H, right: r / W, bottom: b / H });
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const base = (extra) => Object.assign({ line: 40 / H, lineH: 40 / H, fg: '#FFFFFF', weight: 700, upper: true, align: 'center',
  surface: { background: '#3A3A3A', foreground: '#FFFFFF', flat: false },
  style: { align: 'center', bold: true, condensed: true, upper: true } }, extra);
const items = [
  // 0) Yanına yazma: özgün "GREET" 1000-1100; Türkçe solunda (spot 880-980, boş alan 700'e kadar).
  base({ text: 'SELAMLA', box: px(1002, 502, 1098, 538), cover: px(1000, 500, 1100, 540), bg: '#3A3A3A', bgPat: true,
    mode: 'beside', spot: px(880, 500, 980, 540), spotRoom: px(700, 500, 980, 540) }),
  // 1-2) İkiz: özgün balon 1400-1800 x 800-960 (resim 1420-1460, ad, mesaj); ikiz üstte, 0,58 katında.
  { text: 'Jason', box: px(1480, 820, 1580, 860), line: 40 / H, lineH: 40 / H, cover: px(1478, 818, 1582, 862),
    bg: '#E2EBD2', fg: '#202020', weight: 700, upper: false, align: 'left', mode: 'twin', scale: 0.58, radius: 20 / H,
    tail: 'left', twinBox: px(1400, 701, 1632, 794), spot: px(1446, 711, 1506, 737), spotRoom: px(1446, 711, 1788, 737),
    icon: { src: PNG, box: px(1412, 712, 1435, 735) },
    surface: { background: '#E2EBD2', foreground: '#202020', flat: true }, style: { align: 'left', bold: true, condensed: false, upper: false } },
  { text: 'Uyandın mı, iyi misin?', box: px(1420, 880, 1760, 920), line: 40 / H, lineH: 40 / H, cover: px(1418, 878, 1762, 922),
    bg: '#E2EBD2', fg: '#202020', weight: 400, upper: false, align: 'left', mode: 'twin', scale: 0.58, radius: 20 / H,
    tail: 'left', twinBox: px(1400, 701, 1632, 794), spot: px(1410, 746, 1610, 771), spotRoom: px(1410, 746, 1788, 771),
    icon: { src: PNG, box: px(1412, 712, 1435, 735) },
    surface: { background: '#E2EBD2', foreground: '#202020', flat: true }, style: { align: 'left', bold: false, condensed: false, upper: false } },
  // 3) Eski gönderi (kip yok): örtme.
  base({ text: 'ESKİ', box: px(200, 300, 300, 340), cover: px(198, 298, 302, 342), bg: '#202020' }),
  // 4) Kip var ama spot eksik: örtme.
  base({ text: 'EKSİK', box: px(200, 400, 300, 440), cover: px(198, 398, 302, 442), bg: '#202020', mode: 'beside' }),
];

function render() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'couchsubs-modes-'));
  try {
    const html = `<!doctype html><meta charset="utf-8"><style>${fs.readFileSync(path.join(root, 'style.css'), 'utf8')}</style>
      <div id="regions" class="hidden"></div><div id="screen"></div><pre id="result"></pre><script>
      Object.defineProperty(window, 'innerWidth', { value: ${W} });
      Object.defineProperty(window, 'innerHeight', { value: ${H} });
      function $(id) { return document.getElementById(id); }
      function hideSubtitle() {}
      function resolveLayers() {}
      var diag = { regions: 0, big: 0 };
      var setApart = true;
      var fontBase = 46;
      ${slice('  function validBox(box)', '\n  //')}
      ${slice('  function fillText(el, text, icons)', '\n  //')}
      ${slice('  var screenTimer = null;', '\n  // --- Ek alanlar')}
      showScreen(${JSON.stringify(items)}, 20000);
      var out = Array.from($('screen').children).map(function (el) {
        var b = el.getBoundingClientRect(), cs = getComputedStyle(el);
        var lines = Array.from(el.querySelectorAll('.exact-line')).map(function (row) {
          var range = document.createRange();
          range.selectNodeContents(row);
          var r = range.getBoundingClientRect(), rb = row.getBoundingClientRect();
          return { text: row.textContent, left: r.left, right: r.right, top: rb.top, bottom: rb.bottom };
        });
        var img = el.querySelector('img'), tail = el.querySelector('.exact-tail');
        return { text: el.textContent, cls: el.className, left: b.left, top: b.top, right: b.right, bottom: b.bottom,
          bg: cs.backgroundColor, radius: cs.borderTopLeftRadius, bottomLeft: cs.borderBottomLeftRadius,
          shadow: cs.textShadow, font: parseFloat(cs.fontSize), lines: lines,
          img: img ? Object.assign({ radius: getComputedStyle(img).borderTopLeftRadius }, JSON.parse(JSON.stringify(img.getBoundingClientRect()))) : null,
          tail: !!tail };
      });
      $('result').textContent = btoa(unescape(encodeURIComponent(JSON.stringify(out))));
      </script>`;
    const file = path.join(temp, 'modes.html');
    fs.writeFileSync(file, html);
    const run = spawnSync(browser, ['--headless=new', '--disable-gpu', '--disable-background-networking', '--no-first-run',
      '--no-default-browser-check', '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + W + ',' + (H + 200),
      ...(process.platform === 'linux' ? ['--no-sandbox'] : []), '--user-data-dir=' + path.join(temp, 'profile'), '--dump-dom',
      pathToFileURL(file).href], { encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024, windowsHide: true });
    assert.equal(run.status, 0, String(run.error || run.stderr));
    const match = run.stdout.match(/<pre id="result">([A-Za-z0-9+/=]+)<\/pre>/);
    assert.ok(match, 'Tarayıcı ölçüm üretmedi: ' + run.stdout.slice(-1000));
    return JSON.parse(Buffer.from(match[1], 'base64').toString('utf8'));
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

function overlaps(a, l, t, r, b) { return a.right > l + 0.5 && a.left < r - 0.5 && a.bottom > t + 0.5 && a.top < b - 0.5; }

test('kipler: yanına yazma kutusuz ve özgünün solunda, ikiz küçük ve üstte, eski gönderi örtme', { skip: !browser && 'tarayıcı yok' }, () => {
  const drawn = render(); if (process.env.DUMP) console.log(JSON.stringify(drawn.map(e => [e.text, e.cls, e.lines.map(l => [l.text, l.left, l.right])])));
  // Sıra: ikiz panel önce, sonra öğeler.
  const panel = drawn.find(el => / twin/.test(el.cls) && !el.lines.length);
  assert.ok(panel, 'ikiz panel çizilir: ' + drawn.map(el => el.cls).join(' | '));
  assert.ok(drawn.indexOf(panel) < drawn.findIndex(el => el.text === 'Jason'), 'panel yazılardan önce');
  const beside = drawn.find(el => el.text === 'SELAMLA');
  const name = drawn.find(el => el.text === 'Jason');
  const message = drawn.find(el => el.text === 'Uyandın mı, iyi misin?');
  const old = drawn.find(el => el.text === 'ESKİ'), missing = drawn.find(el => el.text === 'EKSİK');

  // Yanına yazma.
  assert.equal(beside.bg, 'rgba(0, 0, 0, 0)', 'kutu yok: ' + beside.bg);
  assert.notEqual(beside.shadow, 'none', 'okunurluk konturu var');
  assert.ok(!overlaps(beside, 1000, 500, 1100, 540), 'özgün yazı açık kalır');
  assert.ok(beside.lines[0].right <= 980 + 1 && beside.lines[0].right >= 980 - 3, 'özgüne yaslı: ' + beside.lines[0].right);
  assert.ok(Math.abs(beside.top - 500) <= 1 && Math.abs(beside.bottom - 540) <= 1, 'aynı satır');
  assert.ok(Math.abs(beside.font - 0.95 * 40) <= 0.5, 'aynı yazı boyu: ' + beside.font);
  assert.equal(beside.lines[0].text, 'SELAMLA', 'büyük harf korunur');

  // İkiz.
  assert.equal(panel.bg, 'rgb(226, 235, 210)', 'özgün zemin rengi');
  assert.ok(parseFloat(panel.radius) >= 19, 'yuvarlak köşe: ' + panel.radius);
  assert.equal(panel.bottomLeft, '0px', 'kuyruklu köşe köşeli');
  assert.ok(panel.tail, 'kuyruk çizilir');
  assert.ok(Math.abs(panel.left - 1400) <= 1, 'sol kenar özgünle hizalı');
  assert.ok(panel.bottom <= 800, 'özgün balonun üstünde, örtmez');
  assert.ok(panel.right < 1800 - 50, 'genişlik içeriğe göre (özgünden dar): ' + panel.right);
  assert.ok(panel.right >= message.lines[0].right, 'yazı panelin içinde');
  assert.ok(panel.img && Math.abs(panel.img.left - 1412) <= 1 && panel.img.radius === '50%', 'kişi resmi yuvarlak: ' + JSON.stringify(panel.img));
  for (const el of [name, message]) {
    assert.equal(el.bg, 'rgba(0, 0, 0, 0)', el.text + ': yazının kendi kutusu yok');
    assert.ok(!overlaps(el, 1400, 800, 1800, 960), el.text + ': özgün balon örtülmez');
    assert.ok(Math.abs(el.font - 0.95 * 40 * 0.58) <= 0.5, el.text + ': yazı 0,58 katında: ' + el.font);
  }

  // Eski/eksik gönderi: örtme.
  for (const el of [old, missing]) {
    assert.match(el.bg, /^rgb\(/, el.text + ': opak örtü');
    assert.ok(Math.abs(el.left - 198) <= 1, el.text + ': örtünün yerinde');
  }
});

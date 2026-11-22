// SPDX-License-Identifier: AGPL-3.0-only
// #1055 (LG OLED C4): çeviri sırasında ekran kararıp "HDR" yazısıyla geri geliyordu. Aynı HDMI girişini yeniden açmak
// <video>'yu bırakıp yeniden kurar (webOS platform.showHdmi); TV uygulaması 0.9.80'den beri bilgisayarın/telefonun
// bildirdiği giriş (açılış parametresi `hdmi`, stil `hdmiInput`) zaten gösterilen girişse görüntüye dokunulmaz. Kumandayla
// seçim ve farklı giriş eskisi gibi açılır. Sayfa app.js'i ortak kullanır (scripts/tv-live-page.js).
// Çalıştırma: node --test scripts/tv-hdmi-reselect.test.js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startPage } = require('./tv-live-page');

test('bilgisayarın bildirdiği giriş zaten açıksa görüntü yeniden kurulmaz; başka giriş açılır', () => {
  const page = startPage({ params: null, port: 2 });
  try {
    const before = page.shownPorts();
    assert.deepEqual(before.slice(-1), [2]);
    // Bekçi uygulamayı aynı girişle yeniden açtı (her yeniden açışta aynı değer): görüntüye dokunulmaz.
    for (let i = 0; i < 5; i++) page.relaunch({ hdmi: 2 });
    assert.equal(page.shownPorts().length, before.length);
    assert.equal(page.stored('hdmi'), '2');
    // Başka giriş bildirildi: o giriş açılır.
    page.relaunch({ hdmi: 3 });
    assert.deepEqual(page.shownPorts().slice(before.length), [3]);
  } finally {
    page.close();
  }
});

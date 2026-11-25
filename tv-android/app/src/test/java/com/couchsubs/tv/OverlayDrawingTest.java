// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

/** #1074: katman penceresi donanımla çizilirken süreç çökerse (EGL_BAD_ALLOC) sonraki açılış yazılımla çizer. */
public class OverlayDrawingTest {
    /** SharedPreferences yerine; süreç ölünce de kalan disk. */
    private static final class Disk implements OverlayDrawing.Store {
        final Map<String, Boolean> values = new HashMap<>();

        @Override
        public boolean get(String key) { return Boolean.TRUE.equals(values.get(key)); }

        @Override
        public void put(String key, boolean value) { values.put(key, value); }
    }

    @Test
    public void firstWindowDrawsWithHardware() {
        OverlayDrawing drawing = new OverlayDrawing(new Disk());
        assertFalse(drawing.software());
        assertEquals("draw hw", drawing.diagnostics());
    }

    @Test
    public void crashWhileDrawingWithHardwareSwitchesToSoftwareForGood() {
        Disk disk = new Disk();
        OverlayDrawing first = new OverlayDrawing(disk);
        first.windowShown(1_000);
        first.inputOpened(1_500);
        // Philips 55PUS7503: HDMI açıkken ilk çizimde süreç ölür; survived/closed hiç çağrılmaz.
        assertTrue(first.proves(4_000));

        OverlayDrawing next = new OverlayDrawing(disk);
        assertTrue(next.software());
        assertEquals("draw software (crash)", next.diagnostics());
        next.windowShown(50_000);
        assertFalse("yazılımlı pencere deneme sayılmaz", next.proves(80_000));
        next.closed();

        OverlayDrawing later = new OverlayDrawing(disk);
        assertTrue("bu TV için saklandı", later.software());
        assertEquals("draw software (saved)", later.diagnostics());
    }

    @Test
    public void hardwareThatSurvivesWithHdmiOpenStaysHardware() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk);
        drawing.windowShown(1_000);
        assertEquals("draw hw checking", drawing.diagnostics());
        // HDMI açılmadan önceki çizim kanıt değil.
        assertFalse(drawing.proves(1_200));
        drawing.inputOpened(2_000);
        assertFalse("giriş yeni açıldı", drawing.proves(3_000));
        assertTrue(drawing.proves(2_000 + OverlayDrawing.INPUT_SETTLE_MS));
        drawing.survived();
        assertFalse(drawing.proves(60_000));
        assertEquals("draw hw", drawing.diagnostics());

        // Süreç sonra başka nedenle ölse de (TV kapandı) yazılıma geçilmez.
        assertFalse(new OverlayDrawing(disk).software());
    }

    @Test
    public void withoutKnownInputADrawAfterTheSettleTimeProves() {
        OverlayDrawing drawing = new OverlayDrawing(new Disk());
        drawing.windowShown(1_000);
        assertFalse(drawing.proves(1_000 + OverlayDrawing.SETTLE_MS - 1));
        assertTrue(drawing.proves(1_000 + OverlayDrawing.SETTLE_MS));
    }

    @Test
    public void cleanCloseBeforeProofDoesNotCountAsCrash() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk);
        drawing.windowShown(1_000);
        drawing.closed();
        assertFalse(new OverlayDrawing(disk).software());
    }

    @Test
    public void rendererCrashWithHardwareMakesTheNextWindowSoftware() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk);
        drawing.windowShown(1_000);
        assertTrue(drawing.rendererCrashed());
        assertTrue(drawing.software());
        assertEquals("draw software (renderer)", drawing.diagnostics());
        // Yazılımla da çökerse yapılacak başka bir şey yok (PageRestarts sınırlar).
        drawing.windowShown(5_000);
        assertFalse(drawing.rendererCrashed());
        assertTrue(new OverlayDrawing(disk).software());
    }

    // #1255, #1259: deneme sırasında süreci öldüren sıradan olay (güncelleme, kapatıp açma, TV'nin kapanması) katmanı
    // kalıcı olarak yazılım çizimine geçiriyordu; o modda altyazı yatayda ezik çiziliyordu.
    @Test
    public void processKilledDuringTrialWithoutNativeCrashStaysHardware() {
        Disk disk = new Disk();
        OverlayDrawing first = new OverlayDrawing(disk, false);
        first.windowShown(1_000);
        // Süreç burada güncelleme ya da force-stop ile ölür: survived/closed çağrılmaz.
        OverlayDrawing next = new OverlayDrawing(disk, false);
        assertFalse(next.software());
        assertEquals("draw hw", next.diagnostics());
        assertFalse("deneme işareti temizlendi", disk.get(OverlayDrawing.KEY_HARDWARE_TRYING));
    }

    @Test
    public void nativeCrashDuringTrialSwitchesToVerifiedSoftware() {
        Disk disk = new Disk();
        new OverlayDrawing(disk, false).windowShown(1_000);
        OverlayDrawing next = new OverlayDrawing(disk, true);
        assertTrue(next.software());
        assertEquals("draw software (crash)", next.diagnostics());
        // Doğrulanmış tercih sonraki açılışlarda silinmez.
        OverlayDrawing later = new OverlayDrawing(disk, false);
        assertTrue(later.software());
        assertEquals("draw software (saved)", later.diagnostics());
    }

    @Test
    public void unverifiedSoftwareFromOlderVersionIsRetriedOnceWithHardware() {
        Disk disk = new Disk();
        // 0.9.106 ve öncesi yalnız overlaySoftware yazıyordu.
        disk.put(OverlayDrawing.KEY_SOFTWARE, true);
        OverlayDrawing drawing = new OverlayDrawing(disk, false);
        assertFalse(drawing.software());
        assertEquals("draw hw (rechecked)", drawing.diagnostics());
        assertFalse(disk.get(OverlayDrawing.KEY_SOFTWARE));
        drawing.windowShown(1_000);
        assertEquals("draw hw checking (rechecked)", drawing.diagnostics());
        // Donanım gerçekten çöküyorsa bir sonraki açılış yazılıma döner ve öyle kalır.
        assertTrue(new OverlayDrawing(disk, true).software());
        assertTrue(new OverlayDrawing(disk, false).software());
    }

    @Test
    public void withoutExitReasonsOlderTvsKeepTheOldBehaviour() {
        // Android 10 ve öncesi (Philips 55PUS7503, Android 8): neden bilinmez, saklı tercih kalır.
        Disk disk = new Disk();
        disk.put(OverlayDrawing.KEY_SOFTWARE, true);
        assertTrue(new OverlayDrawing(disk, null).software());
        Disk tried = new Disk();
        new OverlayDrawing(tried, null).windowShown(1_000);
        assertTrue(new OverlayDrawing(tried, null).software());
    }

    @Test
    public void rendererCrashSoftwareIsKept() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk, false);
        drawing.windowShown(1_000);
        assertTrue(drawing.rendererCrashed());
        assertTrue(new OverlayDrawing(disk, false).software());
    }
}

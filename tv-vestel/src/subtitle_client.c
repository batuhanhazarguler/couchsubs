/* CouchSubs — Vestel MB130 yerel DirectFB canlı altyazı istemcisi (Stage 6).
 *
 * TV'den CouchSubs bilgisayarına BAĞLANIR (dışa bağlantı; TV'de port açmaz).
 * GET /hello ile tanır, GET /events SSE akışını dinler, subtitle/clear/style/exit olaylarını
 * işler. DirectFBInit/Create bir kez; tek band pencere yeniden kullanılır (yalnız kendi yüzeyi).
 * Güvenlik: session=0 + force-slave + DLSCL_SHARED + ghost/no-focus (Stage 4B/5A'dan kanıtlı).
 *
 * Ağ/SSE döngüsü DirectFB'den bağımsızdır; HOST_TEST ile renderer printf stub'a döner ve Mac'te
 * sahte sunucuya karşı çalışır (bkz. test/fake_couchsubs.py).
 *
 * TV derleme : arm-linux-gnueabi-gcc -I dfb-include -Os -o couchsubs-tv src/subtitle_client.c src/sse.c -ldl
 * Host test  : cc -DHOST_TEST -Isrc -o couchsubs-host src/subtitle_client.c src/sse.c
 * SPDX-License-Identifier: AGPL-3.0-only
 */
#define _POSIX_C_SOURCE 200809L
#include "sse.h"
#include "pair.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/select.h>

#ifndef HOST_TEST
#include <stddef.h>
#include <dlfcn.h>
#include <directfb.h>
_Static_assert(offsetof(IDirectFB, Release) == 12, "Release offset != 12 (ARM32)");
#endif

#define SCREEN_W 1920
#define SCREEN_H 1080
#define BAND_W   1760
#define BAND_H   320
#define BAND_X   ((SCREEN_W - BAND_W) / 2)
#define PAD_X    28
#define PAD_Y    14
#define LINE_GAP 8
#define INNER_BOTTOM 12
#define FONT_PATH "/vendor/fonts/OpenSans-Regular.ttf"
#define BOLD_FONT_PATH "/vendor/fonts/OpenSans-Bold.ttf"   /* TV'de mevcut (21.11): aynı aile bold */
#define STREAM_TIMEOUT_MS 45000   /* ping 15s; 3 kayıp ping sonrası yeniden bağlan */
#define RECONNECT_MS      2000
#define REGION_MAX     3          /* ek alan sayısı (CouchSubs ExtraArea.maxCount ile aynı) */
#define REGION_W       820        /* ek alan penceresi (şeffaf tuval; görünen kutu içine çizilir) */
#define REGION_H       260
#define REGION_FONT_PX 30
#define RPAD           16

/* ---- durum ---- */
static SubStyle g_style = { 46, 7, 90, 0, "white", "cover", 1, 0 };
static char g_text[SSE_TEXT_MAX];                                    /* güncel altyazı satırı (yığma kararı için) */
static char g_disp[SSE_TEXT_MAX];                                    /* ekranda gösterilen (yığıldıysa önceki + güncel) */
static long long g_shown_at;                                        /* güncel altyazının gösterilme anı (yığma penceresi) */
static int  g_paragraphs;                                           /* güncel altyazı çok satırlı panel mi (yığma dışı) */
#define CONDENSE_SCALE 0.85    /* condensed: metin genişliği bu orana iner (harfler oranlı küçülür, iç içe geçmez) */
static SseSpeaker g_speakers[SPEAKERS_MAX]; static int g_nspeakers;   /* gösterilen satırların ad renkleri (güncel + yığıldıysa önceki) */
static double g_subbox[4]; static int g_have_subbox;                 /* son altyazının İngilizce yeri (placement) */
#define STACK_WITHIN_MS 1500   /* yeni altyazı bu süre içinde gelirse önceki üstte kalır (webOS ile aynı) */
static int  g_visible = 0;
static long long g_hide_at = 0;
static long long g_screen_hide_at = 0;   /* "Ekranı çevir" öğeleri bu anda kalkar (0: screen-clear'e kadar) */
static volatile sig_atomic_t g_quit = 0, g_exit_evt = 0;

static long long now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
static void sleep_ms(int ms) { struct timespec t = { ms / 1000, (long)(ms % 1000) * 1000000 }; nanosleep(&t, 0); }

/* Satır başı "Ad:" (ya da tam-genişlik "Ad：") bir konuşana uyuyorsa boyanacak önek bayt sayısını döner (0=yok),
   *color'a o konuşanın rengini yazar. En uzun ad eşleşmesi kazanır (webOS speakerSegments ile aynı). */
static int speaker_prefix_len(const char *line, unsigned *color) {
    int best = 0;
    for (int i = 0; i < g_nspeakers; i++) {
        const char *nm = g_speakers[i].name;
        int L = (int)strlen(nm);
        if (L == 0 || strncmp(line, nm, (size_t)L) != 0) continue;
        const char *p = line + L;
        if (*p == ' ') p++;
        int clen = 0;
        if (*p == ':') clen = (int)(p - line) + 1;
        else if ((unsigned char)p[0] == 0xEF && (unsigned char)p[1] == 0xBC && (unsigned char)p[2] == 0x9A)
            clen = (int)(p - line) + 3;                 /* tam-genişlik ： (U+FF1A) */
        if (clen > best) { best = clen; *color = g_speakers[i].color; }
    }
    return best;
}

/* ================= RENDERER ================= */
#ifdef HOST_TEST
static int  render_init(void) { printf("[render] init (host stub)\n"); return 0; }
static void render_show(const char *text, const SubStyle *st) {
    char flat[SSE_TEXT_MAX]; int o = 0;        /* çok satırlıyı tek satırda yaz ('\n' -> '|') */
    for (const char *s = text; *s && o < (int)sizeof(flat) - 1; s++) flat[o++] = (*s == '\n') ? '|' : *s;
    flat[o] = 0;
    printf("[render] SHOW font=%d bg=%d bottom%%=%d color=%s bold=%d placement=%s band=%d para=%d speakers=%d stack=%d text=\"%s\"\n",
           st->fontSize, st->background, st->bottomPercent, st->textColor, st->bold,
           st->placement[0] ? st->placement : "?", g_style.bandShape, g_paragraphs, g_nspeakers, g_style.stackPrevious, flat);
    if (g_have_subbox) printf("[render] BOX %.3f,%.3f,%.3f,%.3f place=%s\n",
                              g_subbox[0], g_subbox[1], g_subbox[2], g_subbox[3],
                              st->placement[0] ? st->placement : "cover");
    /* ad rengi satır-satır (gerçek renderer gibi; yığmada ad ikinci satırda olabilir) */
    const char *line = text;
    while (line) {
        unsigned c; int pl = speaker_prefix_len(line, &c);
        if (pl > 0) printf("[render] NAME \"%.*s\" color=%06x\n", pl, line, c);
        const char *nl = strchr(line, '\n');
        line = nl ? nl + 1 : NULL;
    }
}
static void render_hide(void) { printf("[render] HIDE\n"); }
static void render_deinit(void) { printf("[render] deinit\n"); }
/* Box'tan pencere yeri/genişliği (gerçek renderer ile aynı hesap; köşe alanların doğru yerleştiğini testlemek için). */
static void panel_geom(const double box[4], int *x, int *w) {
    *x = (int)(box[0] * 1920); if (*x < 0) *x = 0; if (*x > 1919) *x = 1919;
    *w = (int)((box[2] - box[0]) * 1920); if (*w < 160) *w = 160; if (*w > 1920 - *x) *w = 1920 - *x;
}
static void region_show(const char *id, const char *text, const double box[4], double line) {
    int x, w; panel_geom(box, &x, &w);
    printf("[region] SHOW id=%s box=%.3f,%.3f,%.3f,%.3f x=%d w=%d line=%.3f text=\"%s\"\n",
           id, box[0], box[1], box[2], box[3], x, w, line, text);
}
static void region_hide(const char *id) { printf("[region] HIDE id=%s\n", id); }
static void regions_clear(void) { printf("[region] CLEAR-ALL\n"); }
static void screen_show(int idx, const char *text, const double box[4], double line, int haveSurf, unsigned bg, unsigned fg, int bold, int cond) {
    int x, w; panel_geom(box, &x, &w);
    printf("[screen] SHOW id=scr%d box=%.3f,%.3f,%.3f,%.3f x=%d w=%d line=%.3f surf=%d bg=%06x fg=%06x bold=%d cond=%d text=\"%s\"\n",
           idx, box[0], box[1], box[2], box[3], x, w, line, haveSurf, bg, fg, bold, cond, text);
}
static void screen_clear(void) { printf("[screen] CLEAR-ALL\n"); }
static void blocks_show(const char *id, const char *text, const double box[4], double line, int haveSurf, unsigned bg, unsigned fg, int bold, int cond) {
    int x, w; panel_geom(box, &x, &w);
    printf("[blocks] SHOW id=%s box=%.3f,%.3f,%.3f,%.3f x=%d w=%d line=%.3f surf=%d bg=%06x fg=%06x bold=%d cond=%d text=\"%s\"\n",
           id, box[0], box[1], box[2], box[3], x, w, line, haveSurf, bg, fg, bold, cond, text);
}
static void blocks_clear(const char *prefix) { printf("[blocks] CLEAR id=%s#\n", prefix); }
static void blocks_clear_all(void) { printf("[blocks] CLEAR-ALL\n"); }
#else
typedef DFBResult   (*InitFn)(int *, char *(*[]));
typedef DFBResult   (*CreateFn)(IDirectFB **);
typedef const char *(*ErrStrFn)(DFBResult);
typedef DFBResult   (*ConfigSetFn)(const char *, const char *);
static void *R_h;
static IDirectFB *R_dfb; static IDirectFBDisplayLayer *R_layer;
static IDirectFBWindow *R_win; static IDirectFBSurface *R_surf; static IDirectFBFont *R_font;
static IDirectFBFont *R_bfont; static int R_font_px, R_bfont_px; static int R_bfont_gone;  /* bold yüklenemedi */
static IDirectFBFont *R_active;      /* ölçüm hangi yüze göre yapılacak (regular/bold) */
static InitFn R_Init; static CreateFn R_Create; static ErrStrFn R_Err; static ConfigSetFn R_Cfg;
#define RERR(r) (R_Err ? R_Err(r) : "?")
static void render_hide(void);   /* render_show içinde kullanılıyor */

static int R_measure(void *ctx, const char *s, int bytes) {
    (void)ctx; int w = 0;
    IDirectFBFont *f = R_active ? R_active : R_font;
    if (!f) return -1;
    if (f->GetStringWidth(f, s, bytes, &w) != 0) return -1;
    return w;
}
static void ensure_font(int px) {
    if (px < 12) px = 12; if (px > 120) px = 120;
    if (R_font && R_font_px == px) return;
    if (R_font) { R_font->Release(R_font); R_font = NULL; }
    DFBFontDescription fd; fd.flags = DFDESC_HEIGHT; fd.height = px;
    if (R_dfb->CreateFont(R_dfb, FONT_PATH, &fd, &R_font) != 0) { R_font = NULL; return; }
    R_font_px = px;
}
/* Gerçek bold font (aynı aile; TV'de varsa). Yoksa NULL döner → çağıran faux-bold'a düşer. */
static IDirectFBFont *ensure_bfont(int px) {
    if (R_bfont_gone) return NULL;
    if (px < 12) px = 12; if (px > 120) px = 120;
    if (R_bfont && R_bfont_px == px) return R_bfont;
    if (R_bfont) { R_bfont->Release(R_bfont); R_bfont = NULL; }
    DFBFontDescription fd; fd.flags = DFDESC_HEIGHT; fd.height = px;
    if (R_dfb->CreateFont(R_dfb, BOLD_FONT_PATH, &fd, &R_bfont) != 0) { R_bfont = NULL; R_bfont_gone = 1; return NULL; }
    R_bfont_px = px;
    return R_bfont;
}
static int render_init(void) {
    R_h = dlopen("/usr/lib/libdirectfb.so", RTLD_NOW | RTLD_LOCAL);
    if (!R_h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    R_Init = (InitFn) dlsym(R_h, "DirectFBInit");
    R_Create = (CreateFn) dlsym(R_h, "DirectFBCreate");
    R_Err = (ErrStrFn) dlsym(R_h, "DirectFBErrorString");
    R_Cfg = (ConfigSetFn) dlsym(R_h, "dfb_config_set");
    if (!R_Init || !R_Create || !R_Cfg) { fprintf(stderr, "sembol yok\n"); return 1; }
    char *prog = "couchsubs"; char *av[] = { prog, NULL }; int ac = 1; char **avp = av;
    DFBResult r = R_Init(&ac, &avp);
    if (r != 0) { fprintf(stderr, "DirectFBInit %d\n", r); return 1; }
    if (R_Cfg("session", "0") != 0 || R_Cfg("force-slave", NULL) != 0) {
        fprintf(stderr, "guvenlik ayarlari reddedildi\n"); return 1; }
    R_Cfg("no-cursor", NULL);
    if ((r = R_Create(&R_dfb)) != 0 || !R_dfb) { fprintf(stderr, "DirectFBCreate %d (%s)\n", r, RERR(r)); return 1; }
    if (R_dfb->GetDisplayLayer(R_dfb, DLID_PRIMARY, &R_layer) != 0) { fprintf(stderr, "GetDisplayLayer\n"); return 1; }
    if (R_layer->SetCooperativeLevel(R_layer, DLSCL_SHARED) != 0) { fprintf(stderr, "SetCoopLevel\n"); return 1; }
    DFBWindowDescription wd;
    wd.flags = DWDESC_CAPS | DWDESC_WIDTH | DWDESC_HEIGHT | DWDESC_PIXELFORMAT | DWDESC_POSX | DWDESC_POSY | DWDESC_OPTIONS;
    wd.caps = DWCAPS_ALPHACHANNEL | DWCAPS_NOFOCUS;
    wd.options = DWOP_GHOST | DWOP_ALPHACHANNEL;
    wd.width = BAND_W; wd.height = BAND_H; wd.pixelformat = DSPF_ARGB;
    wd.posx = BAND_X; wd.posy = SCREEN_H - BAND_H - 20;
    if (R_layer->CreateWindow(R_layer, &wd, &R_win) != 0 || !R_win) { fprintf(stderr, "CreateWindow\n"); return 1; }
    if (R_win->GetSurface(R_win, &R_surf) != 0 || !R_surf) { fprintf(stderr, "GetSurface\n"); return 1; }
    R_win->SetOpacity(R_win, 0x00);
    R_surf->Clear(R_surf, 0, 0, 0, 0); R_surf->Flip(R_surf, NULL, DSFLIP_NONE);
    fprintf(stderr, "[render] DirectFB band pencere hazir (%dx%d)\n", BAND_W, BAND_H);
    return 0;
}
static void render_show(const char *text, const SubStyle *st) {
    if (!R_surf || !R_win) return;
    int px = st->fontSize > 0 ? st->fontSize : 46;
    ensure_font(px);
    if (!R_font) return;
    /* bold: gerçek bold font varsa onu kullan; yoksa faux-bold (çift çizim). */
    IDirectFBFont *face = R_font; int fauxBold = 0;
    if (st->bold) { IDirectFBFont *b = ensure_bfont(px); if (b) face = b; else fauxBold = 1; }
    R_active = face;
    static char lines[WRAP_MAX_LINES][WRAP_MAX_BYTES];
    int maxw = BAND_W - 2 * PAD_X;
    int n = wrap_text(text, lines, WRAP_MAX_LINES, maxw, R_measure, NULL);
    if (n <= 0) { render_hide(); return; }
    int line_h = 0; if (face->GetHeight(face, &line_h) != 0 || line_h <= 0) line_h = px + 8;
    int block_w = 0;
    for (int i = 0; i < n; i++) { int w = R_measure(NULL, lines[i], -1); if (w > block_w) block_w = w; }
    int box_w = block_w + 2 * PAD_X; if (box_w > BAND_W) box_w = BAND_W;
    if (st->bandShape > 0) box_w = BAND_W;    /* backgroundShape=band: tam genişlik bant (yazı ortalı) */
    int box_h = n * line_h + (n - 1) * LINE_GAP + 2 * PAD_Y; if (box_h > BAND_H) box_h = BAND_H;
    int box_x = (BAND_W - box_w) / 2;
    int box_y = BAND_H - box_h - INNER_BOTTOM;
    /* placement: cover/above/below İngilizce altyazının yerine (`g_subbox`) göre; fixed ya da kutu yoksa bottomPercent.
       shortcut: yatayda band hep ortalı (altyazılar ortalı gelir); yatay kaydırma sonraki tura. */
    int posy;
    int useBox = g_have_subbox && st->placement[0] && strcmp(st->placement, "fixed") != 0;
    if (useBox) {
        int top = (int)(g_subbox[1] * SCREEN_H), bot = (int)(g_subbox[3] * SCREEN_H);
        if (strcmp(st->placement, "above") == 0)      posy = top - (box_y + box_h);   /* metin altı box.top'ta */
        else if (strcmp(st->placement, "below") == 0) posy = bot - box_y;             /* metin üstü box.bottom'ta */
        else { int cy = (top + bot) / 2; posy = cy - (box_y + box_h / 2); }           /* cover: metin ortası box ortasında */
    } else {
        /* bottomPercent: kutu altının ekran altından uzaklığı. */
        int pct = st->bottomPercent >= 0 ? st->bottomPercent : 7;
        posy = SCREEN_H - (pct * SCREEN_H / 100) - (box_y + box_h);
    }
    if (posy < 0) posy = 0; if (posy > SCREEN_H - BAND_H) posy = SCREEN_H - BAND_H;
    R_win->MoveTo(R_win, BAND_X, posy);
    /* çiz: şeffaf temizle → yarı saydam siyah kutu → beyaz/sarı metin (yalnız kendi yüzey) */
    R_surf->Clear(R_surf, 0, 0, 0, 0);
    int bg = st->background >= 0 ? st->background : 90;
    if (bg > 0) {
        int a = bg * 255 / 100; if (a > 255) a = 255;
        R_surf->SetDrawingFlags(R_surf, DSDRAW_NOFX);
        R_surf->SetColor(R_surf, 0, 0, 0, (unsigned char)a);
        R_surf->FillRectangle(R_surf, box_x, box_y, box_w, box_h);
    }
    int yellow = (strcmp(st->textColor, "yellow") == 0);
    unsigned char dr = 0xFF, dg = 0xFF, db = yellow ? 0x00 : 0xFF;   /* varsayılan metin rengi */
    R_surf->SetFont(R_surf, face);
    for (int i = 0; i < n; i++) {
        int ty = box_y + PAD_Y + i * (line_h + LINE_GAP);
        int tx = box_x + box_w / 2;
        unsigned sc; int plen = speaker_prefix_len(lines[i], &sc);
        if (plen <= 0) {
            /* tek renk, ortalı */
            R_surf->SetColor(R_surf, dr, dg, db, 0xFF);
            R_surf->DrawString(R_surf, lines[i], -1, tx, ty, DSTF_TOPCENTER);
            if (fauxBold) R_surf->DrawString(R_surf, lines[i], -1, tx + 1, ty, DSTF_TOPCENTER);
        } else {
            /* "Ad:" konuşan renginde, kalanı varsayılan renkte — sola yaslı iki parça (ortalı bloktan başla) */
            int lw = R_measure(NULL, lines[i], -1); if (lw < 0) lw = 0;
            int lx = tx - lw / 2;
            int nameW = R_measure(NULL, lines[i], plen); if (nameW < 0) nameW = 0;
            R_surf->SetColor(R_surf, (sc >> 16) & 0xFF, (sc >> 8) & 0xFF, sc & 0xFF, 0xFF);
            R_surf->DrawString(R_surf, lines[i], plen, lx, ty, DSTF_TOPLEFT);
            if (fauxBold) R_surf->DrawString(R_surf, lines[i], plen, lx + 1, ty, DSTF_TOPLEFT);
            R_surf->SetColor(R_surf, dr, dg, db, 0xFF);
            R_surf->DrawString(R_surf, lines[i] + plen, -1, lx + nameW, ty, DSTF_TOPLEFT);
            if (fauxBold) R_surf->DrawString(R_surf, lines[i] + plen, -1, lx + nameW + 1, ty, DSTF_TOPLEFT);
        }
    }
    R_active = NULL;
    R_surf->Flip(R_surf, NULL, DSFLIP_NONE);
    R_win->SetOpacity(R_win, 0xFF);
}
static void render_hide(void) {
    if (R_surf) { R_surf->Clear(R_surf, 0, 0, 0, 0); R_surf->Flip(R_surf, NULL, DSFLIP_NONE); }
    if (R_win) R_win->SetOpacity(R_win, 0x00);
}
/* ---- ek alanlar: her alan için küçük, kendi yüzeyli bir ghost pencere (band ile aynı kanıtlı desen) ---- */
typedef struct { char id[64]; IDirectFBWindow *win; IDirectFBSurface *surf; int w, h; } Region;
static Region R_reg[REGION_MAX];              /* canlı ek alanlar (birleşik metin) */
static Region R_scr[SCREEN_ITEMS_MAX];        /* "Ekranı çevir" öğeleri (ayrı havuz) */
static Region R_blk[SCREEN_ITEMS_MAX];        /* ek alan blokları ("id#n" anahtarlı; ayrı havuz) */
static IDirectFBFont *R_rfont; static int R_rfont_px;

static int rfont_measure(void *ctx, const char *s, int bytes) {
    (void)ctx; int w = 0;
    if (!R_rfont) return -1;
    if (R_rfont->GetStringWidth(R_rfont, s, bytes, &w) != 0) return -1;
    return w;
}
/* Ek alan fontu, box'ın satır yüksekliğine göre (özgün yazı boyutuyla eşleşsin). px değişince yeniden kurulur. */
static void ensure_rfont(int px) {
    if (px < 16) px = 16; if (px > 72) px = 72;
    if (R_rfont && R_rfont_px == px) return;
    if (R_rfont) { R_rfont->Release(R_rfont); R_rfont = NULL; }
    DFBFontDescription fd; fd.flags = DFDESC_HEIGHT; fd.height = px;
    if (R_dfb->CreateFont(R_dfb, FONT_PATH, &fd, &R_rfont) != 0) { R_rfont = NULL; return; }
    R_rfont_px = px;
}
static int make_window(int w, int h, int x, int y, IDirectFBWindow **win, IDirectFBSurface **surf) {
    DFBWindowDescription wd;
    wd.flags = DWDESC_CAPS | DWDESC_WIDTH | DWDESC_HEIGHT | DWDESC_PIXELFORMAT | DWDESC_POSX | DWDESC_POSY | DWDESC_OPTIONS;
    wd.caps = DWCAPS_ALPHACHANNEL | DWCAPS_NOFOCUS;
    wd.options = DWOP_GHOST | DWOP_ALPHACHANNEL;
    wd.width = w; wd.height = h; wd.pixelformat = DSPF_ARGB; wd.posx = x; wd.posy = y;
    if (R_layer->CreateWindow(R_layer, &wd, win) != 0 || !*win) return 1;
    if ((*win)->GetSurface(*win, surf) != 0 || !*surf) { (*win)->Release(*win); *win = NULL; return 1; }
    (*win)->SetOpacity(*win, 0x00);
    (*surf)->Clear(*surf, 0, 0, 0, 0); (*surf)->Flip(*surf, NULL, DSFLIP_NONE);
    return 0;
}
static Region *pool_slot(Region *pool, int size, const char *id) {
    for (int i = 0; i < size; i++)
        if (pool[i].win && !strcmp(pool[i].id, id)) return &pool[i];
    return NULL;
}
static void region_destroy(Region *r) {
    if (r->surf) { r->surf->Release(r->surf); r->surf = NULL; }
    if (r->win) { r->win->SetOpacity(r->win, 0x00); r->win->Destroy(r->win); r->win->Release(r->win); r->win = NULL; }
    r->id[0] = 0;
}
static void pool_clear(Region *pool, int size) { for (int i = 0; i < size; i++) if (pool[i].win) region_destroy(&pool[i]); }
static void region_hide(const char *id) { Region *r = pool_slot(R_reg, REGION_MAX, id); if (r) region_destroy(r); }
static void regions_clear(void) { pool_clear(R_reg, REGION_MAX); }
static void screen_clear(void) { pool_clear(R_scr, SCREEN_ITEMS_MAX); }
static void blocks_clear_all(void) { pool_clear(R_blk, SCREEN_ITEMS_MAX); }
/* Yalnız "<prefix>#" ile başlayan blok pencerelerini kaldır (o ek alanın blokları). */
static void blocks_clear(const char *prefix) {
    size_t pl = strlen(prefix);
    for (int i = 0; i < SCREEN_ITEMS_MAX; i++)
        if (R_blk[i].win && !strncmp(R_blk[i].id, prefix, pl) && R_blk[i].id[pl] == '#') region_destroy(&R_blk[i]);
}

/* Bir pool slot'una yarı saydam kutu + metin çizer. haveSurf=0 → varsayılan siyah kutu (%90) + beyaz yazı;
   haveSurf=1 → özgün renkler (bg kutu, fg yazı; kutu neredeyse opak). bold → faux-bold (çift çizim).
   condensed → metni yatayda %85 sıkıştır (DirectFB SetMatrix; desteklenmezse normal genişlikte çizilir). */
static void panel_draw(Region *pool, int size, const char *id, const char *text, const double box[4],
                       double line, int haveSurf, unsigned bg, unsigned fg, int bold, int condensed) {
    if (!R_layer) return;
    /* font: box'ın satır yüksekliğine (`line`) göre — özgün yazı boyutuyla eşleşsin; yoksa varsayılan. */
    int px = line > 0 ? (int)(line * SCREEN_H * 0.95) : REGION_FONT_PX;
    ensure_rfont(px); if (!R_rfont) return;
    Region *r = pool_slot(pool, size, id);
    if (!r) { for (int i = 0; i < size; i++) if (!pool[i].win) { r = &pool[i]; break; } }
    if (!r) return;                                   /* havuz dolu: fazlasını atla */
    /* Pencere İngilizce yazının yerine (box sol-üst), box GENİŞLİĞİNDE; ekran kenarına sığdırılır.
       Böylece sol-alt/sağ-üst/sağ-alt gibi her köşedeki alan kendi yerinde kalır (sabit genişlik kaydırmıyor). */
    int x = (int)(box[0] * SCREEN_W), y = (int)(box[1] * SCREEN_H);
    if (x < 0) x = 0; if (y < 0) y = 0;
    if (x > SCREEN_W - 1) x = SCREEN_W - 1; if (y > SCREEN_H - 1) y = SCREEN_H - 1;
    int bw = (int)((box[2] - box[0]) * SCREEN_W);
    if (bw < 160) bw = 160;                           /* çok dar kutuda da okunur kalsın */
    if (bw > SCREEN_W - x) bw = SCREEN_W - x;          /* ekranın sağına taşmasın */
    static char lines[WRAP_MAX_LINES][WRAP_MAX_BYTES];
    int n = wrap_text(text, lines, WRAP_MAX_LINES, bw - 2 * RPAD, rfont_measure, NULL);
    if (n <= 0) { region_destroy(r); return; }
    int line_h = 0; if (R_rfont->GetHeight(R_rfont, &line_h) != 0 || line_h <= 0) line_h = px + 6;
    int bh = n * line_h + (n - 1) * LINE_GAP + 2 * RPAD;
    if (y + bh > SCREEN_H) bh = SCREEN_H - y;          /* ekranın altına taşmasın (kırpılır) */
    if (bh < line_h) bh = line_h;
    /* pencereyi oluştur; boyut değişmişse yeniden kur (DirectFB Resize yerine güvenli yeniden yaratma), yoksa taşı. */
    if (!r->win || r->w != bw || r->h != bh) {
        if (r->win) region_destroy(r);
        if (make_window(bw, bh, x, y, &r->win, &r->surf) != 0) { r->win = NULL; return; }
        strncpy(r->id, id, sizeof(r->id) - 1); r->id[sizeof(r->id) - 1] = 0;
        r->w = bw; r->h = bh;
    } else {
        r->win->MoveTo(r->win, x, y);
    }
    r->surf->Clear(r->surf, 0, 0, 0, 0);
    r->surf->SetDrawingFlags(r->surf, DSDRAW_NOFX);
    if (haveSurf) r->surf->SetColor(r->surf, (bg >> 16) & 0xFF, (bg >> 8) & 0xFF, bg & 0xFF, 0xF0);
    else          r->surf->SetColor(r->surf, 0, 0, 0, (unsigned char)(90 * 255 / 100));
    r->surf->FillRectangle(r->surf, 0, 0, bw, bh);
    r->surf->SetFont(r->surf, R_rfont);
    if (haveSurf) r->surf->SetColor(r->surf, (fg >> 16) & 0xFF, (fg >> 8) & 0xFF, fg & 0xFF, 0xFF);
    else          r->surf->SetColor(r->surf, 0xFF, 0xFF, 0xFF, 0xFF);
    /* condensed: yalnız metni yatayda 0.85 ölçekle (kutu dolgusundan SONRA; sol pad RPAD sabit kalsın diye öteleme).
       Desteklenmezse (eski/kısıtlı sürücü) SetRenderOptions hata döner, metin normal genişlikte çizilir. */
    int matrixOn = 0;
    if (condensed) {
        int f = (int)(CONDENSE_SCALE * 65536);   /* X' = f·X/65536 + sol pad sabit kalsın diye öteleme */
        s32 m[9] = { f, 0, (s32)(((1 << 16) - f) * RPAD), 0, 1 << 16, 0, 0, 0, 1 << 16 };
        if (r->surf->SetMatrix(r->surf, m) == DFB_OK && r->surf->SetRenderOptions(r->surf, DSRO_MATRIX) == DFB_OK)
            matrixOn = 1;
    }
    for (int i = 0; i < n; i++) {
        int ty = RPAD + i * (line_h + LINE_GAP);
        r->surf->DrawString(r->surf, lines[i], -1, RPAD, ty, DSTF_TOPLEFT);
        if (bold) r->surf->DrawString(r->surf, lines[i], -1, RPAD + 1, ty, DSTF_TOPLEFT);   /* faux-bold */
    }
    if (matrixOn) r->surf->SetRenderOptions(r->surf, DSRO_NONE);
    r->surf->Flip(r->surf, NULL, DSFLIP_NONE);
    r->win->SetOpacity(r->win, 0xFF);
}
static void region_show(const char *id, const char *text, const double box[4], double line) {
    panel_draw(R_reg, REGION_MAX, id, text, box, line, 0, 0, 0, 0, 0);
}
static void screen_show(int idx, const char *text, const double box[4], double line, int haveSurf, unsigned bg, unsigned fg, int bold, int cond) {
    char id[16]; snprintf(id, sizeof id, "scr%d", idx);
    panel_draw(R_scr, SCREEN_ITEMS_MAX, id, text, box, line, haveSurf, bg, fg, bold, cond);
}
static void blocks_show(const char *id, const char *text, const double box[4], double line, int haveSurf, unsigned bg, unsigned fg, int bold, int cond) {
    panel_draw(R_blk, SCREEN_ITEMS_MAX, id, text, box, line, haveSurf, bg, fg, bold, cond);
}

static void render_deinit(void) {
    regions_clear(); screen_clear(); blocks_clear_all();
    if (R_rfont) R_rfont->Release(R_rfont);
    if (R_font) R_font->Release(R_font);
    if (R_bfont) R_bfont->Release(R_bfont);
    if (R_surf) R_surf->Release(R_surf);
    if (R_win) { R_win->SetOpacity(R_win, 0x00); R_win->Destroy(R_win); R_win->Release(R_win); }
    if (R_layer) R_layer->Release(R_layer);
    if (R_dfb) R_dfb->Release(R_dfb);
    if (R_h) dlclose(R_h);
}
#endif

/* ================= style birleştirme + olay ================= */
static void merge_style(const SubStyle *in) {
    if (in->fontSize > 0) g_style.fontSize = in->fontSize;
    if (in->bottomPercent >= 0) g_style.bottomPercent = in->bottomPercent;
    if (in->background >= 0) g_style.background = in->background;
    g_style.bold = in->bold;
    if (in->textColor[0]) { strncpy(g_style.textColor, in->textColor, sizeof(g_style.textColor) - 1);
                            g_style.textColor[sizeof(g_style.textColor) - 1] = 0; }
    if (in->placement[0]) { strncpy(g_style.placement, in->placement, sizeof(g_style.placement) - 1);
                            g_style.placement[sizeof(g_style.placement) - 1] = 0; }
    if (in->stackPrevious >= 0) g_style.stackPrevious = in->stackPrevious;
    if (in->bandShape >= 0) g_style.bandShape = in->bandShape;
}
static void on_event(const SseEvent *e, void *u) {
    (void)u;
    switch (e->type) {
        case EV_SUBTITLE: {
            if (e->text[0] == 0) { render_hide(); g_visible = 0; g_hide_at = 0; g_text[0] = 0; g_disp[0] = 0;
                                   g_nspeakers = 0; g_have_subbox = 0; g_shown_at = 0; g_paragraphs = 0; break; }
            long long now = now_ms();
            /* stackPrevious: yeni satır öncekini kısa süre içinde (replace değil, aynı değil) takip ediyorsa önceki üstte kalır.
               En çok tek önceki satır tutulur (ekranı kaplamaz); çok satırlı paneller (paragraphs) yığılmaz. */
            int stack = g_style.stackPrevious && g_visible && g_text[0] && !e->replace
                        && !e->paragraphs && !g_paragraphs
                        && (now - g_shown_at < STACK_WITHIN_MS) && strcmp(g_text, e->text) != 0;
            /* gösterilen satırların ad renkleri: güncel + (yığıldıysa) önceki — speaker_prefix_len hepsini eşler */
            SseSpeaker merged[SPEAKERS_MAX]; int m = 0;
            for (int i = 0; i < e->nspeakers && m < SPEAKERS_MAX; i++) merged[m++] = e->speakers[i];
            if (stack) for (int i = 0; i < g_nspeakers && m < SPEAKERS_MAX; i++) merged[m++] = g_speakers[i];
            if (stack) snprintf(g_disp, sizeof g_disp, "%s\n%s", g_text, e->text);
            else { strncpy(g_disp, e->text, sizeof g_disp - 1); g_disp[sizeof g_disp - 1] = 0; }
            strncpy(g_text, e->text, sizeof(g_text) - 1); g_text[sizeof(g_text) - 1] = 0;   /* güncel satır (sonraki yığma kararı) */
            g_nspeakers = m; for (int i = 0; i < m; i++) g_speakers[i] = merged[i];
            g_have_subbox = e->have_box;
            if (e->have_box) { for (int i = 0; i < 4; i++) g_subbox[i] = e->box[i]; }
            g_paragraphs = e->paragraphs;
            g_shown_at = now;
            render_show(g_disp, &g_style); g_visible = 1;
            { int d = e->durationMs > 0 ? e->durationMs : 8000; if (d < 1000) d = 1000; g_hide_at = now + d; }
            break;
        }
        case EV_CLEAR: render_hide(); g_visible = 0; g_hide_at = 0; g_text[0] = 0; g_disp[0] = 0; g_shown_at = 0; g_paragraphs = 0; break;
        case EV_STYLE: merge_style(&e->style); if (g_visible) render_show(g_disp, &g_style); break;
        case EV_EXIT:  render_hide(); regions_clear(); screen_clear(); blocks_clear_all(); g_visible = 0; g_text[0] = 0; g_exit_evt = 1; break;
        case EV_REGION:
            /* blocks varsa her alt-çeviriyi kendi yerinde göster (birleşik pencereyi gizle); yoksa birleşik metin. */
            if (!e->id[0]) break;
            blocks_clear(e->id);                     /* bu alanın eski blokları */
            if (e->nitems > 0) {
                region_hide(e->id);                  /* blok modunda birleşik pencere olmasın */
                char bid[80];
                for (int i = 0; i < e->nitems; i++) {
                    if (!e->items[i].have_box || e->items[i].text[0] == 0) continue;
                    snprintf(bid, sizeof bid, "%s#%d", e->id, i);
                    blocks_show(bid, e->items[i].text, e->items[i].box, e->items[i].line,
                                e->items[i].have_surface, e->items[i].bg, e->items[i].fg,
                                e->items[i].bold, e->items[i].condensed);
                }
                break;
            }
            if (e->text[0] == 0 || !e->have_box) { region_hide(e->id); break; }
            region_show(e->id, e->text, e->box, e->line);
            break;
        case EV_REGION_CLEAR: regions_clear(); blocks_clear_all(); break;
        case EV_SCREEN: {
            /* Her "Ekranı çevir" öğesini İngilizce yazının yerinde, varsa özgün renk/bold ile göster (ayrı havuz:
               canlı ek alanlara dokunmaz). En çok SCREEN_ITEMS_MAX öğe. */
            screen_clear();
            for (int i = 0; i < e->nitems; i++) {
                if (!e->items[i].have_box || e->items[i].text[0] == 0) continue;
                screen_show(i, e->items[i].text, e->items[i].box, e->items[i].line,
                            e->items[i].have_surface, e->items[i].bg, e->items[i].fg,
                            e->items[i].bold, e->items[i].condensed);
            }
            g_screen_hide_at = e->screenDurationMs > 0 ? now_ms() + e->screenDurationMs : 0;
            break;
        }
        case EV_SCREEN_CLEAR: screen_clear(); g_screen_hide_at = 0; break;
        case EV_PING: case EV_OTHER: default: break;
    }
}

/* ================= ağ + eşleştirme ================= */
static void on_sig(int s) { (void)s; g_quit = 1; }

/* Anahtar YALNIZ bellekte (Stage 6.1 kapsamı; kalıcı saklama ayrı aşama). Hiçbir yere yazdırılmaz. */
static char g_key[KEY_MAX];

/* Eşleştirme kodunu TV'de göster (code boşsa gizle). */
static void show_code(const char *code, void *ud) {
    (void)ud;
    if (!code || !code[0]) { render_hide(); return; }
    char msg[160];
    snprintf(msg, sizeof msg, "CouchSubs eşleştirme kodu: %s\nBilgisayarda CouchSubs'ta onaylayın", code);
    render_show(msg, &g_style);
}

/* HTTP başlıklarını tüket; gövde başlangıcını parser'a besle. return: HTTP status (-1 hata). */
static int consume_headers(int fd, SseParser *p) {
    char buf[4096]; int tot = 0, n;
    while (tot < (int)sizeof(buf) - 1) {
        n = (int)recv(fd, buf + tot, sizeof(buf) - 1 - tot, 0);
        if (n <= 0) return -1;
        tot += n; buf[tot] = 0;
        char *end = strstr(buf, "\r\n\r\n");
        if (end) {
            if (strncmp(buf, "HTTP/1.", 7) != 0) return -1;
            int status = atoi(buf + 9);
            if (status != 200) return status;              /* 401/403 vb. ASLA akış sayılmaz */
            if (!strstr(buf, "text/event-stream")) return -1;
            int bodyoff = (int)(end - buf) + 4;
            if (bodyoff < tot) sse_feed(p, buf + bodyoff, tot - bodyoff, on_event, NULL);
            return 200;
        }
    }
    return -1;                                             /* başlık çok büyük */
}

int main(int argc, char **argv) {
    const char *host = (argc > 1) ? argv[1] : getenv("COUCHSUBS_HOST");
    if (!host) host = "127.0.0.1";
    int port = (argc > 2) ? atoi(argv[2]) : (getenv("COUCHSUBS_PORT") ? atoi(getenv("COUCHSUBS_PORT")) : 8787);
    if (port <= 0 || port > 65535) { fprintf(stderr, "gecersiz port\n"); return 1; }

    signal(SIGINT, on_sig); signal(SIGTERM, on_sig); signal(SIGPIPE, SIG_IGN);
    if (render_init() != 0) { fprintf(stderr, "render init basarisiz\n"); return 1; }
    printf("[main] CouchSubs istemci: %s:%d\n", host, port);
    g_key[0] = 0;

    while (!g_quit && !g_exit_evt) {
        /* 1) /hello: sunucuyu tanı + auth gereksinimi */
        int auth = 0; char id[80] = "";
        int hs = pair_hello(host, port, &auth, id, sizeof id);
        if (hs != 200) {
            printf("[hello] %s (status=%d), %dms sonra\n", hs == -2 ? "yanit CouchSubs degil" : "ulasilamadi", hs, RECONNECT_MS);
            render_hide(); g_visible = 0; sleep_ms(RECONNECT_MS); continue;
        }
        printf("[hello] CouchSubs (id=%s, auth=%d)\n", id[0] ? id : "?", auth);

        /* 2) Anahtar: auth=1 ise doğrula ya da eşleştir (legacy'ye bağımlı değil) */
        /* app.js ile aynı: her bağlanmada kayıtlı anahtar doğrulanır (valid→kullan, expired→yeniden eşleş). */
        if (!pair_obtain_key(host, port, auth, g_key, sizeof g_key, show_code, NULL, &g_quit)) break;

        /* 3) /events (?k=KEY) */
        int fd = cs_tcp_connect(host, port);
        if (fd < 0) { render_hide(); g_visible = 0; printf("[net] baglanamadi, %dms sonra\n", RECONNECT_MS); sleep_ms(RECONNECT_MS); continue; }
        char req[320];
        int rl = snprintf(req, sizeof req,
            "GET /events%s%s HTTP/1.1\r\nHost: %s:%d\r\nAccept: text/event-stream\r\nConnection: keep-alive\r\n\r\n",
            g_key[0] ? "?k=" : "", g_key[0] ? g_key : "", host, port);
        if (rl <= 0 || rl >= (int)sizeof req || cs_send_all(fd, req, rl) != 0) {
            memset(req, 0, sizeof req); close(fd); render_hide(); sleep_ms(RECONNECT_MS); continue; }
        memset(req, 0, sizeof req);                         /* anahtar içeren isteği bellekte bırakma */
        SseParser p; sse_init(&p);
        int st = consume_headers(fd, &p);
        if (st != 200) {
            close(fd); render_hide(); g_visible = 0;
            if (st == 401) {
                printf("[net] /events 401: anahtar yok/yanlis/yenilenmis -> yeniden eslestirme\n");
                g_key[0] = 0; sleep_ms(1000);
            } else if (st == 403) {
                printf("[net] /events 403: erisim reddedildi (Origin/yerel ag disi). Bekleniyor.\n");
                sleep_ms(10000);
            } else {
                printf("[net] /events basarisiz (status=%d), %dms sonra\n", st, RECONNECT_MS);
                sleep_ms(RECONNECT_MS);
            }
            continue;
        }
        printf("[net] bagli, /events akisi (%s)\n", g_key[0] ? "kimlik dogrulamali" : "anahtarsiz");
        long long last_rx = now_ms();
        while (!g_quit && !g_exit_evt) {
            fd_set rf; FD_ZERO(&rf); FD_SET(fd, &rf);
            struct timeval tv = { 0, 200000 };
            int sr = select(fd + 1, &rf, NULL, NULL, &tv);
            long long now = now_ms();
            if (sr > 0 && FD_ISSET(fd, &rf)) {
                char buf[4096]; int n = (int)recv(fd, buf, sizeof buf, 0);
                if (n <= 0) { printf("[net] baglanti koptu\n"); break; }
                last_rx = now;
                sse_feed(&p, buf, n, on_event, NULL);
            }
            if (g_visible && g_hide_at && now >= g_hide_at) { render_hide(); g_visible = 0; g_hide_at = 0; }
            if (g_screen_hide_at && now >= g_screen_hide_at) { screen_clear(); g_screen_hide_at = 0; }
            if (now - last_rx > STREAM_TIMEOUT_MS) { printf("[net] akis durgun -> yeniden baglan\n"); break; }
        }
        close(fd);
        render_hide(); regions_clear(); screen_clear(); blocks_clear_all(); g_visible = 0; g_hide_at = 0; g_screen_hide_at = 0;  /* eski altyazı/alanlar ekranda kalmasın */
        if (g_quit || g_exit_evt) break;
        sleep_ms(RECONNECT_MS);
    }
    memset(g_key, 0, sizeof g_key);
    render_hide(); render_deinit();
    printf("[main] temiz cikis\n");
    return 0;
}

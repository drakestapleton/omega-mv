/* allen_ui_stream_test.c -- a streamed answer must keep the letters already on screen (L853). The
 * courier hands each later fragment over as the whole text so far, through
 * ck_allen_ui_said_more, which joins it to the words showing. ck_allen_ui_said
 * still starts a fresh reply: the "restart" arm shows that old path blanks the
 * strip, so the checks can see the defect. Allen cannot speak until he has
 * formed (FORMED_MS + 300), so every arm waits for that before the first words.
 * One arm per run: allen_ui_stream_test join|glide|restart|mismatch|pending|faded|coalesced */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "ui/allen_ui.h"

static uint64_t now_us;
static uint32_t *fb, *copy;
static uint32_t W = 1920, H = 1080;

static uint32_t now_ms(void) { return (uint32_t)(now_us / 1000); }

static void run_to(uint32_t ms)
{
    for (; now_us <= (uint64_t)ms * 1000u; now_us += 16000)
        ck_allen_ui_tick(now_us);
}

/* Pixels in the strip under Allen where his words go. Settled letters are
 * near white; faint() also counts letters that are still coming in. */
static unsigned strip(int faint)
{
    unsigned n = 0;
    uint32_t cy = H * 40 / 100;
    for (uint32_t y = cy + 216; y < cy + 456 && y < H; y++)
        for (uint32_t x = W / 2 - 460; x < W / 2 + 460; x++) {
            uint32_t c = fb[(size_t)y * W + x];
            unsigned r = c & 255, g = c >> 8 & 255, b = c >> 16 & 255;
            if (faint ? r > 40 : r > 200 && g > 200 && b > 200)
                n++;
        }
    return n;
}

static unsigned ink(void) { return strip(0); }
static unsigned faint(void) { return strip(1); }

/* Pixels where the last frame, drawn only where it changed, differs from the
 * same frame drawn whole. */
static unsigned stale(void)
{
    memcpy(copy, fb, (size_t)W * H * 4);
    ck_allen_ui_refresh();
    ck_allen_ui_tick(now_us - 16000);
    unsigned n = 0;
    for (size_t i = 0; i < (size_t)W * H; i++) {
        uint32_t a = fb[i], b = copy[i];
        for (int s = 0; s < 24; s += 8) {
            int e = (int)(a >> s & 255) - (int)(b >> s & 255);
            if (e > 6 || e < -6) {
                n++;
                break;
            }
        }
    }
    return n;
}

static void fail(const char *why)
{
    printf("ALLEN_UI_STREAM: FAIL %s\n", why);
    exit(1);
}

static unsigned base;

static unsigned above(unsigned from, unsigned n) { return n > from ? n - from : 0; }

static void boot(void)
{
    fb = calloc((size_t)W * H, 4);
    copy = malloc((size_t)W * H * 4);
    size_t need = ck_allen_ui_mem_bytes(W, H);
    void *mem = malloc(need);
    if (!fb || !copy || !mem || ck_allen_ui_start(fb, W, H, W, 1, mem, need, 1000000, 0, 0))
        fail("the window did not start");
    run_to(9000);
    ck_allen_ui_wake(0, now_us);
    run_to(16000); /* formed at 15300; the first words wait until 15600 */
    base = ink();
}

/* The first fragment, said and settled: the ink it leaves. */
static unsigned first(const char *p1)
{
    uint32_t t0 = now_ms();
    ck_allen_ui_said(0, p1, now_us);
    run_to(t0 + 2800);
    unsigned a = above(base, ink());
    printf("note: first fragment ink %u\n", a);
    if (a < 400)
        fail("the first fragment left too little ink to judge a restart");
    return a;
}

/* Lets the words on screen go: their fade (450 ms) has begun once the white
 * is nearly gone, and once it ends they are cleared. */
static void until_gone(void)
{
    uint32_t t0 = now_ms();
    while (above(base, ink()) >= 40) {
        run_to(now_ms() + 32);
        if (now_ms() > t0 + 16000)
            fail("the first answer did not leave the screen");
    }
    run_to(now_ms() + 600);
}

/* The next 500 ms after the call just made: did the strip go (nearly) blank? */
static int blanks(unsigned a)
{
    uint32_t at = now_ms();
    unsigned low = a;
    for (uint32_t dt = 16; dt <= 500; dt += 16) {
        run_to(at + dt);
        unsigned n = above(base, ink());
        low = n < low ? n : low;
    }
    printf("note: lowest ink %u of %u\n", low, a);
    return low * 4 < a;
}

/* Joins whole after a, sampling every frame: never blanks, partial redraw
 * equals full redraw while lines glide, and the new letters arrive. */
static void joins(unsigned a, const char *whole)
{
    ck_allen_ui_said_more(whole, now_us);
    uint32_t at = now_ms();
    unsigned worst = 0;
    for (uint32_t dt = 16; dt <= 700; dt += 16) {
        run_to(at + dt);
        unsigned n = above(base, ink());
        if (n * 10 < a * 9) {
            printf("note: ink %u at +%u ms, was %u\n", n, dt, a);
            fail("a later fragment blanked the letters already showing");
        }
        unsigned st = stale();
        worst = st > worst ? st : worst;
    }
    printf("note: worst stale %u while the words joined\n", worst);
    if (worst >= 40)
        fail("joining words left a partial redraw");
    run_to(at + 3000);
    unsigned b = above(base, ink());
    printf("note: joined ink %u\n", b);
    if (b * 10 <= a * 13)
        fail("the later fragment did not add letters");
}

int main(int argc, char **argv)
{
    const char *mode = argc > 1 ? argv[1] : "join";
    const char *p1 = "Gravity pulls them together because";
    char full[160], more[192], glide[160];
    snprintf(full, sizeof full, "%s %s", p1, "they orbit a common center of mass.");
    snprintf(more, sizeof more, "%s %s", full, "It takes time.");
    /* At 1920 wide the first line holds about 79 letters: one short word
     * still fits on it, the rest wraps, so that line glides less than it grows. */
    const char *g1 = "Gravity pulls them together because they orbit a common center of";
    snprintf(glide, sizeof glide, "%s %s", g1, argc > 2 ? argv[2] : "mass, notwithstanding everything.");
    boot();
    printf("note: baseline ink %u at %u ms\n", base, now_ms());

    if (!strcmp(mode, "join")) {
        joins(first(p1), full);
    } else if (!strcmp(mode, "glide")) {
        joins(first(g1), glide);
    } else if (!strcmp(mode, "restart")) {
        /* the old call with the same text: the defect, visible to these checks */
        unsigned a = first(p1);
        ck_allen_ui_said(0, full, now_us);
        if (!blanks(a))
            fail("the old call did not blank the strip; this check cannot see the defect");
    } else if (!strcmp(mode, "mismatch")) {
        /* longer than the words showing but not their continuation: a fresh reply */
        unsigned a = first(p1);
        ck_allen_ui_said_more("Gravity pulls them apart when nothing else holds them.", now_us);
        if (!blanks(a))
            fail("a reply that is not a continuation stayed glued on");
    } else if (!strcmp(mode, "pending")) {
        /* The second fragment comes before the first has started to speak. It
         * joins the waiting words: their start stays (a fresh reply would wait
         * another 500 ms), nothing restarts, and all of it is said. The ink one
         * fragment leaves is measured first, then left to go. */
        unsigned a = first(p1);
        until_gone();
        uint32_t t0 = now_ms();
        ck_allen_ui_said(0, p1, now_us);
        run_to(t0 + 200);
        ck_allen_ui_said_more(full, now_us);
        unsigned quiet = faint();
        run_to(t0 + 650);
        unsigned early = above(quiet, faint());
        printf("note: letters 650 ms after the first fragment %u\n", early);
        if (early < 15)
            fail("an early continuation delayed the first letters");
        unsigned most = early;
        for (uint32_t dt = 666; dt <= 4800; dt += 16) {
            run_to(t0 + dt);
            unsigned n = above(quiet, faint());
            if (n * 4 < most)
                fail("an early continuation restarted the letters");
            most = n > most ? n : most;
        }
        unsigned b = above(base, ink());
        printf("note: whole answer ink %u, one fragment %u\n", b, a);
        if (b * 10 <= a * 13)
            fail("an early continuation did not say all of the answer");
    } else if (!strcmp(mode, "faded")) {
        first(p1);
        until_gone();
        ck_allen_ui_said_more(full, now_us);
        uint32_t at = now_ms();
        run_to(at + 400);
        if (above(base, ink()) > 200)
            fail("a continuation after the words were gone painted at once");
        run_to(at + 3000);
        printf("note: fresh ink %u\n", above(base, ink()));
        if (above(base, ink()) < 400)
            fail("a continuation after the words were gone did not start fresh");
    } else if (!strcmp(mode, "coalesced")) {
        /* A fresh reply and its continuation arrive between two frames. The
         * continuation belongs to that reply, not to the words still showing,
         * even though those words begin it: the old words go. */
        unsigned a = first(p1);
        ck_allen_ui_said(0, full, now_us);
        ck_allen_ui_said_more(more, now_us);
        if (!blanks(a))
            fail("a continuation of a reply not yet shown was glued to the old words");
    } else
        fail("unknown mode");
    printf("ALLEN_UI_STREAM: PASS %s\n", mode);
    return 0;
}

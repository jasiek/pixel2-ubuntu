// SPDX-License-Identifier: MIT
/*
 * pixel2-screen: text console on the Pixel 2 OLED, dark after IDLE seconds,
 * touch (or a volume key) wakes it.
 *
 * Drawing: mdss_fb only has framebuffer memory while a process has /dev/fb0
 * mmapped (allocated on mmap, freed on release), so the kernel's fbcon can't
 * draw. We draw a text grid into the mmapped framebuffer ourselves and pan
 * to kick a frame (command-mode panel: one transfer per pan).
 *
 * Panel power follows the driver's own open/release path: opening fb0 powers
 * the panel on, closing it (last user) powers it off. At start we draw one
 * black frame and close, which hands the panel over cleanly from the
 * bootloader splash. (The old blank-ioctl sequence left the DSI link unable
 * to power up again; see docs/log.md, P8.1.)
 *
 * Text source:
 *   - CMD (default /usr/local/bin/pixel2-console) runs on a pseudo-terminal
 *     sized to the screen; a small VT100/linux-console emulator keeps the
 *     grid (enough for status scripts, journalctl, top-style redraws).
 *   - If the kernel has a VT (/dev/vcsa1 exists) and VCSA=1, the grid is
 *     copied from the VT instead (a real tty1 console with getty).
 *
 * Font: the kernel's 8x16 VGA font (CP437), scaled 2x: 67 x 60 characters.
 * Env: IDLE (s, default 300), SCALE (1-4, default 2), CMD, VCSA.
 *
 * Mainline kernel (fb0 is a DRM fbdev, "msmdrmfb"): fbcon already draws the
 * VT on the panel, so nothing is drawn here. CMD runs on /dev/tty1 (shown by
 * fbcon; font TER16x32 from the cmdline gives the same 67 x 60 grid) and the
 * panel is switched with /sys/class/graphics/fb0/blank (0 = on, 4 = off,
 * which disables the DSI panel).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "font_8x16.h" /* generated from the kernel's lib/fonts/font_8x16.c */

#define FB_DEV   "/dev/fb0"
#define VCSA_DEV "/dev/vcsa1"
#define MAX_IN   4
#define MAXR     128
#define MAXC     160
#define DEF_ATTR 0x07 /* light grey on black */

static const char *input_names[] = { "synaptics_dsxv26", "gpio-keys", "Synaptics S3708AR" };

/* VGA palette (R, G, B) for the 16 console colours. */
static const uint8_t pal[16][3] = {
	{0, 0, 0}, {170, 0, 0}, {0, 170, 0}, {170, 85, 0},
	{0, 0, 170}, {170, 0, 170}, {0, 170, 170}, {170, 170, 170},
	{85, 85, 85}, {255, 85, 85}, {85, 255, 85}, {255, 255, 85},
	{85, 85, 255}, {255, 85, 255}, {85, 255, 255}, {255, 255, 255},
};
/* ANSI colour index -> VGA attribute index (ANSI 1=red, VGA 4=red). */
static const uint8_t ansi2vga[8] = { 0, 4, 2, 6, 1, 5, 3, 7 };

/* ---------------------------------------------------------------- grid -- */

struct cell { uint8_t ch, attr; };
static struct cell grid[MAXR][MAXC];  /* what should be on screen */
static struct cell shown[MAXR][MAXC]; /* what is in the framebuffer */
static int nrows = 25, ncols = 80;
static int cx, cy;                    /* cursor */
static int cur_shown_x = -1, cur_shown_y = -1;
static int full_redraw = 1;

static void logmsg(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void logmsg(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fputs("pixel2-screen: ", stdout);
	vprintf(fmt, ap);
	putchar('\n');
	fflush(stdout);
	va_end(ap);
}

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

/* ------------------------------------------------------------ terminal -- */

static uint8_t attr = DEF_ATTR;
static int bold, reverse;
static int fg = 7, bg = 0;
static enum { S_NORMAL, S_ESC, S_CSI, S_OSC, S_CHARSET } st;
static int par[16], npar, priv;
static uint32_t utf_cp;
static int utf_left;
static int wrap_pending;

static void set_attr(void)
{
	int f = fg + (bold && fg < 8 ? 8 : 0), b = bg;
	attr = reverse ? (uint8_t)((f & 7) << 4 | b) : (uint8_t)(b << 4 | f);
}

static void clear_cells(int y, int x0, int x1)
{
	for (int x = x0; x < x1 && x < ncols; x++)
		grid[y][x] = (struct cell){ ' ', (uint8_t)(attr & 0x70) | 0x07 };
}

static void scroll_up(void)
{
	memmove(grid[0], grid[1], sizeof(grid[0]) * (nrows - 1));
	clear_cells(nrows - 1, 0, ncols);
}

static void newline(void)
{
	if (++cy >= nrows) {
		cy = nrows - 1;
		scroll_up();
	}
}

/* Map the Unicode characters journalctl/systemd use to CP437 glyphs. */
static uint8_t to_cp437(uint32_t c)
{
	static const struct { uint32_t u; uint8_t g; } map[] = {
		{0x25cf, 0x07}, {0x2022, 0x07}, {0x2500, 0xc4}, {0x2502, 0xb3},
		{0x250c, 0xda}, {0x2510, 0xbf}, {0x2514, 0xc0}, {0x2518, 0xd9},
		{0x251c, 0xc3}, {0x2524, 0xb4}, {0x252c, 0xc2}, {0x2534, 0xc1},
		{0x253c, 0xc5}, {0x2192, 0x1a}, {0x2190, 0x1b}, {0x2191, 0x18},
		{0x2193, 0x19}, {0x00b0, 0xf8}, {0x00b7, 0xfa}, {0x2026, '~'},
		{0x2713, 0xfb}, {0x00e9, 0x82}, {0x00e8, 0x8a}, {0x00fc, 0x81},
		{0x00f6, 0x94}, {0x00e4, 0x84}, {0x00df, 0xe1}, {0x00b5, 0xe6},
	};
	if (c < 0x80)
		return (uint8_t)c;
	for (size_t i = 0; i < sizeof(map) / sizeof(*map); i++)
		if (map[i].u == c)
			return map[i].g;
	return '?';
}

static void put_glyph(uint8_t g)
{
	if (wrap_pending) {
		wrap_pending = 0;
		cx = 0;
		newline();
	}
	grid[cy][cx] = (struct cell){ g, attr };
	if (cx == ncols - 1)
		wrap_pending = 1;
	else
		cx++;
}

static int p(int i, int def) { return i < npar && par[i] > 0 ? par[i] : def; }

static void clampcur(void)
{
	if (cx < 0) cx = 0;
	if (cx >= ncols) cx = ncols - 1;
	if (cy < 0) cy = 0;
	if (cy >= nrows) cy = nrows - 1;
	wrap_pending = 0;
}

static void sgr(void)
{
	if (!npar)
		par[npar++] = 0;
	for (int i = 0; i < npar; i++) {
		int v = par[i];
		if (v == 0) { bold = reverse = 0; fg = 7; bg = 0; }
		else if (v == 1) bold = 1;
		else if (v == 22) bold = 0;
		else if (v == 7) reverse = 1;
		else if (v == 27) reverse = 0;
		else if (v >= 30 && v <= 37) fg = ansi2vga[v - 30];
		else if (v == 39) fg = 7;
		else if (v >= 40 && v <= 47) bg = ansi2vga[v - 40];
		else if (v == 49) bg = 0;
		else if (v >= 90 && v <= 97) fg = ansi2vga[v - 90] + 8;
		else if (v >= 100 && v <= 107) bg = ansi2vga[v - 100];
		else if ((v == 38 || v == 48) && i + 1 < npar)
			i += par[i + 1] == 5 ? 2 : 4; /* 256/true colour: skip */
	}
	set_attr();
}

static void csi(char f)
{
	if (priv)
		return; /* ?25l cursor hide etc.: ignore */
	switch (f) {
	case 'A': cy -= p(0, 1); clampcur(); break;
	case 'B': case 'e': cy += p(0, 1); clampcur(); break;
	case 'C': case 'a': cx += p(0, 1); clampcur(); break;
	case 'D': cx -= p(0, 1); clampcur(); break;
	case 'E': cy += p(0, 1); cx = 0; clampcur(); break;
	case 'F': cy -= p(0, 1); cx = 0; clampcur(); break;
	case 'G': case '`': cx = p(0, 1) - 1; clampcur(); break;
	case 'd': cy = p(0, 1) - 1; clampcur(); break;
	case 'H': case 'f': cy = p(0, 1) - 1; cx = p(1, 1) - 1; clampcur(); break;
	case 'J':
		if (p(0, 0) == 0) {
			clear_cells(cy, cx, ncols);
			for (int y = cy + 1; y < nrows; y++) clear_cells(y, 0, ncols);
		} else if (p(0, 0) == 1) {
			for (int y = 0; y < cy; y++) clear_cells(y, 0, ncols);
			clear_cells(cy, 0, cx + 1);
		} else {
			for (int y = 0; y < nrows; y++) clear_cells(y, 0, ncols);
		}
		break;
	case 'K':
		if (p(0, 0) == 0) clear_cells(cy, cx, ncols);
		else if (p(0, 0) == 1) clear_cells(cy, 0, cx + 1);
		else clear_cells(cy, 0, ncols);
		break;
	case 'X': clear_cells(cy, cx, cx + p(0, 1)); break;
	case 'P': {
		int n = p(0, 1);
		if (n > ncols - cx) n = ncols - cx;
		memmove(&grid[cy][cx], &grid[cy][cx + n], sizeof(struct cell) * (ncols - cx - n));
		clear_cells(cy, ncols - n, ncols);
		break;
	}
	case 'm': sgr(); break;
	default: break;
	}
}

static void term_byte(uint8_t b)
{
	switch (st) {
	case S_ESC:
		st = S_NORMAL;
		if (b == '[') { st = S_CSI; npar = 0; priv = 0; memset(par, 0, sizeof(par)); }
		else if (b == ']') st = S_OSC;
		else if (b == '(' || b == ')') st = S_CHARSET;
		else if (b == 'c') { bold = reverse = 0; fg = 7; bg = 0; set_attr(); cx = cy = 0;
			for (int y = 0; y < nrows; y++) clear_cells(y, 0, ncols); }
		else if (b == 'D') newline();
		else if (b == 'M') { if (cy > 0) cy--; }
		return;
	case S_CSI:
		if (b >= '0' && b <= '9') {
			if (!npar) npar = 1;
			par[npar - 1] = par[npar - 1] * 10 + (b - '0');
		} else if (b == ';') {
			if (!npar) npar = 1;
			if (npar < 16) par[npar++] = 0;
		} else if (b == '?' || b == '>' || b == '=') {
			priv = 1;
		} else if (b >= 0x40 && b <= 0x7e) {
			st = S_NORMAL;
			csi((char)b);
		}
		return;
	case S_OSC:
		if (b == 7 || b == 0x9c) st = S_NORMAL;
		else if (b == 0x1b) st = S_ESC; /* ESC \ */
		return;
	case S_CHARSET:
		st = S_NORMAL;
		return;
	case S_NORMAL:
		break;
	}

	if (utf_left) {
		if ((b & 0xc0) == 0x80) {
			utf_cp = utf_cp << 6 | (b & 0x3f);
			if (--utf_left == 0)
				put_glyph(to_cp437(utf_cp));
			return;
		}
		utf_left = 0;
		put_glyph('?');
	}
	if (b >= 0xc0 && b < 0xf8) {
		utf_left = b >= 0xf0 ? 3 : b >= 0xe0 ? 2 : 1;
		utf_cp = b & (0x3f >> utf_left);
		return;
	}
	switch (b) {
	case 0x1b: st = S_ESC; break;
	case '\r': cx = 0; wrap_pending = 0; break;
	case '\n': case 0x0b: case 0x0c: newline(); wrap_pending = 0; break;
	case '\b': if (cx > 0) cx--; wrap_pending = 0; break;
	case '\t': cx = (cx + 8) & ~7; if (cx >= ncols) cx = ncols - 1; break;
	case 7: case 0: break;
	default:
		if (b >= 0x20 && b < 0x80)
			put_glyph(b);
		break;
	}
}

/* --------------------------------------------------------- framebuffer -- */

static int fb = -1;
static uint8_t *fbmem;
static struct fb_var_screeninfo var;
static struct fb_fix_screeninfo fix;
static uint32_t colour[16];
static int scale = 2;

static void pan(void)
{
	var.yoffset = 0;
	var.activate = FB_ACTIVATE_VBL;
	if (ioctl(fb, FBIOPAN_DISPLAY, &var))
		logmsg("pan: %s", strerror(errno));
}

/* Open fb0 (panel on) and map it. */
static int fb_on(void)
{
	fb = open(FB_DEV, O_RDWR | O_CLOEXEC);
	if (fb < 0) {
		logmsg("%s: %s", FB_DEV, strerror(errno));
		return -1;
	}
	if (ioctl(fb, FBIOGET_VSCREENINFO, &var) || ioctl(fb, FBIOGET_FSCREENINFO, &fix) ||
	    var.bits_per_pixel != 32) {
		logmsg("fb info: %s (bpp %u)", strerror(errno), var.bits_per_pixel);
		goto fail;
	}
	fbmem = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fb, 0);
	if (fbmem == MAP_FAILED) {
		logmsg("mmap: %s", strerror(errno));
		goto fail;
	}
	for (int i = 0; i < 16; i++) {
		colour[i] = (uint32_t)pal[i][0] << var.red.offset |
			    (uint32_t)pal[i][1] << var.green.offset |
			    (uint32_t)pal[i][2] << var.blue.offset;
		if (var.transp.length)
			colour[i] |= 0xffu << var.transp.offset;
	}
	return 0;
fail:
	close(fb);
	fb = -1;
	return -1;
}

/* Unmap and close fb0: the last release powers the panel off. */
static void fb_off(void)
{
	if (fb < 0)
		return;
	munmap(fbmem, fix.smem_len);
	close(fb);
	fb = -1;
}

static void fill_black(void)
{
	for (unsigned y = 0; y < var.yres; y++) {
		uint32_t *row = (uint32_t *)(fbmem + y * fix.line_length);
		for (unsigned x = 0; x < var.xres; x++)
			row[x] = colour[0];
	}
}

static void draw_cell(int x, int y, struct cell c, int cursor)
{
	uint32_t f = colour[c.attr & 0x0f], b = colour[(c.attr >> 4) & 0x07];
	const uint8_t *glyph = fontdata_8x16 + c.ch * 16;
	unsigned px0 = x * 8 * scale, py0 = y * 16 * scale;

	for (unsigned gy = 0; gy < 16; gy++) {
		uint8_t bits = cursor && gy >= 14 ? 0xff : glyph[gy];
		for (int sy = 0; sy < scale; sy++) {
			uint32_t *row = (uint32_t *)(fbmem + (py0 + gy * scale + sy) * fix.line_length) + px0;
			for (unsigned gx = 0; gx < 8; gx++) {
				uint32_t px = bits & (0x80 >> gx) ? f : b;
				for (int sx = 0; sx < scale; sx++)
					*row++ = px;
			}
		}
	}
}

/* Draw the cells that differ from what is shown; returns 1 if any. */
static int render(void)
{
	int drawn = 0;
	for (int y = 0; y < nrows; y++)
		for (int x = 0; x < ncols; x++) {
			int cur = x == cx && y == cy;
			int was = x == cur_shown_x && y == cur_shown_y;
			if (!full_redraw && !cur && !was &&
			    !memcmp(&grid[y][x], &shown[y][x], sizeof(struct cell)))
				continue;
			draw_cell(x, y, grid[y][x], cur);
			shown[y][x] = grid[y][x];
			drawn = 1;
		}
	cur_shown_x = cx;
	cur_shown_y = cy;
	full_redraw = 0;
	return drawn;
}

/* --------------------------------------------------------- text source -- */

static int use_vcsa;

static void read_vcsa(void)
{
	static uint8_t buf[4 + 2 * MAXR * MAXC];
	int v = open(VCSA_DEV, O_RDONLY | O_CLOEXEC);
	if (v < 0)
		return;
	ssize_t n = read(v, buf, sizeof(buf));
	close(v);
	if (n < 4)
		return;
	int vr = buf[0], vc = buf[1];
	cx = buf[2];
	cy = buf[3];
	for (int y = 0; y < nrows && y < vr; y++)
		for (int x = 0; x < ncols && x < vc; x++) {
			size_t o = 4 + 2 * (size_t)(y * vc + x);
			if (o + 1 < (size_t)n)
				grid[y][x] = (struct cell){ buf[o], buf[o + 1] };
		}
}

static void size_vt(void)
{
	int t = open("/dev/tty1", O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (t < 0)
		return;
	struct winsize ws = { .ws_row = nrows, .ws_col = ncols };
	ioctl(t, TIOCSWINSZ, &ws);
	close(t);
}

/* Start CMD on a new pseudo-terminal; returns the master fd. */
static int start_cmd(const char *cmd, pid_t *pid)
{
	int m = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (m < 0 || grantpt(m) || unlockpt(m)) {
		logmsg("pty: %s", strerror(errno));
		return -1;
	}
	struct winsize ws = { .ws_row = nrows, .ws_col = ncols };
	ioctl(m, TIOCSWINSZ, &ws);
	char *name = ptsname(m);
	*pid = fork();
	if (*pid == 0) {
		setsid();
		int s = open(name, O_RDWR);
		if (s < 0)
			_exit(127);
		ioctl(s, TIOCSCTTY, 0);
		dup2(s, 0);
		dup2(s, 1);
		dup2(s, 2);
		if (s > 2)
			close(s);
		setenv("TERM", "linux", 1);
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	fcntl(m, F_SETFL, O_NONBLOCK);
	logmsg("running \"%s\" on %s (pid %d)", cmd, name, (int)*pid);
	return m;
}

/* -------------------------------------------------------------- inputs -- */

static int open_inputs(struct pollfd *pfd)
{
	FILE *f = fopen("/proc/bus/input/devices", "r");
	char line[512], name[128] = "";
	int n = 0;
	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f) && n < MAX_IN) {
		if (sscanf(line, "N: Name=\"%127[^\"]\"", name) == 1)
			continue;
		char *ev = strstr(line, "event");
		if (strncmp(line, "H: Handlers=", 12) || !ev)
			continue;
		for (size_t i = 0; i < sizeof(input_names) / sizeof(*input_names); i++) {
			if (strcmp(name, input_names[i]))
				continue;
			char path[64];
			snprintf(path, sizeof(path), "/dev/input/%.*s", (int)strcspn(ev, " \n"), ev);
			int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
			if (fd < 0) {
				logmsg("%s: %s", path, strerror(errno));
				continue;
			}
			pfd[n] = (struct pollfd){ .fd = fd, .events = POLLIN };
			n++;
			logmsg("watching %s (%s)", name, path);
		}
	}
	fclose(f);
	return n;
}

static int has_touch(void)
{
	FILE *f = fopen("/proc/bus/input/devices", "r");
	char line[512];
	int found = 0;
	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f))
		if (strstr(line, input_names[0]) || strstr(line, input_names[2]))
			found = 1;	/* a touchscreen: 4.4 or mainline name */
	fclose(f);
	return found;
}

/* ------------------------------------------------- mainline (fbcon) -- */

static int fbcon_mode, con_on;

static int fb0_is_drm(void)
{
	char name[64] = "";
	FILE *f = fopen("/sys/class/graphics/fb0/name", "r");
	if (!f)
		return 0;
	if (!fgets(name, sizeof(name), f))
		name[0] = 0;
	fclose(f);
	return strstr(name, "drmfb") != NULL;
}

static void fb0_blank(int level)
{
	FILE *f = fopen("/sys/class/graphics/fb0/blank", "w");
	if (!f) {
		logmsg("fb0/blank: %s", strerror(errno));
		return;
	}
	fprintf(f, "%d\n", level);
	fclose(f);
}

/* Start CMD with /dev/tty1 as its controlling terminal (fbcon shows it). */
static int start_cmd_tty1(const char *cmd, pid_t *pid)
{
	*pid = fork();
	if (*pid < 0)
		return -1;
	if (*pid == 0) {
		setsid();
		int t = open("/dev/tty1", O_RDWR);
		if (t < 0)
			_exit(127);
		ioctl(t, TIOCSCTTY, 1);
		dup2(t, 0);
		dup2(t, 1);
		dup2(t, 2);
		if (t > 2)
			close(t);
		setenv("TERM", "linux", 1);
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	logmsg("running \"%s\" on /dev/tty1 (pid %d)", cmd, (int)*pid);
	return 0;
}

/* ---------------------------------------------------------------- main -- */

static volatile sig_atomic_t stop;
static void on_signal(int sig) { (void)sig; stop = 1; }

static void screen_on(void)
{
	if (fbcon_mode) {
		if (!con_on) {
			fb0_blank(0);
			con_on = 1;
			logmsg("on");
		}
		return;
	}
	if (fb >= 0 || fb_on())
		return;
	fill_black();
	full_redraw = 1;
	if (use_vcsa)
		read_vcsa();
	render();
	pan();
	logmsg("on");
}

static void screen_off(void)
{
	if (fbcon_mode) {
		if (con_on) {
			fb0_blank(4);
			con_on = 0;
			logmsg("off");
		}
		return;
	}
	if (fb < 0)
		return;
	fill_black();
	pan();
	fb_off();
	logmsg("off");
}

int main(void)
{
	int idle = getenv("IDLE") ? atoi(getenv("IDLE")) : 300;
	const char *cmd = getenv("CMD") ? getenv("CMD") : "/usr/local/bin/pixel2-console";
	if (getenv("SCALE"))
		scale = atoi(getenv("SCALE"));
	if (scale < 1 || scale > 4)
		scale = 2;
	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);
	signal(SIGPIPE, SIG_IGN);

	fbcon_mode = fb0_is_drm();
	if (fbcon_mode) {
		con_on = 1;		/* fbcon unblanks at boot */
		screen_off();
		logmsg("mainline: fbcon on tty1, panel off");
	} else if (fb_on() == 0) {
		/* Hand the panel over from the bootloader splash, then dark. */
		fill_black();
		pan();
		nrows = var.yres / (16 * scale);
		ncols = var.xres / (8 * scale);
		if (nrows > MAXR) nrows = MAXR;
		if (ncols > MAXC) ncols = MAXC;
		fb_off();
		logmsg("splash cleared, panel off; text %dx%d", ncols, nrows);
	}
	for (int y = 0; y < nrows; y++)
		clear_cells(y, 0, ncols);

	use_vcsa = getenv("VCSA") && atoi(getenv("VCSA")) && access(VCSA_DEV, R_OK) == 0;
	pid_t child = 0;
	int pty = -1;
	if (fbcon_mode)
		start_cmd_tty1(cmd, &child);
	else if (use_vcsa)
		size_vt();
	else
		pty = start_cmd(cmd, &child);

	/* The touch driver is a module and may still be loading at boot. */
	for (int i = 0; i < 60 && !has_touch() && !stop; i++)
		sleep(1);
	struct pollfd pfd[MAX_IN + 1];
	int nin = open_inputs(pfd);
	if (!nin)
		logmsg("no input devices: screen stays off");
	if (pty >= 0)
		pfd[nin] = (struct pollfd){ .fd = pty, .events = POLLIN };

	double last_input = 0, last_frame = 0;
	int dirty = 0;
	while (!stop) {
		int on = fbcon_mode ? con_on : fb >= 0;
		int r = poll(pfd, nin + (pty >= 0), on ? 250 : (fbcon_mode ? 5000 : -1));
		if (r < 0 && errno != EINTR)
			break;
		int touched = 0;
		for (int i = 0; i < nin; i++)
			if (pfd[i].revents & POLLIN) {
				struct input_event ev[64];
				while (read(pfd[i].fd, ev, sizeof(ev)) > 0)
					;
				touched = 1;
			}
		if (pty >= 0 && pfd[nin].revents & (POLLIN | POLLHUP)) {
			uint8_t buf[4096];
			ssize_t n;
			while ((n = read(pty, buf, sizeof(buf))) > 0) {
				for (ssize_t i = 0; i < n; i++)
					term_byte(buf[i]);
				dirty = 1;
			}
			if (n == 0 || (n < 0 && errno == EIO)) { /* command exited: restart */
				close(pty);
				waitpid(child, NULL, 0);
				sleep(2);
				pty = start_cmd(cmd, &child);
				if (pty >= 0)
					pfd[nin].fd = pty;
			}
		}
		if (fbcon_mode && child > 0 && waitpid(child, NULL, WNOHANG) == child) {
			sleep(2);	/* command exited: restart */
			start_cmd_tty1(cmd, &child);
		}
		if (touched) {
			last_input = now();
			screen_on();
		}
		if (fbcon_mode) {
			if (con_on && now() - last_input >= idle)
				screen_off();
		} else if (fb >= 0) {
			if (now() - last_input >= idle) {
				screen_off();
			} else if (use_vcsa || (dirty && now() - last_frame >= 0.1)) {
				if (use_vcsa)
					read_vcsa();
				if (render())
					pan();
				last_frame = now();
				dirty = 0;
			}
		}
	}
	screen_off();
	if (child > 0)
		kill(child, SIGTERM);
	return 0;
}

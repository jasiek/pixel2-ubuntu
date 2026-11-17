/* fbtest: draw colour bars into /dev/fb0 via mmap + FBIOPAN_DISPLAY.
 * mdss_fb only allocates framebuffer memory on mmap (write() returns ENODEV),
 * so this is the minimal "can we draw" test for the walleye panel.
 *   fbtest [seconds] [phases]   phases: string of b(ars)/k(black), one per
 *   `seconds` (default 10 s, "b"), all with fb0 kept open; then exits
 *   (memory freed and panel powered down on close). */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static void draw(uint8_t *p, struct fb_var_screeninfo *v, struct fb_fix_screeninfo *f, int black)
{
	static const uint8_t bars[8][3] = { {255,255,255}, {255,255,0}, {0,255,255}, {0,255,0},
					    {255,0,255}, {255,0,0}, {0,0,255}, {40,40,40} };
	unsigned bpp = v->bits_per_pixel / 8;
	for (unsigned y = 0; y < v->yres; y++) {
		uint8_t *row = p + y * f->line_length;
		for (unsigned x = 0; x < v->xres; x++) {
			const uint8_t *c = bars[x * 8 / v->xres];
			uint32_t px = black ? 0 : (uint32_t)c[0] << v->red.offset |
				(uint32_t)c[1] << v->green.offset | (uint32_t)c[2] << v->blue.offset;
			if (v->transp.length) px |= 0xffu << v->transp.offset;
			memcpy(row + x * bpp, &px, bpp);
		}
	}
}

int main(int argc, char **argv)
{
	int secs = argc > 1 ? atoi(argv[1]) : 10;
	struct fb_var_screeninfo v;
	struct fb_fix_screeninfo f;
	int fd = open("/dev/fb0", O_RDWR);
	if (fd < 0) { perror("open"); return 1; }
	if (ioctl(fd, FBIOGET_VSCREENINFO, &v) || ioctl(fd, FBIOGET_FSCREENINFO, &f)) { perror("ioctl"); return 1; }
	printf("%ux%u virt %ux%u bpp %u line %u smem %u  R%u/%u G%u/%u B%u/%u A%u/%u\n",
	       v.xres, v.yres, v.xres_virtual, v.yres_virtual, v.bits_per_pixel, f.line_length, f.smem_len,
	       v.red.offset, v.red.length, v.green.offset, v.green.length, v.blue.offset, v.blue.length,
	       v.transp.offset, v.transp.length);
	uint8_t *p = mmap(NULL, f.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	const char *phases = argc > 2 ? argv[2] : "b";
	for (const char *ph = phases; *ph; ph++) {
		draw(p, &v, &f, *ph == 'k');
		struct timespec t0, t1;
		v.yoffset = 0;
		v.activate = FB_ACTIVATE_VBL;
		clock_gettime(CLOCK_MONOTONIC, &t0);
		int r = ioctl(fd, FBIOPAN_DISPLAY, &v);
		clock_gettime(CLOCK_MONOTONIC, &t1);
		printf("%c pan: %d (%.0f ms)\n", *ph, r, (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6);
		fflush(stdout);
		if (r) perror("FBIOPAN_DISPLAY");
		sleep(secs);
	}
	munmap(p, f.smem_len);
	close(fd);
	return 0;
}

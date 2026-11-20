#!/usr/bin/env python3
"""Renders the LidarLinks point-cloud golf ball (docs/brand/ball.png).

The ball is drawn the way a lidar scanner sees it: a cloud of points on a
sphere (a Fibonacci spiral, so they sit evenly like dimples), each point lit
by a soft key light from the top left with a green bounce from below, and
sized and faded by how much it faces the viewer. A cyan scan line crosses
the ball with a soft glow. The result is a transparent PNG that
make_brand.py drops into the icon and wordmark.

	python3 tools/brand/ball.py
"""
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parents[2] / "docs" / "brand" / "ball.png"
SIZE = 700          # output px; the ball radius is RADIUS of that
RADIUS = 300
SS = 4              # supersampling
POINTS = 3400
SCAN_Y = -0.02      # scan line height, as a fraction of the radius (down +)

GREEN = np.array([22, 120, 70], float)
WHITE = np.array([248, 252, 250], float)
CYAN = np.array([110, 235, 250], float)


def norm(v: np.ndarray) -> np.ndarray:
	return v / np.linalg.norm(v, axis=-1, keepdims=True)


def main() -> None:
	n = SIZE * SS
	r = RADIUS * SS
	c = n / 2
	i = np.arange(POINTS) + 0.5
	y = 1 - 2 * i / POINTS
	ring = np.sqrt(1 - y * y)
	th = math.pi * (3 - math.sqrt(5)) * i
	p = np.stack([ring * np.cos(th), y, ring * np.sin(th)], 1)
	# A slight tilt so the spiral's pole isn't facing us.
	a = 0.5
	rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
	p = p @ rx.T
	p = p[p[:, 2] > -0.05]
	p = p[np.argsort(p[:, 2])]          # back to front

	key = norm(np.array([-0.5, -0.6, 0.65]))
	lam = np.clip(p @ key, 0, 1)
	bounce = np.clip(p[:, 1], 0, 1) ** 2           # +y is down on screen
	facing = np.clip(p[:, 2], 0, 1)
	b = 0.08 + 0.92 * lam ** 0.75
	col = GREEN[None] * (1 - b[:, None]) + WHITE[None] * b[:, None]
	col = col * (1 - 0.35 * bounce[:, None]) + GREEN[None] * 0.35 * bounce[:, None]
	near_scan = np.exp(-((p[:, 1] - SCAN_Y) / 0.035) ** 2)
	col = col * (1 - near_scan[:, None]) + CYAN[None] * near_scan[:, None]
	alpha = np.clip(0.25 + 0.75 * (0.35 + 0.65 * facing) * (0.4 + 0.6 * b) + near_scan, 0, 1)
	rad = (1.6 + 5.0 * facing ** 0.8) * SS

	img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	for (px, py, _), cc, al, rr in zip(p, col, alpha, rad):
		x, yy = c + px * r, c + py * r
		d.ellipse([x - rr, yy - rr, x + rr, yy + rr], fill=(int(cc[0]), int(cc[1]), int(cc[2]), int(255 * al)))

	# Scan line: a thin bright core with a wide soft glow, fading at the ends.
	scan = Image.new("RGBA", (n, n), (0, 0, 0, 0))
	sd = ImageDraw.Draw(scan)
	sy = c + SCAN_Y * r
	half = r * 1.15
	steps = 200
	for k in range(steps):
		t = k / (steps - 1)
		x0 = c - half + 2 * half * t
		fade = math.sin(math.pi * t) ** 1.5
		sd.rectangle([x0, sy - 1.6 * SS, x0 + 2 * half / steps + 1, sy + 1.6 * SS], fill=(200, 250, 255, int(255 * fade)))
	wide = Image.new("RGBA", (n, n), (0, 0, 0, 0))
	wd = ImageDraw.Draw(wide)
	for k in range(steps):
		t = k / (steps - 1)
		x0 = c - half + 2 * half * t
		fade = math.sin(math.pi * t) ** 1.2
		wd.rectangle([x0, sy - 7 * SS, x0 + 2 * half / steps + 1, sy + 7 * SS], fill=(90, 225, 245, int(200 * fade)))
	glow = wide.filter(ImageFilter.GaussianBlur(14 * SS))
	glow2 = scan.filter(ImageFilter.GaussianBlur(3 * SS))
	out = Image.alpha_composite(img, glow)
	out = Image.alpha_composite(out, glow)
	out = Image.alpha_composite(out, glow2)
	out = Image.alpha_composite(out, scan)
	out = out.resize((SIZE, SIZE), Image.LANCZOS)
	OUT.parent.mkdir(parents=True, exist_ok=True)
	out.save(OUT)
	print("wrote", OUT)


if __name__ == "__main__":
	main()

// Renders the promo's titles (overlay.html) and device frames (devices.html)
// to transparent PNGs with the pre-installed Chromium (Playwright).
//   node tools/promo/overlays.js spec.json out_dir
// spec.json: [{"name": "hook", "page": "overlay.html", "query": "kind=hook&t=...", "w": 1920, "h": 1080}, ...]
// Also writes out_dir/screens.json, devices.html's screen rectangles.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
	const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
	const out = process.argv[3];
	fs.mkdirSync(out, { recursive: true });
	const browser = await chromium.launch();
	for (const j of jobs) {
		const ctx = await browser.newContext({ viewport: { width: j.w || 1920, height: j.h || 1080 } });
		const page = await ctx.newPage();
		await page.goto('file://' + path.join(__dirname, j.page || 'overlay.html') + '?' + (j.query || ''));
		await page.waitForLoadState('networkidle');
		await page.evaluate(() => document.fonts.ready);
		await page.screenshot({ path: path.join(out, j.name + '.png'), omitBackground: true });
		if (j.page === 'devices.html') {
			const s = await page.evaluate(() => window.SCREENS);
			fs.writeFileSync(path.join(out, 'screens.json'), JSON.stringify(s));
		}
		await ctx.close();
	}
	await browser.close();
})();

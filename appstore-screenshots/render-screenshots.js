const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const NAMES = [
  '01-dashboard',
  '02-ai-tracking',
  '03-reports',
  '04-properties',
  '05-settings'
];

// Scale factor: makes content bigger so it fills the tall phone frame
// The phone frame is ~2476px tall but content is ~1200px at full width.
// We layout content at phoneWidth/SCALE width, then scale it up visually.
const CONTENT_SCALE = 1.85;

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: fs.existsSync('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
      ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      : undefined,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const filePath = path.resolve(__dirname, 'screenshot-generator.html');

  for (let i = 0; i < NAMES.length; i++) {
    const name = NAMES[i];
    const outPath = path.resolve(__dirname, `${name}.png`);

    const page = await browser.newPage();
    await page.setViewport({ width: 1290, height: 2796, deviceScaleFactor: 1 });
    await page.goto(`file://${filePath}`, { waitUntil: 'networkidle0', timeout: 30000 });
    await page.evaluate(() => document.fonts.ready);
    await new Promise(r => setTimeout(r, 2000));

    // Isolate the target screenshot and scale up phone content
    await page.evaluate((index, scale) => {
      // Hide page-level elements
      document.querySelectorAll('.toolbar, .progress-bar-export, .modal-overlay').forEach(el => {
        el.style.display = 'none';
      });
      document.querySelectorAll('.gallery-label, .gallery-actions').forEach(el => {
        el.style.display = 'none';
      });

      const gallery = document.querySelector('.gallery');
      if (gallery) {
        gallery.style.display = 'block';
        gallery.style.padding = '0';
        gallery.style.margin = '0';
        gallery.style.overflow = 'visible';
      }

      document.querySelectorAll('.gallery-item').forEach((item, idx) => {
        if (idx !== index) {
          item.style.display = 'none';
        } else {
          item.style.display = 'block';
          item.style.padding = '0';
          item.style.margin = '0';
        }
      });

      document.querySelectorAll('.gallery-frame').forEach((frame, idx) => {
        if (idx === index) {
          frame.style.width = '1290px';
          frame.style.height = '2796px';
          frame.style.borderRadius = '0';
          frame.style.boxShadow = 'none';
          frame.style.overflow = 'visible';
        }
      });

      document.querySelectorAll('.screenshot').forEach((el, idx) => {
        if (idx === index) {
          el.style.transform = 'none';
          el.style.transformOrigin = 'top left';
        }
      });

      // Scale up the app content within the phone frame for this screenshot
      const screenshot = document.querySelectorAll('.screenshot')[index];
      if (screenshot) {
        const appContent = screenshot.querySelector('.app-content');
        const appScroll = screenshot.querySelector('.app-scroll');

        if (appContent && appScroll) {
          const scrollWidth = appScroll.offsetWidth;
          // Set content to a narrower layout width, then scale visually
          appContent.style.width = (scrollWidth / scale) + 'px';
          appContent.style.padding = '0 ' + Math.round(26 / scale) + 'px';
          appContent.style.transform = `scale(${scale})`;
          appContent.style.transformOrigin = 'top left';
        }
      }

      document.body.style.margin = '0';
      document.body.style.padding = '0';
      document.body.style.overflow = 'hidden';
      document.body.style.background = 'transparent';
    }, i, CONTENT_SCALE);

    await new Promise(r => setTimeout(r, 500));

    await page.screenshot({
      path: outPath,
      clip: { x: 0, y: 0, width: 1290, height: 2796 }
    });

    console.log(`Saved ${outPath}`);
    await page.close();
  }

  await browser.close();
  console.log('Done!');
})();

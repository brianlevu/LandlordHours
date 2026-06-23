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

const WIDTH = 2064;
const HEIGHT = 2752;
const CONTENT_SCALE = 1.95;

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: fs.existsSync('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
      ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      : undefined,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const filePath = path.resolve(__dirname, 'screenshot-generator.html');
  const ipadDir = path.resolve(__dirname, 'ipad-13');
  const fastlaneDir = path.resolve(__dirname, '..', 'fastlane', 'screenshots', 'en-US');
  fs.mkdirSync(ipadDir, { recursive: true });
  fs.mkdirSync(fastlaneDir, { recursive: true });

  for (let i = 0; i < NAMES.length; i++) {
    const name = NAMES[i];
    const outPath = path.resolve(ipadDir, `${name}-ipad-13.png`);
    const fastlanePath = path.resolve(fastlaneDir, `${name}-ipad-13.png`);

    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: 1 });
    await page.goto(`file://${filePath}`, { waitUntil: 'networkidle0', timeout: 30000 });
    await page.evaluate(() => document.fonts.ready);
    await new Promise(r => setTimeout(r, 1500));

    await page.evaluate((index, scale, width, height) => {
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
          frame.style.width = `${width}px`;
          frame.style.height = `${height}px`;
          frame.style.borderRadius = '0';
          frame.style.boxShadow = 'none';
          frame.style.overflow = 'visible';
        }
      });

      document.querySelectorAll('.screenshot').forEach((el, idx) => {
        if (idx === index) {
          el.style.width = `${width}px`;
          el.style.height = `${height}px`;
          el.style.transform = 'none';
          el.style.transformOrigin = 'top left';
        }
      });

      const style = document.createElement('style');
      style.textContent = `
        .screenshot {
          width: ${width}px !important;
          height: ${height}px !important;
        }
        .gallery-frame .screenshot {
          transform: none !important;
        }
        .screenshot::before {
          width: 1840px !important;
          height: 1840px !important;
          right: -610px !important;
          top: 600px !important;
          opacity: 0.72 !important;
        }
        .screenshot::after {
          background:
            radial-gradient(circle at 70% 52%, transparent 0%, rgba(5,0,62,0.10) 34%, rgba(5,0,62,0.44) 78%),
            linear-gradient(90deg, rgba(5,0,62,0.04), rgba(5,0,62,0.00) 48%, rgba(5,0,62,0.26)) !important;
        }
        .bottom-text {
          top: 112px !important;
          left: 112px !important;
          right: 112px !important;
        }
        .bottom-text::before {
          font-size: 42px !important;
          margin-bottom: 108px !important;
        }
        .bt-headline {
          font-size: 184px !important;
          line-height: 0.9 !important;
          letter-spacing: -5px !important;
          max-width: 1450px !important;
          margin-bottom: 48px !important;
        }
        .bt-sub {
          font-size: 50px !important;
          line-height: 1.18 !important;
          max-width: 820px !important;
        }
        .app-frame {
          box-shadow: 0 110px 230px rgba(0,0,0,0.52) !important;
        }
        #ss-0 .app-frame { top: 1170px !important; left: 930px !important; width: 1160px !important; height: 2380px !important; transform: rotate(-8deg) !important; }
        #ss-1 .app-frame { top: 1050px !important; left: 940px !important; width: 1160px !important; height: 2380px !important; transform: rotate(-7deg) !important; }
        #ss-2 .app-frame { top: 1110px !important; left: 970px !important; width: 1140px !important; height: 2340px !important; transform: rotate(-8deg) !important; }
        #ss-3 .app-frame { top: 1110px !important; left: 920px !important; width: 1160px !important; height: 2380px !important; transform: rotate(-7deg) !important; }
        #ss-4 .app-frame { top: 1100px !important; left: 970px !important; width: 1140px !important; height: 2340px !important; transform: rotate(-8deg) !important; }
      `;
      document.head.appendChild(style);

      const screenshot = document.querySelectorAll('.screenshot')[index];
      if (screenshot) {
        const appContent = screenshot.querySelector('.app-content');
        const appScroll = screenshot.querySelector('.app-scroll');

        if (appContent && appScroll) {
          const scrollWidth = appScroll.offsetWidth;
          appContent.style.width = `${scrollWidth / scale}px`;
          appContent.style.padding = `0 ${Math.round(26 / scale)}px`;
          appContent.style.transform = `scale(${scale})`;
          appContent.style.transformOrigin = 'top left';
        }
      }

      document.body.style.margin = '0';
      document.body.style.padding = '0';
      document.body.style.overflow = 'hidden';
      document.body.style.background = 'transparent';
    }, i, CONTENT_SCALE, WIDTH, HEIGHT);

    await new Promise(r => setTimeout(r, 500));

    await page.screenshot({
      path: outPath,
      clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT }
    });
    fs.copyFileSync(outPath, fastlanePath);

    console.log(`Saved ${outPath}`);
    console.log(`Copied ${fastlanePath}`);
    await page.close();
  }

  await browser.close();
  console.log('Done!');
})();

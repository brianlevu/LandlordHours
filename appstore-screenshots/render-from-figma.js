const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const W = 1290;
const H = 2796;
const PHONE_W = 430;
const PHONE_H = 932;
const FIGMA_DIR = path.resolve(__dirname, '../figma-redesign');

// Each screenshot config
const SCREENS = [
  {
    name: '01-dashboard',
    file: 'dashboard.html',
    phoneIndex: 1, // 0=Trial Active, 1=Paid User, 2=Trial Expired
    headline: 'Track every hour\ntoward tax status',
    bgGradient: 'linear-gradient(165deg, #1a1028 0%, #0e0e18 40%, #0a0a12 100%)',
    accentBlob: 'rgba(123,104,238,0.15)',
  },
  {
    name: '02-ai-tracking',
    file: 'track-v3.html',
    phoneIndex: 2, // 0=Empty, 1=AI Suggestion, 2=After Auto-fill
    headline: 'AI does the\nheavy lifting',
    bgGradient: 'linear-gradient(165deg, #14101f 0%, #0e0e18 40%, #0a0a12 100%)',
    accentBlob: 'rgba(123,104,238,0.12)',
  },
  {
    name: '03-reports',
    file: 'reports-v3.html',
    phoneIndex: 0, // Single phone with interactive goals
    headline: 'Smart reports\nfor tax season',
    bgGradient: 'linear-gradient(165deg, #110f20 0%, #0e0e18 40%, #0a0a12 100%)',
    accentBlob: 'rgba(139,92,246,0.12)',
  },
  {
    name: '04-properties',
    file: 'property-and-tax-profile.html',
    phoneIndex: 0, // 0=Add Property
    headline: 'All properties,\none view',
    bgGradient: 'linear-gradient(165deg, #1a1210 0%, #12100e 40%, #0a0a12 100%)',
    accentBlob: 'rgba(255,138,122,0.10)',
  },
  {
    name: '05-settings',
    file: 'settings.html',
    phoneIndex: 0, // 0=Pro User, 1=Free/Trial
    headline: 'Built for\nlandlords',
    bgGradient: 'linear-gradient(165deg, #14101f 0%, #0e0e18 40%, #0a0a12 100%)',
    accentBlob: 'rgba(123,104,238,0.12)',
  }
];

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  for (const screen of SCREENS) {
    console.log(`Rendering ${screen.name} from ${screen.file} [phone index ${screen.phoneIndex}]...`);

    // Step 1: Capture the phone element from the figma HTML
    const capturePage = await browser.newPage();
    // Use 3x DPR to get a high-res capture
    await capturePage.setViewport({ width: 1200, height: 2000, deviceScaleFactor: 2 });

    const htmlPath = path.join(FIGMA_DIR, screen.file);
    await capturePage.goto(`file://${htmlPath}`, { waitUntil: 'networkidle0', timeout: 30000 });
    await capturePage.evaluate(() => document.fonts.ready);
    await new Promise(r => setTimeout(r, 2000));

    // Get the correct phone element by index
    const phones = await capturePage.$$('.phone');
    console.log(`  Found ${phones.length} .phone elements`);

    if (screen.phoneIndex >= phones.length) {
      console.log(`  Phone index ${screen.phoneIndex} out of range, using 0`);
      screen.phoneIndex = 0;
    }

    const phone = phones[screen.phoneIndex];
    const phoneScreenshot = await phone.screenshot({ type: 'png' });
    const phonePngPath = path.join(__dirname, `_phone_${screen.name}.png`);
    fs.writeFileSync(phonePngPath, phoneScreenshot);

    const phoneBox = await phone.boundingBox();
    console.log(`  Phone box: ${Math.round(phoneBox.width)}x${Math.round(phoneBox.height)}`);

    await capturePage.close();

    // Step 2: Compose the final App Store screenshot
    const composePage = await browser.newPage();
    await composePage.setViewport({ width: W, height: H, deviceScaleFactor: 1 });

    const phoneBase64 = fs.readFileSync(phonePngPath).toString('base64');
    const headlineHTML = screen.headline.split('\n').join('<br>');

    const composeHTML = `<!DOCTYPE html>
<html>
<head>
<link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display&family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  width: ${W}px; height: ${H}px;
  overflow: hidden;
  background: ${screen.bgGradient};
  position: relative;
  font-family: 'DM Sans', sans-serif;
}
.blob1 {
  position: absolute; top: -100px; right: -100px;
  width: 600px; height: 600px; border-radius: 50%;
  background: radial-gradient(circle, ${screen.accentBlob}, transparent 70%);
  filter: blur(80px);
}
.blob2 {
  position: absolute; bottom: 200px; left: -150px;
  width: 500px; height: 500px; border-radius: 50%;
  background: radial-gradient(circle, ${screen.accentBlob}, transparent 70%);
  filter: blur(70px);
}
.phone-img-wrap {
  position: absolute;
  top: 40px; left: 40px; right: 40px;
  bottom: 320px;
  border-radius: 55px;
  overflow: hidden;
  box-shadow:
    0 0 0 1px rgba(255,255,255,0.06),
    0 25px 80px rgba(0,0,0,0.6),
    0 8px 30px rgba(0,0,0,0.4);
}
.phone-img-wrap img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: top center;
}
.bottom-text {
  position: absolute;
  bottom: 55px; left: 75px; right: 75px;
}
.headline {
  font-family: 'DM Serif Display', serif;
  font-size: 82px;
  color: #fff;
  line-height: 1.05;
  letter-spacing: -1.5px;
}
.phone-glow {
  position: absolute;
  top: 30px; left: 30px; right: 30px;
  bottom: 310px;
  border-radius: 60px;
  box-shadow: 0 0 120px 20px rgba(123,104,238,0.08);
}
</style>
</head>
<body>
  <div class="blob1"></div>
  <div class="blob2"></div>
  <div class="phone-glow"></div>
  <div class="phone-img-wrap">
    <img src="data:image/png;base64,${phoneBase64}" />
  </div>
  <div class="bottom-text">
    <div class="headline">${headlineHTML}</div>
  </div>
</body>
</html>`;

    await composePage.setContent(composeHTML, { waitUntil: 'networkidle0', timeout: 60000 });
    await composePage.evaluate(() => document.fonts.ready);
    await new Promise(r => setTimeout(r, 1500));

    const outPath = path.join(__dirname, `${screen.name}.png`);
    await composePage.screenshot({
      path: outPath,
      clip: { x: 0, y: 0, width: W, height: H }
    });
    console.log(`  Saved ${outPath}`);

    await composePage.close();
    fs.unlinkSync(phonePngPath);
  }

  await browser.close();
  console.log('\nAll done!');
})();

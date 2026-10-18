from PIL import Image, ImageDraw, ImageFont
R = '/Users/brian/AgentScratch/landlordhours/2026-10-18/refs-hifi'
F = '/Users/brian/AgentScratch/landlordhours/2026-10-18/hifi-frames'
O = F + '/compare'
pairs = [
    ('a-home', 'a-home/bevel-2-trends.png', 'today-behind'),
    ('a-home-onpace', 'a-home/cashapp-3-status-progress.png', 'today-onpace'),
    ('b-inbox', 'b-inbox/flighty-3-result-rows.png', 'inbox'),
    ('c-detail', 'c-detail/flighty-1-detail-hero.png', 'detail'),
    ('d-lockscreen', 'd-lockscreen/flighty-1-live-activity.png', 'lockscreen'),
    ('e-onboarding-welcome', 'e-onboarding/lyft-3-calendar-priming.png', 'onb-welcome'),
    ('e-onboarding-property', 'e-onboarding/flighty-2-select-calendars.png', 'onb-property'),
    ('e-onboarding-calendar', 'e-onboarding/flighty-1-calendar-sync-privacy.png', 'onb-calendar'),
    ('e-onboarding-location', 'e-onboarding/sesame-4-location-alert-preview.png', 'onb-location'),
    ('f-share', 'f-share/brex-1-auto-verified-sheet.png', 'share'),
    ('g-records', 'g-records/remote-2-status-rows.png', 'records'),
    ('h-report', 'h-report/flighty-1-report-summary.png', 'report'),
    ('h-export', 'h-report/crouton-2-pdf-preview-toggles.png', 'export'),
    ('i-paywall', 'i-paywall/flighty-1-product-hero-plan-card.png', 'paywall'),
    ('i-locked', 'i-paywall/flighty-2-locked-preview-inline.png', 'locked'),
    ('j-settings', 'j-settings/wisprflow-2-privacy-toggles.png', 'settings'),
    ('k-empty-today', 'k-empty/mercury-5-zero-state-home.png', 'empty-today'),
    ('k-empty-inbox', 'k-empty/flighty-1-list-empty.png', 'empty-inbox'),
    ('l-tabbar', 'l-tabbar/flighty-1-tabs-plus-search-circle.png', 'today-behind'),
]
H = 1300
try:
    font = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 30)
except Exception:
    font = ImageFont.load_default()

def fit(p):
    im = Image.open(p).convert('RGB')
    return im.resize((int(im.width * H / im.height), H))

for name, ref, ours in pairs:
    ims = [fit(f'{R}/{ref}'), fit(f'{F}/{ours}-light.png'), fit(f'{F}/{ours}-dark.png')]
    labels = ['REFERENCE: ' + ref.split('/')[-1].replace('.png', ''), 'OURS · light', 'OURS · dark']
    W = sum(i.width for i in ims) + 40 * 4
    m = Image.new('RGB', (W, H + 110), (236, 236, 240))
    d = ImageDraw.Draw(m)
    x = 40
    for im, lab in zip(ims, labels):
        m.paste(im, (x, 90))
        d.text((x, 34), lab, fill=(30, 30, 30), font=font)
        x += im.width + 40
    m.save(f'{O}/{name}.jpg', quality=88)
print(len(pairs))

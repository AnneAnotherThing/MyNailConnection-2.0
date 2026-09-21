"""Preview sheets: one PNG per ad set, feed frames in a grid.
Run from campaign/insta-ads after render.sh."""
from PIL import Image

SETS = {
    'preview-feed.png': ['01-hook', '02-filter', '03-one-tap', '04-use-some',
                         '05-only-pay', '06-no-cut', '07-cta'],
    'preview-open-today.png': ['open-01-hook', 'open-02-what-happens', 'open-03-always-true',
                               'open-04-compare', 'open-05-honest', 'open-06-cta'],
}
W, H, GAP = 432, 540, 12

for out, names in SETS.items():
    cols = 4 if len(names) > 6 else 3
    rows = -(-len(names) // cols)
    sheet = Image.new('RGB', (cols * W + (cols + 1) * GAP, rows * H + (rows + 1) * GAP), '#E9E4E4')
    for i, n in enumerate(names):
        im = Image.open(f'png/feed-{n}.png').convert('RGB').resize((W, H), Image.LANCZOS)
        sheet.paste(im, (GAP + (i % cols) * (W + GAP), GAP + (i // cols) * (H + GAP)))
    sheet.save(out)
    print('wrote', out)

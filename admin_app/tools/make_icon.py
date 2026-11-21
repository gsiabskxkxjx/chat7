# يولّد أيقونة تطبيق الأدمن (درع بنفسجي) ويكتبها بمجلد android/app/src/main/res
import os
from PIL import Image, ImageDraw

RES = 'android/app/src/main/res'
BG = (69, 39, 160)      # بنفسجي غامق
FG = (255, 255, 255)


def shield(size, scale):
    """درع أبيض مع قفل صغير بالنص، على خلفية شفافة"""
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = size * scale
    cx, cy = size / 2, size / 2
    w, h = s * 0.74, s * 0.86
    top = cy - h / 2
    pts = [
        (cx, top),
        (cx + w / 2, top + h * 0.14),
        (cx + w / 2, top + h * 0.52),
        (cx + w * 0.36, top + h * 0.76),
        (cx, top + h),
        (cx - w * 0.36, top + h * 0.76),
        (cx - w / 2, top + h * 0.52),
        (cx - w / 2, top + h * 0.14),
    ]
    d.polygon(pts, fill=FG + (255,))
    # ثقب مفتاح بلون الخلفية
    r = w * 0.11
    ky = top + h * 0.42
    d.ellipse((cx - r, ky - r, cx + r, ky + r), fill=BG + (255,))
    d.polygon([(cx - r * 0.55, ky + r * 0.6), (cx + r * 0.55, ky + r * 0.6),
               (cx + r * 0.85, ky + h * 0.26), (cx - r * 0.85, ky + h * 0.26)], fill=BG + (255,))
    return im


def put(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
adaptive = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

big = 1024
for d, n in legacy.items():
    base = Image.new('RGBA', (big, big), BG + (255,))
    base.alpha_composite(shield(big, 0.82))
    ic = base.resize((n, n), Image.LANCZOS)
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.22), fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.paste(ic, (0, 0), mask)
    put(out, f'{RES}/mipmap-{d}/ic_launcher.png')

for d, n in adaptive.items():
    fg = shield(big, 0.62).resize((n, n), Image.LANCZOS)   # يبقى داخل المنطقة الآمنة
    put(fg, f'{RES}/mipmap-{d}/ic_launcher_foreground.png')
    mono = Image.new('RGBA', (n, n), (255, 255, 255, 0))
    mono.putalpha(fg.getchannel('A'))
    put(mono, f'{RES}/mipmap-{d}/ic_launcher_monochrome.png')

os.makedirs(f'{RES}/values', exist_ok=True)
with open(f'{RES}/values/ic_launcher_background.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % BG)
os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
with open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
print('admin icon generated')

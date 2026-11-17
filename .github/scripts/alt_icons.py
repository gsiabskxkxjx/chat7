"""أيقونات بديلة لتطبيق بيناتنا (أندرويد).

يولّد من logo.png أربع نسخ بألوان ثانية، ويسجّلها كـ activity-alias بالـ manifest.
أي فشل بأي مرحلة = ما نغيّر شي، وتبقى الأيقونة الأساسية شغالة كالعادة.
تشغيل محلي للتجربة: ANDROID_ROOT=/مسار python3 alt_icons.py
"""
import os
import re
import sys

try:
    from PIL import Image, ImageDraw
except Exception as e:  # pillow مو موجود
    print('alt icons skipped: no PIL', e)
    sys.exit(0)

ROOT = os.environ.get('ANDROID_ROOT', '.')
RES = os.path.join(ROOT, 'android/app/src/main/res')
MANIFEST = os.path.join(ROOT, 'android/app/src/main/AndroidManifest.xml')
LOGO = os.path.join(ROOT, 'logo.png')

# الاسم -> (اسم الملف، إزاحة اللون أو None لليلي)
VARIANTS = [
    ('Rose', 'rose', 60),
    ('Mint', 'mint', 184),
    ('Sunset', 'sunset', 89),
    ('Night', 'night', None),
]
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}


def shift_hue(im, shift):
    alpha = im.getchannel('A')
    h, s, v = im.convert('RGB').convert('HSV').split()
    h = h.point(lambda x: (x + shift) % 256)
    out = Image.merge('HSV', (h, s, v)).convert('RGB').convert('RGBA')
    out.putalpha(alpha)
    return out


def night(im):
    alpha = im.getchannel('A')
    g = im.convert('L').point(lambda v: int(255 * ((v / 255.0) ** 2.4)))
    out = Image.merge('RGB', (g, g, g)).convert('RGBA')
    out.putalpha(alpha)
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def make(base, key, shift):
    im = night(base) if shift is None else shift_hue(base, shift)
    for d, n in LEGACY.items():
        ic = im.resize((n, n), Image.LANCZOS)
        mask = Image.new('L', (n, n), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.22), fill=255)
        out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
        out.paste(ic, (0, 0), mask)
        save(out, f'{RES}/mipmap-{d}/ic_alt_{key}.png')
    for d, n in ADAPTIVE.items():
        save(im.resize((n, n), Image.LANCZOS), f'{RES}/mipmap-{d}/ic_alt_{key}_foreground.png')
    r, g, b = im.resize((8, 8), Image.LANCZOS).convert('RGB').getpixel((0, 0))
    os.makedirs(f'{RES}/values', exist_ok=True)
    with open(f'{RES}/values/ic_alt_{key}_background.xml', 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                f'    <color name="ic_alt_{key}_background">#{r:02X}{g:02X}{b:02X}</color>\n</resources>\n')
    os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
    mono = '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n' if os.path.exists(
        f'{RES}/mipmap-xxxhdpi/ic_launcher_monochrome.png') else ''
    with open(f'{RES}/mipmap-anydpi-v26/ic_alt_{key}.xml', 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                f'    <background android:drawable="@color/ic_alt_{key}_background"/>\n'
                f'    <foreground android:drawable="@mipmap/ic_alt_{key}_foreground"/>\n'
                f'{mono}</adaptive-icon>\n')


def main():
    if not os.path.exists(LOGO):
        print('alt icons skipped: no logo.png')
        return
    if not os.path.exists(MANIFEST):
        print('alt icons skipped: no manifest')
        return
    s = open(MANIFEST, encoding='utf-8').read()
    if 'IconDefault' in s:
        print('alt icons already added')
        return
    # فلتر التشغيل الرئيسي لازم يكون واحد بالضبط، وهو اللي ننقله للـ alias
    pat = re.compile(
        r'\s*<intent-filter>\s*<action android:name="android\.intent\.action\.MAIN"\s*/>\s*'
        r'<category android:name="android\.intent\.category\.LAUNCHER"\s*/>\s*</intent-filter>')
    if len(pat.findall(s)) != 1:
        print('alt icons skipped: launcher filter not found exactly once')
        return

    im = Image.open(LOGO).convert('RGBA')
    w, h = im.size
    side = min(w, h)
    base = im.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
    done = []
    for name, key, shift in VARIANTS:
        try:
            make(base, key, shift)
            done.append((name, key))
        except Exception as e:
            print('variant failed', name, e)
    if not done:
        print('alt icons skipped: no variant generated')
        return

    launcher = ('<intent-filter><action android:name="android.intent.action.MAIN"/>'
                '<category android:name="android.intent.category.LAUNCHER"/></intent-filter>')
    aliases = (f'\n        <activity-alias android:name="com.bainatna.chat.IconDefault" android:targetActivity=".MainActivity"'
               f' android:enabled="true" android:exported="true" android:icon="@mipmap/ic_launcher" android:label="بيناتنا">'
               f'{launcher}</activity-alias>')
    for name, key in done:
        aliases += (f'\n        <activity-alias android:name="com.bainatna.chat.Icon{name}" android:targetActivity=".MainActivity"'
                    f' android:enabled="false" android:exported="true" android:icon="@mipmap/ic_alt_{key}" android:label="بيناتنا">'
                    f'{launcher}</activity-alias>')
    s = pat.sub('', s, count=1)
    if '</application>' not in s:
        print('alt icons skipped: no </application>')
        return
    s = s.replace('</application>', aliases + '\n    </application>', 1)
    open(MANIFEST, 'w', encoding='utf-8').write(s)
    print('alt icons added:', [n for n, _ in done])


main()

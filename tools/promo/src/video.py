#!/usr/bin/env python3
"""메에일 홍보 영상(세로 1080x1920, 30fps, 약 11초).

재료(모두 이 저장소에서 만든 것):
  - 앱 화면: apps/mobile/build/screenshots/*.png  (flutter test --tags screenshot)
  - 염소 프레임: apps/mobile/build/promo/*.png    (flutter test --tags promo)
  - 배경음악: apps/mobile/build/promo/bgm.wav     (pnpm --filter @meeil/tools-promo bgm)
  - 효과음: apps/mobile/assets/sounds/*.wav       (tools/sounds 합성)
결과: docs/promo/meeil_promo.mp4
"""
import math
import os
import random
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MOB = os.path.join(ROOT, 'apps/mobile')
SHOTS = os.path.join(MOB, 'build/screenshots')
PROMO = os.path.join(MOB, 'build/promo')
SOUNDS = os.path.join(MOB, 'assets/sounds')
FONTS = os.path.join(MOB, 'assets/fonts')
OUT_DIR = os.path.join(ROOT, 'docs/promo')

W, H, FPS = 1080, 1920, 30
DUR = 11.0
N = int(DUR * FPS)

CREAM = (255, 248, 236)
SKY = (205, 235, 255)
MINT = (189, 235, 215)
PINK = (255, 201, 214)
YELLOW = (255, 224, 138)
BROWN = (90, 70, 54)
OUTLINE = (122, 92, 72)
HEART = (255, 143, 171)

JUA = lambda s: ImageFont.truetype(os.path.join(FONTS, 'Jua-Regular.ttf'), s)
BODY = lambda s: ImageFont.truetype(os.path.join(FONTS, 'GowunDodum-Regular.ttf'), s)

# ───────── 이징 ─────────
clamp = lambda x, a=0.0, b=1.0: max(a, min(b, x))
ease_out = lambda t: 1 - (1 - clamp(t)) ** 3
ease_in_out = lambda t: (lambda u: 3 * u * u - 2 * u * u * u)(clamp(t))


def back_out(t, s=1.9):
    t = clamp(t) - 1
    return t * t * ((s + 1) * t + s) + 1


def prog(t, a, b):
    return clamp((t - a) / (b - a))


# ───────── 재료 불러오기 ─────────
def load(name):
    return Image.open(os.path.join(SHOTS, f'{name}.png')).convert('RGB')


def seq(prefix, n):
    return [Image.open(os.path.join(PROMO, f'{prefix}_{i:02d}.png')).convert('RGBA') for i in range(n)]


shots = {k: load(k) for k in [
    'm2_01_map_nation', 'm3_01_compose_ready', 'm3_03_handoff', 'm3_08_arrival',
    'm4_02_nation_paper', 'm6_02_eaten_sender',
]}
walk = {c: seq(f'goat_{c}_walk', 15) for c in ['red', 'blue', 'nation']}
idle = seq('goat_red_idle', 60)
eat = seq('eat', 78)
face = Image.open(os.path.join(ROOT, 'docs/store/icon-512.png')).convert('RGBA')


def goat_face(size):
    """아이콘에서 노랑 바탕을 뺀 얼굴(스플래시 그림)"""
    p = os.path.join(MOB, 'android/app/src/main/res/drawable-nodpi/splash_goat.png')
    return Image.open(p).convert('RGBA').resize((size, size), Image.LANCZOS)


FACE = goat_face(520)

# ───────── 그리기 도구 ─────────
def rounded_mask(size, r):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m


def phone(img, width, zoom=1.0, focus=(0.5, 0.3), height=None):
    """앱 화면을 폰 모양 카드로. zoom>1이면 focus 쪽으로 확대(켄번스)"""
    sw, sh = img.size
    cw = int(sw / zoom)
    ch = int(cw * (height or 1700) / width) if height else int(sh / zoom)
    cx = int(clamp(focus[0] * sw - cw / 2, 0, sw - cw))
    cy = int(clamp(focus[1] * sh - ch / 2, 0, sh - ch))
    crop = img.crop((cx, cy, cx + cw, cy + ch))
    hh = height or int(width * sh / sw)
    crop = crop.resize((width, hh), Image.BILINEAR)
    border = 12
    card = Image.new('RGBA', (width + border * 2, hh + border * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, card.width - 1, card.height - 1], 54, fill=OUTLINE)
    card.paste(crop, (border, border), rounded_mask(crop.size, 44))
    return card


def shadowed(card, blur=18, off=(0, 18)):
    sh = Image.new('RGBA', (card.width + blur * 4, card.height + blur * 4), (0, 0, 0, 0))
    a = card.split()[3].point(lambda v: int(v * 0.25))
    sh.paste((60, 40, 30, 255), (blur * 2 + off[0], blur * 2 + off[1]), a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    sh.alpha_composite(card, (blur * 2, blur * 2))
    return sh, blur * 2


def paste_center(base, img, cx, cy, scale=1.0, alpha=1.0, angle=0.0):
    if scale <= 0.01 or alpha <= 0.01:
        return
    im = img
    if scale != 1.0:
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.BILINEAR)
    if angle:
        im = im.rotate(angle, resample=Image.BICUBIC, expand=True)
    if alpha < 1:
        a = im.split()[3].point(lambda v: int(v * alpha))
        im = im.copy()
        im.putalpha(a)
    base.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def caption(text, sub=None, color=BROWN, size=78):
    """하얀 알약 위 굵은 자막(외곽선), 아래에 작은 설명"""
    f = JUA(size)
    tw, th = f.getbbox(text)[2], f.getbbox(text)[3]
    pad_x, pad_y = 46, 26
    sub_f = BODY(40)
    sw = sub_f.getbbox(sub)[2] if sub else 0
    w = max(tw, sw) + pad_x * 2
    h = th + pad_y * 2 + (64 if sub else 0)
    img = Image.new('RGBA', (w + 20, h + 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([10, 16, w + 10, h + 16], 44, fill=(122, 92, 72, 90))
    d.rounded_rectangle([10, 10, w + 10, h + 10], 44, fill=(255, 255, 255, 245), outline=OUTLINE, width=6)
    d.text((10 + (w - tw) / 2, 10 + pad_y - 4), text, font=f, fill=color)
    if sub:
        d.text((10 + (w - sw) / 2, 10 + pad_y + th + 18), sub, font=sub_f, fill=BROWN)
    return img


def star(d, x, y, r, fill):
    pts = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.38
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    d.polygon(pts, fill=fill)


def heart(d, x, y, r, fill):
    d.ellipse([x - r, y - r * 0.9, x, y + r * 0.1], fill=fill)
    d.ellipse([x, y - r * 0.9, x + r, y + r * 0.1], fill=fill)
    d.polygon([(x - r * 0.98, y - r * 0.3), (x + r * 0.98, y - r * 0.3), (x, y + r * 1.05)], fill=fill)


def background(color, t, dots=True):
    bg = Image.new('RGBA', (W, H), color + (255,))
    if dots:
        d = ImageDraw.Draw(bg)
        # 천천히 떠오르는 동그라미 무늬
        rnd = random.Random(3)
        for i in range(16):
            x = rnd.uniform(0, W)
            y = (rnd.uniform(0, H) - t * rnd.uniform(30, 70)) % (H + 200) - 100
            r = rnd.uniform(18, 60)
            d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(min(255, c + 14) for c in color) + (255,))
    return bg


def particles(base, t, t0, kind, origin, n=26, seed=1, life=1.2, spread=520, rise=-380):
    """반짝이/하트 꽃가루: t0에 origin에서 터져 퍼진다"""
    age = t - t0
    if age < 0 or age > life:
        return
    d = ImageDraw.Draw(base)
    rnd = random.Random(seed)
    for i in range(n):
        ang = rnd.uniform(0, 2 * math.pi)
        speed = rnd.uniform(0.35, 1.0)
        p = ease_out(age / life)
        x = origin[0] + math.cos(ang) * spread * speed * p
        y = origin[1] + math.sin(ang) * spread * 0.6 * speed * p + rise * p * rnd.uniform(0.2, 1) + 380 * (age / life) ** 2
        fade = 1 - clamp((age / life - 0.6) / 0.4)
        r = rnd.uniform(12, 28) * (0.6 + 0.4 * fade)
        if r < 2 or fade <= 0:
            continue
        if kind == 'heart':
            heart(d, x, y, r, HEART if i % 3 else PINK)
        else:
            star(d, x, y, r, YELLOW if i % 2 else (255, 255, 255))


def walker(base, t, color, y, t0, t1, x0=-200, x1=W + 200, scale=0.75):
    if t < t0 or t > t1:
        return
    x = x0 + (x1 - x0) * (t - t0) / (t1 - t0)
    fr = walk[color][int(t * FPS) % 15]
    paste_center(base, fr, x, y, scale)


def whip(a, b, p):
    """휙 넘기기: a는 왼쪽으로, b는 오른쪽에서. 가로 흐림으로 속도감"""
    e = ease_in_out(p)
    off = int(W * e)
    out = Image.new('RGBA', (W, H))
    out.alpha_composite(a, (-off, 0))
    out.alpha_composite(b, (W - off, 0))
    blur = math.sin(math.pi * p)
    if blur > 0.05:
        small = out.resize((max(1, int(W / (1 + 18 * blur))), H), Image.BILINEAR)
        out = Image.blend(out, small.resize((W, H), Image.BILINEAR), 0.7 * blur)
    return out


# ───────── 장면 ─────────
CUTS = [0.0, 1.95, 3.95, 5.95, 7.45, 8.45, 9.25, DUR]


def screen_scene(t, t0, t1, shot, bg, cap, sub, zoom=(1.0, 1.12), focus=(0.5, 0.35), extra=None):
    p = prog(t, t0, t1)
    base = background(bg, t)
    z = zoom[0] + (zoom[1] - zoom[0]) * ease_in_out(p)
    card = phone(shots[shot], 760, zoom=z, focus=focus, height=1500)
    img, pad = shadowed(card)
    # 들어올 때 살짝 아래에서 튀어오름
    rise = (1 - back_out(prog(t, t0, t0 + 0.45))) * 120
    base.alpha_composite(img, (int(W / 2 - card.width / 2 - pad), int(380 + rise - pad)))
    if extra:
        extra(base, t)
    c = caption(cap, sub)
    cp = back_out(prog(t, t0 + 0.08, t0 + 0.42))
    paste_center(base, c, W / 2, 210, scale=0.4 + 0.6 * cp, alpha=clamp(cp * 1.5))
    return base


def scene_intro(t):
    base = background(CREAM, t)
    # 둥근 해 + 햇살
    d = ImageDraw.Draw(base)
    sp = back_out(prog(t, 0.05, 0.6))
    cx, cy = W / 2, 760
    for i in range(14):
        a = i * 2 * math.pi / 14 + t * 0.6
        r0, r1 = 300 * sp, 520 * sp
        d.polygon([(cx + math.cos(a - 0.09) * r0, cy + math.sin(a - 0.09) * r0),
                   (cx + math.cos(a) * r1, cy + math.sin(a) * r1),
                   (cx + math.cos(a + 0.09) * r0, cy + math.sin(a + 0.09) * r0)], fill=(255, 236, 170, 255))
    d.ellipse([cx - 330 * sp, cy - 330 * sp, cx + 330 * sp, cy + 330 * sp], fill=YELLOW)
    bob = math.sin(t * 6) * 10
    paste_center(base, FACE, cx, cy + bob, scale=0.95 * back_out(prog(t, 0.1, 0.6)), angle=math.sin(t * 5) * 4)
    particles(base, t, 0.55, 'star', (cx, cy), n=22, seed=4, life=1.1)
    # 제목
    tp = back_out(prog(t, 0.6, 1.0))
    title = Image.new('RGBA', (900, 260), (0, 0, 0, 0))
    td = ImageDraw.Draw(title)
    f = JUA(210)
    tw = f.getbbox('메에일')[2]
    td.text(((900 - tw) / 2, 0), '메에일', font=f, fill=BROWN, stroke_width=10, stroke_fill=(255, 255, 255))
    paste_center(base, title, W / 2, 1280 - (1 - tp) * 200, scale=0.5 + 0.5 * tp, alpha=clamp(tp * 2))
    sp2 = ease_out(prog(t, 0.95, 1.3))
    sub = caption('우체부 염소가 전해 주는 느린 편지', size=56)
    paste_center(base, sub, W / 2, 1490 + (1 - sp2) * 60, alpha=sp2)
    walker(base, t, 'red', 1760, 0.2, 2.6, scale=0.62)
    return base


def map_extra(base, t):
    walker(base, t, 'blue', 1770, 2.0, 4.2, scale=0.7)
    walker(base, t, 'nation', 1790, 2.4, 4.6, scale=0.55)


def handoff_extra(base, t):
    particles(base, t, 4.95, 'star', (W / 2, 1100), n=20, seed=8, life=1.0)


def arrival_extra(base, t):
    particles(base, t, 6.05, 'heart', (W / 2, 1150), n=30, seed=11, life=1.3, spread=620)
    particles(base, t, 6.5, 'heart', (W / 2, 1050), n=18, seed=12, life=1.0)


def scene_compose(t):
    # 4.85초에 편지 쓰기 → 맡기기 화면으로 번쩍
    if t < 4.85:
        return screen_scene(t, CUTS[2], CUTS[3], 'm3_01_compose_ready', YELLOW,
                            '우리 동네에 염소가 오면', '편지를 맡겨요', zoom=(1.0, 1.08), focus=(0.5, 0.25))
    img = screen_scene(t, CUTS[2], CUTS[3], 'm3_03_handoff', YELLOW,
                       '염소 가방에 편지를 쏙!', '도착까지 최대 3일, 느려서 더 설레요',
                       zoom=(1.05, 1.15), focus=(0.5, 0.55), extra=handoff_extra)
    flash = 1 - prog(t, 4.85, 5.05)
    if flash > 0:
        img = Image.blend(img, Image.new('RGBA', (W, H), (255, 255, 255, 255)), 0.8 * flash)
    return img


def scene_eat(t):
    t0, t1 = CUTS[5], CUTS[6]
    base = background(PINK, t)
    # 0.8초에 먹기 연출 78장을 빠르게
    i = min(77, int(prog(t, t0, t1 - 0.05) * 77))
    fr = eat[i]
    shake = (math.sin(t * 90) * 10, math.cos(t * 70) * 8) if 0.25 < prog(t, t0, t1) < 0.75 else (0, 0)
    card = Image.new('RGBA', (980, 640), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle([0, 0, 979, 639], 60, fill=(255, 255, 255, 255), outline=OUTLINE, width=8)
    card.alpha_composite(fr.resize((960, 600), Image.LANCZOS), (10, 20))
    paste_center(base, card, W / 2 + shake[0], 1050 + shake[1], scale=back_out(prog(t, t0, t0 + 0.25)))
    c = caption('나쁜 편지는 염소가 냠냠!', '신고·차단으로 안전하게')
    paste_center(base, c, W / 2, 330, scale=back_out(prog(t, t0 + 0.05, t0 + 0.3)))
    return base


def scene_outro(t):
    t0 = CUTS[6]
    base = background(CREAM, t, dots=False)
    d = ImageDraw.Draw(base)
    d.rectangle([0, 1560, W, H], fill=MINT)
    d.ellipse([-300, 1440, 700, 1720], fill=MINT)
    d.ellipse([500, 1480, 1500, 1700], fill=MINT)
    pop = back_out(prog(t, t0, t0 + 0.45))
    paste_center(base, FACE, W / 2, 640 + math.sin(t * 6) * 8, scale=0.9 * pop)
    tp = back_out(prog(t, t0 + 0.15, t0 + 0.55))
    title = Image.new('RGBA', (900, 240), (0, 0, 0, 0))
    td = ImageDraw.Draw(title)
    f = JUA(190)
    tw = f.getbbox('메에일')[2]
    td.text(((900 - tw) / 2, 0), '메에일', font=f, fill=BROWN, stroke_width=10, stroke_fill=(255, 255, 255))
    # 도장 쾅: 크게 들어와 제자리
    paste_center(base, title, W / 2, 1060, scale=1 + 0.6 * (1 - tp), alpha=clamp(tp * 2))
    particles(base, t, t0 + 0.5, 'star', (W / 2, 1060), n=26, seed=21, life=1.0, spread=640)
    sp = ease_out(prog(t, t0 + 0.6, t0 + 0.9))
    c = caption('곧 Google Play에서 만나요', size=60)
    paste_center(base, c, W / 2, 1300 + (1 - sp) * 50, alpha=sp)
    walker(base, t, 'red', 1600, t0 + 0.1, DUR, x0=-150, x1=W * 0.95, scale=0.55)
    walker(base, t, 'nation', 1640, t0 + 0.3, DUR, x0=-250, x1=W * 0.75, scale=0.5)
    walker(base, t, 'blue', 1620, t0 + 0.5, DUR, x0=-350, x1=W * 0.55, scale=0.5)
    fade = prog(t, DUR - 0.5, DUR)
    if fade > 0:
        base = Image.blend(base, Image.new('RGBA', (W, H), CREAM + (255,)), fade)
    return base


SCENES = [
    scene_intro,
    lambda t: screen_scene(t, CUTS[1], CUTS[2], 'm2_01_map_nation', SKY, '우체부 염소들이 전국을 돌아요',
                           '지도 위를 뒤뚱뒤뚱 걷는 염소들', zoom=(1.0, 1.25), focus=(0.48, 0.42), extra=map_extra),
    scene_compose,
    lambda t: screen_scene(t, CUTS[3], CUTS[4], 'm3_08_arrival', PINK, '편지가 도착했어요!',
                           '염소가 문 앞까지 가져다줘요', zoom=(1.0, 1.2), focus=(0.5, 0.55), extra=arrival_extra),
    lambda t: screen_scene(t, CUTS[4], CUTS[5], 'm4_02_nation_paper', MINT, '다 같이 쓰는 롤링페이퍼',
                           '전국·도·시 두루마리 염소가 오면 한마디', zoom=(1.0, 1.1), focus=(0.5, 0.45)),
    scene_eat,
    scene_outro,
]
WHIP = 0.2  # 장면 사이 휙 넘기기(초)


def frame(t):
    k = max(i for i in range(len(SCENES)) if t >= CUTS[i])
    cur = SCENES[k](t)
    # 다음 장면 시작 직전 WHIP초는 넘기기 전환(인트로→지도, 롤링→먹기 등 모든 컷)
    if k + 1 < len(SCENES) and t > CUTS[k + 1] - WHIP and k not in (2,):
        nxt = SCENES[k + 1](CUTS[k + 1] + 0.01)
        return whip(cur, nxt, prog(t, CUTS[k + 1] - WHIP, CUTS[k + 1]))
    return cur


# ───────── 소리 ─────────
SFX = [  # (초, 파일, 음량)
    (0.22, 'goat-bleat-1', 0.9),
    (2.15, 'goat-bleat-2', 0.8),
    (4.85, 'letter-open', 0.9),
    (5.0, 'goat-bleat-2', 0.6),
    (6.0, 'points', 0.8),
    (6.45, 'letter-open', 0.7),
    (7.5, 'stamp', 0.6),
    (8.5, 'chomp', 0.65),
    (9.55, 'stamp', 1.0),
    (9.75, 'points', 0.7),
    (10.1, 'goat-bleat-1', 0.7),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    video = os.path.join(PROMO, 'video_only.mp4')
    preview = os.path.join(PROMO, 'frames')
    os.makedirs(preview, exist_ok=True)
    enc = subprocess.Popen(
        ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
         '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
         '-pix_fmt', 'yuv420p', video],
        stdin=subprocess.PIPE,
    )
    for i in range(N):
        t = i / FPS
        img = frame(t).convert('RGB')
        enc.stdin.write(img.tobytes())
        if i % 15 == 0:
            img.resize((270, 480)).save(os.path.join(preview, f'{i:03d}.png'))
        if i % 30 == 0:
            print(f'{t:4.1f}s', file=sys.stderr)
    enc.stdin.close()
    enc.wait()

    # 소리: 브금 + 효과음(지정 시각에) → AAC
    inputs = ['-i', video, '-i', os.path.join(PROMO, 'bgm.wav')]
    chains, labels = ['[1:a]volume=0.55[bgm]'], ['[bgm]']
    for j, (at, name, vol) in enumerate(SFX):
        inputs += ['-i', os.path.join(SOUNDS, f'{name}.wav')]
        ms = int(at * 1000)
        chains.append(f'[{j + 2}:a]aresample=44100,volume={vol},adelay={ms}|{ms}[s{j}]')
        labels.append(f'[s{j}]')
    mix = ';'.join(chains) + ';' + ''.join(labels) + f'amix=inputs={len(labels)}:normalize=0,alimiter=limit=0.95[a]'
    out = os.path.join(OUT_DIR, 'meeil_promo.mp4')
    subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error', *inputs, '-filter_complex', mix, '-map', '0:v', '-map', '[a]',
         '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', str(DUR), '-movflags', '+faststart', out],
        check=True,
    )
    print(out)


if __name__ == '__main__':
    main()

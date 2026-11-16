# 원본(왼쪽 또는 위)과 mock으로 찍은 Roblox 쪽 화면(오른쪽 또는 아래)을 나란히 붙인 그림을 만든다 → work/cmp-<이름>-<크기>.png
#   python tools/ui/cmp.py 1280x720 menu hud-boss …      (이름을 주지 않으면 둘 다 있는 것 전부)
#   python tools/ui/cmp.py --real 1280x720 …             (shots/real-<이름>-… : 진짜 Gfx로 찍은 것과 견준다)
import sys, os, glob
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
prefix = ''
if args and args[0] == '--real':
    prefix = 'real-'
    args = args[1:]
size = args[0]
names = args[1:] or sorted(os.path.basename(p)[: -len(size) - 5] for p in glob.glob(os.path.join(here, 'ref', '*-%s.png' % size)))
for n in names:
    ra = os.path.join(here, 'ref', '%s-%s.png' % (n, size))
    rb = os.path.join(here, 'shots', '%s%s-%s.png' % (prefix, n, size))
    if not (os.path.exists(ra) and os.path.exists(rb)):
        continue
    a, b = Image.open(ra).convert('RGB'), Image.open(rb).convert('RGB')
    if a.width <= a.height * 1.2:
        im = Image.new('RGB', (a.width + b.width + 8, max(a.height, b.height)), (255, 0, 255))
        im.paste(a, (0, 0))
        im.paste(b, (a.width + 8, 0))
    else:
        im = Image.new('RGB', (max(a.width, b.width), a.height + b.height + 8), (255, 0, 255))
        im.paste(a, (0, 0))
        im.paste(b, (0, a.height + 8))
    out = os.path.join(here, 'work', 'cmp-%s%s-%s.png' % (prefix, n, size))
    im.save(out)
    print(out)

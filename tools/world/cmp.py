# 원본과 우리 화면을 나란히 붙인다: python tools/world/cmp.py <화면 크기> <장면.이름> [배율] [x y w h (잘라 볼 곳)]
import sys
from PIL import Image
vp, name = sys.argv[1], sys.argv[2]
k = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
d = 'tools/world/shots/%s/' % vp
a = Image.open(d + name + '.orig.png').convert('RGB')
b = Image.open(d + name + '.png').convert('RGB')
if len(sys.argv) > 7:
    x, y, w, h = map(int, sys.argv[4:8])
    a = a.crop((x, y, x + w, y + h)); b = b.crop((x, y, x + w, y + h))
w, h = int(a.width * k), int(a.height * k)
a = a.resize((w, h), Image.LANCZOS); b = b.resize((w, h), Image.LANCZOS)
out = Image.new('RGB', (w * 2 + 6, h), (255, 0, 255))
out.paste(a, (0, 0)); out.paste(b, (w + 6, 0))
import os
os.makedirs('tools/world/work/cmp', exist_ok=True)
out.save('tools/world/work/cmp/%s.%s.png' % (vp, name))
print('tools/world/work/cmp/%s.%s.png' % (vp, name), out.size)

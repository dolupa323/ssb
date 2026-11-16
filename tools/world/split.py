# 세로로 긴 그림을 높이 h마다 잘라 여러 파일로: python split.py <긴 그림> <h> <파일…>
import sys
from PIL import Image
im = Image.open(sys.argv[1])
h = int(sys.argv[2])
for i, n in enumerate(sys.argv[3:]):
    im.crop((0, i * h, im.width, (i + 1) * h)).save(n)
print(im.size)

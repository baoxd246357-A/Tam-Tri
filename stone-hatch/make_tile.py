"""Nắn phối cảnh ảnh tấm đá -> ảnh chữ nhật đúng kích thước (1 px = 1 mm, DPI 25.4)
dùng cho AutoCAD Express Tools > Draw > Super Hatch > Image.
Dùng: python3 make_tile.py anh.jpg ra.png 2600 1850 "x,y x,y x,y x,y"   (TL TR BR BL, đơn vị pixel ảnh gốc)"""
import sys
import numpy as np
from PIL import Image

def coeffs(dst, src):
    A = []
    for (x, y), (u, v) in zip(dst, src):
        A += [[x, y, 1, 0, 0, 0, -u*x, -u*y], [0, 0, 0, x, y, 1, -v*x, -v*y]]
    return np.linalg.solve(np.array(A, float), np.array(src, float).reshape(8))

src, out, W, H, pts = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
P = [tuple(map(float, p.split(','))) for p in pts.split()]
im = Image.open(src).convert('RGB')
res = im.transform((W, H), Image.PERSPECTIVE, coeffs([(0, 0), (W, 0), (W, H), (0, H)], P), Image.BICUBIC)
res.save(out, dpi=(25.4, 25.4))  # PNG: giữ DPI 25.4 chính xác (JPEG làm tròn thành 25)
print(out, W, 'x', H)

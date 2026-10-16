"""Nắn phối cảnh ảnh tấm đá -> ảnh chữ nhật đúng kích thước (1 px = 1 mm, DPI 25.4)
cho AutoCAD Express Tools > Draw > Super Hatch > Image, kèm xóa chữ viết tay / logo.

Dùng:
  python3 make_tile.py anh.jpg ra.png 2600 1850 "TLx,y TRx,y BRx,y BLx,y" [--erase x,y,w,h ...] [--erase-full x,y,w,h ...]
  - Toạ độ 4 góc (TL TR BR BL) tính theo pixel ảnh GỐC.
  - --erase      : hộp (theo pixel ảnh KẾT QUẢ = mm) quanh chữ viết tay/vạch phấn; chỉ xóa nét mảnh sáng/tối nổi trên nền.
  - --erase-full : hộp quanh logo/mảng lớn; xóa hết nội dung trong hộp rồi tái tạo vân từ xung quanh.
Cần: pip install pillow numpy opencv-python-headless"""
import argparse
import cv2
import numpy as np
from PIL import Image

def coeffs(dst, src):
    A = []
    for (x, y), (u, v) in zip(dst, src):
        A += [[x, y, 1, 0, 0, 0, -u*x, -u*y], [0, 0, 0, x, y, 1, -v*x, -v*y]]
    return np.linalg.solve(np.array(A, float), np.array(src, float).reshape(8))

def box(s):
    return tuple(int(v) for v in s.split(','))

def erase(img, x, y, w, h, full, pad=25):
    """img: BGR ndarray. Tạo mask trong hộp rồi inpaint."""
    H, W = img.shape[:2]
    mask = np.zeros((H, W), np.uint8)
    if full:
        mask[y:y+h, x:x+w] = 255
    else:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.int16)
        bg = cv2.medianBlur(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), 41).astype(np.int16)
        diff = np.abs(gray - bg)
        sub = diff[y:y+h, x:x+w]
        thr = max(12, float(np.percentile(sub, 93)))   # nét phấn nổi hơn nền
        m = (sub > thr).astype(np.uint8) * 255
        mask[y:y+h, x:x+w] = m
        mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    # Vân đá chạy ngang: chép mảng vân sạch cùng hàng từ bên cạnh rồi hòa mép (giữ nguyên hạt đá)
    dx = w + 60
    if x - dx < 0:
        dx = -dx
    shifted = np.roll(img, dx, axis=1)           # pixel (i) lấy từ (i - dx)
    if not full:
        mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
    alpha = cv2.GaussianBlur(mask, (0, 0), 6).astype(np.float32) / 255.0
    alpha = np.clip(alpha * 1.6, 0, 1)[..., None]
    # chỉnh sáng nền cho khớp vùng xung quanh
    ring = cv2.dilate(mask, np.ones((41, 41), np.uint8)) & ~cv2.dilate(mask, np.ones((9, 9), np.uint8))
    ring_s = np.roll(ring, dx, axis=1)
    if ring.any():
        gain = img[ring > 0].mean(0) - shifted[ring_s > 0].mean(0)
        shifted = np.clip(shifted.astype(np.float32) + gain, 0, 255)
    img[:] = (img * (1 - alpha) + shifted * alpha).astype(np.uint8)

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('out'); ap.add_argument('W', type=int); ap.add_argument('H', type=int)
ap.add_argument('pts')
ap.add_argument('--erase', action='append', default=[], type=box)
ap.add_argument('--erase-full', action='append', default=[], type=box)
a = ap.parse_args()

P = [tuple(map(float, p.split(','))) for p in a.pts.split()]
im = Image.open(a.src).convert('RGB')
res = im.transform((a.W, a.H), Image.PERSPECTIVE, coeffs([(0, 0), (a.W, 0), (a.W, a.H), (0, a.H)], P), Image.BICUBIC)
arr = cv2.cvtColor(np.array(res), cv2.COLOR_RGB2BGR)
for b in a.erase: erase(arr, *b, full=False)
for b in a.erase_full: erase(arr, *b, full=True)
Image.fromarray(cv2.cvtColor(arr, cv2.COLOR_BGR2RGB)).save(a.out, dpi=(25.4, 25.4))  # PNG giữ DPI 25.4 chính xác
print(a.out, a.W, 'x', a.H)

import cv2, numpy as np
im=cv2.imread('anh_goc.jpg');print(im.shape)
x0,x1,y0,y1=60,1882,10,1110
c=im[y0:y1,x0:x1]
g=cv2.cvtColor(c,cv2.COLOR_BGR2GRAY).astype(np.float32)
bg=cv2.GaussianBlur(g,(0,0),12)
top=np.clip((g-bg-35)/60,0,1)          # chi' giu diem sang noi bat (van trang)
top*=(g>150)
top=cv2.GaussianBlur(top,(0,0),0.8)
base=np.full(g.shape,14,np.float32)+np.random.default_rng(1).normal(0,3,g.shape)
out=np.clip(base*(1-top)+235*top,0,255).astype(np.uint8)
out=cv2.resize(out,(3180,1920),interpolation=cv2.INTER_CUBIC)
cv2.imwrite('./vein.png',out)
cv2.imwrite('./vein_s.jpg',cv2.resize(out,(1590,960)))

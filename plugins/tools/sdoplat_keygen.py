#!/usr/bin/env python3
"""Tao Ma kich hoat cho khach (chay tren may NGUOI BAN, khong gui cho khach).

  export SDOPLAT_SECRET='chuoi-bi-mat-cua-ban'          # cung gia tri dung khi build goi ban
  python3 sdoplat_keygen.py ABCD-EFGH-JKLM "Ten khach"   # in ma + ghi vao nhat ky

Nhat ky licenses.csv (cung thu muc chay lenh): ngay, khach, ma may, ma kich hoat.
Neu ma may da cap truoc do, lenh bao lai de tranh cap trung.
"""
import sys, os, csv, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sdoplat_lic import activation_code, norm

secret = os.environ.get('SDOPLAT_SECRET')
if not secret or len(sys.argv) < 2:
    sys.exit(__doc__)
mid = sys.argv[1].strip().upper()
if len(norm(mid)) != 12:
    sys.exit('Ma may phai co 12 ky tu (dang XXXX-XXXX-XXXX).')
cust = sys.argv[2] if len(sys.argv) > 2 else ''
code = activation_code(mid, secret)
log = 'licenses.csv'
rows = list(csv.reader(open(log, encoding='utf-8'))) if os.path.exists(log) else []
prev = [r for r in rows if len(r) > 2 and norm(r[2]) == norm(mid)]
if prev:
    print('Luu y: ma may nay da duoc cap ngay', prev[-1][0], 'cho', prev[-1][1])
with open(log, 'a', newline='', encoding='utf-8') as f:
    csv.writer(f).writerow([datetime.date.today().isoformat(), cust, mid, code])
print('Ma kich hoat:', code)

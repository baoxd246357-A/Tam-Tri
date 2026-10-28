#!/usr/bin/env python3
"""Tach phan LISP op lat tu ShopDrawing/ShopDrawing.lsp thanh goi ban rieng.

Dung:  python3 -I build_oplat.py <thu-muc-ShopDrawing> <thu-muc-dau-ra>
Khong sua nguon. Goi ra: SDOpLat.lsp, SDOpLat.mnu, SDOpLat.mnl, huong dan, icon, map, pat.
"""
import re, sys, os, shutil, collections

SRC, OUT = sys.argv[1], sys.argv[2]
NL = '\r\n'
PRODUCT = 'Op Lat Tools'
PRODUCT_VER = '1.0.0'

src = open(f'{SRC}/ShopDrawing.lsp', encoding='latin-1', newline='').read()

# ---------------------------------------------------------------- lenh dua vao goi
rows_all = re.findall(r'^\s*\("([^"]+)" "(SD[A-Z0-9]+)" "([^"]*)" "([A-Z0-9]+)" "([A-Z0-9]+)"\)', src, re.M)
TILING = [r[1] for r in rows_all if r[0] == 'Op lat da granite / gach' and r[1] != 'SDLENH']
EXTRA = ['SDSET', 'SDHANDINH', 'SDHELP', 'SDPANEL', 'SDMENU', 'SDMENUXOA', 'SDTUNAP', 'SDDLG']
CMDS = TILING + [e for e in EXTRA if e not in TILING]
CMDSET = set(CMDS)

# ---------------------------------------------------------------- tach nguon thanh cac form cap cao nhat
def strip(s):
    o = []; i = 0; n = len(s)
    while i < n:
        c = s[i]
        if c == ';':
            if s[i+1:i+2] == '|':
                j = s.find('|;', i+2); o.append(' ' * (j+2-i)); i = j+2; continue
            j = i
            while j < n and s[j] != '\n': j += 1
            o.append(' ' * (j-i)); i = j; continue
        if c == '"':
            j = i+1
            while s[j] != '"': j += 2 if s[j] == '\\' else 1
            j += 1; o.append('"' + ' ' * (j-i-2) + '"'); i = j; continue
        o.append(c); i += 1
    return ''.join(o)

def split_forms(text):
    t = strip(text); assert len(t) == len(text)
    forms = []; d = 0; st = None; prev = 0
    for i, c in enumerate(t):
        if c == '(':
            if d == 0: st = i
            d += 1
        elif c == ')':
            d -= 1
            if d == 0:
                forms.append(dict(start=prev, form=st, end=i+1)); prev = i+1
    for f in forms:
        h = t[f['form']:f['form']+200]
        m = re.match(r'\(defun\s+(\S+)', h); sm = re.match(r'\(setq\s+(\S+)', h)
        f['kind'] = 'defun' if m else 'setq' if sm else 'other'
        f['name'] = m.group(1) if m else sm.group(1) if sm else None
    return forms, t, text[prev:]

# ---------------------------------------------------------------- sua nhung form dac biet truoc khi tinh phu thuoc
def patch(text):
    forms, t, tail = split_forms(text)
    out = []
    for f in forms:
        seg = text[f['start']:f['end']]
        if f['name'] == '*SD:CMDS*':
            head = seg[:seg.index("'(")+2]
            body = seg[seg.index("'(")+2:]
            keep = []
            for ln in body.split('\n'):
                m = re.match(r'\s*\("[^"]+" "(SD[A-Z0-9]+)"', ln)
                if m and m.group(1) in CMDSET:
                    keep.append(ln.rstrip('\r').rstrip(')').rstrip() + ')')
            seg = head + NL.join(keep).lstrip() + '))' + NL
            seg = seg.replace(head + '(', head + '(', 1)
        elif f['name'] == '*SD:PICS*':
            def keep_pair(m):
                return m.group(0) if m.group(1) in CMDSET else ''
            seg = re.sub(r'\(cons "(SD[A-Z0-9]+)" \'sd:pic-[a-z0-9-]+\)\s*', keep_pair, seg)
        elif f['name'] == '*SD:QTSTEPS*':
            seg = re.sub(r'\("SDKIEMTRA" "[^"]*" "[^"]*"\)',
                         '("SDKTLAT" "Kiem tra ban ve lat (chi doc): vien cat hep / nho, ron khong deu, o thieu ma vat lieu" "Khoanh do cho co van de tren layer SD-KIEMTRA, xuat CSV.")', seg)
        elif f['name'] == 'c:SDMENU':
            seg = seg.replace("(vl-catch-all-apply 'sd:tm-init nil)", "")
        out.append(dict(f, seg=seg))
    return out, t, tail

forms, _, tail = patch(src)

# ---------------------------------------------------------------- phu thuoc
fl = []
for f in forms:
    f['toks'] = set(x.lower() for x in re.findall(r"[^\s()'\"`]+", strip(f['seg'])))
defs = {f['name'].lower(): k for k, f in enumerate(forms) if f['kind'] == 'defun'}
setqs = collections.defaultdict(list)
for k, f in enumerate(forms):
    if f['kind'] == 'setq': setqs[f['name'].lower()].append(k)
refs = [set(defs[x] for x in f['toks'] if x in defs) | set(j for x in f['toks'] if x in setqs for j in setqs[x]) for f in forms]
roots = set(defs['c:' + c.lower()] for c in CMDS)
# form cap cao khac can giu: nap thu vien, bien mac dinh, tao lenh tat, tu nap
for k, f in enumerate(forms):
    if (f['kind'] == 'other' and 'sd:tm-init' not in f['seg']) or f['name'] in ('*SD:VER*', '*SD:CMDS*'):
        roots.add(k)
keep = set(roots); st = list(roots)
while st:
    k = st.pop()
    for r in refs[k]:
        if r not in keep: keep.add(r); st.append(r)

# bo cac form khoi dong khong thuoc goi
DROP_OTHER = ("sd:tm-init",)
parts = []
for k in sorted(keep):
    seg = forms[k]['seg']
    if forms[k]['kind'] == 'other' and any(d in seg for d in DROP_OTHER): continue
    parts.append(seg)
body = ''.join(parts) + tail

# ---------------------------------------------------------------- doi ten san pham
body = body.replace('(setq *SD:VER* "2.58.0")', '(setq *SD:VER* "%s")' % PRODUCT_VER)
body = body.replace('ShopDrawing Tools v', PRODUCT + ' v').replace('SDKIEMTRA', 'SDKTLAT')
body = body.replace('SHOPDRAWINGRIBBON', 'SDOPLATRIBBON').replace('SHOPDRAWING', 'SDOPLAT').replace('ShopDrawing', 'SDOpLat')
header = (";;; ==========================================================================\r\n"
          ";;;  %s v%s - bo cong cu lap shop drawing op lat da / gach cho AutoCAD\r\n"
          ";;;  Nap: APPLOAD -> SDOpLat.lsp, roi go SDMENU (menu + toolbar) hoac SDPANEL.\r\n"
          ";;;  File sinh tu dong tu ShopDrawing 2.58.0 boi tools/build_oplat.py - khong sua tay.\r\n"
          ";;; ==========================================================================\r\n") % (PRODUCT, PRODUCT_VER)
os.makedirs(OUT, exist_ok=True)
open(f'{OUT}/SDOpLat.lsp', 'w', encoding='latin-1', newline='').write(header + body)

# ---------------------------------------------------------------- menu .mnu
mnu = open(f'{SRC}/ShopDrawing.mnu', encoding='latin-1', newline='').read().replace('\r\n', '\n').split('\n')
def cmd_of(line):
    m = re.search(r'\^C\^C(SD[A-Z0-9]+)\s*$', line)
    return m.group(1) if m else None
sect = None; out = []; groups = []   # POP1: [(header, [items])]
tb = []; cur = None; helps = []
newitem = {}
for ln in mnu:
    if ln.startswith('***'): sect = ln; out_sect = sect
    # (xu ly o duoi)
text = '\n'.join(mnu)
pre, rest = text.split('***POP1', 1)
pop, rest = rest.split('***TOOLBARS', 1)
tbs, hlp = rest.split('***HELPSTRINGS', 1)
# POP1
pl = [l for l in pop.split('\n')]
res_pop = []; grp = None; items = []; extra_tail = []
def flush():
    global grp, items
    if grp is not None:
        its = [i for i in items if cmd_of(i) in CMDSET]
        if its:
            res_pop.append(grp)
            for n, i in enumerate(its):
                i = i.replace('[<-', '[')
                if n == len(its) - 1: i = i.replace('[', '[<-', 1)
                res_pop.append(i)
    grp = None; items = []
for l in pl:
    if re.match(r'ID_SD_G\d+ \[->', l): flush(); grp = l; continue
    if grp is not None and l.startswith('ID_SD_') and cmd_of(l) is not None and not l.startswith('ID_SD_POP_'):
        items.append(l); continue
    if grp is not None and (l.strip() == '' or l.startswith('[--]') or l.startswith('ID_SD_POP_')):
        flush()
    if grp is None: res_pop.append(l)
flush()
popt = '\n'.join(res_pop)
# them SDHANDINH vao nhom Tien ich neu chua co
if 'SDHANDINH' not in popt:
    hd = 'ID_SD_SDHANDINH [Han dinh: gop dinh polyline lech nhau, chen dinh nut chu T (SDHANDINH / HDI)]^C^CSDHANDINH'
    popt = popt.replace('ID_SD_SDPANEL [', hd + '\nID_SD_SDPANEL [', 1)
# TOOLBARS
tbl = []; blocks = re.split(r'\n(?=\*\*SD_TB\d+)', tbs)
for b in blocks:
    lines = b.split('\n')
    if not lines[0].startswith('**SD_TB'):
        tbl.append(b); continue
    btn = [l for l in lines[2:] if cmd_of(l) in CMDSET]
    if lines[0].strip() and btn: tbl.append('\n'.join(lines[:2] + btn) + '\n')
tbt = '\n'.join(tbl)
if 'SDHANDINH' not in tbt:
    hdb = 'ID_SD_TB_SDHANDINH [_Button("Han dinh polyline: gop dinh lech, chen dinh nut chu T (HDI)", "SD_SDPURGE_16.bmp", "SD_SDPURGE_32.bmp")]^C^CSDHANDINH'
    tbt = tbt.replace('ID_SD_TB_SDPANEL [', hdb + '\nID_SD_TB_SDPANEL [', 1)
# HELPSTRINGS
hl = []
for l in hlp.split('\n'):
    m = re.match(r'ID_SD_(?:TB_)?(SD[A-Z0-9]+) \[', l)
    if m and m.group(1) in CMDSET: hl.append(l)
    elif not m and l.strip(): hl.append(l)
hl.append('ID_SD_SDHANDINH [SDHANDINH (lenh tat HDI): Han dinh polyline]')
hl.append('ID_SD_TB_SDHANDINH [SDHANDINH (lenh tat HDI): Han dinh polyline]')
final = pre + '***POP1' + popt + '\n***TOOLBARS' + tbt + '\n***HELPSTRINGS\n' + '\n'.join(hl) + '\n'
final = final.replace('ShopDrawing Tools v2.58.0', PRODUCT + ' v' + PRODUCT_VER)
final = final.replace('ShopDrawing Tools', PRODUCT).replace('SHOPDRAWING', 'SDOPLAT').replace('ShopDrawing', 'SDOpLat')
final = final.replace('SD Op lat da', 'SD Op lat da')
open(f'{OUT}/SDOpLat.mnu', 'w', encoding='latin-1', newline='').write(final.replace('\n', NL))

# ---------------------------------------------------------------- mnl
open(f'{OUT}/SDOpLat.mnl', 'w', encoding='latin-1', newline='').write(
    open(f'{SRC}/ShopDrawing.mnl', encoding='latin-1', newline='').read().replace('ShopDrawing', 'SDOpLat'))

# ---------------------------------------------------------------- icon, map, pat, md
n = 0
for c in CMDS + ['SDPURGE']:
    for sz in ('16', '32'):
        f = f'SD_{c}_{sz}.bmp'
        if os.path.exists(f'{SRC}/{f}'): shutil.copy(f'{SRC}/{f}', f'{OUT}/{f}'); n += 1
if os.path.isdir(f'{SRC}/Maps'):
    shutil.copytree(f'{SRC}/Maps', f'{OUT}/Maps', dirs_exist_ok=True)
for f in os.listdir(SRC):
    if f.lower().endswith('.pat') or f == 'HuongDanQuyTrinhDa.md':
        shutil.copy(f'{SRC}/{f}', f'{OUT}/{f}')
md = open(f'{OUT}/HuongDanQuyTrinhDa.md', encoding='utf-8', newline='').read()
md = md.replace('| 10 | `SDKIEMTRA` | Tác tử kiểm tra bản vẽ (chỉ đọc), gợi ý lệnh chạy tiếp |', '| 10 | `SDKTLAT` | Kiểm tra bản vẽ lát (chỉ đọc): viên cắt hẹp / nhỏ, ron không đều, ô thiếu mã vật liệu |')
md = md.replace('Cuối cùng **10 `SDKIEMTRA`**', 'Cuối cùng **10 `SDKTLAT`**').replace('SDKIEMTRA', 'SDKTLAT')
open(f'{OUT}/HuongDanQuyTrinhDa.md', 'w', encoding='utf-8', newline='').write(md)

# ---------------------------------------------------------------- LenhTat.csv
raw = open(f'{SRC}/LenhTat.csv', 'rb').read().decode('utf-8-sig').split('\r\n')
keepcsv = [raw[0]] + [l for l in raw[1:] if l and l.split(';')[2] in CMDSET]
open(f'{OUT}/LenhTat.csv', 'wb').write(('﻿' + '\r\n'.join(keepcsv) + '\r\n').encode('utf-8'))

# ---------------------------------------------------------------- HuongDanLenh.html
h = open(f'{SRC}/HuongDanLenh.html', encoding='utf-8', newline='').read()
alias = set(r[4] for r in rows_all if r[1] in CMDSET) | set(r[3] for r in rows_all if r[1] in CMDSET)
def cmd_block(m):
    code = re.search(r'<code>(SD[A-Z0-9]+)</code>', m.group(0))
    return m.group(0) if code and code.group(1) in CMDSET else ''
h = re.sub(r'<div class="cmd"[^>]*>.*?</div>\n?', cmd_block, h, flags=re.S)
h = re.sub(r'<tr><td class="a">[^<]*</td><td class="c">(SD[A-Z0-9]+)</td>.*?</tr>\s*', lambda m: m.group(0) if m.group(1) in CMDSET else '', h, flags=re.S)
h = re.sub(r'<div class="box"><h3[^>]*>[^<]*</h3><table>\s*</table></div>\s*', '', h)
def flow(m):
    ks = re.findall(r'<span class="k">([^<]*)</span>', m.group(0))
    return m.group(0) if all(k in alias for k in ks) else ''
h = h.replace('<span class="k">KTA</span>', '<span class="k">KLT</span>')
h = re.sub(r'<p class="flow">.*?</p>\n?', flow, h, flags=re.S)
h = re.sub(r'<h3><span class="dot"[^>]*></span>[^<]*</h3>\s*(?=<h3>|<p class="note">|</main>)', '', h)
h = re.sub(r'<p class="note">Sinh t[^<]*</p>', '', h)
h = h.replace('ShopDrawing Tools', PRODUCT).replace('SDKIEMTRA', 'SDKTLAT')
open(f'{OUT}/HuongDanLenh.html', 'w', encoding='utf-8', newline='').write(h)
print('cmds', len(CMDS), 'lsp bytes', os.path.getsize(f'{OUT}/SDOpLat.lsp'), 'icons', n)

# ---------------------------------------------------------------- CaiDat.txt, BanQuyen.txt
CAIDAT = """OP LAT TOOLS v%s - PLUGIN AUTOLISP OP LAT DA / GACH CHO AUTOCAD
================================================================

CAI DAT
1. Giai nen ca thu muc vao mot cho co dinh, vi du D:\\SDOpLat (khong de trong Downloads hay thu muc tam).
2. Mo AutoCAD, go APPLOAD, chon SDOpLat.lsp, bam Load.
3. Go SDMENU (lan dau chon file SDOpLat.mnu trong thu muc tren). Lenh tu them thu muc vao
   Support File Search Path va nap menu + toolbar. Tu do plugin tu nap cho moi ban ve.
   Khong muon cai menu: sau APPLOAD go SDTUNAP mot lan de plugin tu nap moi khi mo AutoCAD.
4. Nang cap: giai nen ban moi vao thu muc MOI, dong han AutoCAD, mo lai, APPLOAD roi SDMENU.
5. Go: lenh SDMENUXOA.

CACH NHANH (chi LISP, chay duoc ca ZWCAD / GstarCAD / BricsCAD)
- APPLOAD > SDOpLat.lsp > Load, roi go SDPANEL de mo bang lenh.

BAT DAU
- SDPANEL: bang lenh.  SDHELP: danh sach lenh.  SDQUYTRINH (QT): quy trinh da lat lien hoan.
- HuongDanLenh.html: huong dan tung lenh (mo bang trinh duyet).  HuongDanQuyTrinhDa.md: quy trinh da lat.
- LenhTat.csv: danh sach lenh tat.
- Thu muc Maps: map da granite cho SDMAP / SDANHDA; file .pat: van da cho SDVANDA.
- Chay TYLE (SDSET) dau tien cho ban ve moi de dat ty le, layer, dimstyle.

LUU Y
- Chay tren AutoCAD (Windows) 2018 tro len. Bang Excel, hop thoai can Windows.
- Moi lenh gom vao mot lan Undo: go U de hoan tac ca lenh.
- Bao loi kem phien ban AutoCAD, ten lenh va cac dong lenh hien ra.
""" % PRODUCT_VER
open(f'{OUT}/CaiDat.txt', 'w', encoding='utf-8-sig', newline='').write(CAIDAT.replace('\n', '\r\n'))
BANQUYEN = """BAN QUYEN VA DIEU KHOAN SU DUNG (MAU - NGUOI BAN TU DIEN VA THAM KHAO Y KIEN PHAP LY)
Op Lat Tools v%s
(c) [TEN CONG TY / CA NHAN] - Bao luu moi quyen.

1. Phan mem cap phep su dung, khong chuyen nhuong quyen so huu.
2. Gioi han: [SO MAY / SO NGUOI DUNG].
3. Khong duoc sao chep de phan phoi, ban lai, cho thue hoac go bo thong tin ban quyen.
4. Phan mem cung cap nguyen trang, khong bao dam phu hop moi muc dich; trach nhiem toi da
   gioi han trong muc phi da thu. Nguoi dung tu kiem tra ket qua truoc khi thi cong / dat hang.
5. Lien he ho tro: [EMAIL / DIEN THOAI].
""" % PRODUCT_VER
open(f'{OUT}/BanQuyen.txt', 'w', encoding='utf-8-sig', newline='').write(BANQUYEN.replace('\n', '\r\n'))

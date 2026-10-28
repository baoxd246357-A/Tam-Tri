#!/usr/bin/env python3
"""Tach phan LISP op lat tu ShopDrawing/ShopDrawing.lsp thanh goi ban rieng.

Dung:  python3 -I build_oplat.py <thu-muc-ShopDrawing> <thu-muc-dau-ra>
Khong sua nguon. Goi ra: SDOpLat.lsp, SDOpLat.mnu, SDOpLat.mnl, huong dan, icon, map, pat.
"""
import re, sys, os, shutil, collections

args = [a for a in sys.argv[1:] if not a.startswith('--')]
SRC, OUT = args[0], args[1]
LICENSED = '--licensed' in sys.argv
SECRET = os.environ.get('SDOPLAT_SECRET', '')
TRIAL = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--trial=')), 10))
FAS = '--fas' in sys.argv  # goi chi co .fas (da bienpile): doi ten file nap .lsp -> .fas
if LICENSED and (len(SECRET) < 16 or not SECRET.isascii()):
    sys.exit('Ban co khoa: dat bien moi truong SDOPLAT_SECRET (>= 16 ky tu ASCII, bi mat cua ban) truoc khi build.')
FREE = {'SDKICHHOAT', 'SDHELP', 'SDPANEL', 'SDMENU', 'SDMENUXOA', 'SDTUNAP', 'SDDLG'}
NL = '\r\n'
PRODUCT = 'Op Lat Tools'
PRODUCT_VER = '1.0.0'

src = open(f'{SRC}/ShopDrawing.lsp', encoding='latin-1', newline='').read()

# ---------------------------------------------------------------- lenh dua vao goi
rows_all = re.findall(r'^\s*\("([^"]+)" "(SD[A-Z0-9]+)" "([^"]*)" "([A-Z0-9]+)" "([A-Z0-9]+)"\)', src, re.M)
TILING = [r[1] for r in rows_all if r[0] == 'Op lat da granite / gach' and r[1] != 'SDLENH']
EXTRA = ['SDSET', 'SDHANDINH', 'SDHELP', 'SDPANEL', 'SDMENU', 'SDMENUXOA', 'SDTUNAP', 'SDDLG']
CMDS = TILING + [e for e in EXTRA if e not in TILING]
MODCMDS = ['SDDIMGD']                     # lenh tich hop tu module ngoai (tools/modules/*.lsp), khong co trong ShopDrawing.lsp
CMDSET = set(CMDS) | set(MODCMDS)
DGD_ROW = '    ("Thiet lap va ban ve" "SDDIMGD" "Dim giao diem: ve 1 duong cat, tu dong dim tung doan giua cac giao diem + dim tong" "DGD" "DGD")'
BASIC = ['SDSET', 'SDGACH', 'SDRAITAM', 'SDDOCDA', 'SDANHDA', 'SDVANDA', 'SDGACHTK', 'SDKTLAT', 'SDQUYTRINH']
BASIC_MENU = '--menu=basic' in sys.argv   # menu / toolbar chi hien 9 lenh co ban; cac lenh con lai van chay, mo bang SDPANEL
MENUSET = (set(BASIC) | {'SDDIMGD', 'SDKICHHOAT', 'SDPANEL', 'SDHELP', 'SDMENUXOA'}) if BASIC_MENU else CMDSET

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
            keep.append(DGD_ROW)
            if LICENSED:
                keep.append('    ("Tien ich" "SDKICHHOAT" "Kich hoat ban quyen tren may nay bang Ma kich hoat" "KH" "KHB")')
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

# ---------------------------------------------------------------- module ngoai (DGD)
_anchor = '(princ (strcat "\\n[SD] ShopDrawing Tools v"'
assert body.count(_anchor) == 1
_mod = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'modules', 'dgd.lsp'), encoding='utf-8').read()
assert _mod.isascii()
body = body.replace(_anchor, _mod.replace('\r\n', '\n').replace('\n', '\r\n') + '\r\n' + _anchor)

# ---------------------------------------------------------------- khoa ban quyen theo may
if LICENSED:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sdoplat_lic as lic
    vec_mid = lic.lic_mid_of('G:TEST-MACHINE')
    mod = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'license_module.lsp'), encoding='utf-8').read()
    mod = mod.replace('@@SECRET@@', SECRET.replace('\\', '\\\\').replace('"', '\\"')).replace('@@TRIAL@@', str(TRIAL)).replace('@@VEC_MID@@', vec_mid).replace('@@VEC_CODE@@', lic.lic_code(vec_mid + '|TEST'))
    gated = [c for c in CMDS + MODCMDS if c not in FREE]
    for c in gated:
        body, n = re.subn(r'\(defun c:%s(\s*\()' % c, r'(defun sd:cmd-%s\1' % c, body)
        assert n == 1, c
    wr = ''.join('(defun c:%s () (sd:lic-run (quote sd:cmd-%s)))\r\n' % (c, c) for c in gated)
    mod += '\r\n;; Cac lenh duoc khoa\r\n' + wr + "(vl-catch-all-apply (quote (lambda () (if (not (sd:lic-ok)) (princ (strcat \"\\n[SD] Chua kich hoat: go SDKICHHOAT. Ma may: \" (sd:lic-mid)))))) nil)\r\n"
    anchor = '(princ (strcat "\\n[SD] ShopDrawing Tools v"'
    assert body.count(anchor) == 1
    body = body.replace(anchor, mod.replace('\r\n', '\n').replace('\n', '\r\n') + anchor)

# ---------------------------------------------------------------- doi ten san pham
body = body.replace('(setq *SD:VER* "2.58.0")', '(setq *SD:VER* "%s")' % PRODUCT_VER)
body = body.replace('ShopDrawing Tools v', PRODUCT + ' v').replace('SDKIEMTRA', 'SDKTLAT')
body = body.replace('SHOPDRAWINGRIBBON', 'SDOPLATRIBBON').replace('SHOPDRAWING', 'SDOPLAT').replace('ShopDrawing', 'SDOpLat')
header = (";;; ==========================================================================\r\n"
          ";;;  %s v%s - bo cong cu lap shop drawing op lat da / gach cho AutoCAD\r\n"
          ";;;  Nap: APPLOAD -> SDOpLat.lsp, roi go SDMENU (menu + toolbar) hoac SDPANEL.\r\n"
          ";;;  File sinh tu dong tu ShopDrawing 2.58.0 boi tools/build_oplat.py - khong sua tay.\r\n"
          ";;; ==========================================================================\r\n") % (PRODUCT, PRODUCT_VER)
body = body[body.index('(vl-load-com)'):]  # bo comment dau file cu (noi dung BTCT / thep)
os.makedirs(OUT, exist_ok=True)
if FAS:
    body = body.replace('SDOpLat.lsp', 'SDOpLat.fas')
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
DGD_POP = 'ID_SD_SDDIMGD [Dim giao diem: ve duong cat, tu dong dim tung doan + dim tong (SDDIMGD / DGD)]^C^CSDDIMGD'
pop = re.sub(r'(ID_SD_SDSET \[[^\n]*\n)', lambda m: m.group(1) + DGD_POP + '\n', pop, count=1)
pl = [l for l in pop.split('\n')]
res_pop = []; grp = None; items = []; extra_tail = []
def flush():
    global grp, items
    if grp is not None:
        its = [i for i in items if cmd_of(i) in MENUSET]
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
if 'SDHANDINH' not in popt and not BASIC_MENU:
    hd = 'ID_SD_SDHANDINH [Han dinh: gop dinh polyline lech nhau, chen dinh nut chu T (SDHANDINH / HDI)]^C^CSDHANDINH'
    popt = popt.replace('ID_SD_SDPANEL [', hd + '\nID_SD_SDPANEL [', 1)
if LICENSED and 'SDKICHHOAT' not in popt:
    popt = popt.replace('ID_SD_SDPANEL [', 'ID_SD_SDKICHHOAT [Kich hoat ban quyen tren may nay (SDKICHHOAT / KHB)]^C^CSDKICHHOAT\nID_SD_SDPANEL [', 1)
# TOOLBARS
tbl = []; blocks = re.split(r'\n(?=\*\*SD_TB\d+)', tbs)
for b in blocks:
    lines = b.split('\n')
    if not lines[0].startswith('**SD_TB'):
        tbl.append(b); continue
    btn = [l for l in lines[2:] if cmd_of(l) in MENUSET]
    if lines[0].strip() and btn: tbl.append('\n'.join(lines[:2] + btn) + '\n')
tbt = '\n'.join(tbl)
DGD_TB = 'ID_SD_TB_SDDIMGD [_Button("Dim giao diem: tu dong dim tung doan + dim tong (DGD)", "SD_SDDIMVIEN_16.bmp", "SD_SDDIMVIEN_32.bmp")]^C^CSDDIMGD'
tbt = re.sub(r'(ID_SD_TB_SDSET \[[^\n]*\n)', lambda m: m.group(1) + DGD_TB + '\n', tbt, count=1)
if 'SDHANDINH' not in tbt and not BASIC_MENU:
    hdb = 'ID_SD_TB_SDHANDINH [_Button("Han dinh polyline: gop dinh lech, chen dinh nut chu T (HDI)", "SD_SDPURGE_16.bmp", "SD_SDPURGE_32.bmp")]^C^CSDHANDINH'
    tbt = tbt.replace('ID_SD_TB_SDPANEL [', hdb + '\nID_SD_TB_SDPANEL [', 1)
# HELPSTRINGS
hl = []
for l in hlp.split('\n'):
    m = re.match(r'ID_SD_(?:TB_)?(SD[A-Z0-9]+) \[', l)
    if m and m.group(1) in MENUSET: hl.append(l)
    elif not m and l.strip(): hl.append(l)
hl.append('ID_SD_SDDIMGD [SDDIMGD (lenh tat DGD): Dim giao diem]')
hl.append('ID_SD_TB_SDDIMGD [SDDIMGD (lenh tat DGD): Dim giao diem]')
if LICENSED:
    hl.append('ID_SD_SDKICHHOAT [SDKICHHOAT (lenh tat KHB): Kich hoat ban quyen]')
if not BASIC_MENU:
    hl.append('ID_SD_SDHANDINH [SDHANDINH (lenh tat HDI): Han dinh polyline]')
    hl.append('ID_SD_TB_SDHANDINH [SDHANDINH (lenh tat HDI): Han dinh polyline]')
final = pre + '***POP1' + popt + '\n***TOOLBARS' + tbt + '\n***HELPSTRINGS\n' + '\n'.join(hl) + '\n'
final = final.replace('ShopDrawing Tools v2.58.0', PRODUCT + ' v' + PRODUCT_VER)
final = final.replace('ShopDrawing Tools', PRODUCT).replace('SHOPDRAWING', 'SDOPLAT').replace('ShopDrawing', 'SDOpLat')
final = final.replace('SD Op lat da', 'SD Op lat da')
open(f'{OUT}/SDOpLat.mnu', 'w', encoding='latin-1', newline='').write(final.replace('\n', NL))

# ---------------------------------------------------------------- mnl
open(f'{OUT}/SDOpLat.mnl', 'w', encoding='latin-1', newline='').write(
    open(f'{SRC}/ShopDrawing.mnl', encoding='latin-1', newline='').read().replace('ShopDrawing', 'SDOpLat').replace('SDOpLat.lsp', 'SDOpLat.fas' if FAS else 'SDOpLat.lsp'))

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
keepcsv.append('Thiết lập và bản vẽ;DGD;SDDIMGD;Dim giao điểm;Vẽ một đường cắt, tự động dim từng đoạn giữa các giao điểm và dim tổng')
if LICENSED:
    keepcsv.append('Tiện ích;KHB;SDKICHHOAT;Kích hoạt bản quyền;Hiện Mã máy và nhập Mã kích hoạt do nhà cung cấp cấp')
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
_dgd = '<div class="cmd" style="--grp:#3465a4"><h4><span class="k">DGD</span> &nbsp;<code>SDDIMGD</code></h4><p>Dim giao điểm: vẽ một đường cắt qua các đối tượng, lệnh tự tìm các giao điểm và dim từng đoạn giữa các giao điểm liên tiếp, cộng thêm một dim tổng. Tích hợp từ DimGiaoDiem v2.</p><ol><li>Chọn điểm bắt đầu và điểm kết thúc của đường cắt.</li><li>Chọn vị trí đặt đường dim chi tiết.</li></ol><p><b>Kết quả:</b> Dim từng đoạn giữa các giao điểm (theo kiểu dim hiện hành) và một dim tổng, đẩy ra phía xa đường cắt hơn dim chi tiết. Dòng lệnh in số đoạn, tổng và độ dài từng đoạn (2 số lẻ) để đối chiếu làm tròn. Đúng cả khi UCS xoay; Esc hoặc lỗi giữa chừng trả lại OSMODE và gỡ đường cắt tạm; U hoàn tác cả lệnh.</p><p class="note"><b>Lưu ý:</b> Cần đường cắt qua ít nhất 2 giao điểm. Dùng dimstyle hiện hành (chạy SDSET để có dimstyle SD-1-&lt;tỷ lệ&gt;). Chưa thử trên AutoCAD thật trong gói này.</p></div>\n'
_i = h.index('<h2>Hướng dẫn chi tiết từng lệnh</h2>')
_j = h.index('</h3>', _i) + len('</h3>')
h = h[:_j] + '\n' + _dgd + h[_j:] if '<code>SDDIMGD</code>' not in h else h
if LICENSED:
    blk = '<div class="cmd" style="--grp:#5a5a5a"><h4><span class="k">KHB</span> &nbsp;<code>SDKICHHOAT</code></h4><p>Kích hoạt bản quyền trên máy này. Lệnh hiện <b>Mã máy</b>; gửi mã này cho nhà cung cấp để nhận <b>Mã kích hoạt</b>, rồi nhập vào.</p><ol><li>Gõ SDKICHHOAT, ghi lại Mã máy (dạng XXXX-XXXX-XXXX).</li><li>Gửi Mã máy cho nhà cung cấp, nhận Mã kích hoạt (dạng XXXXX-XXXXX-XXXXX).</li><li>Gõ lại SDKICHHOAT và nhập mã.</li></ol><p class="note"><b>Lưu ý:</b> Mã chỉ dùng được trên đúng máy đã gửi Mã máy. Cài lại Windows hoặc đổi máy thì Mã máy đổi, cần xin mã mới theo chính sách của nhà cung cấp.</p></div>\n'
    h = h.replace('<h3><span class="dot"', blk + '<h3><span class="dot"', 1) if False else h
    h = re.sub(r'(<h2>Hướng dẫn chi tiết từng lệnh</h2>)', r'\1\n' + blk.replace('\\', '\\\\'), h, count=1)
def flow(m):
    ks = re.findall(r'<span class="k">([^<]*)</span>', m.group(0))
    return m.group(0) if all(k in alias for k in ks) else ''
h = h.replace('<span class="k">KTA</span>', '<span class="k">KLT</span>')
h = re.sub(r'<p class="flow">.*?</p>\n?', flow, h, flags=re.S)
h = re.sub(r'<h3><span class="dot"[^>]*></span>[^<]*</h3>\s*(?=<h3>|<p class="note">|</main>)', '', h)
h = re.sub(r'<p class="note">Sinh t[^<]*</p>', '', h)
h = re.sub(r'(<p class="sub">.*?</p>)', r'\1<p class="note"><b>Luu y:</b> Cac so lieu, tieu chuan va goi y trong huong dan chi de tham khao; nguoi dung tu kiem tra va chiu trach nhiem ve ban ve, khoi luong, dat hang va thi cong. Can Windows; lenh xuat Excel can Microsoft Excel (hoac phan mem tuong tu co ho tro COM, chua kiem tra).</p>', h, count=1, flags=re.S)
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

CACH NHANH (khong cai menu)
- APPLOAD > SDOpLat.lsp > Load, roi go SDPANEL de mo bang lenh.

BAT DAU
- SDPANEL: bang lenh.  SDHELP: danh sach lenh.  SDQUYTRINH (QT): quy trinh da lat lien hoan.
- HuongDanLenh.html: huong dan tung lenh (mo bang trinh duyet).  HuongDanQuyTrinhDa.md: quy trinh da lat.
- LenhTat.csv: danh sach lenh tat.
- Thu muc Maps: map da granite cho SDMAP / SDANHDA; file .pat: van da cho SDVANDA.
- Chay TYLE (SDSET) dau tien cho ban ve moi de dat ty le, layer, dimstyle.

LUU Y VE TIEU CHUAN VA TRACH NHIEM
- Cac so lieu, tieu chuan (TCVN, ISPSC, quy dinh xay dung nuoc ngoai...) va goi y trong plugin chi de THAM KHAO.
  Nguoi dung tu kiem tra, doi chieu ho so thiet ke / tieu chuan ap dung va chiu trach nhiem ve ban ve, khoi luong, dat hang, thi cong.

LUU Y
- He dieu hanh: Windows (plugin dung COM / Visual LISP nen khong dung cho Mac). Phan mem CAD: AutoCAD ban day du; AutoCAD LT chua duoc kiem tra
  (LT khong ho tro COM / Visual LISP day du nen nhieu lenh co the khong chay).
  Co the chay tren cac phan mem CAD tuong tu ho tro AutoLISP / Visual LISP (vi du ZWCAD, GstarCAD, BricsCAD) nhung chua duoc kiem tra.
- Cac lenh xuat bang sang Excel can Microsoft Excel (hoac phan mem bang tinh tuong tu co ho tro COM - chua kiem tra). Khong co Excel thi cac lenh co xuat file CSV van co the mo bang phan mem khac.
- Chua kiem tra tren moi phien ban AutoCAD.
@@LICNOTE@@- SDMENU / SDTUNAP them thu muc cai dat vao Support File Search Path va Trusted Locations (TRUSTEDPATHS) va co the ghi khoi tu nap vao acaddoc.lsp cua nguoi dung; go bang SDMENUXOA va chay lai SDTUNAP.
- Moi lenh gom vao mot lan Undo: go U de hoan tac ca lenh.
- Bao loi kem phien ban AutoCAD, ten lenh va cac dong lenh hien ra.
""" % PRODUCT_VER
CAIDAT = CAIDAT.replace('@@LICNOTE@@', ('- Ban quyen: moi may dung thu %d lan chay lenh, sau do go SDKICHHOAT, gui Ma may cho nha cung cap de nhan Ma kich hoat.\n' % TRIAL) if LICENSED else '')
if FAS:
    CAIDAT = CAIDAT.replace('SDOpLat.lsp', 'SDOpLat.fas')
open(f'{OUT}/CaiDat.txt', 'w', encoding='utf-8-sig', newline='').write(CAIDAT.replace('\n', '\r\n'))
BANQUYEN = """BAN QUYEN VA DIEU KHOAN SU DUNG (MAU - NGUOI BAN TU DIEN VA THAM KHAO Y KIEN PHAP LY)
Op Lat Tools v%s
(c) [TEN CONG TY / CA NHAN] - Bao luu moi quyen.

1. Phan mem cap phep su dung, khong chuyen nhuong quyen so huu.
2. Gioi han: [SO MAY / SO NGUOI DUNG].
3. Khong duoc sao chep de phan phoi, ban lai, cho thue hoac go bo thong tin ban quyen.
4. Cac so lieu, tieu chuan va goi y trong phan mem chi de tham khao; nguoi dung tu kiem tra va chiu trach nhiem ve ban ve, khoi luong, dat hang va thi cong.
5. Phan mem cung cap nguyen trang, khong bao dam phu hop moi muc dich; trach nhiem toi da
   gioi han trong muc phi da thu. Nguoi dung tu kiem tra ket qua truoc khi thi cong / dat hang.
6. Lien he ho tro: [EMAIL / DIEN THOAI].
""" % PRODUCT_VER
open(f'{OUT}/BanQuyen.txt', 'w', encoding='utf-8-sig', newline='').write(BANQUYEN.replace('\n', '\r\n'))

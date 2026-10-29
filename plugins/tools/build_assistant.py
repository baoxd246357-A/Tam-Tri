#!/usr/bin/env python3
"""Dong goi huong dan thanh tro ly OFFLINE (1 file HTML, khong goi mang).

  python3 -I build_assistant.py <thu-muc-goi-SDOpLat> <HuongDanKhach.html> <file-ra.html> [--contact="email / sdt"] [--keep-untested]

Doc: HuongDanLenh.html, LenhTat.csv, CaiDat.txt, HuongDanQuyTrinhDa.md trong thu muc goi + HuongDanKhach.html.
Mac dinh bo cac cau "Chua thu tren AutoCAD that" khoi cau tra loi (da co mien tru chung); --keep-untested de giu lai.
Khong doc BAN_HANG, secret hay cong cu nguoi ban.
"""
import re, sys, os, csv, json, html

args = [a for a in sys.argv[1:] if not a.startswith('--')]
PKG, GUIDE, OUT = args[:3]
CONTACT = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--contact=')), '')
KEEP = '--keep-untested' in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))

def txt(s):
    s = re.sub(r'<br\s*/?>', ' ', s)
    return html.unescape(re.sub(r'<[^>]+>', '', s)).strip()

def clean(s):
    if KEEP: return s
    # bo cau "Chua thu tren AutoCAD that ..." (den dau cham ket cau)
    s = re.sub(r'\s*Chưa thử[^.]*\.', '', s)
    return re.sub(r'\s+', ' ', s).strip()

# ------------------------------------------------------------------ lenh
rows = list(csv.reader(open(f'{PKG}/LenhTat.csv', encoding='utf-8-sig'), delimiter=';'))[1:]
meta = {r[2]: dict(group=r[0], alias=r[1], title=r[3]) for r in rows if len(r) >= 4}
doc = open(f'{PKG}/HuongDanLenh.html', encoding='utf-8').read()
cmds = {}
for m in re.finditer(r'<div class="cmd"[^>]*>(.*?)</div>', doc, re.S):
    b = m.group(1); code = re.search(r'<code>(SD[A-Z0-9]+)</code>', b)
    if not code or code.group(1) not in meta: continue
    code = code.group(1)
    ps = re.findall(r'<p(?: class="note")?>(.*?)</p>', b, re.S)
    res = next((txt(p)[len('Kết quả:'):].strip() for p in ps if txt(p).startswith('Kết quả:')), '')
    note = next((txt(p) for p in ps if txt(p).startswith('Lưu ý:')), '')
    summ = txt(ps[0]) if ps else ''
    cmds[code] = dict(code=code, alias=meta[code]['alias'], group=meta[code]['group'], title=meta[code]['title'],
                      summary=clean(summ), steps=[clean(txt(x)) for x in re.findall(r'<li>(.*?)</li>', b, re.S)],
                      result=clean(res), note=clean(note))
    if note and not clean(note).replace('Lưu ý:', '').strip(): cmds[code]['note'] = ''
for code, m in meta.items():           # lenh co trong csv nhung khong co khoi huong dan (vd SDMENUXOA)
    if code not in cmds:
        cmds[code] = dict(code=code, alias=m['alias'], group=m['group'], title=m['title'], summary=m['title'], steps=[], result='', note='')
CORE = ['SDSET', 'SDGACH', 'SDRAITAM', 'SDDOCDA', 'SDANHDA', 'SDVANDA', 'SDGACHTK', 'SDKTLAT', 'SDQUYTRINH', 'SDDIMGD']
order = sorted(cmds.values(), key=lambda c: (0 if c['code'] in CORE else 1, CORE.index(c['code']) if c['code'] in CORE else 0,
                                              list(meta).index(c['code'])))
group_order = []
for c in order:
    if c['group'] not in group_order: group_order.append(c['group'])
# nhom "co ban" len dau
BASIC_NAME = 'Lệnh cơ bản'
for c in order:
    if c['code'] in CORE: c['group'] = BASIC_NAME
groups = [BASIC_NAME] + [g for g in group_order if g != BASIC_NAME]

# ------------------------------------------------------------------ tai lieu dang van ban (guides)
def html_to_md(frag):
    frag = re.sub(r'<h3[^>]*>(.*?)</h3>', lambda m: '\n### ' + txt(m.group(1)) + '\n', frag, flags=re.S)
    frag = re.sub(r'<table[^>]*>(.*?)</table>', lambda m: '\n' + '\n'.join(
        '| ' + ' | '.join(txt(c) for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', r, re.S)) + ' |' + ('\n|---|---|---|' if i == 0 else '')
        for i, r in enumerate(re.findall(r'<tr[^>]*>(.*?)</tr>', m.group(1), re.S))) + '\n', frag, flags=re.S)
    frag = re.sub(r'<ol[^>]*>(.*?)</ol>', lambda m: '\n' + '\n'.join(f'{i+1}. ' + txt(x) for i, x in enumerate(re.findall(r'<li>(.*?)</li>', m.group(1), re.S))) + '\n', frag, flags=re.S)
    frag = re.sub(r'<ul[^>]*>(.*?)</ul>', lambda m: '\n' + '\n'.join('- ' + txt(x) for x in re.findall(r'<li>(.*?)</li>', m.group(1), re.S)) + '\n', frag, flags=re.S)
    frag = re.sub(r'<p[^>]*>(.*?)</p>', lambda m: '\n' + txt(m.group(1)) + '\n', frag, flags=re.S)
    frag = re.sub(r'<div class="(?:note)"[^>]*>(.*?)</div>', lambda m: '\n' + txt(m.group(1)) + '\n', frag, flags=re.S)
    frag = re.sub(r'<[^>]+>', '', frag)
    return re.sub(r'\n{3,}', '\n\n', html.unescape(frag)).strip()

g = open(GUIDE, encoding='utf-8').read()
body = g[g.index('<main>'):]
guides = []
secs = re.split(r'(?=<h2>)', body)
for sct in secs[1:]:
    title = txt(re.match(r'<h2>(.*?)</h2>', sct, re.S).group(1))
    t = re.sub(r'^\d+\.\s*', '', title)
    text = html_to_md(sct.split('</h2>', 1)[1].split('<footer')[0])
    if t.startswith('Gặp sự cố') or t.startswith('Làm theo thứ tự') or t.startswith('Các lệnh cơ bản'): continue  # co faq / the lenh rieng
    guides.append(dict(title=t, text=text, src='Hướng dẫn nhanh (HuongDanKhach.html)'))
caidat = open(f'{PKG}/CaiDat.txt', encoding='utf-8-sig').read()
qt = open(f'{PKG}/HuongDanQuyTrinhDa.md', encoding='utf-8').read()
for sct in re.split(r'(?m)^(?=## )', qt)[1:]:
    t = re.match(r'## (.*)', sct).group(1)
    guides.append(dict(title='Quy trình đá lát liên hoàn: ' + re.sub(r'^\d+\.\s*', '', t), text=sct.split('\n', 1)[1].strip(), src='HuongDanQuyTrinhDa.md'))
ver = (re.search(r'v(\d+\.\d+\.\d+)', caidat) or [None, ''])[1]

# ------------------------------------------------------------------ hoi dap (soan tu tai lieu cua goi)
def F(id, title, q, a, src='Hướng dẫn nhanh'):
    return dict(id=id, title=title, q=q, a=a, src=src)
faq = [
 F('chon-lenh', 'Nên dùng lệnh nào cho việc của tôi?', ['nên dùng lệnh nào', 'chọn lệnh nào', 'bắt đầu từ đâu'],
   '''| Tình huống | Lệnh |
|---|---|
| Một vùng lát đã có polyline kín, cần chia viên | `SDGACH` |
| Nhiều ô / phòng, rải theo kho tấm (Panel hoặc Đá) | `SDRAITAM` |
| Bản vẽ chỉ có nét rời (LINE, polyline hở), chưa có polyline kín | `SDDOCDA` |
| Đã có viên và có ảnh tấm đá thật | `SDANHDA` |
| Đã có viên nhưng chưa có ảnh tấm đá | `SDVANDA` |
| Cần bảng thống kê và số lượng đặt hàng | `SDGACHTK` |
| Kiểm tra viên hẹp, ron không đều trước khi phát hành | `SDKTLAT` |
| Không nhớ thứ tự các bước | `SDQUYTRINH` |
| Dim các đoạn giữa các giao điểm trên một đường cắt | `SDDIMGD` (DGD) |

Bản vẽ mới: chạy `SDSET` trước để đặt tỷ lệ, layer, kiểu chữ.''', 'Hướng dẫn nhanh · Các bước làm việc'),
 F('cai-dat', 'Cài đặt', ['cài đặt', 'cài plugin', 'cách cài', 'cài đặt thế nào', 'appload', 'nạp lisp', 'giải nén'],
   '''1. Giải nén cả thư mục vào một chỗ cố định, ví dụ `D:\\SDOpLat` (không để trong Downloads hay thư mục tạm).
2. Mở AutoCAD, gõ `APPLOAD`, chọn file `SDOpLat.lsp` (hoặc `SDOpLat.fas` nếu bạn nhận bản đã biên dịch), bấm Load.
3. Gõ `SDMENU`: lần đầu chọn file `SDOpLat.mnu` trong thư mục vừa giải nén. Menu và thanh công cụ hiện ra, lần sau tự nạp.
4. Không muốn cài menu: gõ `SDPANEL` để mở bảng lệnh, hoặc gõ `SDTUNAP` một lần để tự nạp mỗi lần mở AutoCAD.
5. Gỡ menu: `SDMENUXOA`.'''),
 F('kich-hoat', 'Kích hoạt bản quyền', ['kích hoạt', 'mã máy', 'mã kích hoạt', 'nhập mã', 'nhập mã ở đâu', 'dán mã ở đâu', 'gõ mã ở đâu', 'bản quyền', 'sdkichhoat', 'activate'],
   '''1. Gõ `SDKICHHOAT` (lệnh tắt `KHB`), ghi lại **Mã máy** dạng `XXXX-XXXX-XXXX`.
2. Gửi Mã máy cho nhà cung cấp. Bạn sẽ nhận **Mã kích hoạt** dạng `XXXXX-XXXXX-XXXXX`.
3. Gõ lại `SDKICHHOAT` và dán mã vào **dòng hỏi** "Nhap Ma kich hoat" rồi Enter. **Không** gõ mã ở dòng `Command:`, AutoCAD sẽ báo `Unknown command`.

Mã chỉ dùng được trên đúng máy đã gửi Mã máy. Báo "không đúng cho máy này" nghĩa là mã cấp cho máy khác hoặc Mã máy gửi đi chưa đúng.'''),
 F('het-luot', 'Hết lượt dùng thử', ['hết lượt dùng thử', 'dùng thử', 'còn lần', 'bị chặn', 'het 10 lan', 'trial'],
   '''Bản dùng thử chạy được một số lần giới hạn. Mỗi lần chạy một lệnh chính tính một lần; AutoCAD hiện "Ban dung thu: con x / N lan". Hết lượt, lệnh bị chặn và hiện Mã máy.

Để dùng tiếp: gõ `SDKICHHOAT`, gửi Mã máy cho nhà cung cấp, nhập Mã kích hoạt nhận được. Các lệnh `SDKICHHOAT`, `SDHELP`, `SDPANEL`, `SDMENU` luôn chạy được.'''),
 F('doi-may', 'Đổi máy hoặc cài lại Windows', ['đổi máy', 'cài lại windows', 'máy mới', 'mã máy thay đổi', 'chuyển sang máy khác'],
   'Mã kích hoạt gắn với Mã máy. Đổi máy hoặc cài lại Windows có thể làm Mã máy thay đổi, khi đó mã cũ không còn đúng. Chạy `SDKICHHOAT` để lấy Mã máy mới rồi liên hệ nhà cung cấp để được hỗ trợ.'),
 F('mat-lenh', 'Không thấy lệnh sau khi mở lại AutoCAD', ['không thấy lệnh sau khi mở lại autocad', 'mất lệnh', 'unknown command', 'lệnh không chạy', 'phải appload lại', 'tự nạp'],
   '''`APPLOAD` thường chỉ nạp cho phiên hiện tại; mở lại AutoCAD là mất lệnh. Cách xử lý:
- Gõ `SDTUNAP` một lần để plugin tự nạp mỗi khi mở AutoCAD.
- Hoặc gõ `SDMENU` để cài menu và nạp lại tự động.

Nếu gõ tên lệnh mà AutoCAD báo `Unknown command`, kiểm tra plugin đã được nạp (dòng "da nap" hiện ra) và gõ đúng tên lệnh hoặc lệnh tắt.'''),
 F('menu-khong-hien', 'Menu hoặc thanh công cụ không hiện', ['menu không hiện', 'không thấy menu', 'thanh công cụ không hiện', 'toolbar', 'ribbon', 'sdmenu'],
   '''- Gõ `SDMENU` và chọn đúng file `SDOpLat.mnu` trong thư mục vừa giải nén.
- Nếu đã từng cài bản cũ, xóa các thư mục bản cũ khỏi `OPTIONS > Files > Support File Search Path` để tránh nạp nhầm menu bản cũ.
- Không thấy mục trên thanh menu: `CUI > Workspaces > (workspace đang dùng) > Customize Workspace > tích menu SDOpLat > Apply`.
- Gói không kèm tab Ribbon; dùng menu, thanh công cụ hoặc `SDPANEL`.'''),
 F('excel', 'Lệnh xuất bảng và Excel', ['excel', 'xuất bảng', 'csv', 'không có excel', 'xuất sang excel'],
   'Các lệnh xuất bảng sang Excel cần Microsoft Excel (hoặc phần mềm bảng tính tương tự có hỗ trợ COM, chưa được kiểm tra). Nếu không có Excel, các lệnh có xuất file CSV vẫn có thể mở bằng phần mềm bảng tính khác.'),
 F('he-thong', 'Yêu cầu hệ thống', ['yêu cầu hệ thống', 'windows', 'mac', 'autocad lt', 'zwcad', 'gstarcad', 'bricscad', 'phiên bản autocad'],
   '''- Windows (plugin dùng COM / Visual LISP nên không dùng cho Mac).
- AutoCAD bản đầy đủ. AutoCAD LT chưa được kiểm tra: nhiều lệnh có thể không chạy.
- Các phần mềm CAD tương tự hỗ trợ AutoLISP (ZWCAD, GstarCAD, BricsCAD) có thể chạy nhưng chưa được kiểm tra.
- Chưa kiểm tra trên mọi phiên bản AutoCAD.'''),
 F('bao-mat', 'Cảnh báo bảo mật khi cài', ['cảnh báo bảo mật', 'trusted locations', 'trustedpaths', 'acaddoc', 'phần mềm diệt virus', 'support path'],
   '`SDMENU` và `SDTUNAP` thêm thư mục cài đặt vào **Support File Search Path** và **Trusted Locations** (`TRUSTEDPATHS`) của AutoCAD, và `SDTUNAP` có thể ghi khối tự nạp vào `acaddoc.lsp` của bạn. Phần mềm bảo mật có thể hỏi lại; chỉ cho phép nếu bạn tin tưởng nguồn tải. Gỡ bằng `SDMENUXOA` và chạy lại `SDTUNAP` để tắt tự nạp.'),
 F('anh-khong-cat', 'SDANHDA không cắt được ảnh', ['sdanhda không cắt được ảnh', 'ảnh không cắt', 'imageclip lỗi', 'ảnh tấm đá không đúng tỷ lệ', 'ảnh bị xoay'],
   '''- Ảnh phải có **góc xoay 0** và **đúng tỷ lệ thật** của tấm (ví dụ 2450 × 1170 mm), chèn bằng `IMAGEATTACH`.
- Viên quá lớn so với tấm sẽ không xếp được; chiều vân `Ngang` với viên dài hơn cạnh tấm thì báo không cắt được.
- Chiều vân chỉ xoay theo bội 90° so với cạnh dài viên.
- Gói có ảnh mẫu trong thư mục `Maps` (tên file có đuôi `_DàixRộng` thì `SDMAP` tự dùng khổ đó).''', 'HuongDanQuyTrinhDa.md · Lưu ý'),
 F('khong-thay-van', 'Không thấy vân đá (SDVANDA)', ['không thấy vân', 'không tìm thấy file pat', 'pat', 'hatch vân lỗi', 'sdvanda lỗi'],
   'Báo lỗi khi AutoCAD không tìm thấy file `.pat` (Platinus, DaSocDua, ViaLactea, DaVanGoXam, DaVanGoCo). Chạy lại `SDMENU` để thư mục cài đặt được thêm vào Support File Search Path, hoặc kiểm tra các file `.pat` nằm cùng thư mục với `SDOpLat.lsp`.'),
 F('ghi-vien-le', 'Ghi hoặc không ghi mã viên cắt (viên lẻ)', ['ghi mã viên lẻ', 'tắt mã viên cắt', 'bản vẽ rối chữ', 'nhãn viên cắt', 'không ghi viên lẻ', 'ẩn mã G1-C'],
   'Trong hộp thoại `SDGACH` có ô **"Ghi ma len vien cat / vien le (G1-C1...)"**. Bỏ tích ô này để bản vẽ không ghi mã lên các viên cắt (mã vẫn lưu trong dữ liệu viên nên `SDGACHTK`, `SDDATHO`, `SDGIACONG` vẫn dùng bình thường). Ô **"Ghi ma len vien nguyen"** điều khiển nhãn trên viên nguyên.', 'HuongDanLenh.html · SDGACH'),
 F('ban-cu', 'Hộp thoại thiếu ô hoặc lệnh không tồn tại (đang nạp bản cũ)', ['lệnh không tồn tại sdraitam', 'sdgach thiếu ô cắt ảnh', 'hộp thoại thiếu', 'unknown command sdraitam', 'sdddimgd unknown command', 'bản cũ', 'phiên bản'],
   '''Nếu một lệnh báo `Unknown command` (ví dụ `SDRAITAM`, `SDDIMGD`) hoặc hộp thoại `SDGACH` không có ô "Cat anh tam da that vao cac vien", thường là AutoCAD đang nạp **một bản cũ** của bộ lệnh (từ lần cài trước) thay vì bản mới.

1. Gõ `!*SD:VER*` rồi Enter: bản mới hiện `"1.0.0"` hoặc cao hơn.
2. Xóa bản cũ khỏi `OPTIONS > Files > Support File Search Path` và khỏi `Startup Suite`; kiểm tra `acaddoc.lsp` không còn dòng nạp bản cũ (`SDTUNAP` ghi dòng này).
3. Đóng AutoCAD, mở lại, cài bản mới.''', 'Hướng dẫn nhanh'),
 F('hoan-tac', 'Hoàn tác một lệnh', ['hoàn tác', 'undo', 'làm lại', 'xóa kết quả lệnh', 'bấm nhầm'],
   'Mỗi lệnh gom vào một lần Undo: gõ `U` để hoàn tác cả lệnh. Bấm Esc giữa chừng thì lệnh dừng; với `SDDIMGD` (DGD) lệnh tự trả lại cài đặt hệ thống.'),
 F('bao-loi', 'Báo lỗi cho nhà cung cấp', ['báo lỗi', 'gửi lỗi', 'lệnh bị lỗi', 'error', 'hỗ trợ', 'liên hệ'],
   'Gửi cho nhà cung cấp: phiên bản AutoCAD (gõ `ABOUT`), tên lệnh, và các dòng lệnh hiện ra (nhấn `F2` để xem lịch sử, chép nguyên dòng báo lỗi). Nếu được, gửi kèm bản sao bản vẽ nhỏ tái hiện lỗi.'),
 F('tham-khao', 'Số liệu và trách nhiệm', ['trách nhiệm', 'tham khảo', 'tiêu chuẩn', 'miễn trừ', 'có chính xác không', 'kiểm tra kết quả'],
   'Các số liệu, tiêu chuẩn và gợi ý trong phần mềm và tài liệu chỉ để **tham khảo**. Bạn tự kiểm tra, đối chiếu hồ sơ thiết kế và tiêu chuẩn áp dụng, và chịu trách nhiệm về bản vẽ, khối lượng, đặt hàng và thi công. Hãy chạy thử trên bản sao bản vẽ trước khi dùng cho hồ sơ thật.'),
]
topics = [['Nên dùng lệnh nào?', 'Chọn lệnh theo việc cần làm', 'nên dùng lệnh nào'], ['Cài đặt', 'APPLOAD, SDMENU, SDPANEL', 'cài đặt'],
          ['Kích hoạt bản quyền', 'Mã máy, mã kích hoạt, dùng thử', 'kích hoạt'], ['Quy trình làm việc', 'Các bước từ chia viên đến thống kê', 'quy trình làm việc'],
          ['Sự cố thường gặp', 'Mất lệnh, menu không hiện, lỗi ảnh', 'không thấy lệnh sau khi mở lại AutoCAD'], ['Yêu cầu hệ thống', 'Windows, AutoCAD, Excel', 'yêu cầu hệ thống']]
nxt = {'SDSET': ['SDGACH', 'SDRAITAM', 'SDDOCDA'], 'SDGACH': ['SDANHDA', 'SDVANDA'], 'SDRAITAM': ['SDANHDA', 'SDVANDA'], 'SDDOCDA': ['SDANHDA', 'SDVANDA'],
       'SDANHDA': ['SDGACHTK', 'SDKTLAT'], 'SDVANDA': ['SDGACHTK', 'SDKTLAT'], 'SDGACHTK': ['SDKTLAT'], 'SDTKDA': ['SDGACHTK'], 'SDDOCDATK': ['SDKTLAT'], 'SDANHDATK': ['SDKTLAT']}
footer = ('Chạy hoàn toàn trên máy bạn, không cần mạng. Nội dung từ tài liệu của gói v%s; số liệu chỉ để tham khảo, hãy chạy thử trên bản sao bản vẽ.' % ver
          + ((' Hỗ trợ: ' + CONTACT) if CONTACT else ' Cần hỗ trợ thêm: liên hệ nhà cung cấp phần mềm.'))
kb = dict(version=ver, cmds=[dict(c) for c in order], groups=[dict(name=g) for g in groups], faq=faq, guides=guides, topics=topics, next=nxt, footer=footer)
for c in kb['cmds']:
    c['aliases'] = [c['alias']] if c['alias'] else []
KW = {  # tu khoa dung-khi (do nguoi soan dat), giup tim dung lenh khi nguoi dung mo ta bang loi
 'SDSET': 'ty le layer kieu chu dimstyle ban ve moi bat dau thiet lap',
 'SDGACH': 'chia gach chia vien lat gach op lat mot vung mot phong polyline kin duong bao thang so le xuong ca chevron',
 'SDRAITAM': 'rai tam rai panel kho tam nhieu o nhieu phong go bu tam di hinh rai da theo kho',
 'SDDOCDA': 'doc mat bang net roi line roi polyline ho chua co polyline khong ve lai dung o kin bang csv',
 'SDANHDA': 'anh tam da cat anh imageclip van that anh chup tam da hao it xep tam',
 'SDVANDA': 'hatch van da pat chua co anh khong co anh van gia',
 'SDGACHTK': 'thong ke dat hang so luong vien bang thong ke du tru hao hut hao phi',
 'SDKTLAT': 'kiem tra vien hep vien nho ron khong deu thieu ma vat lieu khe gian no',
 'SDQUYTRINH': 'quy trinh thu tu cac buoc buoc tiep theo khong nho lien hoan hop thoai goi y',
 'SDDIMPOLY': 'dim polyline kin dim canh cung tron dpk dim tung canh chu ra ngoai goc hep',
 'SDDIMGD': 'dim giao diem duong cat dim tung doan dim tong kich thuoc',
 'SDDATHO': 'cat vien tu da tho so do cat hieu suat hao hut hao phi slab kho tam',
 'SDLOT': 'nhieu phong chay lo hang loat nhieu khu vuc',
 'SDTUNAP': 'tu nap mat lenh mo lai autocad khong phai appload',
}
for c in kb['cmds']:
    c['kw'] = KW.get(c['code'], '')
tpl = open(os.path.join(HERE, 'assistant_template.html'), encoding='utf-8').read()
open(OUT, 'w', encoding='utf-8').write(tpl.replace('__KB__', json.dumps(kb, ensure_ascii=False).replace('</', '<\\/')))
print('lenh', len(kb['cmds']), 'faq', len(faq), 'tai lieu', len(guides), 'bytes', os.path.getsize(OUT))

#!/usr/bin/env python3
"""Sinh checklist thu tung lenh tren AutoCAD that: python3 -I build_checklist.py <thu-muc-SDOpLat> <file-html-ra>"""
import re, sys, html, json

D, OUT = sys.argv[1], sys.argv[2]
h = open(f'{D}/HuongDanLenh.html', encoding='utf-8').read()
lsp = open(f'{D}/SDOpLat.lsp', encoding='latin-1').read()
rows = re.findall(r'^\s*\(?\(?"([^"]+)" "(SD[A-Z0-9]+)" "([^"]*)" "([A-Z0-9]+)" "([A-Z0-9]+)"\)', lsp, re.M)
info = {r[1]: dict(group=r[0], desc=r[2], alias=r[4]) for r in rows}

def txt(s):
    s = re.sub(r'<[^>]+>', '', s)
    return html.unescape(s).strip()

cmds = {}
for m in re.finditer(r'<div class="cmd"[^>]*>(.*?)</div>', h, re.S):
    b = m.group(1)
    code = re.search(r'<code>(SD[A-Z0-9]+)</code>', b)
    if not code: continue
    ps = re.findall(r'<p(?: class="note")?>(.*?)</p>', b, re.S)
    steps = [txt(x) for x in re.findall(r'<li>(.*?)</li>', b, re.S)]
    res = next((txt(p)[len('Kết quả:'):].strip() for p in ps if txt(p).startswith('Kết quả:')), '')
    note = next((txt(p) for p in ps if txt(p).startswith('Lưu ý:')), '')
    cmds[code.group(1)] = dict(summary=txt(ps[0]) if ps else '', steps=steps, result=res, note=note)

CORE = ['SDSET', 'SDGACH', 'SDRAITAM', 'SDDOCDA', 'SDANHDA', 'SDVANDA', 'SDGACHTK', 'SDTKDA', 'SDDOCDATK', 'SDANHDATK',
        'SDQUYTRINH', 'SDKTLAT', 'SDVAN', 'SDDIEMBD', 'SDKHEGIAN', 'SDHANDINH', 'SDRON', 'SDRONIN', 'SDLOT', 'SDDATHO', 'SDGIACONG']
order = [c for c in CORE if c in info] + [c for c in info if c not in CORE and c in cmds]
GN = {'Op lat da granite / gach': 'Ốp lát đá granite / gạch (còn lại)', 'Tien ich': 'Tiện ích', 'Thiet lap va ban ve': 'Thiết lập và bản vẽ'}
def gname(c):
    return 'Quy trình ốp lát chính (thử trước)' if c in CORE else GN.get(info[c]['group'], info[c]['group'])
pos = {c: i for i, c in enumerate(order)}
order.sort(key=lambda c: (0 if c in CORE else 1, ['Op lat da granite / gach', 'Thiet lap va ban ve', 'Tien ich'].index(info[c]['group']) if c not in CORE else 0, pos[c]))
EXTRA_NOTE = {'SDHANDINH': 'Thử trên bản vẽ có polyline lệch đỉnh (vd file V6.dxf): sau lệnh, đỉnh các polyline kề nhau phải trùng; U hoàn tác được.',
              'SDKTLAT': 'Thử thêm ô "khe giãn nở": nhập > 0, chọn polyline biên; vòng đỏ ở viên sát tường hoặc chỗ đổi vật liệu.',
              'SDVAN': 'Thử thêm tùy chọn bookmatch (cần đã chạy SDANHDA với ≥ 2 tấm).',
              'SDDIEMBD': 'Thử thêm ô "Khe sát tường" > 0: biên lùi vào, lỗ/cột nở ra.',
              'SDDOCDA': 'Kiểm tra các ô kề nhau trùng đỉnh (chạy SDHANDINH không còn thay đổi gì).'}
COMMON = ['Chạy không báo lỗi (không có "error:" hay bản vẽ treo)', 'Hộp thoại mở đúng, nhập số/ký tự tiếng Việt không vỡ', 'Kết quả đúng như mô tả (kích thước, layer, số lượng)', 'Esc giữa chừng: không để đối tượng dở dang, lệnh sau vẫn chạy', 'U hoàn tác cả lệnh một lần']

sections = [
 ('Chuẩn bị', [
   'Ghi lại: phiên bản AutoCAD (gõ ABOUT), Windows, có Excel không',
   'Mở bản vẽ thử gồm: 1 hình chữ nhật 4×5 m, 1 hình có cột/lỗ, 1 vùng bất quy tắc; chuẩn bị 1 ảnh tấm đá (Maps\\Xam-van-go_2450x1170.jpg) đúng tỷ lệ thật',
   'Sao lưu bản vẽ thật trước khi thử trên bản thật']),
 ('Cài đặt và nạp', [
   'APPLOAD nạp SDOpLat.lsp (hoặc .fas nếu đã biên dịch): có dòng "da nap", không báo lỗi',
   'Gõ SDHELP: hiện danh sách lệnh đủ 3 nhóm; SDPANEL mở hộp thoại, bấm thử vài lệnh từ đây',
   'SDMENU: nạp menu + toolbar; kiểm tra pull-down "SDOpLat" và toolbar ốp lát hiện, icon hiện đúng',
   'Đóng AutoCAD, mở lại: lệnh còn không? (nếu đã SDMENU/SDTUNAP)',
   'SDTUNAP bật/tắt tự nạp; kiểm tra file acaddoc.lsp không bị ghi trùng sau khi bật 2 lần',
   'SDMENUXOA gỡ sạch menu/toolbar',
   'Lệnh tắt (vd CHV, RTA, ADA, HDI): chạy đúng như lệnh đầy đủ',
   'SDDLG tắt hộp thoại: lệnh chuyển sang nhập trên dòng lệnh; bật lại bình thường']),
 ('Khóa bản quyền (chỉ với bản build --licensed)', [
   'Chưa kích hoạt: chạy lệnh khóa (vd SDGACH) → hiện "Bản dùng thử: còn x / 10 lần" và lệnh vẫn chạy',
   'Chạy tiếp đủ số lần dùng thử: lần thứ 11 bị chặn, hiện Mã máy',
   'SDKICHHOAT hiện Mã máy dạng XXXX-XXXX-XXXX; ghi lại gửi cho người bán',
   'Nhập mã sai: báo sai, vẫn bị khóa',
   'Nhập mã đúng (tạo bằng sdoplat_keygen.py): "Kích hoạt thành công", lệnh chạy không còn thông báo dùng thử',
   'Đóng AutoCAD, mở lại: vẫn đã kích hoạt',
   'Gõ (sd:lic-selftest): in "OK"',
   'Xóa registry HKCU\\Software\\SDOpLat\\Uses và file %APPDATA%\\SDOpLat.dat → bộ đếm dùng thử về 0 (đã biết giới hạn); sửa tay giá trị Uses → bị coi hết lượt',
   'Bản .fas: không còn file .lsp trong gói, APPLOAD .fas vẫn chạy đủ lệnh']),
]
payload = dict(sections=sections, cmds=[dict(code=c, alias=info[c]['alias'], group=gname(c), desc=info[c]['desc'],
        summary=cmds[c]['summary'], steps=cmds[c]['steps'], result=cmds[c]['result'], note=cmds[c]['note'], extra=EXTRA_NOTE.get(c, '')) for c in order],
        common=COMMON)

page = '''<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Checklist thử SDOpLat</title>
<style>
:root{--bg:#f7f7f5;--fg:#1d1d1b;--mut:#6b6b66;--card:#fff;--bd:#dcdcd6;--ok:#1e7a3c;--bad:#b3261e;--skip:#8a6d00;--acc:#2a5db0}
@media(prefers-color-scheme:dark){:root{--bg:#171715;--fg:#ececE8;--mut:#9a9a93;--card:#222220;--bd:#3a3a36;--ok:#5fcf86;--bad:#ff8a80;--skip:#e0bf55;--acc:#7fb0ff}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:900px;margin:0 auto;padding:16px}
h1{font-size:22px;margin:8px 0}h2{font-size:18px;margin:28px 0 8px}
.bar{position:sticky;top:0;background:var(--bg);padding:8px 0;border-bottom:1px solid var(--bd);z-index:5;display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.bar button,.bar select{font:inherit;padding:6px 10px;border:1px solid var(--bd);border-radius:6px;background:var(--card);color:var(--fg);cursor:pointer}
.sum{color:var(--mut);font-size:14px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:8px;padding:12px;margin:10px 0}
.card h3{margin:0 0 4px;font-size:16px}.card code{background:var(--bg);padding:1px 5px;border-radius:4px}
.mut{color:var(--mut);font-size:13px}ol,ul{margin:6px 0 6px 20px;padding:0}
.row{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px;align-items:center}
.st button{font:inherit;padding:4px 10px;border:1px solid var(--bd);border-radius:6px;background:var(--bg);color:var(--fg);cursor:pointer}
.st button.on.ok{background:var(--ok);color:#fff;border-color:var(--ok)}.st button.on.bad{background:var(--bad);color:#fff;border-color:var(--bad)}.st button.on.skip{background:var(--skip);color:#fff;border-color:var(--skip)}
textarea{flex:1;min-width:200px;font:inherit;padding:6px;border:1px solid var(--bd);border-radius:6px;background:var(--bg);color:var(--fg)}
label.c{display:block;margin:3px 0}details summary{cursor:pointer;color:var(--acc)}
@media print{.bar{display:none}.card{break-inside:avoid}}
</style></head><body><main>
<h1>Checklist thử SDOpLat trên AutoCAD thật</h1>
<p class="mut">Với mỗi lệnh: chạy theo các bước, rồi bấm <b>Đạt</b> / <b>Lỗi</b> / <b>Bỏ qua</b>. Khi lỗi, ghi vào ô ghi chú: phiên bản AutoCAD, các dòng lệnh hiện ra, bước nào lỗi. Dữ liệu lưu ngay trong trình duyệt này; bấm <b>Xuất CSV</b> để gửi lại kết quả.</p>
<div class="bar"><span class="sum" id="sum"></span><select id="flt"><option value="">Tất cả</option><option value="none">Chưa thử</option><option value="bad">Lỗi</option><option value="ok">Đạt</option></select><button id="exp">Xuất CSV</button><button id="rst">Xóa kết quả</button></div>
<div id="root"></div>
<script>
const D=__DATA__;
const KEY='sdoplat-checklist-v1';let S={};try{S=JSON.parse(localStorage.getItem(KEY)||'{}')}catch(e){}
const save=()=>{try{localStorage.setItem(KEY,JSON.stringify(S))}catch(e){}};
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const items=[];
function card(id,title,body,sub){items.push(id);return `<div class="card" data-id="${id}"><h3>${title}</h3>${sub?`<div class="mut">${sub}</div>`:''}${body}
<div class="row"><span class="st">${[['ok','Đạt'],['bad','Lỗi'],['skip','Bỏ qua']].map(([k,l])=>`<button data-k="${k}" class="${k}">${l}</button>`).join(' ')}</span>
<textarea rows="1" placeholder="Ghi chú / lỗi / dòng lệnh" data-n="${id}"></textarea></div></div>`}
let out='';
D.sections.forEach((s,i)=>{out+=`<h2>${esc(s[0])}</h2>`;s[1].forEach((t,j)=>{out+=card(`s${i}.${j}`,esc(t),'')})});
out+='<h2>Từng lệnh</h2><p class="mut">Mỗi lệnh kiểm tra thêm 5 mục chung: '+D.common.map(esc).join('; ')+'.</p>';
let grp='';
D.cmds.forEach(c=>{if(c.group!==grp){grp=c.group;out+=`<h2>${esc(grp)}</h2>`}
 const b=`<p>${esc(c.summary||c.desc)}</p>`+(c.steps.length?'<ol>'+c.steps.map(x=>`<li>${esc(x)}</li>`).join('')+'</ol>':'')+(c.result?`<p><b>Kết quả mong đợi:</b> ${esc(c.result)}</p>`:'')+(c.extra?`<p><b>Thử thêm:</b> ${esc(c.extra)}</p>`:'')+(c.note?`<details><summary>Lưu ý của tài liệu</summary><p class="mut">${esc(c.note)}</p></details>`:'');
 out+=card(c.code,`<code>${c.code}</code> ${c.alias&&c.alias!==c.code?`<span class="mut">(lệnh tắt ${c.alias})</span>`:''}`,b,'')});
document.getElementById('root').innerHTML=out;
function paint(){document.querySelectorAll('.card').forEach(el=>{const id=el.dataset.id,v=(S[id]||{});el.querySelectorAll('.st button').forEach(b=>b.classList.toggle('on',v.s===b.dataset.k));const t=el.querySelector('textarea');if(document.activeElement!==t)t.value=v.n||''});
 let ok=0,bad=0,sk=0;items.forEach(i=>{const s=(S[i]||{}).s;if(s==='ok')ok++;else if(s==='bad')bad++;else if(s==='skip')sk++});
 document.getElementById('sum').textContent=`Đạt ${ok} · Lỗi ${bad} · Bỏ qua ${sk} · Còn ${items.length-ok-bad-sk} / ${items.length}`;filter()}
function filter(){const f=document.getElementById('flt').value;document.querySelectorAll('.card').forEach(el=>{const s=(S[el.dataset.id]||{}).s;el.style.display=!f||(f==='none'?!s:s===f)?'':'none'});
 document.querySelectorAll('#root h2').forEach(h=>{let n=h.nextElementSibling,any=false,hasCard=false;while(n&&n.tagName!=='H2'){if(n.classList.contains('card')){hasCard=true;if(n.style.display!=='none')any=true}n=n.nextElementSibling}h.style.display=(!hasCard||any)?'':'none'})}
document.getElementById('root').addEventListener('click',e=>{const b=e.target.closest('.st button');if(!b)return;const id=b.closest('.card').dataset.id;S[id]=S[id]||{};S[id].s=S[id].s===b.dataset.k?'':b.dataset.k;save();paint()});
document.getElementById('root').addEventListener('input',e=>{if(e.target.dataset.n){const id=e.target.dataset.n;S[id]=S[id]||{};S[id].n=e.target.value;save()}});
document.getElementById('flt').onchange=filter;
document.getElementById('rst').onclick=()=>{if(confirm('Xóa toàn bộ kết quả đã ghi?')){S={};save();paint()}};
document.getElementById('exp').onclick=()=>{const L={ok:'Dat',bad:'Loi',skip:'Bo qua','':'Chua thu'};const rows=[['Muc','Ket qua','Ghi chu']];
 document.querySelectorAll('.card').forEach(el=>{const id=el.dataset.id,v=S[id]||{};rows.push([el.querySelector('h3').textContent.trim(),L[v.s||''],v.n||''])});
 const csv='\\ufeff'+rows.map(r=>r.map(x=>'"'+String(x).replace(/"/g,'""')+'"').join(',')).join('\\r\\n');
 const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv'}));a.download='ket-qua-thu-SDOpLat.csv';a.click()};
paint();
</script></main></body></html>'''
open(OUT, 'w', encoding='utf-8').write(page.replace('__DATA__', json.dumps(payload, ensure_ascii=False)))
print('lenh', len(order), 'muc', sum(len(s[1]) for s in sections) + len(order))

#!/usr/bin/env python3
"""Sinh TaoFileCaiDat.html: cong cu cua NGUOI BAN chay trong trinh duyet, chon thu muc goi (co SDOpLat.fas) -> tai file SDOpLat-Setup.lsp.
Khong can Python. Khong gui du lieu di dau (xu ly cuc bo)."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
tpl = open(os.path.join(HERE, 'setup_template.lsp'), encoding='utf-8').read()
page = r'''<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tạo file cài đặt SDOpLat</title>
<style>
:root{--bg:#f7f7f5;--fg:#1d1d1b;--mut:#6b6b66;--card:#fff;--bd:#d9d9d3;--acc:#1f5aa8}
@media(prefers-color-scheme:dark){:root{--bg:#171715;--fg:#ececE8;--mut:#9a9a93;--card:#222220;--bd:#3a3a36;--acc:#8ab6ff}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,sans-serif}main{max-width:680px;margin:0 auto;padding:16px}
h1{font-size:22px}label{display:block;margin:14px 0 4px;font-weight:600}input[type=text]{width:100%;font:inherit;padding:8px;border:1px solid var(--bd);border-radius:6px;background:var(--card);color:var(--fg)}
button{font:inherit;padding:9px 16px;border:1px solid var(--acc);background:var(--acc);color:#fff;border-radius:6px;cursor:pointer;margin-top:14px}button:disabled{opacity:.5;cursor:not-allowed}
.box{background:var(--card);border:1px solid var(--bd);border-radius:8px;padding:12px;margin-top:14px}.mut{color:var(--mut);font-size:14px}.warn{color:#b3261e}.ok{color:#2b7a57}
</style></head><body><main>
<h1>Tạo file cài đặt SDOpLat</h1>
<p class="mut">Công cụ của <b>người bán</b>. Chọn thư mục gói đã có <code>SDOpLat.fas</code>; công cụ đóng gói tất cả thành <b>một file</b> <code>SDOpLat-Setup.lsp</code> để gửi khách. Xử lý ngay trong trình duyệt, không gửi dữ liệu đi đâu.</p>
<label for="dir">Thư mục gói (chứa SDOpLat.fas, SDOpLat.mnu, Maps…)</label><input id="dir" type="file" webkitdirectory directory multiple>
<label for="ver">Số phiên bản</label><input id="ver" type="text" value="1.0.0">
<label for="main">File chính (đã biên dịch)</label><input id="main" type="text" value="SDOpLat.fas">
<button id="go" disabled>Tạo SDOpLat-Setup.lsp</button>
<div class="box" id="out">Chưa chọn thư mục.</div>
<script>
const TPL=__TPL__;
const $=id=>document.getElementById(id);let files=[];
$('dir').onchange=e=>{files=[...e.target.files];$('go').disabled=!files.length;$('out').textContent=files.length?`Đã chọn ${files.length} file.`:'Chưa chọn thư mục.'};
function b64(buf){const u=new Uint8Array(buf);let s='';for(let i=0;i<u.length;i+=0x8000)s+=String.fromCharCode.apply(null,u.subarray(i,i+0x8000));return btoa(s)}
$('go').onclick=async()=>{const out=$('out'),ver=$('ver').value.trim()||'1.0.0',main=$('main').value.trim()||'SDOpLat.fas';out.className='box';
 const list=files.map(f=>({rel:f.webkitRelativePath.split('/').slice(1).join('\\'),f})).filter(x=>x.rel);
 if(!list.some(x=>x.rel===main)){out.className='box warn';out.textContent='Không thấy '+main+' trong thư mục. Hãy biên dịch .fas trước và chọn đúng thư mục chứa nó.';return}
 const skip=list.filter(x=>x.rel.toLowerCase().endsWith('.lsp'));const use=list.filter(x=>!x.rel.toLowerCase().endsWith('.lsp'));
 use.sort((a,b)=>(a.rel===main?0:1)-(b.rel===main?0:1)||(a.rel<b.rel?-1:a.rel>b.rel?1:0));
 const blocks=[];let total=0;
 for(let i=0;i<use.length;i++){out.textContent=`Đang xử lý ${i+1}/${use.length}: ${use[i].rel}`;const buf=await use[i].f.arrayBuffer();total+=buf.byteLength;const s=b64(buf);const ch=[];for(let k=0;k<s.length;k+=400)ch.push(s.slice(k,k+400));
  const esc=use[i].rel.replace(/\\/g,'\\\\');blocks.push(`(sdsu:f "${esc}" ${buf.byteLength})`+(ch.length?'\n'+ch.map(c=>`(sdsu:c "${c}")`).join('\n'):'')+'\n(sdsu:e)')}
 const text=TPL.split('@@VER@@').join(ver).split('@@MAIN@@').join(main).replace('@@FILES@@',()=>blocks.join('\n')).replace(/\r?\n/g,'\r\n');
 const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([text],{type:'text/plain'}));a.download='SDOpLat-Setup.lsp';a.click();
 out.className='box ok';out.innerHTML=`Xong: đóng gói ${use.length} file (${(total/1048576).toFixed(1)} MB) → SDOpLat-Setup.lsp (${(text.length/1048576).toFixed(1)} MB).`+(skip.length?`<br><span class="warn">Đã bỏ qua ${skip.length} file .lsp (nguồn) để không lộ mã: ${skip.map(x=>x.rel).join(', ')}</span>`:'')}
</script></main></body></html>'''
open(os.path.join(HERE, 'TaoFileCaiDat.html'), 'w', encoding='utf-8').write(page.replace('__TPL__', json.dumps(tpl, ensure_ascii=False)))
print('da tao TaoFileCaiDat.html')

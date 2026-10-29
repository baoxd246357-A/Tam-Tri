#!/usr/bin/env python3
"""Dong goi 1 thu muc ban hang (da co SDOpLat.fas) thanh 1 file cai dat tu dong SDOpLat-Setup.lsp.

  python3 -I build_setup.py <thu-muc-goi> <SDOpLat-Setup.lsp> [--ver=1.0.0] [--main=SDOpLat.fas]
Khach keo tha file .lsp vao AutoCAD: tu giai ma ra %APPDATA%\\Autodesk\\ApplicationPlugins\\SDOpLat.bundle\\Contents,
sinh PackageContents.xml (tu nap khi khoi dong), nap lenh va cai menu.
"""
import sys, os, base64, re
args = [a for a in sys.argv[1:] if not a.startswith('--')]
PKG, OUT = args[:2]
opt = lambda k, d: next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--' + k + '=')), d)
VER, MAIN = opt('ver', '1.0.0'), opt('main', 'SDOpLat.fas')
if not os.path.exists(os.path.join(PKG, MAIN)):
    sys.exit('Khong thay %s trong %s (hay bien dich .fas truoc).' % (MAIN, PKG))
BAD_EXT = {'.lsp'}   # khong dua nguon .lsp vao goi cai dat
files = []
for root, _, names in os.walk(PKG):
    for n in sorted(names):
        full = os.path.join(root, n); rel = os.path.relpath(full, PKG).replace('/', '\\')
        if os.path.splitext(n)[1].lower() in BAD_EXT:
            print('Bo qua (khong dong goi nguon):', rel); continue
        files.append((rel, full))
files.sort(key=lambda x: (x[0] != MAIN, x[0]))
blocks = []
total = 0
for rel, full in files:
    data = open(full, 'rb').read(); total += len(data)
    b64 = base64.b64encode(data).decode('ascii')
    chunks = [b64[i:i + 3000] for i in range(0, len(b64), 3000)] or ['']
    esc = rel.replace('\\', '\\\\')
    blocks.append('(sdsu:put "%s" %d (list\n%s))' % (esc, len(data), '\n'.join('  "%s"' % c for c in chunks)))
tpl = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'setup_template.lsp'), encoding='utf-8').read()
out = tpl.replace('@@VER@@', VER).replace('@@MAIN@@', MAIN).replace('@@FILES@@', '\n'.join(blocks))
assert out.isascii()
open(OUT, 'w', encoding='ascii', newline='\r\n').write(out)
print('dong goi', len(files), 'file,', total, 'byte ->', OUT, os.path.getsize(OUT), 'byte')

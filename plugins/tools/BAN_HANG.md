# Quy trình bán SDOpLat có khóa kích hoạt theo máy

## Nguyên tắc
- Khách chạy `SDKICHHOAT` → thấy **Mã máy** (XXXX-XXXX-XXXX) → gửi cho bạn.
- Bạn tạo **Mã kích hoạt** bằng `tools/sdoplat_keygen.py` trên máy bạn → gửi lại → khách nhập một lần.
- Mã chỉ đúng với Mã máy đã gửi. Dùng sang máy khác thì báo sai. Mã được lưu trong registry của khách (HKCU\Software\SDOpLat) và kiểm tra lại mỗi phiên.
- Bạn có nhật ký `licenses.csv` (ngày, khách, mã máy, mã) để biết đã cấp cho ai; keygen cảnh báo nếu một Mã máy xin lại.

## Làm bản bán (làm trên máy bạn, KHÔNG commit)
```bash
export SDOPLAT_SECRET='chuoi-bi-mat-dai-hon-16-ky-tu'   # giữ kín, mất là không cấp mã lại được cho khách cũ
python3 -I plugins/tools/build_oplat.py plugins/ShopDrawing /duong/dan/ngoai/repo/SDOpLat-ban-hang --licensed
```
Gói trong repo (`plugins/SDOpLat`) là bản **không khóa** để phát triển/thử. Không bán bản đó.

## Cấp mã cho khách
```bash
export SDOPLAT_SECRET='cung-chuoi-bi-mat-o-tren'
python3 -I plugins/tools/sdoplat_keygen.py ABCD-EFGH-JKLM "Tên khách"
```
Đổi secret thì mã đã cấp cho khách cũ không còn đúng với bản build mới.

## Kiểm tra thuật toán
- `python3 -I plugins/tools/lisp_emu.py` — mô phỏng đoạn LISP của khóa, đối chiếu với Python trên 300 chuỗi ngẫu nhiên, báo nếu số nguyên tràn 32 bit.
- Trong AutoCAD, gõ `(sd:lic-selftest)` trên bản có khóa: phải in "OK". Bước này **bạn cần chạy một lần trên AutoCAD thật** (đọc registry MachineGuid, ghi registry, `getstring` chưa được thử).

## Giới hạn cần biết (nói thật)
- File `.lsp` là văn bản. Ai biết LISP có thể xóa đoạn kiểm tra hoặc đọc secret rồi tự tạo mã. Khóa này ngăn dùng chung thông thường, không ngăn người cố tình bẻ.
- Muốn khó bẻ hơn: biên dịch sang `.vlx` — AutoCAD, lệnh `VLIDE` → Tools → Make Application → Application Wizard, chọn `SDOpLat.lsp`, đóng gói thành `SDOpLat.vlx`; khi bán chỉ gửi `.vlx` (APPLOAD nạp `.vlx` bình thường). Tôi không biên dịch được ở đây. `.vlx` vẫn có thể bị dịch ngược nhưng khó hơn nhiều.
- "Dùng một lần" ở đây là *một mã gắn một máy*. Chưa có máy chủ nên chưa chặn được việc khách xin mã nhiều lần cho nhiều máy (nhật ký csv chỉ để bạn theo dõi). Muốn khóa thật sự chặt thì cần dịch vụ kích hoạt online.
- Cài lại Windows có thể đổi MachineGuid → Mã máy mới → bạn cần quyết chính sách cấp lại.
- Máy không đọc được registry MachineGuid sẽ dùng tên máy + số serial ổ C: (kém ổn định hơn).

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

## Dùng thử N lần rồi mới kích hoạt
Build có khóa mặc định cho **10 lần chạy lệnh khóa** trước khi yêu cầu kích hoạt; đổi bằng `--trial=N`:
```bash
SDOPLAT_SECRET='...' python3 -I plugins/tools/build_oplat.py plugins/ShopDrawing <thu-muc-ngoai-repo> --licensed --trial=10
```
- Mỗi lần chạy một lệnh bị khóa (đếm cả lệnh con do `SDQUYTRINH` gọi) tính là 1 lần; mỗi lần hiện "còn x / N lần".
- Bộ đếm lưu 2 nơi: registry `HKCU\Software\SDOpLat\Uses` và file `%APPDATA%\SDOpLat.dat`, kèm mã kiểm tra gắn với máy; sửa tay hoặc chép từ máy khác sẽ bị coi là **hết lượt**.
- Chống lách yếu: xóa cả hai nơi thì bộ đếm về 0. Đây là giới hạn của khóa offline.
- Đếm theo *lần chạy lệnh*, không theo ngày. Muốn dùng thử theo ngày cần viết thêm.

## Biên dịch thành .fas (bạn làm trong AutoCAD)
Tôi không biên dịch được ngoài AutoCAD. Cách làm:
1. Build bản bán với `--licensed --fas` (file nạp và `.mnl` sẽ trỏ tới `SDOpLat.fas`):
   `... build_oplat.py plugins/ShopDrawing <thu-muc-ban-hang> --licensed --fas`
2. Trong AutoCAD: `APPLOAD` → `plugins/tools/compile_to_fas.lsp` → gõ `BIENDICH` → chọn `<thu-muc-ban-hang>\SDOpLat.lsp`. Sinh ra `SDOpLat.fas`.
3. **Xóa `SDOpLat.lsp`** khỏi thư mục bán, kiểm tra `APPLOAD` → `SDOpLat.fas` chạy bình thường, `SDKICHHOAT` hoạt động.
4. Muốn `.vlx` thay vì `.fas`: `VLIDE` → Tools → Make Application → Application Wizard, chọn `SDOpLat.fas`.
Nếu `BIENDICH` báo lỗi, dùng `VLIDE` biên dịch thủ công, hoặc gửi lại thông báo lỗi cho tôi.

## Lệnh tích hợp từ module ngoài
`SDDIMGD` (lệnh tắt `DGD`) lấy từ DimGiaoDiem v2 theo yêu cầu khách hàng: mã nằm ở `plugins/tools/modules/dgd.lsp`, `build_oplat.py` tự chèn vào mọi bản build (bị khóa như các lệnh khác khi build `--licensed`). Logic giữ nguyên bản gốc; chỉ đổi tên lệnh, bỏ dấu trong dòng nhắc và thêm tiền tố `[SD]`. Mã do chủ sở hữu sản phẩm tự phát triển (có hỗ trợ công cụ AI), nên không cần xin phép bên thứ ba.

## Bài học: kiểm tra tên hàm AutoLISP
`lisp_emu.py` có thêm bước kiểm tra mọi hàm trong `license_module.lsp` có phải hàm AutoLISP thật không (bắt được lỗi dùng `logxor` — AutoLISP không có hàm này, phải dùng `(logior)` trừ `(logand)`). Chạy lại sau mỗi lần sửa module khóa.

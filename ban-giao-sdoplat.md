# Bàn giao: Op Lat Tools (SDOpLat) / ShopDrawing
Ngày: 2026-10-31    Người hoặc agent giao: Claude (phiên claude.ai/code session_01NSXUAemyeNgJj1MDLag75D)    Người hoặc agent nhận: phiên Claude Code mới

## 1. Mục tiêu
Chủ sở hữu plugin AutoCAD AutoLISP "ShopDrawing" (repo `baoxd246357-A/Tam-Tri`, nhánh `claude/nice-bell-8hgv63`, PR #8) bán một gói ốp lát riêng tên "Op Lat Tools" (SDOpLat): khóa bản quyền theo máy, 10 lần dùng thử, file `.fas` biên dịch, menu cơ bản 9 lệnh, tích hợp lệnh dim DGD/DPK, hướng dẫn khách, trợ lý offline, bộ cài một file (`SDOpLat-Setup.lsp`). Giao tiếp bằng tiếng Việt. Bản ShopDrawing hiện là v2.59.0. Cần: các lệnh chạy ổn trên AutoCAD thật (2027), dim ra đẹp như dim ShopDrawing, clip quảng bá Facebook.

## 2. Trạng thái hiện tại
### Đã xong (mỗi dòng kèm bằng chứng)
- [x] Bộ cài certutil (ghi file `.b64` rồi `certutil -decode`) chạy thật trên máy người dùng, ghi 142 file (bằng chứng: log người dùng "Da ghi 142 file ... XONG"; `!*SD:VER*` = "1.0.0").
- [x] Sửa lỗi `no function definition: SD:DLG-OK` trong SDGACH: bộ dựng bỏ sót hàm chỉ được gọi trong chuỗi `action_tile` (bằng chứng: commit "build_oplat: giu ham chi duoc goi trong chuoi", dựng lại gói có `sd:dlg-ok`; quét không còn hàm thiếu).
- [x] DGD/DPK gộp vào bản 2.59 từ `DimGiaoDiem_v2.lsp`/`DimPolyline_v2.lsp`; bản gốc có dấu giữ ở `plugins/ShopDrawing/goc/` (bằng chứng: commit "DGD/DPK: kieu dim ShopDrawing ...", thư mục `goc/`).
- [x] SDGACH đánh dấu viên bắt đầu (layer `SD-DIEMBD`, khung + X + vòng tròn + chữ "BAT DAU") cho lát Thẳng/So le (bằng chứng: commit "SDGACH: danh dau vien bat dau"; gói dựng có chuỗi "BAT DAU").
- [x] Kịch bản 6 clip Facebook (bằng chứng: `marketing/kich-ban-clip-facebook.md`, đã push; trình kiểm lỗi marketing 0 lỗi).

### Đang dở
- [ ] Dim DGD chữ đè nhau ở đoạn ngắn: đã làm thu nhỏ chữ theo mức 0,75/0,6/0,45 và đặt chữ cạnh đường dim so le 2 mức bằng `DIMTEDIT` (v15/v16); người dùng nói "mẫu chữ dim nhảy ra bên cạnh chưa theo mong muốn" nhưng chưa nói rõ mong muốn.
- [ ] DPK thiếu cạnh (cạnh xiên/cung): đã thêm kiểm tra từng cạnh, fallback dim dây cung, in danh sách cạnh không dim được; chưa có phản hồi thử lại của người dùng.
- [ ] SDANHDA: người dùng muốn thấy viên bắt đầu và chiều cạnh dài của map đá để dễ căn chỉnh; chưa làm, chờ trả lời (mục 8).

### Chưa bắt đầu
- [ ] Biên dịch `.fas` bản v16, dựng lại bộ cài, người dùng chạy thử toàn bộ.
- [ ] Điền thông tin thương mại (Zalo, giá), bí mật riêng của người bán, đánh giá pháp lý, tùy chọn bảo vệ `.vlx`.

## 3. Quyết định đã chốt
- [U] Gói thương mại tách riêng, khóa theo máy, 10 lần dùng thử, `.fas`, menu cơ bản.
- [U] Gộp DGD + DPK vào 2.59, giữ bản gốc để truy hồi.
- [U] Nhúng DIMATFIT 1, DIMTIX 0, DIMTMOVE 0 vào DGD (tùy chọn "chữ dim cạnh đường dim", mặc định BẬT, gõ `C`).
- [U] Dim DGD/DPK phải giống dim ShopDrawing (xanh, tick kiến trúc, chữ nhỏ ở đoạn ngắn).
- [M] Mặc định bật "kiểu dim ShopDrawing" (`K`): dimstyle `SD-1-<tỷ lệ>`, layer `SD-KICHTHUOC`, tỷ lệ từ `*SD:SCALE*` (mặc định 100, đặt bằng `SDSET`).
- [M] Dựng gói bằng closure hàm từ lệnh gốc; module DGD/DPK dán vào `ShopDrawing.lsp` từ `tools/modules/`.

## 4. Ràng buộc và quy tắc người dùng đã nêu
- Giao tiếp tiếng Việt. Máy người dùng là Windows, AutoCAD 2027; người dùng dán log từ dòng lệnh AutoCAD.
- Đơn vị mm. Dim tổng phải ra phía ngoài, chữ đoạn ngắn nhỏ, không đè nhau.
- Chỉ commit/push lên nhánh `claude/nice-bell-8hgv63`; không tạo PR mới trừ khi được yêu cầu (PR #8 đã có).
- Mọi thay đổi code chưa được thử trên AutoCAD thật phải nói rõ là chưa thử.
- Không đưa bí mật bản quyền vào repo.

## 5. Giả định chưa kiểm chứng
- [GIẢ ĐỊNH] Toàn bộ sửa lỗi sau bản V5 (IMAGECLIP, vùng có cung, DGD/DPK 2.59, chữ dim, đánh dấu viên bắt đầu) chạy đúng trên AutoCAD thật; mới kiểm tĩnh (ngoặc cân, dựng được, hàm có mặt).
- [GIẢ ĐỊNH] Chữ dim dồn một đầu ở ảnh cũ do tỷ lệ bản vẽ (`*SD:SCALE*` mặc định 100) lệch; chưa xác nhận.
- [GIẢ ĐỊNH] `DIMTEDIT` qua `command` đặt chữ đúng vị trí; chưa thử.
- [GIẢ ĐỊNH] Bản ShopDrawing v2.0.0 xuất hiện lúc trước không quay lại sau khi khởi động lại AutoCAD; chưa kiểm.
- [GIẢ ĐỊNH] Lỗi cài `Stream.Open` lần gần nhất do người dùng dùng file `TaoFileCaiDat.html` cũ; chưa xác nhận.

## 6. Tệp và vị trí
| Tệp | Vị trí | Dùng để | Trạng thái |
|---|---|---|---|
| ShopDrawing.lsp | plugins/ShopDrawing/ShopDrawing.lsp | nguồn chính v2.59.0 (latin-1, lẫn CRLF/LF, sửa theo byte) | mới nhất |
| dgd.lsp, dpk.lsp | plugins/tools/modules/ | nguồn module DGD/DPK (chép vào ShopDrawing.lsp bằng script thay thế) | mới nhất |
| build_oplat.py | plugins/tools/build_oplat.py | dựng gói SDOpLat | mới nhất (có sửa chuỗi) |
| setup_template.lsp, build_setup.py, TaoFileCaiDat.html | plugins/tools/ | bộ cài certutil | mới nhất |
| goc/ | plugins/ShopDrawing/goc/ | bản gốc DGD/DPK có dấu | giữ để truy hồi |
| ShopDrawing-v2_59_0.zip | plugins/ | gói ShopDrawing | cập nhật mỗi lần |
| kich-ban-clip-facebook.md | marketing/ | kịch bản clip | nháp chờ duyệt |
| Gói khách v16 | scratchpad/rel19/ (SDOpLat-v1.0.0-thuong-mai-DGD-v16-CHUA-BIEN-DICH.zip, TaoFileCaiDat.html) | gói chưa biên dịch gửi người dùng | mới nhất; scratchpad là `/tmp/claude-0/-home-user-Tam-Tri/0f150ad6-bf5b-5d92-b340-c24da1c840ea/scratchpad`, mất khi container hết hạn |
| secret.txt | scratchpad/ | bí mật dựng bản có khóa (biến `SDOPLAT_SECRET`) | KHÔNG đưa vào repo; giá trị [ĐÃ ẨN] |

## 7. Việc đã chạy và kết quả
- Dựng gói: `SDOPLAT_SECRET=$(cat secret.txt) python3 -I tools/build_oplat.py ShopDrawing <thư mục ra> --licensed --trial=10 --menu=basic`. Kết quả: 55 lệnh, hàm cần có đều có mặt.
- Lỗi gặp và cách xử lý: `Stream.Open` (đổi sang certutil); `write-char` làm hỏng nhị phân (bỏ); chia 0 ở SDRAITAM (vùng có cung đổi sang polyline có bulge); IMAGECLIP (xóa clip cũ `_D` trước `_N`); chữ dim đè nhau (thu nhỏ + `DIMTEDIT`); thiếu `sd:dlg-ok` (sửa bộ dựng).
- Chưa chạy: bất kỳ lệnh nào trên AutoCAD thật ở bản v13–v16.
- Lưu ý: khi kiểm cân bằng ngoặc bằng script, dấu `;` trong chuỗi (ví dụ trong `princ`) làm kết quả sai; so sánh với bản git trước đó thay vì tin số tuyệt đối.

## 8. Vấn đề mở và câu hỏi chưa trả lời
- Chữ dim đoạn ngắn: "2" nên đặt phía nào so với đường dim và cách bao xa? Người dùng quyết. Nên có DXF hoặc ảnh rõ (file `.dwg` mẫu `mau_dim_DGD_DPK.dwg` không đọc được ở môi trường này, không có công cụ DWG).
- SDANHDA: dấu hiệu mong muốn là mũi tên chiều vân, ô tô màu viên đầu, hay chữ "cạnh dài map"? Đảo chiều bằng tùy chọn khi chạy lệnh hay sửa sau? Người dùng quyết.
- DPK còn thiếu cạnh nào, nguyên nhân gốc? Cần dòng "Canh KHONG dim duoc ..." từ người dùng hoặc DWG nhỏ.
- Lỗi "Vien (600 x 1200) lon hon tam da" (khung vân lệch 90°) còn nghi ngờ; mới chỉ thêm gợi ý.
- Artefact hình nêm ở mép trái ảnh cung chưa xử lý.
- Thông tin thương mại (Zalo, giá, điều kiện) và bí mật riêng của người bán chưa có.

## 9. Rủi ro và điều KHÔNG được làm
- Không đưa `secret.txt`/`SDOPLAT_SECRET` vào repo, log hay tin nhắn.
- Không đăng/gửi thay người dùng (clip, bài Facebook).
- Không chuẩn hóa line ending của `ShopDrawing.lsp` (đã từng hỏng); sửa bằng thay thế theo byte, giữ latin-1.
- Không tạo PR mới; chỉ push lên nhánh `claude/nice-bell-8hgv63`.
- Không khẳng định tính năng chạy được khi chưa thử trên AutoCAD thật.
- Container và scratchpad là tạm: commit/push mọi thứ cần giữ.

## 10. Việc đầu tiên khi tiếp tục
1. Chờ người dùng biên dịch `.fas` từ gói v16 (`compile_to_fas.lsp`), dựng bộ cài bằng `TaoFileCaiDat.html`, chạy thử SDGACH (có viên bắt đầu), DGD, DPK trên bản vẽ mẫu, rồi đọc log/ảnh họ gửi. Trong lúc chờ, trả lời hai câu mở ở mục 8 (vị trí chữ dim, dấu hiệu SDANHDA) rồi mới làm SDANHDA: đọc `sd:anhda` quanh dòng 13000–13066 trong `plugins/ShopDrawing/ShopDrawing.lsp`.

## 11. Đoạn dán để bắt đầu phiên mới
> Đọc tài liệu bàn giao này (`ban-giao-sdoplat.md` ở gốc repo `baoxd246357-A/Tam-Tri`, nhánh `claude/nice-bell-8hgv63`). Nói lại mục tiêu bằng lời của bạn và liệt kê điều chưa rõ (tối đa 3 câu hỏi). Chưa làm gì ngoài đọc tệp cho tới khi tôi xác nhận. Sau đó làm "việc đầu tiên khi tiếp tục".

# ShopDrawing 2.57.0 (từ 2.56.0)

- Tạo polyline: `sd:plinew` và viên gạch (`sd:mk-tile-poly`) loại điểm trùng/hỏng, bỏ hình suy biến thay vì báo lỗi entmake im lặng.
- SDDIEMBD: ô "Khe sát tường" (lùi biên, nở lỗ/cột).
- SDKTLAT: kiểm khe giãn nở chu vi và chỗ chuyển tiếp vật liệu thiếu khe.
- SDVAN: tùy chọn ghép vân đối xứng (bookmatch).
- Dọn: khai báo biến cục bộ bị rò (SDGIACONG, SDTKBLOCK, SDKHAOSAT, SDLOC), giải phóng đối tượng Excel COM, thêm SDMENUXOA vào LenhTat.csv.

Chưa chạy thử trên AutoCAD thật; mới kiểm tra tĩnh (ngoặc cân, không gọi hàm thiếu).

# 2.58.0
- SDDOCDA: giữ đỉnh nút chữ T khi dựng ô (trước đây sd:dm-simp xóa, làm ô kề nhau lệch đỉnh); ô chữ nhật có đỉnh T vẫn nhận là chữ nhật.
- SDHANDINH (HDI): lệnh mới, gộp đỉnh lệch tọa độ và chèn đỉnh nút T cho polyline sẵn có. Mô phỏng trên bản vẽ V6: layer SD-GACH-DOC 127 nút lệch + 778 chỗ T lệch -> 0; SD-GACH-CAT, SD-GACH-ANH, đá xám vân gỗ cũng về 0.

# 2.59.0
- Tích hợp 2 lệnh của khách: DGD (`SDDIMGD`, dim giao điểm) và DPK (`SDDIMPOLY`, dim polyline kín) từ DimGiaoDiem_v2.lsp / DimPolyline_v2.lsp. Bản gốc nguyên văn lưu trong `goc/` để truy hồi; bản tích hợp bỏ dấu tiếng Việt, thêm tiền tố `[SD]`.
- Tùy chọn "chữ dim cạnh đường dim" (gõ `C` ở câu hỏi đầu của DGD / DPK): bật = ép DIMATFIT 1, DIMTIX 0, DIMTMOVE 0 khi dim rồi trả lại; tắt = giữ kiểu dim của bản vẽ. Nhớ theo bản vẽ, mặc định bật.
- Sửa SDRAITAM: mảnh cắt suy biến không còn gây "divide by zero".
- Sửa cắt ảnh tấm đá (IMAGECLIP): xóa đường cắt cũ của ảnh trước khi tạo đường mới, tránh bị hỏi "Delete old boundary?" nuốt sai đối số.
- SDGACH: ô bật/tắt ghi mã lên viên cắt / viên lẻ.
- Quy tắc dim rón áp cho cả dim của ShopDrawing (`sd:dim`, `sd:dimal`: SDDIMVIEN, SDGIACONG...): chữ cạnh đường dim theo cùng tùy chọn chữ dim, dim xong trả lại biến.

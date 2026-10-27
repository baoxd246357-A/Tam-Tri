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

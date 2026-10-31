# Hướng dẫn: quy trình đá lát liên hoàn (SDQUYTRINH)

Gõ **`SDQUYTRINH`** (lệnh tắt `QT` hoặc `QTR`) để mở hộp thoại thông minh, ra lệnh liên hoàn từ chia viên, cắt ảnh tấm đá, hatch vân, đến thống kê và kiểm tra.

## 1. Hộp thoại làm gì

- Dòng đầu cho biết **trạng thái bản vẽ**: số viên, số ảnh tấm đá, số ảnh đã cắt, số hatch vân, và **bước gợi ý** tiếp theo (dòng có `<== goi y` được chọn sẵn).
- Danh sách 10 bước. Chọn một bước rồi bấm **Chạy bước chọn**, hoặc tích nhiều bước (Ctrl / Shift) rồi bấm **Chạy liên hoàn** để chạy lần lượt theo thứ tự trong danh sách.
- Sau mỗi bước hộp thoại tự mở lại và cập nhật trạng thái. Bấm **Đóng** để thoát. **Hướng dẫn** hiện tóm tắt quy trình.
- Nhấn Esc trong một bước chỉ dừng bước đó; chuỗi liên hoàn vẫn đi tiếp bước kế.

| # | Lệnh | Việc |
|---|---|---|
| 1 | `SDRAITAM` | Chia viên / rải tấm theo kho: Panel (tấm tiêu chuẩn + tấm dị hình + gỗ bù) hoặc Đá (viên nguyên + viên cắt mép) |
| 2 | `SDGACH` | Chia viên cho một vùng (thẳng / so le / xương cá / chevron, viên viền) |
| 3 | `SDDOCDA` | Đọc mặt bằng ốp lát từ nét rời: dựng ô kín, bảng CSV / JSON để soát, mã vật liệu từ chữ / hatch, khoét lỗ / cột, vẽ polyline kín (không phải vẽ lại polyline) |
| 4 | `SDANHDA` | Cắt ảnh tấm đá thô (IMAGECLIP) vào các viên, xếp cắt xuyên, đánh số thứ tự đường cắt, khoanh phế liệu |
| 5 | `SDVANDA` | Hatch vân đá từ file `.pat` (khi chưa có ảnh thật) |
| 6 | `SDGACHTK` | Thống kê viên + dự trù đặt hàng |
| 7 | `SDDATHO` | Sơ đồ cắt viên từ đá thô (kho tấm, hao phí) |
| 8 | `SDGIACONG` | Bản vẽ gia công từng mã viên gửi xưởng |
| 9 | `SDTKDA` | Quét polyline viên đá cắt → bảng thống kê theo nhóm kích thước (SL, diện tích, cạnh mài) + chi tiết từng viên (mã T.., tấm đá số) + CSV |
| 10 | `SDKTLAT` | Kiểm tra bản vẽ lát (chỉ đọc): viên cắt hẹp / nhỏ, ron không đều, ô thiếu mã vật liệu |

## 2. Quy trình mẫu: lát đá có vân thật

1. **Chuẩn bị:** vẽ các polyline kín là vùng lát (phòng, viền). Chèn ảnh tấm đá thô bằng `IMAGEATTACH` đúng tỷ lệ thật (VD 2450 × 1170, góc xoay 0).
2. Mở `SDQUYTRINH`, chọn bước **1 `SDRAITAM`** (chế độ Đá) hoặc **2 `SDGACH`** để chia viên. Nhập kích thước viên, mạch, kiểu lát.
   - Với `SDGACH` có thể tích **Cắt ảnh tấm đá thật vào các viên**: chia xong lệnh tự mở hộp thoại khai báo của `SDANHDA` (bước 4) và cắt ảnh cho tất cả viên vừa chia, bỏ qua việc quét chọn lại.
3. Chọn bước **4 `SDANHDA`**:
   - tích *Lấy kích thước tấm từ ảnh* (mặc định bật) hoặc nhập dài × rộng thật;
   - xén biên và bề rộng lưỡi cắt (tấm vừa khít, ví dụ 3 × 390 = 1170, thì đặt cả hai bằng 0);
   - **Chiều vân:** `Toiuu` (tự xoay 90°), `Doc` (vân theo cạnh dài viên), `Ngang` (vuông góc cạnh dài);
   - **Cách xếp:** `Toiuu` = cắt xuyên cho máy cắt đá cầu, viên nhỏ lấp vào phế liệu hình L, ít tấm nhất; `Thutu` = theo thứ tự lát (vân gần nhau); `Duongviem` = chạy dọc đường viền (vân chạy liên tục quanh viền, dùng cho viền rộng 390…);
   - chọn ảnh (nhiều ảnh cùng kích thước = nhiều tấm khác vân), **quét chọn** vùng nhiều polyline viên đá, chọn điểm đặt sơ đồ cắt.
4. Xem sơ đồ cắt (layer `SD-DUONG-CAT`): **số thứ tự đường cắt** — đường tách miếng lớn đánh số trước, viên nhỏ cắt sau cùng để không xô lệch; các ô phế liệu còn dùng được ghi `VUN dài x rộng`.
5. Chạy **6 `SDGACHTK`** (thống kê, đặt hàng) và **8 `SDGIACONG`** (bản vẽ gia công). Chạy **9 `SDTKDA`**: quét các polyline viên đã cắt ra bảng thống kê (nhóm kích thước, số lượng, diện tích, cạnh mài; chi tiết từng viên kèm tấm đá số). Cuối cùng **10 `SDKTLAT`** để rà lỗi trước khi phát hành.

## 3. Chạy liên hoàn: ví dụ

Chọn các bước **1, 4, 6** rồi **Chạy liên hoàn**: `SDRAITAM` → `SDANHDA` → `SDGACHTK` chạy lần lượt, mỗi lệnh hiện hộp thoại riêng để nhập thông số.

## 4. Lưu ý

- `SDANHDA` cần ảnh góc xoay 0 và đúng tỷ lệ tấm thật; viên không chữ nhật được xếp theo khung chữ nhật quanh nó, ảnh cắt theo đúng biên viên.
- Chiều vân chỉ xoay theo bội 90° so với cạnh dài viên. `Ngang` với viên dài hơn cạnh tấm thì báo không cắt được.
- Các file vân `.pat` (Platinus, DaSocDua, ViaLactea, DaVanGoXam, DaVanGoCo) nằm cùng thư mục cài đặt; `SDMENU` thêm thư mục này vào Support Path.
- Kết quả đã kiểm tra bằng mô phỏng; nếu lệnh báo lỗi trên máy bạn, chụp các dòng lệnh gửi cho người hỗ trợ kèm tên lệnh và số phiên bản (`SDMENU` in ra số phiên bản).

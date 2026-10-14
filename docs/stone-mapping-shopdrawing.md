# Thiết kế: Map đá & Shopdrawing

Module mở rộng cho AI Site Control: quản lý từng tấm đá theo bản vẽ shopdrawing, theo dõi vòng đời (sản xuất → giao → lắp) và đối chiếu với ảnh hiện trường do AI phân tích.

Trạng thái: **thiết kế, chưa code**. Chờ file bản vẽ thực tế để chốt định dạng nhập liệu.

## 1. Mục tiêu

1. Mỗi tấm đá có **mã duy nhất** gắn với vị trí trên bản vẽ.
2. Biết tấm nào đang ở trạng thái nào (chưa SX / đã cắt / đã giao / đã lắp / lỗi).
3. Từ ảnh hiện trường, AI gợi ý tấm đá/khu vực nào đang thi công và đối chiếu với shopdrawing.
4. Xuất bảng thống kê (số lượng, m², theo loại đá/khu vực) và bản vẽ tô màu tiến độ.

Ngoài phạm vi giai đoạn 1: tự vẽ shopdrawing, tối ưu cắt (nesting), đọc DWG trực tiếp.

## 2. Khái niệm

| Thuật ngữ | Ý nghĩa |
|---|---|
| Shopdrawing (SD) | Bản vẽ triển khai ốp/lát đá theo từng mặt đứng, sàn, khu vực. Mỗi file có mã + revision. |
| Map đá | Sơ đồ chia tấm: mỗi ô là một tấm có mã, kích thước, loại đá, hướng vân. |
| Tấm (Slab/Panel) | Đơn vị quản lý nhỏ nhất. |
| Revision | SD thay đổi → tấm cũ bị thay thế, giữ lịch sử. |

Quy ước mã tấm đề xuất: `{LOẠI ĐÁ}-{KHU VỰC}-{TẦNG}-{SD}-{STT}`, ví dụ `GR01-LOBBY-L1-SD03-024`. Chốt lại theo quy ước đang dùng ở công trình.

## 3. Mô hình dữ liệu (SQLAlchemy, cùng style `app/main.py`)

```
StoneType      id, code, name, supplier, thickness_mm, finish, note
Drawing        id, project_id, code, title, floor, zone, revision, file_path,
               page, scale, is_current, uploaded_at
Panel          id, drawing_id, stone_type_id, code (unique), width_mm, height_mm,
               area_m2, grain_dir, x, y, w, h        # x,y,w,h = bbox chuẩn hoá 0..1 trên ảnh bản vẽ
               status, replaced_by_id, note
PanelEvent     id, panel_id, status, at, by, photo_id (nullable), note   # lịch sử trạng thái
```

`status`: `PLANNED → CUT → DELIVERED → INSTALLED`, nhánh phụ `DEFECT`, `REPLACED`.

Liên kết với phần hiện có: `PanelEvent.photo_id` trỏ tới `Photo.id`; `SiteVisit.floor/zone` dùng để lọc Drawing/Panel liên quan khi AI phân tích ảnh.

## 4. Luồng chính

1. **Nhập bản vẽ**: upload PDF/ảnh → server render từng trang thành PNG (PyMuPDF) → lưu `Drawing`.
2. **Tạo map tấm** (3 cách, ưu tiên theo thứ tự):
   - **a. Import bảng** (CSV/Excel: mã, W, H, loại, vị trí) – chính xác nhất, nếu có bảng cắt đá từ nhà cung cấp.
   - **b. AI đọc bản vẽ**: Gemini vision trích mã tấm + kích thước từ nhãn trên bản vẽ, trả JSON; người dùng duyệt.
   - **c. Vẽ tay trên UI**: kéo ô chữ nhật trên ảnh bản vẽ, nhập mã.
3. **Cập nhật trạng thái**: chạm vào ô trên bản vẽ (mobile) → chọn trạng thái, đính ảnh. Hoặc quét nhiều tấm cùng lúc theo lô giao hàng.
4. **Đối chiếu ảnh hiện trường**: khi phân tích ảnh (`/photos/{id}/analyze`), nếu visit có tầng/khu vực khớp một Drawing, thêm vào prompt danh sách mã tấm của khu đó; AI trả thêm `matched_panels` + `confidence`. Kết quả chỉ là **gợi ý**, kỹ sư xác nhận mới ghi `PanelEvent`.
5. **Báo cáo**: bản vẽ tô màu theo trạng thái + bảng thống kê (xuất PDF/Excel), gắn vào báo cáo ngày hiện có.

## 5. API đề xuất

```
POST /api/v1/drawings                       upload SD (file, floor, zone, revision)
GET  /api/v1/drawings/{id}                  thông tin + danh sách tấm
POST /api/v1/drawings/{id}/panels/import    CSV/Excel
POST /api/v1/drawings/{id}/panels/extract   AI đọc bản vẽ → đề xuất (chưa lưu)
POST /api/v1/drawings/{id}/panels           lưu/ sửa tấm (sau khi duyệt)
POST /api/v1/panels/{id}/status             đổi trạng thái (+ photo_id, note)
GET  /api/v1/drawings/{id}/overlay.png      bản vẽ tô màu tiến độ
GET  /api/v1/reports/stone-summary          thống kê theo loại/khu vực/trạng thái
```

## 6. Giao diện (mobile-first)

- Tab mới "Map đá": chọn tầng/khu → hiện bản vẽ, pinch-zoom, các ô tô màu theo trạng thái.
- Chạm ô → bottom sheet: mã, kích thước, loại đá, lịch sử, nút đổi trạng thái, chụp/đính ảnh.
- Bộ lọc: trạng thái, loại đá, lỗi.
- Màn xác nhận kết quả AI (extract / matched_panels) trước khi lưu.

## 7. Rủi ro & lưu ý

- **Độ chính xác AI đọc bản vẽ**: nhãn nhỏ, bản vẽ dày → luôn bắt duyệt; ưu tiên import bảng nếu có.
- **DWG**: giai đoạn 1 yêu cầu xuất PDF. Giai đoạn sau có thể đọc DXF (`ezdxf`) để lấy toạ độ tấm chính xác.
- **Revision**: đổi bản vẽ không được xoá tấm cũ đã `INSTALLED`; chỉ đánh `REPLACED`.
- **Khớp ảnh ↔ tấm bằng AI** không đủ tin cậy để tự cập nhật trạng thái.
- SQLite hiện tại đủ cho vài nghìn tấm; cân nhắc Postgres khi nhiều công trình.

## 8. Lộ trình

1. Model + upload bản vẽ + import CSV + xem map & đổi trạng thái thủ công.
2. Overlay tiến độ + thống kê/xuất báo cáo.
3. AI extract từ bản vẽ + đối chiếu ảnh hiện trường.
4. DXF / tối ưu cắt (tuỳ nhu cầu).

## 9. Cần từ bạn (khi gửi bản vẽ)

- 1–2 file SD mẫu (PDF/ảnh/DWG) và bảng cắt đá nếu có.
- Quy ước mã tấm đang dùng.
- Các trạng thái thực tế cần theo dõi (có thêm "mài/ngâm/đóng kiện"... không).
- Người dùng nào được đổi trạng thái (kỹ sư hiện trường, kho, nhà cung cấp).

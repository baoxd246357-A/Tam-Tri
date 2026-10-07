# AI Site Control v1.1 — OpenAI Vision Trial

Mobile-first prototype for construction site inspection.

## What is new in v1.1

- Upload/capture a site photo from a phone.
- Send the image to an OpenAI vision-capable model through the Responses API.
- AI returns structured JSON:
  - work / công tác
  - location / vị trí
  - progress_percent / tiến độ
  - quality_status / chất lượng
  - issues / lỗi
  - recommended_action / đề xuất xử lý
  - safety_status
  - confidence
- The analysis is stored directly against the inspection photo.
- The UI displays the AI result after analysis.

OpenAI's current model catalog states that the latest OpenAI models support text and image input through the Responses API. The default in this prototype is `gpt-5.6-luna`, selected for cost-sensitive workloads; change `OPENAI_MODEL` if you want another supported model.

## Run

```bash
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

pip install -r requirements.txt

copy .env.example .env   # Windows
# or: cp .env.example .env

# Put your OpenAI API key in .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open on the same computer:
`http://localhost:8000`

Open from a phone on the same Wi-Fi:
`http://YOUR-COMPUTER-LAN-IP:8000`

## API

- `POST /api/v1/visits`
- `POST /api/v1/visits/{visit_id}/photos`
- `POST /api/v1/photos/{photo_id}/analyze`
- `GET /api/v1/photos/{photo_id}`
- `POST /api/v1/reports/daily`
- `GET /health`

## Important

This is a field-trial prototype, not a production safety/quality certification system. AI observations must be reviewed by the site engineer/inspector before contractual decisions are made.

## Module BOQ — `/boq`

Quy trình lập BOQ rút gọn: **Bản vẽ → Shopdrawing → 3D → Thống kê → Bóc khối lượng → Excel**.
Mở `http://localhost:8000/boq` (hoặc nút **📐 BOQ** ở trang hiện trường).

| Bước | Làm gì | Ghi chú |
|---|---|---|
| 1. Bản vẽ | Nhập cấu kiện bằng 1 trong 3 cách: **DXF** (CAD), **mẫu Excel**, hoặc **ảnh/PDF + AI đọc** | Kết quả luôn qua bảng *Kiểm tra trước khi thêm* để kỹ sư duyệt |
| 2. Shopdrawing | Sửa/thêm cấu kiện theo tham số; xem bản vẽ chi tiết (mặt cắt, mặt đứng, kích thước mm) | SVG, mở tab mới để in |
| 3. 3D | Mô hình khối 3D, lọc theo tầng, chạm để xem mã cấu kiện | three.js được đóng gói sẵn trong `app/static/vendor` (chạy được không cần CDN) |
| 4. Thống kê | Số lượng theo loại, bê tông/thép/xây theo tầng | |
| 5. Bóc KL | Bảng tổng hợp BOQ + diễn giải từng cấu kiện; nhập đơn giá → thành tiền | |
| 6. Excel | 3 sheet: `TongHop_BOQ`, `ChiTiet`, `ThongKe_CauKien` | Khối lượng là **công thức sống** (`=6*0.3*0.3*3.6`, `=SUMIF(...)`) để kiểm tra/sửa trực tiếp |

**Loại cấu kiện hỗ trợ:** Móng đơn, Cột, Dầm, Sàn, Tường xây, Nền/Lát, Khác (nhập khối lượng trực tiếp).
Mỗi cấu kiện có `Số lượng` và `Bước X/Y` — một dòng "C1 × 6, bước 6 m" thay cho 6 dòng.

**Quy ước tính (mặc định, sửa được theo tham số):**
- Đơn vị mét. Cột: nhập chiều cao thông thủy tới đáy dầm/sàn. Dầm: bê tông = b×(h − dày sàn)×L (phần giao với sàn tính vào sàn).
- Ván khuôn dầm = (b + 2(h − t))×L; cột = 2(b+h)×H; móng = 2(L+B)×H; sàn = L×B.
- Móng: đào đất (L+2a)(B+2a)×sâu, bê tông lót (L+0.2)(B+0.2)×dày.
- Tường: xây = (L×H − lỗ cửa)×dày; trát/sơn = (L×H − lỗ cửa)×số mặt.
- **Cốt thép là ước tính theo hàm lượng kg/m3** — thay bằng bảng thống kê thép shopdrawing khi có.
- Cột "Mã hiệu" trong Excel để trống cho người lập điền mã định mức.

**DXF:** polyline kín, tên layer chứa `COT/COL`, `DAM/BEAM`, `SAN/SLAB`, `TUONG/WALL`, `MONG/FOOT`, `NEN/FLOOR`
(không phân biệt dấu, ví dụ `KC-DẦM`). Hình bao chữ nhật → kích thước; chiều cao lấy theo ô nhập.
Cấu kiện giống nhau được gộp số lượng; dầm/sàn tự đặt cao độ ngang đỉnh cột.

**AI đọc bản vẽ** dùng `GEMINI_API_KEY` sẵn có. AI chỉ đề xuất — luôn kiểm tra kích thước trước khi thêm.

### Construction Cells (WBS)

Mỗi dòng khối lượng có mã 4 cấp: `01` hạng mục (cell 100) → `01.02` phần việc (300) →
`01.02.03` công tác (600) → `01.02.03.004` cấu kiện/vị trí (1000). Hạng mục nhập ở từng cấu kiện
(trường *Hạng mục*, cột cuối mẫu Excel, hoặc ô Hạng mục khi nhập DXF). API: `GET /api/v1/boq/projects/{id}/wbs`.

### Dự toán / QS (bước 6)

1. **Thư viện định mức & đơn giá** cho từng dự án: tài nguyên (VL / NC / M + đơn giá), định mức
   (hao phí cho 1 đơn vị; đơn vị `100m2`, `100m3`… tự quy đổi), ánh xạ công tác BOQ → mã định mức.
   Nhập/xuất bằng Excel (sheet `TaiNguyen`, `DinhMuc`, `AnhXa`). Có **thư viện MẪU** để chạy thử —
   hao phí và giá chỉ minh hoạ, phải thay bằng định mức áp dụng và giá công bố trước khi phát hành.
2. Công tác chưa có định mức dùng **đơn giá nhập trực tiếp** ở bước 5.
3. Tổng hợp chi phí theo bố cục TT 11/2021: T = VL+NC+M(+K); C, LT, TT = T × %; TL = (T+GT) × %;
   G; GTGT; Gxd; dự phòng. Tỷ lệ mặc định chỉ để khởi tạo — sửa theo loại công trình.
4. **Excel dự toán** (`TongHop_ChiPhi`, `DuToan`, `PhanTich_DonGia`, `TongHop_VT`) toàn công thức:
   sửa đơn giá ở `TongHop_VT` hoặc tỷ lệ ở `TongHop_ChiPhi` → cả file tự tính lại.

Chạy test: `pip install -r requirements-dev.txt && python -m pytest -q tests`

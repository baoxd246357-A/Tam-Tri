# QBcons — AI TVGS & triển khai kết cấu

Tên hiển thị lấy từ biến môi trường `APP_NAME` (mặc định `QBcons`, xem `app/branding.py`).

Mobile-first prototype for construction site inspection.

## Kiểm tra hiện trường (`/`)

- Upload/capture a site photo from a phone.
- Send the image (and voice notes) to a Gemini model for analysis.
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

The default model is `gemini-3.7-flash`; set `GEMINI_MODEL` to use another one.

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

# Put your Gemini API key in .env
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

## Triển khai bản vẽ kết cấu (`/ket-cau`)

Nhập cấu kiện → tự động bố trí thép → bản vẽ → thống kê thép.

- **Dầm** nhiều nhịp: thép dưới (1) theo nhịp, thép trên chạy suốt (2), thép mũ gối (3), đai (4) dày L/4 hai đầu nhịp.
- **Cột**: thép dọc có đoạn nối chồng 40d, đai gia cường max(b, h, H/6, 500) ở chân/đỉnh, đai móc khi cạnh > 3 thanh.
- **Sàn** (ô bản kê 4 cạnh): thép lớp dưới theo X/Y neo vào dầm max(10d, bw/2), thép mũ vươn L_ngắn/4 có 2 chân, thép phân bố Ø6a250; bản vẽ mặt bằng + mặt cắt.
- **Móng đơn**: lưới thép đáy 2 phương bẻ móc min(15d, h − 2c), thép chờ cột chân bẻ + nối chồng 40d, đai cổ móng; bê tông lót; bản vẽ mặt cắt + mặt bằng lưới thép.
- Bản vẽ mặt đứng + mặt cắt (SVG trên web), **xuất DXF** mở bằng AutoCAD/ZWCAD (layer BETONG, THEP, THEP_DAI, KICH_THUOC…).
- **Bảng thống kê thép** (số hiệu, hình dạng, Ø, chiều dài, số lượng, khối lượng), tổng hợp theo Ø và nhóm D≤10 / 10<D≤18 / D>18, bê tông m³, bê tông lót m³, cốp pha m² — **xuất CSV** mở bằng Excel.

Quy ước cấu tạo được đơn giản hoá (xem đầu file `app/structural/members.py` và `app/structural/slab_footing.py`); kỹ sư cần kiểm tra lại theo TCVN 5574:2018 và hồ sơ thiết kế.

API: `POST /api/v1/structural/calc`, `/api/v1/structural/export.dxf`, `/api/v1/structural/export.csv` — body `{"project": "...", "members": [{"type": "beam" | "column" | "slab" | "footing", ...}]}`.

Test: `pip install pytest && pytest`

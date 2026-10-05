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

## Kata — Triển khai bản vẽ kết cấu (`/kata`)

Module tham khảo quy trình KataPro: nhập cấu kiện → tự động bố trí thép → bản vẽ → thống kê thép.

- **Dầm** nhiều nhịp: thép dưới (1) theo nhịp, thép trên chạy suốt (2), thép mũ gối (3), đai (4) dày L/4 hai đầu nhịp.
- **Cột**: thép dọc có đoạn nối chồng 40d, đai gia cường max(b, h, H/6, 500) ở chân/đỉnh, đai móc khi cạnh > 3 thanh.
- Bản vẽ mặt đứng + mặt cắt (SVG trên web), **xuất DXF** mở bằng AutoCAD/ZWCAD (layer BETONG, THEP, THEP_DAI, KICH_THUOC…).
- **Bảng thống kê thép** (số hiệu, hình dạng, Ø, chiều dài, số lượng, khối lượng), tổng hợp theo Ø và nhóm D≤10 / 10<D≤18 / D>18, bê tông m³, cốp pha m² — **xuất CSV** mở bằng Excel.

Quy ước cấu tạo được đơn giản hoá (xem đầu file `app/kata/members.py`); kỹ sư cần kiểm tra lại theo TCVN 5574:2018 và hồ sơ thiết kế.

API: `POST /api/v1/kata/calc`, `/api/v1/kata/export.dxf`, `/api/v1/kata/export.csv` — body `{"project": "...", "members": [{"type": "beam", ...}, {"type": "column", ...}]}`.

Test: `pip install pytest && pytest`

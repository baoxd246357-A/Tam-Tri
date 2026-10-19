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

## 📚 Học tập cả nhà (`/hoc`)

Quản lý việc học của gia đình theo khung agent QS (bảng quy tắc `rules.py` + nhật ký + báo cáo), **không dùng AI/API ngoài**.

- Nhiều thành viên, mỗi người một cấp học và mục tiêu.
- **Việc cần làm** có hạn nộp, đánh dấu xong, cảnh báo trễ.
- **Ghi buổi học**: môn, số phút, mức hiểu bài tự đánh giá 1-5.
- **Báo cáo tuần** cho phụ huynh (tính bằng code): tổng giờ, số ngày học, thời gian và mức hiểu theo môn, môn cần chú ý, ngày học quá giới hạn, việc trễ.
- Ngưỡng cảnh báo chỉnh ở `app/hoc/rules.py` (`REVIEWED = False` cho đến khi phụ huynh duyệt).
- API: `/api/v1/hoc/learners`, `/logs`, `/tasks`, `/tasks/{id}/toggle`, `/learners/{id}/tasks`, `/learners/{id}/weekly`.
- Dữ liệu: `data/hoc.db`. Chạy thử: `pip install pytest httpx && pytest tests -q`.

Phần kiểm tra hiện trường (`/`) vẫn dùng Gemini như cũ.

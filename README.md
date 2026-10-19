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

## 📚 Gia sư AI cả nhà (`/hoc`)

Dùng cùng khung với agent QS/TVGS (FastAPI + Gemini + JSON có schema + người duyệt lại), áp dụng cho việc học của gia đình.

| Agent QS | Gia sư gia đình |
|---|---|
| Chụp ảnh hiện trường → JSON công tác/lỗi/đề xuất | Chụp vở/đề → JSON đề bài, gợi ý, bước giải, **lỗi sai**, ôn lại, bài luyện |
| `confidence` thấp → kỹ sư xem lại | `confidence` < 0.7 → **phụ huynh** xem lại, bấm 👍/👎 |
| Bảng quy tắc `rules.py`, `REVIEWED = False` | `app/hoc/rules.py`: cấp học, thang gợi ý, giới hạn giờ học — phụ huynh duyệt |
| Nhật ký/biên bản, báo cáo ngày | Ghi buổi học, báo cáo **tuần** (số liệu tính bằng code, AI chỉ viết nhận xét) |
| Bảng việc (tasks) | Việc cần làm / bài tập có hạn nộp, cảnh báo trễ |

- **Thang gợi ý 4 mức** (hỏi lại đề → hướng làm → làm mẫu bước đầu → giải đầy đủ). Server chỉ trả đáp án ở mức 4; bé bấm "vẫn chưa ra" để lên mức.
- Nhiều thành viên, mỗi người một cấp học (Tiểu học / THCS / THPT / Đại học) → lời giải thích đúng tầm.
- Cảnh báo học quá giờ/ngày, môn hiểu bài thấp (tự đánh giá 1-5).
- API: `/api/v1/hoc/learners`, `/questions`, `/questions/{id}/hint`, `/questions/{id}/review`, `/logs`, `/tasks`, `/learners/{id}/weekly?note=true`.
- Dữ liệu: `data/hoc.db`, ảnh `data/hoc_uploads/`. Trên Render gói free dữ liệu mất khi redeploy — gắn disk nếu muốn giữ lâu dài.
- Chạy thử: `pip install pytest httpx && pytest tests -q` (AI được giả, không cần API key).

AI có thể đọc nhầm đề hoặc giải sai, nhất là môn tính toán — phụ huynh nên xem lại các câu bị gắn cờ.

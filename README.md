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

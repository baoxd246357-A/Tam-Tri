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

## 🤖 Trợ lý học tập cả nhà (`/hoc` + nhóm Zalo)

Trợ lý nghe lệnh tiếng Việt (có dấu hoặc không), dùng chung cho **khung chat trên web** và **nhóm Zalo**. Không dùng AI/API ngoài.

### Đưa vào nhóm Zalo
1. Vào https://bot.zapps.me, tạo bot bằng Zalo cá nhân, lấy **token** (không cần OA doanh nghiệp).
2. Render → Environment → đặt `ZALO_BOT_TOKEN`, redeploy. Bot tự đọc tin bằng getUpdates (không cần webhook). API mặc định `https://bot-api.zaloplatforms.com` (đổi bằng `ZALO_API_BASE`). **Khuyên dùng webhook**: đặt thêm `ZALO_WEBHOOK_SECRET` (chuỗi tự chọn 8-256 ký tự); app tự gọi setWebhook tới `<RENDER_EXTERNAL_URL>/api/v1/hoc/zalo/webhook` khi khởi động và ghi kết quả kiểm tra vào log. Không đặt secret thì dùng getUpdates (Zalo chỉ khuyên cho thử nghiệm). Render gói free ngủ khi rảnh, webhook sẽ đánh thức nó nhưng tin đầu có thể chậm.
3. Thêm bot vào nhóm Zalo của gia đình. Trong nhóm gõ `/menu` (bot chỉ trả lời tin bắt đầu bằng `/` hoặc `bot `; chat riêng thì không cần).
4. Lệnh: `/thêm Bin thcs lớp 7` · `/chọn Bin` · `/việc Bin Toán trang 45 hạn 25/10` · `/ds` · `/xong 3` · `/học Bin Toán 45 hiểu 4` · `/báo cáo`.

Lưu ý: Zalo Bot Platform là dịch vụ bên ngoài, chưa kiểm thử với Zalo thật (chỉ kiểm thử giả lập); nếu bot không nhận tin trong nhóm, kiểm tra quyền bot trong nhóm và log Render. Chỉ chạy 1 worker uvicorn.

### Trang web `/hoc`

Quản lý việc học của gia đình theo khung agent QS (bảng quy tắc `rules.py` + nhật ký + báo cáo), **không dùng AI/API ngoài**.

- Nhiều thành viên, mỗi người một cấp học và mục tiêu.
- **Việc cần làm** có hạn nộp, đánh dấu xong, cảnh báo trễ.
- **Ghi buổi học**: môn, số phút, mức hiểu bài tự đánh giá 1-5.
- **Báo cáo tuần** cho phụ huynh (tính bằng code): tổng giờ, số ngày học, thời gian và mức hiểu theo môn, môn cần chú ý, ngày học quá giới hạn, việc trễ.
- Ngưỡng cảnh báo chỉnh ở `app/hoc/rules.py` (`REVIEWED = False` cho đến khi phụ huynh duyệt).
- API: `/api/v1/hoc/learners`, `/logs`, `/tasks`, `/tasks/{id}/toggle`, `/learners/{id}/tasks`, `/learners/{id}/weekly`.
- Chạy thử: `pip install pytest httpx && pytest tests -q`.

### Vận hành (Render)
| Biến | Tác dụng |
|---|---|
| `DATABASE_URL` | Chuỗi kết nối Postgres (VD Neon/Supabase, dạng `postgresql://user:pass@host/db?sslmode=require`). **Bắt buộc nếu muốn giữ dữ liệu**: không đặt thì dùng SQLite `data/hoc.db`, mất khi Render Free ngủ hoặc deploy lại. Bảng tự tạo ở lần chạy đầu. |
| `HOC_PASSWORD` | Mật khẩu chung cho trang `/hoc` và `/api/v1/hoc/*` (trình duyệt hỏi mật khẩu, tên đăng nhập gõ gì cũng được). Không đặt = ai có link cũng vào được. Webhook Zalo không dùng mật khẩu này (dùng `ZALO_WEBHOOK_SECRET`). |
| `ZALO_BOT_TOKEN`, `ZALO_WEBHOOK_SECRET` | Bot Zalo, xem phần trên. |

Tạo Postgres miễn phí: vào https://neon.tech, tạo project, copy *connection string* rồi dán vào `DATABASE_URL` trên Render (không dán vào chat/repo).
Lệnh trong nhóm Zalo không cần mật khẩu: ai ở trong nhóm đều gõ được, nên chỉ thêm người tin cậy vào nhóm.
Trang `/` (kiểm tra hiện trường) chưa có mật khẩu.

Phần kiểm tra hiện trường (`/`) vẫn dùng Gemini như cũ.


### Nhắc việc quá hạn
Trong nhóm Zalo gõ `/nhắc bật`: mỗi ngày từ 7h sáng (giờ VN) bot gửi danh sách việc trễ hạn, đến hạn hôm nay và ngày mai (chỉ gửi khi có việc). `/nhắc tắt` để tắt, `/nhắc` để xem ngay.
Render Free tự ngủ khi không có người dùng nên cần một dịch vụ ping (UptimeRobot, mỗi 30 phút) gọi
`https://<app>.onrender.com/api/v1/hoc/reminders/run?key=<ZALO_WEBHOOK_SECRET>` — vừa đánh thức app vừa gửi nhắc nếu đến giờ (mỗi chat tối đa 1 lần/ngày).

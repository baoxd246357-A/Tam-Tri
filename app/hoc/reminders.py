"""Nhắc việc quá hạn / đến hạn: mỗi ngày một lần cho các chat đã gõ 'nhắc bật'. Chạy bằng luật, không dùng AI."""
import logging
import os
import threading
from datetime import date, datetime, timedelta

from .db import Learner, ReminderSub, SessionLocal, Task

log = logging.getLogger("tamtri.reminders")
SEND_HOUR_VN = 7          # nhắc từ 7h sáng giờ Việt Nam
MAX_LINES = 12


def vn_now(now: datetime | None = None) -> datetime:
    return now or datetime.utcnow() + timedelta(hours=7)


def build_reminder(db, today: date | None = None) -> str | None:
    """Danh sách việc trễ hạn + đến hạn hôm nay/ngày mai của mọi bé. None nếu không có gì cần nhắc."""
    today = today or vn_now().date()
    t0, t1 = today.isoformat(), (today + timedelta(days=1)).isoformat()
    names = {l.id: l.name for l in db.query(Learner)}
    tasks = db.query(Task).filter(Task.done == 0, Task.due != "", Task.due <= t1).order_by(Task.due).all()
    groups = {"⚠️ Trễ hạn": [], "⏰ Hôm nay": [], "📅 Ngày mai": []}
    for t in tasks:
        key = "⚠️ Trễ hạn" if t.due < t0 else "⏰ Hôm nay" if t.due == t0 else "📅 Ngày mai"
        late = f" (trễ {(today - date.fromisoformat(t.due)).days} ngày)" if t.due < t0 else ""
        groups[key].append(f"• #{t.id} {t.title} — {names.get(t.learner_id, '?')}{late}")
    if not any(groups.values()):
        return None
    out, n = ["🔔 Nhắc việc học"], 0
    for title, rows in groups.items():
        if rows:
            out.append(title)
            for r in rows:
                if n < MAX_LINES:
                    out.append(r)
                n += 1
    if n > MAX_LINES:
        out.append(f"… và {n - MAX_LINES} việc nữa (gõ /việc để xem đủ)")
    out.append("Xong việc nào gõ: /xong <số>")
    return "\n".join(out)


def run_due(db, send, now: datetime | None = None) -> int:
    """Gửi nhắc cho các chat đăng ký, tối đa 1 lần/ngày, từ SEND_HOUR_VN. Trả số tin đã gửi."""
    now = vn_now(now)
    if now.hour < SEND_HOUR_VN:
        return 0
    today = now.date().isoformat()
    subs = [s for s in db.query(ReminderSub) if s.last_sent != today]
    if not subs:
        return 0
    text = build_reminder(db, now.date())
    sent = 0
    for s in subs:
        if text:
            try:
                send(s.chat_id, text)
                sent += 1
            except Exception as e:  # noqa: BLE001
                log.warning("Gửi nhắc lỗi chat=%s: %s", s.chat_id, e)
                continue
        s.last_sent = today          # không có gì để nhắc cũng đánh dấu, tránh kiểm tra lại cả ngày
    db.commit()
    return sent


def tick(bot) -> int:
    with SessionLocal() as db:
        return run_due(db, bot.send)


def loop(bot, stop: threading.Event, every=1800):
    while not stop.wait(every):
        try:
            tick(bot)
        except Exception as e:  # noqa: BLE001
            log.warning("Vòng nhắc việc lỗi: %s", e)


def start_background(bot):
    stop = threading.Event()
    threading.Thread(target=loop, args=(bot, stop), daemon=True, name="hoc-reminders").start()
    return stop

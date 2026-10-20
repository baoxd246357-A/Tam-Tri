"""Bot Zalo (Zalo Bot Platform, docs.zaloplatforms.com) — nhận tin bằng webhook (khuyên dùng) hoặc getUpdates.

Webhook: đặt ZALO_WEBHOOK_SECRET (8-256 ký tự tự chọn) → khi khởi động app tự gọi setWebhook tới
  <RENDER_EXTERNAL_URL hoặc ZALO_WEBHOOK_URL>/api/v1/hoc/zalo/webhook. Không đặt thì dùng getUpdates (chỉ nên để thử nghiệm).
Biến môi trường: ZALO_BOT_TOKEN (bắt buộc), ZALO_API_BASE (tuỳ chọn, mặc định bot-api.zaloplatforms.com). Không có token thì không chạy gì cả.
Trong nhóm bot chỉ trả lời tin bắt đầu bằng '/' hoặc 'bot'; chat riêng trả lời mọi lệnh hợp lệ.
"""
import logging
import os
import threading
import time
import time

import httpx

from . import agent
from .db import SessionLocal

log = logging.getLogger("tamtri.zalo")
DEFAULT_API = "https://bot-api.zaloplatforms.com"


class ZaloBot:
    def __init__(self, token, transport=None, api=None):
        self.token = token
        self.api = (api or os.getenv("ZALO_API_BASE") or DEFAULT_API).rstrip("/")
        self.http = httpx.Client(timeout=45, transport=transport)

    def call(self, method, data):
        r = self.http.post(f"{self.api}/bot{self.token}/{method}", json=data)
        body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        if r.status_code != 200 or body.get("ok") is False:
            raise RuntimeError(f"Zalo {method}: HTTP {r.status_code} {str(body or r.text)[:200]}")
        return body.get("result")

    def send(self, chat_id, text):
        return self.call("sendMessage", {"chat_id": chat_id, "text": text[:2000]})

    def poll(self, timeout=30):
        res = self.call("getUpdates", {"timeout": timeout})
        return res if isinstance(res, list) else [res] if res else []


def extract(event) -> tuple[str, str, bool, str] | None:
    """Sự kiện → (chat_id, text, là_nhóm, tên_người_gửi) hoặc None."""
    event = event or {}
    event = event.get("result") if isinstance(event.get("result"), dict) else event  # webhook bọc trong "result"
    msg = event.get("message") or {}
    text = msg.get("text")
    chat = msg.get("chat") or {}
    sender = msg.get("from") or {}
    chat_id = str(chat.get("id") or sender.get("id") or "")
    if not text or not chat_id:
        return None
    ctype = str(chat.get("chat_type") or chat.get("type") or "").upper()
    return chat_id, str(text), ctype in ("GROUP", "GROUPCHAT", "SUPERGROUP"), sender.get("display_name") or sender.get("name") or ""


BOT_NAME = ""  # display_name của bot (lấy từ getMe) để nhận ra tin nhắc tên bot trong nhóm


def strip_mention(text: str, bot_name: str = ""):
    """Bỏ phần '@Tên bot' ở đầu tin. Trả (text_còn_lại, có_nhắc_bot)."""
    t = text.strip()
    if not t.startswith("@"):
        return t, False
    name = (bot_name or BOT_NAME).strip()
    if name and agent.norm(t[1:]).startswith(agent.norm(name)):
        return t[1 + len(name):].lstrip(" ,:-\u00a0"), True   # norm giữ độ dài ký tự nên cắt theo len(name)
    i = t.find("/")
    if i != -1:
        return t[i:], True
    parts = t.split(None, 1)
    return (parts[1] if len(parts) > 1 else ""), True


def reply_for(event) -> tuple[str, str] | None:
    got = extract(event)
    if not got:
        return None
    chat_id, text, is_group, _ = got
    t = text.strip()
    addressed = t.startswith("/")
    if is_group:
        t, mentioned = strip_mention(t)
        addressed = addressed or mentioned
        if t.lower().startswith("bot "):
            t, addressed = t[4:].strip(), True
        if not addressed:
            log.warning("Zalo nhận tin nhóm không gọi bot (bỏ qua)")
            return None
    log.warning("Zalo nhận tin chat_type=%s", "GROUP" if is_group else "PRIVATE")
    with SessionLocal() as db:
        ans = agent.handle(db, chat_id, t)
    if ans is None:
        if is_group or t.startswith("/"):
            ans = "Chưa hiểu lệnh này. Gõ /menu để xem hướng dẫn."
        else:
            return None
    return chat_id, ans


def handle_event(bot, event):
    r = reply_for(event)
    if r:
        bot.send(*r)


def run_forever(bot, stop: threading.Event):
    while not stop.is_set():
        try:
            for ev in bot.poll():
                try:
                    handle_event(bot, ev)
                except Exception as e:  # noqa: BLE001
                    log.warning("Zalo xử lý tin lỗi: %s", e)
        except Exception as e:  # noqa: BLE001
            log.warning("Zalo getUpdates lỗi: %s", e)
            stop.wait(10)


WEBHOOK_PATH = "/api/v1/hoc/zalo/webhook"


def get_bot():
    token = os.getenv("ZALO_BOT_TOKEN", "")
    return ZaloBot(token) if token else None


def webhook_url():
    base = os.getenv("ZALO_WEBHOOK_URL") or os.getenv("RENDER_EXTERNAL_URL") or ""
    if not base:
        return ""
    return base if base.rstrip("/").endswith(WEBHOOK_PATH) else base.rstrip("/") + WEBHOOK_PATH


def register_webhook(bot, url, secret, delays=(8, 15, 30, 60), sleep=time.sleep):
    """setWebhook, thử lại nếu Zalo báo kiểm tra thất bại (app chưa sẵn sàng). Trả True khi verification ok."""
    for d in delays:
        sleep(d)
        try:
            res = bot.call("setWebhook", {"url": url, "secret_token": secret}) or {}
        except Exception as e:  # noqa: BLE001
            log.warning("Zalo setWebhook lỗi: %s", e)
            continue
        ver = (res.get("verification") or {}) if isinstance(res, dict) else {}
        log.warning("Zalo setWebhook %s → ok=%s outcome=%s hint=%s", url, ver.get("ok"), ver.get("outcome"), ver.get("hint"))
        if ver.get("ok"):
            return True
    return False


def start_background():
    bot = get_bot()
    if not bot:
        return None
    try:
        me = bot.call("getMe", {}) or {}
        global BOT_NAME
        BOT_NAME = (me.get("display_name") or "") if isinstance(me, dict) else ""
        log.warning("Zalo bot sẵn sàng (%s): %s", bot.api, str(me)[:200])
    except Exception as e:  # noqa: BLE001
        log.warning("Zalo getMe lỗi (%s) — kiểm tra ZALO_BOT_TOKEN / ZALO_API_BASE: %s", bot.api, e)
    from . import reminders
    reminders.start_background(bot)
    secret, url = os.getenv("ZALO_WEBHOOK_SECRET", ""), webhook_url()
    if secret and url:
        # Đăng ký sau khi app đã nhận request được: setWebhook làm Zalo gọi thử vào ngay, gọi trong lúc khởi động sẽ báo 5xx.
        threading.Thread(target=register_webhook, args=(bot, url, secret), daemon=True, name="zalo-webhook").start()
        return None
    if secret:
        log.warning("Có ZALO_WEBHOOK_SECRET nhưng thiếu ZALO_WEBHOOK_URL/RENDER_EXTERNAL_URL — chuyển sang getUpdates")
    try:
        bot.call("deleteWebhook", {})  # getUpdates không chạy khi còn webhook cũ
    except Exception as e:  # noqa: BLE001
        log.info("deleteWebhook bỏ qua: %s", e)
    stop = threading.Event()
    threading.Thread(target=run_forever, args=(bot, stop), daemon=True, name="zalo-hoc").start()
    return stop

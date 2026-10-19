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


def reply_for(event) -> tuple[str, str] | None:
    got = extract(event)
    if not got:
        return None
    chat_id, text, is_group, _ = got
    t = text.strip()
    if is_group:
        low = t.lower()
        if t.startswith("/"):
            pass
        elif low.startswith("bot "):
            t = t[4:]
        else:
            return None
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


def start_background():
    bot = get_bot()
    if not bot:
        return None
    try:
        log.warning("Zalo bot sẵn sàng (%s): %s", bot.api, str(bot.call("getMe", {}))[:200])
    except Exception as e:  # noqa: BLE001
        log.warning("Zalo getMe lỗi (%s) — kiểm tra ZALO_BOT_TOKEN / ZALO_API_BASE: %s", bot.api, e)
    secret, url = os.getenv("ZALO_WEBHOOK_SECRET", ""), webhook_url()
    if secret and url:
        try:
            res = bot.call("setWebhook", {"url": url, "secret_token": secret})
            log.warning("Zalo setWebhook %s → %s", url, str(res)[:300])
        except Exception as e:  # noqa: BLE001
            log.warning("Zalo setWebhook lỗi: %s", e)
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

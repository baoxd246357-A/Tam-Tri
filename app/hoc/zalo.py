"""Bot Zalo (Zalo Bot Platform, bot.zapps.me) — đọc tin bằng getUpdates, trả lời bằng trợ lý lệnh.

Biến môi trường: ZALO_BOT_TOKEN. Không có token thì không chạy gì cả.
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
ZALO_API = "https://bot-api.zapps.me"


class ZaloBot:
    def __init__(self, token, transport=None):
        self.token = token
        self.http = httpx.Client(timeout=45, transport=transport)

    def call(self, method, data):
        r = self.http.post(f"{ZALO_API}/bot{self.token}/{method}", json=data)
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
    msg = (event or {}).get("message") or {}
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


def start_background():
    token = os.getenv("ZALO_BOT_TOKEN", "")
    if not token:
        return None
    stop = threading.Event()
    threading.Thread(target=run_forever, args=(ZaloBot(token), stop), daemon=True, name="zalo-hoc").start()
    return stop

"""Kiểm thử module học tập (không dùng AI)."""
import importlib
from datetime import date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.hoc import stats


@pytest.fixture()
def client(tmp_path, monkeypatch):
    import app.hoc.db as hdb
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    eng = create_engine(f"sqlite:///{tmp_path/'t.db'}", connect_args={"check_same_thread": False})
    hdb.Base.metadata.create_all(eng)
    monkeypatch.setattr(hdb, "SessionLocal", sessionmaker(bind=eng))
    import app.hoc.routes as r
    importlib.reload(r)  # lấy SessionLocal đã vá
    monkeypatch.setattr(r, "SessionLocal", hdb.SessionLocal)
    from fastapi import FastAPI
    a = FastAPI()
    a.include_router(r.router)
    a.include_router(r.webhook_router)
    return TestClient(a), r


def mk_learner(c):
    return c.post("/api/v1/hoc/learners", data={"name": "Bin", "level": "thcs", "grade": "Lớp 7"}).json()["id"]


def test_validation(client):
    c, _ = client
    lid = mk_learner(c)
    assert c.post("/api/v1/hoc/logs", data={"learner_id": lid, "minutes": 0}).status_code == 400
    assert c.post("/api/v1/hoc/tasks", data={"learner_id": lid, "title": "a", "due": "31/12"}).status_code == 400
    assert c.post("/api/v1/hoc/learners", data={"name": "A", "level": "x"}).status_code == 400
    assert c.get("/api/v1/hoc/learners/99/weekly").status_code == 404


def test_tasks_and_weekly_endpoint(client):
    c, _ = client
    lid = mk_learner(c)
    tid = c.post("/api/v1/hoc/tasks", data={"learner_id": lid, "title": "BT", "due": "2000-01-01"}).json()["id"]
    c.post("/api/v1/hoc/logs", data={"learner_id": lid, "subject": "Toán", "minutes": 300, "understanding": 2})
    s = c.get(f"/api/v1/hoc/learners/{lid}/weekly").json()["summary"]
    assert s["total_minutes"] == 300 and s["weak_subjects"] == ["Toán"]
    assert s["tasks_overdue"] == ["BT"] and len(s["days_over_limit"]) == 1
    assert c.post(f"/api/v1/hoc/tasks/{tid}/toggle").json()["done"] is True


def test_weekly_summary_window():
    today = date(2026, 10, 19)
    old = datetime(2026, 10, 1, 9)
    new = datetime(2026, 10, 18, 9)
    logs = [{"subject": "Toán", "minutes": 50, "understanding": 5, "created_at": old},
            {"subject": "Toán", "minutes": 30, "understanding": 4, "created_at": new}]
    s = stats.weekly_summary("thcs", logs, [], today)
    assert s["total_minutes"] == 30 and s["weak_subjects"] == []


def test_page_and_main_wiring():
    from app.main import app
    c = TestClient(app)
    assert c.get("/hoc").status_code == 200
    assert c.get("/health").status_code == 200


# ---------------------------------------------------------------- trợ lý lệnh / Zalo
from app.hoc import agent, zalo  # noqa: E402


@pytest.fixture()
def db(tmp_path):
    import app.hoc.db as hdb
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    eng = create_engine(f"sqlite:///{tmp_path/'a.db'}", connect_args={"check_same_thread": False})
    hdb.Base.metadata.create_all(eng)
    with sessionmaker(bind=eng)() as s:
        yield s


def test_agent_flow(db):
    assert "Đã thêm Bin" in agent.handle(db, "g1", "/thêm Bin thcs lớp 7")
    assert agent.handle(db, "g1", "xin chào") is None
    r = agent.handle(db, "g1", "việc Toán bài tập trang 45 hạn 25/10")  # bé duy nhất, tự chọn
    assert "#1" in r and "hạn 25/10" in r
    assert "Đã ghi Bin: Toán 45 phút (hiểu 4/5)" in agent.handle(db, "g1", "hoc Bin toan 45 hieu 4")
    assert "xong" in agent.handle(db, "g1", "xong 1").lower()
    rep = agent.handle(db, "g1", "báo cáo")
    assert "45 phút" in rep and "1 xong" in rep
    assert "Số phút" in agent.handle(db, "g1", "học Toán 900")
    assert "không hợp lệ" in agent.handle(db, "g1", "việc bài a hạn 31/02")


def test_agent_needs_child_when_several(db):
    agent.handle(db, "g", "thêm An")
    agent.handle(db, "g", "thêm Binh")
    assert "Bé nào" in agent.handle(db, "h", "ds")            # nhóm khác, chưa chọn bé
    assert "đang theo dõi Binh" in agent.handle(db, "h", "chọn binh")
    assert "Việc của Binh" in agent.handle(db, "h", "ds")
    assert "Việc của An" in agent.handle(db, "h", "danh sách An")


def test_due_parsing():
    d = date(2026, 10, 19)
    assert agent.parse_due("bài hạn mai".split(), d)[0] == "2026-10-20"
    assert agent.parse_due("bài han 05/10".split(), d)[0] == "2027-10-05"  # đã qua → năm sau
    assert agent.parse_due("bài".split(), d)[0] == ""


def ev(text, chat="c1", ctype="PRIVATE"):
    return {"message": {"text": text, "chat": {"id": chat, "chat_type": ctype}, "from": {"id": "u"}}}


def test_zalo_group_needs_prefix(monkeypatch, db):
    import contextlib
    monkeypatch.setattr(zalo, "SessionLocal", lambda: contextlib.nullcontext(db))
    assert zalo.reply_for(ev("thêm Bin", ctype="GROUP")) is None          # nói chuyện thường trong nhóm
    assert "Đã thêm" in zalo.reply_for(ev("/thêm Bin", ctype="GROUP"))[1]
    assert "Việc của Bin" in zalo.reply_for(ev("bot ds", ctype="GROUP"))[1]
    assert zalo.reply_for(ev("/linhtinh", ctype="GROUP"))[1].startswith("Chưa hiểu")
    assert zalo.reply_for(ev("hello", ctype="PRIVATE")) is None
    assert zalo.reply_for({"message": {"chat": {"id": 1}}}) is None


def test_zalo_client_send_and_poll():
    import httpx, json
    seen = []
    def h(req):
        seen.append((req.url.path, json.loads(req.content)))
        return httpx.Response(200, json={"ok": True, "result": [ev("/menu")] if "getUpdates" in req.url.path else {}})
    bot = zalo.ZaloBot("TKN", httpx.MockTransport(h))
    assert len(bot.poll()) == 1
    bot.send("c1", "hi")
    assert seen[0][0] == "/botTKN/getUpdates" and seen[1][1] == {"chat_id": "c1", "text": "hi"}


def test_web_agent_endpoint(client):
    c, _ = client
    assert "Trợ lý học tập" in c.post("/api/v1/hoc/agent", data={"text": "menu"}).json()["reply"]
    assert "Đã thêm" in c.post("/api/v1/hoc/agent", data={"text": "thêm Bin"}).json()["reply"]


def test_zalo_extract_unwraps_webhook_result():
    wrapped = {"ok": True, "result": {"event_name": "message.text.received", "message": ev("/menu")["message"]}}
    assert zalo.extract(wrapped)[1] == "/menu"
    assert zalo.extract({"ok": True, "result": {"event_name": "message.sticker.received", "message": {"chat": {"id": 1}}}}) is None


def test_zalo_webhook_auth_and_reply(client, monkeypatch):
    c, r = client
    sent = []
    class Bot:
        def send(self, chat, text): sent.append((chat, text))
    monkeypatch.setattr(r.zalo, "get_bot", lambda: Bot())
    monkeypatch.setattr(r.zalo, "reply_for", lambda e: ("c9", "xin chào"))
    body = {"ok": True, "result": ev("/menu")}
    monkeypatch.delenv("ZALO_WEBHOOK_SECRET", raising=False)
    assert c.post("/api/v1/hoc/zalo/webhook", json=body).status_code == 503
    monkeypatch.setenv("ZALO_WEBHOOK_SECRET", "s3cret-key")
    assert c.post("/api/v1/hoc/zalo/webhook", json=body).status_code == 403
    assert c.post("/api/v1/hoc/zalo/webhook", json=body, headers={"X-Bot-Api-Secret-Token": "sai"}).status_code == 403
    ok = c.post("/api/v1/hoc/zalo/webhook", json=body, headers={"X-Bot-Api-Secret-Token": "s3cret-key"})
    assert ok.status_code == 200 and sent == [("c9", "xin chào")]


def test_webhook_url(monkeypatch):
    monkeypatch.delenv("ZALO_WEBHOOK_URL", raising=False)
    monkeypatch.setenv("RENDER_EXTERNAL_URL", "https://x.onrender.com/")
    assert zalo.webhook_url() == "https://x.onrender.com/api/v1/hoc/zalo/webhook"


def test_register_webhook_retries_until_verified():
    calls = []
    class Bot:
        def call(self, method, data):
            calls.append(method)
            ok = len(calls) >= 3
            return {"verification": {"ok": ok, "outcome": "webhook.ok" if ok else "webhook.http.5xx", "hint": ""}}
    assert zalo.register_webhook(Bot(), "https://x/y", "secret123", sleep=lambda s: None) is True
    assert calls == ["setWebhook"] * 3


def test_register_webhook_gives_up_and_survives_errors():
    class Bad:
        def call(self, m, d): raise RuntimeError("boom")
    assert zalo.register_webhook(Bad(), "u", "s", delays=(1, 1), sleep=lambda s: None) is False


def test_webhook_accepts_empty_body(client, monkeypatch):
    c, r = client
    monkeypatch.setattr(r.zalo, "get_bot", lambda: None)
    monkeypatch.setenv("ZALO_WEBHOOK_SECRET", "s3cret-key")
    resp = c.post("/api/v1/hoc/zalo/webhook", headers={"X-Bot-Api-Secret-Token": "s3cret-key"})
    assert resp.status_code == 200


def test_strip_mention():
    n = "Bot Học Tập TV"
    assert zalo.strip_mention("@Bot Học Tập TV /menu", n) == ("/menu", True)
    assert zalo.strip_mention("@Bot Học Tập TV ds", n) == ("ds", True)
    assert zalo.strip_mention("@bot hoc tap tv, báo cáo", n) == ("báo cáo", True)
    assert zalo.strip_mention("@Ai đó /menu", n) == ("/menu", True)
    assert zalo.strip_mention("ds", n) == ("ds", False)


def test_zalo_group_mention_without_slash(monkeypatch, db):
    import contextlib
    monkeypatch.setattr(zalo, "SessionLocal", lambda: contextlib.nullcontext(db))
    monkeypatch.setattr(zalo, "BOT_NAME", "Bot Học Tập TV")
    assert "Trợ lý học tập" in zalo.reply_for(ev("@Bot Học Tập TV menu", ctype="GROUP"))[1]
    assert "Đã thêm" in zalo.reply_for(ev("@Bot Học Tập TV /thêm Bin", ctype="GROUP"))[1]
    assert zalo.reply_for(ev("chiều nay đi học", ctype="GROUP")) is None


# ---------------------------------------------------------------- mật khẩu + CSDL ngoài
def test_password_protects_hoc_but_not_webhook(client, monkeypatch):
    c, r = client
    monkeypatch.setenv("HOC_PASSWORD", "mat-khau-nha")
    monkeypatch.setenv("ZALO_WEBHOOK_SECRET", "s3cret-key")
    monkeypatch.setattr(r.zalo, "get_bot", lambda: None)
    assert c.get("/hoc").status_code == 401
    assert c.get("/hoc").headers["www-authenticate"].startswith("Basic")
    assert c.get("/api/v1/hoc/learners").status_code == 401
    assert c.post("/api/v1/hoc/agent", data={"text": "menu"}).status_code == 401
    assert c.get("/api/v1/hoc/learners", auth=("me", "sai")).status_code == 401
    assert c.get("/api/v1/hoc/learners", auth=("me", "mat-khau-nha")).status_code == 200
    assert c.get("/hoc", auth=("bat-ky", "mat-khau-nha")).status_code == 200
    # webhook Zalo không dùng mật khẩu, chỉ dùng secret header
    ok = c.post("/api/v1/hoc/zalo/webhook", json={}, headers={"X-Bot-Api-Secret-Token": "s3cret-key"})
    assert ok.status_code == 200
    assert c.post("/api/v1/hoc/zalo/webhook", json={}).status_code == 403


def test_open_when_no_password(client, monkeypatch):
    c, _ = client
    monkeypatch.delenv("HOC_PASSWORD", raising=False)
    assert c.get("/api/v1/hoc/learners").status_code == 200


def test_db_url_normalize_and_engine(tmp_path, monkeypatch):
    import app.hoc.db as hdb
    assert hdb.normalize_db_url("postgres://u:p@h/db?sslmode=require") == "postgresql+psycopg2://u:p@h/db?sslmode=require"
    assert hdb.normalize_db_url("postgresql://u:p@h/db") == "postgresql+psycopg2://u:p@h/db"
    assert hdb.normalize_db_url("  sqlite:///x.db ") == "sqlite:///x.db"
    monkeypatch.delenv("DATABASE_URL", raising=False)
    assert hdb.make_engine().dialect.name == "sqlite"
    pg = hdb.make_engine("postgres://u:p@localhost:1/db")   # chỉ tạo engine, chưa kết nối
    assert pg.dialect.name == "postgresql"
    assert hdb.make_engine(f"sqlite:///{tmp_path/'z.db'}").dialect.name == "sqlite"


def test_rename_learner(db):
    agent.handle(db, "g", "thêm Bin thcs lớp 7")
    agent.handle(db, "g", "việc Toán bài 1")
    assert "Bin → Minh" in agent.handle(db, "g", "/đổi Bin Minh")
    assert "Việc của Minh" in agent.handle(db, "g", "ds")               # việc và bé đang chọn đi theo bé
    assert "Không thấy" not in (agent.handle(db, "g", "chọn minh") or "")
    assert "Cú pháp" in agent.handle(db, "g", "đổi Bin Khoa")           # tên cũ không còn
    agent.handle(db, "g", "thêm Khoa")
    assert "Đã có bạn tên khoa" in agent.handle(db, "g", "đổi tên Minh khoa")   # trùng tên (không phân biệt hoa/dấu)
    assert "Thiếu tên mới" in agent.handle(db, "g", "đổi Minh")
    assert "Minh Anh" in agent.handle(db, "g", "đổi Minh Minh_Anh")      # tên nhiều từ
    assert "Việc của Minh Anh" in agent.handle(db, "g", "ds Minh_Anh")
    assert "Minh Anh" in agent.handle(db, "g", "bé")


def test_add_multiword_name(db):
    assert "Đã thêm Bảo An" in agent.handle(db, "g", "thêm Bảo_An thcs lớp 6")
    assert "Việc của Bảo An" in agent.handle(db, "g", "ds Bao_An")


def test_rename_with_grade_and_level_inference(db):
    from app.hoc.db import Learner
    agent.handle(db, "g", "thêm Bin thcs lớp 7")
    r = agent.handle(db, "g", "/đổi Bin Quốc_Thịnh lớp 6")
    assert "Bin → Quốc Thịnh (lớp 6)" in r
    l = db.query(Learner).one()
    assert (l.name, l.grade, l.level) == ("Quốc Thịnh", "lớp 6", "thcs")
    assert "Đã thêm Kiến Văn (Tiểu học, lớp 4)" in agent.handle(db, "g", "/Thêm Kiến_Văn lớp 4")
    assert db.query(Learner).filter_by(name="Kiến Văn").one().level == "tieu_hoc"
    agent.handle(db, "g", "đổi Kiến_Văn Kiến_Văn lớp 10")
    assert db.query(Learner).filter_by(name="Kiến Văn").one().level == "thpt"
    agent.handle(db, "g", "đổi Kiến_Văn Kiến_Văn thcs lớp 5")           # cấp ghi rõ thắng suy luận
    assert db.query(Learner).filter_by(name="Kiến Văn").one().level == "thcs"


def test_infer_level():
    assert [agent.infer_level(x) for x in ("lớp 1", "lớp 5", "lớp 6", "9", "lớp 12", "lớp 13", "mầm non")] == \
        ["tieu_hoc", "tieu_hoc", "thcs", "thcs", "thpt", None, None]


def test_reminder_command_and_text(db):
    from app.hoc import reminders
    agent.handle(db, "g1", "thêm Bin lớp 6")
    agent.handle(db, "g1", "thêm Văn lớp 4")
    today = date(2026, 10, 20)
    assert reminders.build_reminder(db, today) is None
    agent.handle(db, "g1", "việc Bin Bài Toán hạn 18/10/2026")
    agent.handle(db, "g1", "việc Văn Đọc sách hạn 20/10/2026")
    agent.handle(db, "g1", "việc Văn Vẽ hạn 21/10/2026")
    agent.handle(db, "g1", "việc Bin Xa hạn 30/10/2026")
    txt = reminders.build_reminder(db, today)
    assert "Trễ hạn" in txt and "Bài Toán" in txt and "trễ 2 ngày" in txt
    assert "Hôm nay" in txt and "Đọc sách" in txt and "Ngày mai" in txt and "Xa" not in txt
    assert "đang tắt" in agent.handle(db, "g1", "nhắc")
    assert "Đã bật" in agent.handle(db, "g1", "nhắc bật")
    assert "đang bật" in agent.handle(db, "g1", "nhắc")
    assert "Đã tắt" in agent.handle(db, "g1", "nhắc tắt")


def test_reminder_run_due_once_per_day(db):
    from app.hoc import reminders
    agent.handle(db, "g1", "thêm Bin lớp 6")
    agent.handle(db, "g1", "việc Bin Bài Toán hạn 18/10/2026")
    agent.handle(db, "g1", "nhắc bật")
    sent = []
    send = lambda c, t: sent.append((c, t))
    assert reminders.run_due(db, send, datetime(2026, 10, 20, 5, 0)) == 0   # 5h sáng VN: chưa tới giờ
    assert reminders.run_due(db, send, datetime(2026, 10, 20, 7, 30)) == 1
    assert reminders.run_due(db, send, datetime(2026, 10, 20, 10, 0)) == 0   # đã nhắc hôm nay
    assert reminders.run_due(db, send, datetime(2026, 10, 21, 8, 0)) == 1    # ngày sau
    assert len(sent) == 2 and sent[0][0] == "g1"


def test_reminder_endpoint_auth(client, monkeypatch):
    c, r = client
    monkeypatch.setattr(r.zalo, "get_bot", lambda: type("B", (), {"send": lambda s, c, t: None})())
    monkeypatch.setattr(r.reminders, "tick", lambda bot: 2)
    monkeypatch.delenv("ZALO_WEBHOOK_SECRET", raising=False)
    assert c.get("/api/v1/hoc/reminders/run").status_code == 503
    monkeypatch.setenv("ZALO_WEBHOOK_SECRET", "s3cret-key")
    assert c.get("/api/v1/hoc/reminders/run?key=sai").status_code == 403
    assert c.get("/api/v1/hoc/reminders/run?key=s3cret-key").json() == {"sent": 2}


def test_llm_tutor(db, monkeypatch):
    import httpx
    from app.hoc import llm
    for k in ("LLM_API_KEY", "LLM_BASE_URL", "LLM_MODEL"):
        monkeypatch.delenv(k, raising=False)
    assert agent.ask_tutor(db, "c1", "1+1 bằng mấy?") is None            # chưa cấu hình → như cũ
    monkeypatch.setenv("LLM_API_KEY", "k-test")
    monkeypatch.setenv("LLM_BASE_URL", "https://llm.example/v1/")
    monkeypatch.setenv("LLM_MODEL", "m1")
    seen = {}

    def handler(req):
        seen.update(url=str(req.url), auth=req.headers["authorization"], body=req.content.decode())
        return httpx.Response(200, json={"choices": [{"message": {"content": "Bằng 2 nhé"}}]})

    agent.handle(db, "c1", "thêm Bin lớp 6")
    assert llm.ask("1+1?", "THCS", transport=httpx.MockTransport(handler)).endswith("Bằng 2 nhé")
    assert seen["url"] == "https://llm.example/v1/chat/completions" and seen["auth"] == "Bearer k-test"
    assert "Bin" not in seen["body"] and '"m1"' in seen["body"]            # không gửi tên bé
    bad = httpx.MockTransport(lambda r: httpx.Response(500))
    assert llm.ask("x", transport=bad) is None

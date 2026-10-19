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

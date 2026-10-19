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

"""API + trang /hoc: quản lý việc học của cả nhà (không dùng AI)."""
from datetime import date
from pathlib import Path

from fastapi import APIRouter, Form, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from . import rules, stats
from .db import Learner, SessionLocal, StudyLog, Task

router = APIRouter()
templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent.parent / "templates"))


def _learner(db, lid: int) -> Learner:
    l = db.get(Learner, lid)
    if not l:
        raise HTTPException(404, "Không có người học này")
    return l


def _ldict(l: Learner) -> dict:
    return {"id": l.id, "name": l.name, "level": l.level, "grade": l.grade, "goal": l.goal}


@router.get("/hoc", response_class=HTMLResponse)
def hoc_page(request: Request):
    return templates.TemplateResponse(
        request=request, name="hoc.html",
        context={"subjects": rules.SUBJECTS, "reviewed": rules.REVIEWED},
    )


@router.get("/api/v1/hoc/learners")
def list_learners():
    with SessionLocal() as db:
        return [_ldict(l) for l in db.query(Learner).order_by(Learner.id)]


@router.post("/api/v1/hoc/learners")
def add_learner(name: str = Form(...), level: str = Form("thcs"),
                grade: str = Form(""), goal: str = Form("")):
    name = name.strip()
    if not name:
        raise HTTPException(400, "Thiếu tên")
    if level not in rules.LEVELS:
        raise HTTPException(400, "Cấp học không hợp lệ")
    with SessionLocal() as db:
        l = Learner(name=name, level=level, grade=grade.strip(), goal=goal.strip())
        db.add(l)
        db.commit()
        return _ldict(l)


@router.post("/api/v1/hoc/logs")
def add_log(learner_id: int = Form(...), subject: str = Form("Khác"), minutes: int = Form(...),
            understanding: int = Form(3), note: str = Form("")):
    if not 1 <= minutes <= 720:
        raise HTTPException(400, "Số phút phải từ 1 đến 720")
    if not 1 <= understanding <= 5:
        raise HTTPException(400, "Độ hiểu phải từ 1 đến 5")
    with SessionLocal() as db:
        _learner(db, learner_id)
        db.add(StudyLog(learner_id=learner_id, subject=subject if subject in rules.SUBJECTS else "Khác",
                        minutes=minutes, understanding=understanding, note=note.strip()))
        db.commit()
    return {"ok": True}


@router.post("/api/v1/hoc/tasks")
def add_task(learner_id: int = Form(...), title: str = Form(...), subject: str = Form("Khác"),
             due: str = Form("")):
    if due:
        try:
            date.fromisoformat(due)
        except ValueError:
            raise HTTPException(400, "Hạn nộp phải dạng YYYY-MM-DD")
    with SessionLocal() as db:
        _learner(db, learner_id)
        t = Task(learner_id=learner_id, title=title.strip(),
                 subject=subject if subject in rules.SUBJECTS else "Khác", due=due)
        db.add(t)
        db.commit()
        return {"id": t.id}


@router.post("/api/v1/hoc/tasks/{tid}/toggle")
def toggle_task(tid: int):
    with SessionLocal() as db:
        t = db.get(Task, tid)
        if not t:
            raise HTTPException(404, "Không có việc này")
        t.done = 0 if t.done else 1
        db.commit()
        return {"id": t.id, "done": bool(t.done)}


@router.get("/api/v1/hoc/learners/{lid}/tasks")
def list_tasks(lid: int):
    with SessionLocal() as db:
        rows = db.query(Task).filter_by(learner_id=lid).order_by(Task.done, Task.due).all()
        return [{"id": t.id, "title": t.title, "subject": t.subject, "due": t.due,
                 "done": bool(t.done)} for t in rows]


@router.get("/api/v1/hoc/learners/{lid}/weekly")
def weekly(lid: int):
    with SessionLocal() as db:
        l = _learner(db, lid)
        logs = [{"subject": x.subject, "minutes": x.minutes, "understanding": x.understanding,
                 "created_at": x.created_at} for x in db.query(StudyLog).filter_by(learner_id=lid)]
        tasks = [{"title": x.title, "due": x.due, "done": x.done}
                 for x in db.query(Task).filter_by(learner_id=lid)]
        summary = stats.weekly_summary(l.level, logs, tasks)
    return {"learner": _ldict(l), "summary": summary}

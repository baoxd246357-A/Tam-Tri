"""API + trang /hoc: gia sư AI cho cả nhà."""
import json
import os
import shutil
from datetime import date, datetime
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from . import ai, rules, stats
from .db import UPLOADS, Learner, Question, SessionLocal, StudyLog, Task

router = APIRouter()
templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent.parent / "templates"))
ALLOWED_IMAGES = {"image/jpeg", "image/png", "image/webp"}


def _learner(db, lid: int) -> Learner:
    l = db.get(Learner, lid)
    if not l:
        raise HTTPException(404, "Không có người học này")
    return l


def _ldict(l: Learner) -> dict:
    return {"id": l.id, "name": l.name, "level": l.level, "grade": l.grade, "goal": l.goal}


def _qdict(q: Question) -> dict:
    return {
        "id": q.id, "learner_id": q.learner_id, "subject": q.subject, "text": q.text,
        "image": q.image_path, "hint_level": q.hint_level, "ai_status": q.ai_status,
        "ai": json.loads(q.ai_json) if q.ai_json else None,
        "confidence": q.ai_confidence, "needs_review": bool(q.needs_review),
        "parent_review": q.parent_review, "parent_note": q.parent_note,
        "created_at": q.created_at.isoformat(),
    }


def _run_tutor(db, q: Question):
    l = _learner(db, q.learner_id)
    image = None
    if q.image_path:
        p = UPLOADS / os.path.basename(q.image_path)
        if p.exists():
            image = (p.read_bytes(), q.mime_type)
    try:
        result, raw = ai.tutor(_ldict(l), q.subject, q.text, q.hint_level, image)
    except HTTPException:
        raise
    except Exception as exc:
        q.ai_status = "ERROR"
        q.ai_json = json.dumps({"error": str(exc)[:300]}, ensure_ascii=False)
        db.commit()
        raise HTTPException(502, f"AI lỗi: {str(exc)[:200]}")
    # chỉ giữ đáp án khi đã tới mức giải đầy đủ — chốt ở server, không tin hoàn toàn vào AI
    if q.hint_level < rules.MAX_HINT_LEVEL:
        result["answer"] = ""
        result["steps"] = result.get("steps", [])[: q.hint_level]
    conf = float(result.get("confidence") or 0)
    q.ai_json = json.dumps(result, ensure_ascii=False)
    q.ai_confidence = conf
    q.needs_review = int(stats.needs_review(conf))
    q.ai_status = "DONE"
    db.commit()


@router.get("/hoc", response_class=HTMLResponse)
def hoc_page(request: Request):
    return templates.TemplateResponse(
        request=request, name="hoc.html",
        context={"subjects": rules.SUBJECTS, "levels": rules.LEVELS,
                 "reviewed": rules.REVIEWED, "ladder": rules.HINT_LADDER},
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


@router.post("/api/v1/hoc/questions")
async def ask(learner_id: int = Form(...), subject: str = Form("Khác"), text: str = Form(""),
              hint_level: int = Form(rules.DEFAULT_HINT_LEVEL),
              file: UploadFile | None = File(None)):
    if not text.strip() and not file:
        raise HTTPException(400, "Cần câu hỏi hoặc ảnh")
    if subject not in rules.SUBJECTS:
        subject = "Khác"
    with SessionLocal() as db:
        _learner(db, learner_id)
        q = Question(learner_id=learner_id, subject=subject, text=text.strip(),
                     hint_level=stats.clamp_hint_level(hint_level))
        if file and file.filename:
            if file.content_type not in ALLOWED_IMAGES:
                raise HTTPException(400, "Chỉ hỗ trợ JPG, PNG, WEBP")
            name = f"{datetime.utcnow():%Y%m%d_%H%M%S_%f}_{os.path.basename(file.filename)}"
            with open(UPLOADS / name, "wb") as f:
                shutil.copyfileobj(file.file, f)
            q.image_path, q.mime_type = f"/hoc-uploads/{name}", file.content_type
        db.add(q)
        db.commit()
        db.refresh(q)
        _run_tutor(db, q)
        return _qdict(q)


@router.post("/api/v1/hoc/questions/{qid}/hint")
def next_hint(qid: int):
    """Bé thử rồi mà vẫn kẹt → nâng một mức gợi ý và hỏi lại."""
    with SessionLocal() as db:
        q = db.get(Question, qid)
        if not q:
            raise HTTPException(404, "Không có câu hỏi")
        q.hint_level = stats.clamp_hint_level(q.hint_level + 1)
        db.commit()
        _run_tutor(db, q)
        return _qdict(q)


@router.post("/api/v1/hoc/questions/{qid}/review")
def parent_review(qid: int, verdict: str = Form(...), note: str = Form("")):
    if verdict not in ("OK", "WRONG"):
        raise HTTPException(400, "verdict phải là OK hoặc WRONG")
    with SessionLocal() as db:
        q = db.get(Question, qid)
        if not q:
            raise HTTPException(404, "Không có câu hỏi")
        q.parent_review, q.parent_note = verdict, note.strip()
        db.commit()
        return _qdict(q)


@router.get("/api/v1/hoc/learners/{lid}/questions")
def list_questions(lid: int, limit: int = 20):
    with SessionLocal() as db:
        rows = (db.query(Question).filter_by(learner_id=lid)
                .order_by(Question.id.desc()).limit(min(limit, 100)).all())
        return [_qdict(q) for q in rows]


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
def weekly(lid: int, note: bool = False):
    with SessionLocal() as db:
        l = _learner(db, lid)
        logs = [{"subject": x.subject, "minutes": x.minutes, "understanding": x.understanding,
                 "created_at": x.created_at} for x in db.query(StudyLog).filter_by(learner_id=lid)]
        tasks = [{"title": x.title, "due": x.due, "done": x.done}
                 for x in db.query(Task).filter_by(learner_id=lid)]
        qs = [{"created_at": x.created_at, "needs_review": x.needs_review,
               "parent_review": x.parent_review} for x in db.query(Question).filter_by(learner_id=lid)]
        summary = stats.weekly_summary(l.level, logs, tasks, qs)
    out = {"learner": _ldict(l), "summary": summary, "ai_note": None}
    if note:
        try:
            out["ai_note"] = ai.weekly_note(_ldict(l), summary)
        except HTTPException as e:
            out["ai_note_error"] = e.detail
        except Exception as e:
            out["ai_note_error"] = str(e)[:200]
    return out

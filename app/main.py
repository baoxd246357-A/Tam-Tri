import os, json, shutil, re, mimetypes
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import create_engine, Column, Integer, String, Text, Float, DateTime
from sqlalchemy.orm import declarative_base, sessionmaker
from google import genai
from google.genai import types

BASE = Path(__file__).resolve().parent.parent
load_dotenv(BASE / ".env")

DATA = BASE / "data"
UPLOADS = DATA / "uploads"
EVIDENCE = DATA / "evidence"
UPLOADS.mkdir(parents=True, exist_ok=True)
EVIDENCE.mkdir(parents=True, exist_ok=True)

engine = create_engine(
    f"sqlite:///{DATA / 'site_control.db'}",
    connect_args={"check_same_thread": False},
)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class Project(Base):
    __tablename__ = "projects"
    id = Column(Integer, primary_key=True)
    code = Column(String(50), unique=True, nullable=False)
    name = Column(String(255), nullable=False)
    location = Column(String(255))
    status = Column(String(50), default="ACTIVE")


class SiteVisit(Base):
    __tablename__ = "site_visits"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer)
    floor = Column(String(50))
    zone = Column(String(100))
    work = Column(String(255))
    note = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)


class Photo(Base):
    __tablename__ = "photos"
    id = Column(Integer, primary_key=True)
    visit_id = Column(Integer)
    filename = Column(String(255))
    path = Column(String(500))
    mime_type = Column(String(100))
    ai_description = Column(Text)
    ai_work = Column(String(255))
    ai_location = Column(String(255))
    ai_progress = Column(Float, default=0)
    ai_quality_status = Column(String(50))
    ai_issues = Column(Text)
    ai_recommended_action = Column(Text)
    ai_safety_status = Column(String(50))
    ai_confidence = Column(Float, default=0)
    ai_raw = Column(Text)
    ai_status = Column(String(50), default="PENDING")
    created_at = Column(DateTime, default=datetime.utcnow)


class VoiceEvidence(Base):
    __tablename__ = "voice_evidence"
    id = Column(Integer, primary_key=True)
    visit_id = Column(Integer)
    filename = Column(String(255))
    path = Column(String(500))
    mime_type = Column(String(100))
    transcript = Column(Text)
    ai_status = Column(String(50), default="UPLOADED")
    created_at = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(engine)

app = FastAPI(title="AI TVGS Tâm Trí Pilot V0.1")
app.mount("/static", StaticFiles(directory=str(BASE / "app/static")), name="static")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")
app.mount("/evidence", StaticFiles(directory=str(EVIDENCE)), name="evidence")
templates = Jinja2Templates(directory=str(BASE / "app/templates"))


def get_client():
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="GEMINI_API_KEY chưa được cấu hình trên Render")
    return genai.Client(api_key=key)


def clean_json_text(text: str):
    text = (text or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    return text


def analyze_site_photo(image_path: Path, mime_type: str, context: dict):
    client = get_client()
    model = os.getenv("GEMINI_MODEL", "gemini-3.7-flash")
    image_bytes = image_path.read_bytes()
    image_part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)

    prompt = f"""
You are an expert construction site inspection assistant for AI TVGS Tâm Trí.
Analyze ONLY what is reasonably visible in the supplied photo. Do not invent
measurements, drawing references, exact locations, or compliance conclusions.

Project context:
- Project: {context.get("project_name")}
- Floor entered by inspector: {context.get("floor")}
- Zone/room entered by inspector: {context.get("zone")}
- Work entered by inspector: {context.get("work")}
- Inspector note: {context.get("note")}

Return ONLY valid JSON:
{{
  "work": "construction work visible",
  "location": "best visible/entered location; say 'not visible' if unknown",
  "progress_percent": 0,
  "quality_status": "OK|ATTENTION|DEFECT|NOT_DETERMINED",
  "issues": ["issue 1"],
  "recommended_action": "practical next action",
  "safety_status": "OK|ATTENTION|NOT_DETERMINED",
  "safety_observation": "short observation",
  "description": "objective description of what is visible",
  "confidence": 0.0
}}

For progress_percent, estimate only when visual evidence supports an estimate;
otherwise use 0 and explain uncertainty.
Use NOT_DETERMINED when a photo cannot support a reliable quality judgement.
Do not treat an AI visual estimate as an acceptance/measurement result.
Confidence must be between 0 and 1.
"""
    response = client.models.generate_content(
        model=model,
        contents=[prompt, image_part],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema={
                "type": "OBJECT",
                "properties": {
                    "work": {"type": "STRING"},
                    "location": {"type": "STRING"},
                    "progress_percent": {"type": "NUMBER"},
                    "quality_status": {"type": "STRING"},
                    "issues": {"type": "ARRAY", "items": {"type": "STRING"}},
                    "recommended_action": {"type": "STRING"},
                    "safety_status": {"type": "STRING"},
                    "safety_observation": {"type": "STRING"},
                    "description": {"type": "STRING"},
                    "confidence": {"type": "NUMBER"},
                },
                "required": [
                    "work", "location", "progress_percent", "quality_status",
                    "issues", "recommended_action", "safety_status",
                    "safety_observation", "description", "confidence"
                ],
            },
        ),
    )
    raw = response.text
    return json.loads(clean_json_text(raw)), raw


def transcribe_voice(audio_path: Path, mime_type: str, context: dict):
    client = get_client()
    model = os.getenv("GEMINI_MODEL", "gemini-3.7-flash")
    audio_part = types.Part.from_bytes(data=audio_path.read_bytes(), mime_type=mime_type)
    prompt = f"""
You are an assistant for a construction site supervisor.
Transcribe the Vietnamese speech accurately. Then extract useful site information.
Do not invent information.

Context:
Project: {context.get("project_name")}
Floor: {context.get("floor")}
Zone/room: {context.get("zone")}
Work: {context.get("work")}

Return ONLY JSON:
{{
  "transcript": "exact or best-effort Vietnamese transcript",
  "summary": "short structured summary",
  "issues": ["..."],
  "recommended_action": "..."
}}
"""
    response = client.models.generate_content(
        model=model,
        contents=[prompt, audio_part],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema={
                "type": "OBJECT",
                "properties": {
                    "transcript": {"type": "STRING"},
                    "summary": {"type": "STRING"},
                    "issues": {"type": "ARRAY", "items": {"type": "STRING"}},
                    "recommended_action": {"type": "STRING"},
                },
                "required": ["transcript", "summary", "issues", "recommended_action"],
            },
        ),
    )
    raw = response.text
    return json.loads(clean_json_text(raw))


@app.on_event("startup")
def seed():
    db = SessionLocal()
    if db.query(Project).count() == 0:
        db.add(Project(code="PRJ-001", name="Bệnh viện Tâm Trí", location="TP.HCM"))
        db.commit()
    db.close()


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    db = SessionLocal()
    project = db.query(Project).first()
    visits = db.query(SiteVisit).order_by(SiteVisit.created_at.desc()).limit(20).all()
    photos = db.query(Photo).order_by(Photo.created_at.desc()).limit(12).all()
    db.close()
    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={"project": project, "visits": visits, "photos": photos},
    )


@app.post("/api/v1/visits")
def create_visit(
    floor: str = Form(...),
    zone: str = Form(...),
    work: str = Form(...),
    note: str = Form("")
):
    db = SessionLocal()
    visit = SiteVisit(project_id=1, floor=floor, zone=zone, work=work, note=note)
    db.add(visit)
    db.commit()
    db.refresh(visit)
    db.close()
    return JSONResponse({"visit_id": visit.id, "floor": floor, "zone": zone, "work": work})


@app.post("/api/v1/visits/{visit_id}/photos")
async def upload_photo(visit_id: int, file: UploadFile = File(...)):
    db = SessionLocal()
    visit = db.get(SiteVisit, visit_id)
    project = db.get(Project, visit.project_id) if visit else None
    if not visit:
        db.close()
        raise HTTPException(404, "Site visit không tồn tại")

    allowed = {"image/jpeg", "image/png", "image/webp"}
    if file.content_type not in allowed:
        db.close()
        raise HTTPException(400, "Chỉ hỗ trợ JPG, PNG, WEBP")

    safe = os.path.basename(file.filename or "photo.jpg")
    stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
    filename = f"{stamp}_{safe}"
    path = UPLOADS / filename
    with open(path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    photo = Photo(
        visit_id=visit_id,
        filename=filename,
        path=f"/uploads/{filename}",
        mime_type=file.content_type,
        ai_status="UPLOADED",
    )
    db.add(photo)
    db.commit()
    db.refresh(photo)

    context = {
        "project_name": project.name if project else "",
        "floor": visit.floor,
        "zone": visit.zone,
        "work": visit.work,
        "note": visit.note or "",
    }

    try:
        result, raw = analyze_site_photo(path, file.content_type, context)
        photo.ai_description = result.get("description", "")
        photo.ai_work = result.get("work", "")
        photo.ai_location = result.get("location", "")
        photo.ai_progress = float(result.get("progress_percent", 0) or 0)
        photo.ai_quality_status = result.get("quality_status", "NOT_DETERMINED")
        photo.ai_issues = json.dumps(result.get("issues", []), ensure_ascii=False)
        photo.ai_recommended_action = result.get("recommended_action", "")
        photo.ai_safety_status = result.get("safety_status", "NOT_DETERMINED")
        photo.ai_confidence = float(result.get("confidence", 0) or 0)
        photo.ai_raw = raw
        photo.ai_status = "ANALYZED"
    except Exception as e:
        photo.ai_status = "ERROR"
        photo.ai_description = f"AI analysis failed: {str(e)}"

    db.commit()
    db.refresh(photo)
    result = photo_to_dict(photo)
    db.close()
    return JSONResponse(result)


@app.post("/api/v1/visits/{visit_id}/voice")
async def upload_voice(visit_id: int, file: UploadFile = File(...)):
    db = SessionLocal()
    visit = db.get(SiteVisit, visit_id)
    project = db.get(Project, visit.project_id) if visit else None
    if not visit:
        db.close()
        raise HTTPException(404, "Site visit không tồn tại")

    # Android Chrome commonly sends: audio/webm;codecs=opus
    # Gemini only needs the base MIME type. Normalize codec parameters before validation.
    raw_content_type = (file.content_type or "audio/webm").strip().lower()
    content_type = raw_content_type.split(";", 1)[0].strip()
    allowed = {
        "audio/webm", "audio/mp4", "audio/mpeg", "audio/wav",
        "audio/ogg", "audio/x-m4a", "audio/aac"
    }
    if content_type not in allowed:
        db.close()
        raise HTTPException(400, f"Định dạng audio chưa hỗ trợ: {raw_content_type}")

    ext_map = {
        "audio/webm": ".webm", "audio/mp4": ".mp4", "audio/mpeg": ".mp3",
        "audio/wav": ".wav", "audio/ogg": ".ogg", "audio/x-m4a": ".m4a",
        "audio/aac": ".aac"
    }
    ext = ext_map.get(content_type, ".webm")
    filename = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f") + ext
    path = EVIDENCE / filename
    with open(path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    voice = VoiceEvidence(
        visit_id=visit_id,
        filename=filename,
        path=f"/evidence/{filename}",
        mime_type=content_type,
        ai_status="UPLOADED",
    )
    db.add(voice)
    db.commit()
    db.refresh(voice)

    context = {
        "project_name": project.name if project else "",
        "floor": visit.floor,
        "zone": visit.zone,
        "work": visit.work,
    }
    try:
        result = transcribe_voice(path, content_type, context)
        voice.transcript = result.get("transcript", "")
        voice.ai_status = "ANALYZED"
    except Exception as e:
        voice.transcript = f"AI voice analysis failed: {str(e)}"
        voice.ai_status = "ERROR"

    db.commit()
    result = {
        "voice_id": voice.id,
        "path": voice.path,
        "status": voice.ai_status,
        "transcript": voice.transcript or "",
    }
    db.close()
    return JSONResponse(result)


@app.post("/api/v1/photos/{photo_id}/analyze")
def reanalyze_photo(photo_id: int):
    db = SessionLocal()
    photo = db.get(Photo, photo_id)
    if not photo:
        db.close()
        raise HTTPException(404, "Ảnh không tồn tại")
    visit = db.get(SiteVisit, photo.visit_id)
    project = db.get(Project, visit.project_id) if visit else None
    path = BASE / photo.path.lstrip("/")
    context = {
        "project_name": project.name if project else "",
        "floor": visit.floor if visit else "",
        "zone": visit.zone if visit else "",
        "work": visit.work if visit else "",
        "note": visit.note if visit else "",
    }
    try:
        result, raw = analyze_site_photo(path, photo.mime_type, context)
        photo.ai_description = result.get("description", "")
        photo.ai_work = result.get("work", "")
        photo.ai_location = result.get("location", "")
        photo.ai_progress = float(result.get("progress_percent", 0) or 0)
        photo.ai_quality_status = result.get("quality_status", "NOT_DETERMINED")
        photo.ai_issues = json.dumps(result.get("issues", []), ensure_ascii=False)
        photo.ai_recommended_action = result.get("recommended_action", "")
        photo.ai_safety_status = result.get("safety_status", "NOT_DETERMINED")
        photo.ai_confidence = float(result.get("confidence", 0) or 0)
        photo.ai_raw = raw
        photo.ai_status = "ANALYZED"
        db.commit()
    except Exception as e:
        photo.ai_status = "ERROR"
        photo.ai_description = str(e)
        db.commit()
    result = photo_to_dict(photo)
    db.close()
    return JSONResponse(result)


@app.get("/api/v1/photos/{photo_id}")
def get_photo(photo_id: int):
    db = SessionLocal()
    photo = db.get(Photo, photo_id)
    if not photo:
        db.close()
        raise HTTPException(404, "Ảnh không tồn tại")
    result = photo_to_dict(photo)
    db.close()
    return result


def photo_to_dict(p):
    try:
        issues = json.loads(p.ai_issues or "[]")
    except Exception:
        issues = [p.ai_issues] if p.ai_issues else []
    return {
        "photo_id": p.id,
        "visit_id": p.visit_id,
        "path": p.path,
        "status": p.ai_status,
        "work": p.ai_work,
        "location": p.ai_location,
        "progress_percent": p.ai_progress,
        "quality_status": p.ai_quality_status,
        "issues": issues,
        "recommended_action": p.ai_recommended_action,
        "safety_status": p.ai_safety_status,
        "description": p.ai_description,
        "confidence": p.ai_confidence,
    }


@app.get("/api/v1/reports/daily")
def daily_report():
    db = SessionLocal()
    visits = db.query(SiteVisit).all()
    photos = db.query(Photo).all()
    voices = db.query(VoiceEvidence).all()
    result = {
        "report_type": "DAILY",
        "date": datetime.now().strftime("%Y-%m-%d"),
        "visit_count": len(visits),
        "photo_count": len(photos),
        "voice_count": len(voices),
        "analyzed_photo_count": sum(1 for p in photos if p.ai_status == "ANALYZED"),
        "quality": {
            "OK": sum(1 for p in photos if p.ai_quality_status == "OK"),
            "ATTENTION": sum(1 for p in photos if p.ai_quality_status == "ATTENTION"),
            "DEFECT": sum(1 for p in photos if p.ai_quality_status == "DEFECT"),
            "PENDING": sum(1 for p in photos if p.ai_quality_status == "NOT_DETERMINED"),
        },
        "visits": [
            {
                "visit_id": v.id,
                "floor": v.floor,
                "zone": v.zone,
                "work": v.work,
                "note": v.note,
                "photos": [photo_to_dict(p) for p in photos if p.visit_id == v.id],
                "voices": [
                    {"voice_id": x.id, "transcript": x.transcript, "status": x.ai_status}
                    for x in voices if x.visit_id == v.id
                ],
            }
            for v in visits
        ],
    }
    db.close()
    return result


@app.get("/health")
def health():
    return {
        "status": "ok",
        "version": "0.1-pilot",
        "vision_provider": "gemini",
        "ai_configured": bool(os.getenv("GEMINI_API_KEY")),
        "model": os.getenv("GEMINI_MODEL", "gemini-3.7-flash"),
    }

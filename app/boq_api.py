"""BOQ module: web API + storage for the take-off workflow.

Bản vẽ → Shopdrawing → 3D → Thống kê → Bóc khối lượng → Excel
"""
import json
import os
import re
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy import Column, DateTime, Float, Integer, String, Text, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app import boq_engine as eng

BASE = Path(__file__).resolve().parent.parent
DATA = Path(os.getenv("APP_DATA_DIR") or BASE / "data")
DRAWINGS = DATA / "drawings"
DRAWINGS.mkdir(parents=True, exist_ok=True)

engine = create_engine(f"sqlite:///{DATA / 'boq.db'}", connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class BoqProject(Base):
    __tablename__ = "boq_projects"
    id = Column(Integer, primary_key=True)
    code = Column(String(50))
    name = Column(String(255), nullable=False)
    location = Column(String(255))
    prices = Column(Text, default="{}")
    created_at = Column(DateTime, default=datetime.utcnow)


class BoqDrawing(Base):
    __tablename__ = "boq_drawings"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, index=True)
    title = Column(String(255))
    filename = Column(String(255))
    path = Column(String(500))
    mime_type = Column(String(100))
    created_at = Column(DateTime, default=datetime.utcnow)


class BoqElement(Base):
    __tablename__ = "boq_elements"
    id = Column(Integer, primary_key=True)
    project_id = Column(Integer, index=True)
    type = Column(String(20))
    code = Column(String(50))
    floor = Column(String(50))
    n = Column(Integer, default=1)
    x = Column(Float, default=0)
    y = Column(Float, default=0)
    z = Column(Float, default=0)
    dx = Column(Float, default=0)
    dy = Column(Float, default=0)
    grade = Column(String(30))
    item_name = Column(String(255))
    unit = Column(String(30))
    params = Column(Text, default="{}")
    source = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(engine)

router = APIRouter(prefix="/api/v1/boq", tags=["BOQ"])

XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _db():
    return SessionLocal()


def _project(db, project_id: int) -> BoqProject:
    project = db.get(BoqProject, project_id)
    if not project:
        raise HTTPException(404, "Dự án BOQ không tồn tại")
    return project


def _to_element(row: BoqElement) -> eng.Element:
    return eng.Element.from_dict({
        "id": row.id, "type": row.type, "code": row.code, "floor": row.floor, "n": row.n,
        "x": row.x, "y": row.y, "z": row.z, "dx": row.dx, "dy": row.dy, "grade": row.grade,
        "item_name": row.item_name, "unit": row.unit, "params": json.loads(row.params or "{}"),
    })


def _elements(db, project_id: int) -> list[eng.Element]:
    rows = (db.query(BoqElement).filter(BoqElement.project_id == project_id)
            .order_by(BoqElement.id).all())
    return [_to_element(r) for r in rows]


def _apply(row: BoqElement, el: eng.Element):
    row.type, row.code, row.floor, row.n = el.type, el.code, el.floor, el.n
    row.x, row.y, row.z, row.dx, row.dy = el.x, el.y, el.z, el.dx, el.dy
    row.grade, row.item_name, row.unit = el.grade, el.item_name, el.unit
    row.params = json.dumps(el.params)


def _validate(d: dict) -> eng.Element:
    try:
        el = eng.Element.from_dict(d)
        eng.takeoff_element(el)  # surface geometry errors (e.g. opening > wall) now
        return el
    except eng.BoqError as exc:
        raise HTTPException(400, str(exc)) from None


def _project_dict(p: BoqProject) -> dict:
    return {"id": p.id, "code": p.code, "name": p.name, "location": p.location,
            "prices": json.loads(p.prices or "{}")}


def _slug(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", eng._strip_accents(text or "BOQ")).strip("_") or "BOQ"


# ---------------------------------------------------------------------------
# catalogue + projects
# ---------------------------------------------------------------------------


@router.get("/catalog")
def catalog():
    return {
        "element_types": {
            k: {"label": v["label"], "color": v["color"],
                "params": [{"key": pk, "label": lbl, "default": dv}
                           for pk, (lbl, dv) in v["params"].items()]}
            for k, v in eng.ELEMENT_TYPES.items()
        },
        "work_items": eng.WORK_ITEMS,
        "default_grade": eng.DEFAULT_GRADE,
    }


class ProjectIn(BaseModel):
    name: str
    code: str = ""
    location: str = ""


@router.get("/projects")
def list_projects():
    db = _db()
    try:
        return [_project_dict(p) for p in db.query(BoqProject).order_by(BoqProject.id.desc()).all()]
    finally:
        db.close()


@router.post("/projects")
def create_project(body: ProjectIn):
    if not body.name.strip():
        raise HTTPException(400, "Tên dự án không được trống")
    db = _db()
    try:
        p = BoqProject(name=body.name.strip(), code=body.code.strip(), location=body.location.strip())
        db.add(p)
        db.commit()
        db.refresh(p)
        return _project_dict(p)
    finally:
        db.close()


@router.get("/projects/{project_id}")
def get_project(project_id: int):
    db = _db()
    try:
        p = _project(db, project_id)
        drawings = (db.query(BoqDrawing).filter(BoqDrawing.project_id == project_id)
                    .order_by(BoqDrawing.id.desc()).all())
        return {
            **_project_dict(p),
            "drawings": [{"id": d.id, "title": d.title, "path": d.path, "mime_type": d.mime_type}
                         for d in drawings],
            "elements": [e.to_dict() for e in _elements(db, project_id)],
        }
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Step 1 — Bản vẽ: upload drawing, AI read, DXF / Excel import
# ---------------------------------------------------------------------------

DRAWING_TYPES = {"image/jpeg", "image/png", "image/webp", "application/pdf"}


@router.post("/projects/{project_id}/drawings")
async def upload_drawing(project_id: int, title: str = Form(""), file: UploadFile = File(...)):
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if content_type not in DRAWING_TYPES:
        raise HTTPException(400, "Bản vẽ hỗ trợ JPG, PNG, WEBP, PDF. File CAD dùng mục Nhập DXF.")
    db = _db()
    try:
        _project(db, project_id)
        safe = os.path.basename(file.filename or "drawing")
        filename = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f") + "_" + _slug(safe)
        ext = Path(safe).suffix.lower()
        if ext and not filename.endswith(ext):
            filename += ext
        path = DRAWINGS / filename
        path.write_bytes(await file.read())
        d = BoqDrawing(project_id=project_id, title=title or safe, filename=filename,
                       path=f"/drawings/{filename}", mime_type=content_type)
        db.add(d)
        db.commit()
        db.refresh(d)
        return {"id": d.id, "title": d.title, "path": d.path, "mime_type": d.mime_type}
    finally:
        db.close()


AI_PROMPT = """
Bạn là kỹ sư QS (dự toán) lập BOQ. Đọc bản vẽ kết cấu/kiến trúc được cung cấp và
liệt kê các cấu kiện để bóc khối lượng. CHỈ ghi nhận những gì đọc được rõ trên bản vẽ
(ký hiệu, kích thước, số lượng). Không bịa kích thước. Đơn vị: mét.

Loại cấu kiện (type) và tham số (params):
{types}

Trả về JSON: {{"elements": [{{"type": "COT", "code": "C1", "floor": "L01", "n": 4,
"grade": "B25", "params": {{"b": 0.3, "h": 0.3, "H": 3.6}},
"evidence": "trích dẫn ký hiệu/ghi chú trên bản vẽ"}}],
"notes": "những điểm chưa rõ cần kỹ sư kiểm tra"}}
Tầng gợi ý: {floor}
"""


@router.post("/drawings/{drawing_id}/ai-extract")
def ai_extract(drawing_id: int, floor: str = Form("")):
    from google.genai import types

    from app.main import generate_with_retry, get_client

    db = _db()
    try:
        d = db.get(BoqDrawing, drawing_id)
        if not d:
            raise HTTPException(404, "Bản vẽ không tồn tại")
        path = DRAWINGS / d.filename
        mime = d.mime_type
    finally:
        db.close()

    client = get_client()
    model = os.getenv("GEMINI_MODEL", "gemini-3.7-flash")
    type_text = "\n".join(
        f"- {k} ({v['label']}): " + ", ".join(f"{pk} = {lbl}" for pk, (lbl, _) in v["params"].items())
        for k, v in eng.ELEMENT_TYPES.items()
    )
    prompt = AI_PROMPT.format(types=type_text, floor=floor or "không rõ")
    part = types.Part.from_bytes(data=path.read_bytes(), mime_type=mime)
    try:
        response = generate_with_retry(lambda: client.models.generate_content(
            model=model, contents=[prompt, part],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        ))
        data = json.loads(_clean_json(response.text))
    except Exception as exc:
        raise HTTPException(502, f"AI không đọc được bản vẽ: {exc}") from None

    candidates, errors = [], []
    for i, raw in enumerate(data.get("elements", []) or [], start=1):
        try:
            raw = dict(raw)
            raw.setdefault("floor", floor)
            el = eng.Element.from_dict(raw)
            cand = el.to_dict()
            cand["source"] = f"AI · {d.title}"
            cand["evidence"] = str(raw.get("evidence", ""))
            candidates.append(cand)
        except (eng.BoqError, TypeError, ValueError) as exc:
            errors.append(f"Mục {i}: {exc}")
    return {"elements": candidates, "errors": errors, "notes": data.get("notes", "")}


def _clean_json(text: str) -> str:
    text = (text or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    return text


@router.post("/projects/{project_id}/import/dxf")
async def import_dxf(
    project_id: int,
    file: UploadFile = File(...),
    unit: str = Form("mm"),
    floor: str = Form(""),
    z: float = Form(0),
    H_cot: float = Form(3.6),
    h_dam: float = Form(0.5),
    t_san: float = Form(0.12),
    H_tuong: float = Form(3.2),
    H_mong: float = Form(0.5),
):
    scale = {"mm": 0.001, "cm": 0.01, "m": 1.0}.get(unit)
    if scale is None:
        raise HTTPException(400, "Đơn vị bản vẽ phải là mm, cm hoặc m")
    db = _db()
    try:
        _project(db, project_id)
    finally:
        db.close()
    try:
        return eng.import_dxf(await file.read(), unit_scale=scale, floor=floor, z=z,
                              defaults={"H_cot": H_cot, "h_dam": h_dam, "t_san": t_san,
                                        "H_tuong": H_tuong, "H_mong": H_mong})
    except eng.BoqError as exc:
        raise HTTPException(400, str(exc)) from None


@router.get("/template.xlsx")
def template():
    return Response(eng.template_workbook(), media_type=XLSX,
                    headers={"Content-Disposition": 'attachment; filename="Mau_nhap_cau_kien.xlsx"'})


@router.post("/projects/{project_id}/import/excel")
async def import_excel(project_id: int, file: UploadFile = File(...)):
    db = _db()
    try:
        _project(db, project_id)
    finally:
        db.close()
    try:
        return eng.import_template(await file.read())
    except eng.BoqError as exc:
        raise HTTPException(400, str(exc)) from None


# ---------------------------------------------------------------------------
# Step 2 — Shopdrawing: element CRUD + detail sketch
# ---------------------------------------------------------------------------


class ElementsIn(BaseModel):
    elements: list[dict]


@router.post("/projects/{project_id}/elements")
def add_elements(project_id: int, body: ElementsIn):
    if not body.elements:
        raise HTTPException(400, "Chưa có cấu kiện nào")
    validated = [_validate(d) for d in body.elements]
    db = _db()
    try:
        _project(db, project_id)
        rows = []
        for d, el in zip(body.elements, validated):
            row = BoqElement(project_id=project_id, source=str(d.get("source") or "Nhập tay")[:255])
            _apply(row, el)
            db.add(row)
            rows.append(row)
        db.commit()
        return {"added": len(rows), "ids": [r.id for r in rows]}
    finally:
        db.close()


@router.put("/elements/{element_id}")
def update_element(element_id: int, body: dict):
    el = _validate(body)
    db = _db()
    try:
        row = db.get(BoqElement, element_id)
        if not row:
            raise HTTPException(404, "Cấu kiện không tồn tại")
        _apply(row, el)
        db.commit()
        return _to_element(row).to_dict()
    finally:
        db.close()


@router.delete("/elements/{element_id}")
def delete_element(element_id: int):
    db = _db()
    try:
        row = db.get(BoqElement, element_id)
        if not row:
            raise HTTPException(404, "Cấu kiện không tồn tại")
        db.delete(row)
        db.commit()
        return {"deleted": element_id}
    finally:
        db.close()


@router.get("/elements/{element_id}/shop.svg")
def element_svg(element_id: int):
    db = _db()
    try:
        row = db.get(BoqElement, element_id)
        if not row:
            raise HTTPException(404, "Cấu kiện không tồn tại")
        return Response(eng.shop_svg(_to_element(row)), media_type="image/svg+xml")
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Steps 3–6 — 3D, thống kê, bóc khối lượng, Excel
# ---------------------------------------------------------------------------


@router.get("/projects/{project_id}/model3d")
def model3d(project_id: int):
    db = _db()
    try:
        _project(db, project_id)
        return eng.model3d(_elements(db, project_id))
    finally:
        db.close()


@router.get("/projects/{project_id}/stats")
def stats(project_id: int):
    db = _db()
    try:
        _project(db, project_id)
        return eng.statistics(_elements(db, project_id))
    finally:
        db.close()


@router.get("/projects/{project_id}/takeoff")
def takeoff(project_id: int):
    db = _db()
    try:
        p = _project(db, project_id)
        lines = eng.takeoff(_elements(db, project_id))
        return {"lines": [ln.to_dict() for ln in lines],
                "summary": eng.summarize(lines, json.loads(p.prices or "{}"))}
    finally:
        db.close()


class PricesIn(BaseModel):
    prices: dict[str, float]


@router.put("/projects/{project_id}/prices")
def set_prices(project_id: int, body: PricesIn):
    db = _db()
    try:
        p = _project(db, project_id)
        prices = {k: v for k, v in body.prices.items() if v and v > 0}
        p.prices = json.dumps(prices)
        db.commit()
        return {"prices": prices}
    finally:
        db.close()


@router.get("/projects/{project_id}/export.xlsx")
def export(project_id: int):
    db = _db()
    try:
        p = _project(db, project_id)
        data = eng.export_workbook(_project_dict(p), _elements(db, project_id),
                                   json.loads(p.prices or "{}"))
        name = f"BOQ_{_slug(p.code or p.name)}_{datetime.now():%Y%m%d}.xlsx"
        return Response(data, media_type=XLSX,
                        headers={"Content-Disposition": f'attachment; filename="{name}"'})
    finally:
        db.close()

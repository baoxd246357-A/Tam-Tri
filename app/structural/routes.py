import csv
import io
from typing import List

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

from app.branding import APP_SLUG

from .members import DIAMETERS
from .project import Member, build, combined_drawing

router = APIRouter()


class StructuralRequest(BaseModel):
    project: str = "Công trình"
    members: List[Member] = Field(min_length=1, max_length=200)


@router.get("/ket-cau", response_class=HTMLResponse)
def structural_page(request: Request):
    templates = request.app.state.templates
    return templates.TemplateResponse(request=request, name="ket_cau.html", context={"diameters": DIAMETERS})


@router.post("/api/v1/structural/calc")
def structural_calc(req: StructuralRequest):
    results, drawings, summary = build(req.members)
    for res, g in zip(results, drawings):
        res["svg"] = g.to_svg()
    return {"project": req.project, "members": results, "summary": summary}


@router.post("/api/v1/structural/export.dxf")
def structural_dxf(req: StructuralRequest):
    _, drawings, _ = build(req.members)
    dxf = combined_drawing(drawings).to_dxf()
    return Response(dxf.encode("ascii"), media_type="application/dxf",
                    headers={"Content-Disposition": f'attachment; filename="{APP_SLUG}_ban_ve.dxf"'})


@router.post("/api/v1/structural/export.csv")
def structural_csv(req: StructuralRequest):
    results, _, summary = build(req.members)
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow([f"BẢNG THỐNG KÊ CỐT THÉP — {req.project}"])
    w.writerow(["Cấu kiện", "Số hiệu", "Hình dạng", "Ø (mm)", "Chiều dài 1 thanh (mm)",
                "Số thanh/CK", "Số CK", "Tổng số thanh", "Tổng dài (m)", "Khối lượng (kg)", "Ghi chú"])
    for res in results:
        for r in res["schedule"]:
            w.writerow([r["member"], r["mark"], r["shape"], r["d"], r["length"], r["n_per_member"],
                        r["count"], r["n_total"], r["total_length_m"], r["weight_kg"], r["note"]])
    w.writerow([])
    w.writerow(["TỔNG HỢP"])
    for k, v in summary["steel_by_diameter_kg"].items():
        w.writerow([k, "", "", "", "", "", "", "", "", v])
    for k, v in summary["steel_by_group_kg"].items():
        w.writerow([f"Thép {k}", "", "", "", "", "", "", "", "", v])
    w.writerow(["Tổng thép (kg)", "", "", "", "", "", "", "", "", summary["steel_total_kg"]])
    w.writerow(["Bê tông (m³)", "", "", "", "", "", "", "", "", summary["concrete_m3"]])
    w.writerow(["Bê tông lót (m³)", "", "", "", "", "", "", "", "", summary["lean_concrete_m3"]])
    w.writerow(["Cốp pha (m²)", "", "", "", "", "", "", "", "", summary["formwork_m2"]])
    # BOM UTF-8 để Excel hiển thị đúng tiếng Việt
    return Response("\ufeff" + buf.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="{APP_SLUG}_thong_ke_thep.csv"'})

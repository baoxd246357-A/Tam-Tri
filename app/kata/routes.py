import csv
import io
from typing import Annotated, List

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

from .members import DIAMETERS, BeamInput, ColumnInput, build, combined_drawing

router = APIRouter()

MemberField = Annotated[BeamInput | ColumnInput, Field(discriminator="type")]


class KataRequest(BaseModel):
    project: str = "Công trình"
    members: List[MemberField] = Field(min_length=1, max_length=200)


@router.get("/kata", response_class=HTMLResponse)
def kata_page(request: Request):
    templates = request.app.state.templates
    return templates.TemplateResponse(request=request, name="kata.html", context={"diameters": DIAMETERS})


@router.post("/api/v1/kata/calc")
def kata_calc(req: KataRequest):
    results, drawings, summary = build(req.members)
    for res, g in zip(results, drawings):
        res["svg"] = g.to_svg()
    return {"project": req.project, "members": results, "summary": summary}


@router.post("/api/v1/kata/export.dxf")
def kata_dxf(req: KataRequest):
    _, drawings, _ = build(req.members)
    dxf = combined_drawing(drawings).to_dxf()
    return Response(dxf.encode("ascii"), media_type="application/dxf",
                    headers={"Content-Disposition": 'attachment; filename="kata_ban_ve.dxf"'})


@router.post("/api/v1/kata/export.csv")
def kata_csv(req: KataRequest):
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
    w.writerow(["Cốp pha (m²)", "", "", "", "", "", "", "", "", summary["formwork_m2"]])
    # BOM UTF-8 để Excel hiển thị đúng tiếng Việt
    return Response("﻿" + buf.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": 'attachment; filename="kata_thong_ke_thep.csv"'})

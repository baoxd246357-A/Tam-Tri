"""Điều phối các loại cấu kiện: tính thống kê thép, bản vẽ và tổng hợp khối lượng."""
from typing import Annotated, Union

from pydantic import Field

from .drawing import Drawing
from .members import (
    BeamInput, ColumnInput, beam_drawing, beam_quantities, beam_schedule,
    column_drawing, column_quantities, column_schedule,
)
from .slab_footing import (
    FootingInput, SlabInput, footing_drawing, footing_lean_concrete, footing_quantities,
    footing_schedule, slab_drawing, slab_quantities, slab_schedule,
)

Member = Annotated[Union[BeamInput, ColumnInput, SlabInput, FootingInput], Field(discriminator="type")]

HANDLERS = {
    "beam": (beam_schedule, beam_drawing, beam_quantities),
    "column": (column_schedule, column_drawing, column_quantities),
    "slab": (slab_schedule, slab_drawing, slab_quantities),
    "footing": (footing_schedule, footing_drawing, footing_quantities),
}


def process(m):
    schedule, drawing, quantities = HANDLERS[m.type]
    rows = schedule(m)
    concrete, formwork = quantities(m)
    lean = footing_lean_concrete(m) if m.type == "footing" else 0
    return {
        "name": m.name,
        "type": m.type,
        "count": m.count,
        "schedule": rows,
        "steel_kg": round(sum(r["weight_kg"] for r in rows), 2),
        "concrete_m3": round(concrete * m.count, 3),
        "formwork_m2": round(formwork * m.count, 2),
        "lean_concrete_m3": round(lean * m.count, 3),
    }, drawing(m)


def summarize(results):
    groups = {"D≤10": 0.0, "10<D≤18": 0.0, "D>18": 0.0}
    by_d = {}
    for res in results:
        for r in res["schedule"]:
            d, w = r["d"], r["weight_kg"]
            key = "D≤10" if d <= 10 else "10<D≤18" if d <= 18 else "D>18"
            groups[key] += w
            by_d[d] = by_d.get(d, 0) + w
    return {
        "steel_by_group_kg": {k: round(v, 2) for k, v in groups.items()},
        "steel_by_diameter_kg": {f"Ø{d}": round(by_d[d], 2) for d in sorted(by_d)},
        "steel_total_kg": round(sum(groups.values()), 2),
        "concrete_m3": round(sum(r["concrete_m3"] for r in results), 3),
        "lean_concrete_m3": round(sum(r["lean_concrete_m3"] for r in results), 3),
        "formwork_m2": round(sum(r["formwork_m2"] for r in results), 2),
    }


def build(members):
    results, drawings = [], []
    for m in members:
        res, g = process(m)
        results.append(res)
        drawings.append(g)
    return results, drawings, summarize(results)


def combined_drawing(drawings, gap=1500):
    """Xếp các bản vẽ cấu kiện từ trên xuống để xuất một file DXF."""
    out, y = Drawing(), 0
    for g in drawings:
        x0, y0, x1, y1 = g.bbox()
        out.merge(g, dx=-x0, dy=y - y1)
        y -= (y1 - y0) + gap
    return out

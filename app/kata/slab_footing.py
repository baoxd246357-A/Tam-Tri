"""Triển khai sàn (ô bản kê 4 cạnh) và móng đơn.

Quy ước cấu tạo (đơn giản hoá, kỹ sư cần kiểm tra lại theo TCVN 5574:2018 và hồ sơ thiết kế):
- Thép sàn lớp dưới neo vào dầm max(10d, bw/2), không vượt quá bw - lớp bảo vệ.
- Thép mũ sàn vươn L_ngắn/4 từ mép dầm, neo hết bề rộng dầm, hai đầu bẻ xuống chạm lớp dưới.
- Thép phân bố dưới thép mũ: Ø6a250.
- Lưới thép móng bẻ móc lên min(15d, h - 2·lớp bảo vệ) hai đầu.
- Thép chờ cột: chân bẻ max(15d, 150) đặt trên lưới móng, vươn khỏi cổ móng đoạn nối chồng 40d.
- Thanh đầu tiên cách mép 50 mm; số thanh làm tròn lên để khoảng cách không vượt bước thiết kế.
"""
import math
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from .drawing import Drawing
from .members import DIAMETERS, HOOK, LAP, Stirrup, _row, spread, stirrup_length

DIST_D, DIST_S = 6, 250
FIRST = 50


class Mesh(BaseModel):
    d: int = 8
    s: int = Field(200, ge=50, le=400, description="Bước thép (mm)")

    @model_validator(mode="after")
    def check_d(self):
        if self.d not in DIAMETERS:
            raise ValueError(f"Đường kính thép {self.d} không có trong {DIAMETERS}")
        return self


def bar_count(length, s, edge=FIRST):
    """Số thanh rải trên đoạn length, cách mép edge, bước không vượt s."""
    return math.ceil(max(length - 2 * edge, 0) / s) + 1


# --------------------------------------------------------------------------- sàn

class SlabInput(BaseModel):
    type: Literal["slab"] = "slab"
    name: str = "S1"
    count: int = Field(1, ge=1, le=500)
    lx: int = Field(3600, ge=500, le=12000, description="Cạnh ô sàn theo X, thông thuỷ (mm)")
    ly: int = Field(4200, ge=500, le=12000, description="Cạnh ô sàn theo Y, thông thuỷ (mm)")
    t: int = Field(100, ge=60, le=400, description="Chiều dày sàn (mm)")
    cover: int = Field(15, ge=10, le=50)
    bw: int = Field(220, ge=100, le=1000, description="Bề rộng dầm biên ô sàn (mm)")
    bottom_x: Mesh = Mesh()
    bottom_y: Mesh = Mesh()
    top: Mesh = Mesh()


def _slab_anchor(m: SlabInput, d):
    return min(m.bw - m.cover, max(10 * d, m.bw / 2))


def _slab_top_reach(m: SlabInput):
    return min(m.lx, m.ly) / 4


def slab_schedule(m: SlabInput):
    rows = []
    for mark, mesh, span, across, axis in (("1", m.bottom_x, m.lx, m.ly, "X"), ("2", m.bottom_y, m.ly, m.lx, "Y")):
        length = span + 2 * _slab_anchor(m, mesh.d)
        rows.append(_row(mark, m.name, "Thẳng", mesh.d, length, bar_count(across, mesh.s), m.count,
                         f"Lớp dưới theo {axis}, a{mesh.s}"))

    reach, leg = _slab_top_reach(m), m.t - 2 * m.cover
    top_len = reach + (m.bw - m.cover) + 2 * leg
    n_x_edges = 2 * bar_count(m.lx, m.top.s)  # thép mũ trên hai cạnh song song X
    n_y_edges = 2 * bar_count(m.ly, m.top.s)
    rows.append(_row("3.1", m.name, "Thép mũ, 2 chân", m.top.d, top_len, n_x_edges, m.count, f"Cạnh theo X, a{m.top.s}"))
    rows.append(_row("3.2", m.name, "Thép mũ, 2 chân", m.top.d, top_len, n_y_edges, m.count, f"Cạnh theo Y, a{m.top.s}"))

    n_dist = math.floor(reach / DIST_S) + 1
    rows.append(_row("4.1", m.name, "Phân bố", DIST_D, m.lx, 2 * n_dist, m.count, f"Dưới thép mũ cạnh X, a{DIST_S}"))
    rows.append(_row("4.2", m.name, "Phân bố", DIST_D, m.ly, 2 * n_dist, m.count, f"Dưới thép mũ cạnh Y, a{DIST_S}"))
    return rows


def slab_drawing(m: SlabInput):
    g = Drawing()
    lx, ly, bw, cv, t = m.lx, m.ly, m.bw, m.cover, m.t
    th = max(60, min(lx, ly) / 30)

    # Mặt bằng: ô sàn và dầm bao quanh
    g.rect(-bw, -bw, lx + 2 * bw, ly + 2 * bw)
    g.rect(0, 0, lx, ly)

    # Thép lớp dưới — vẽ thanh đại diện và đường phạm vi rải thép
    ax, ay = _slab_anchor(m, m.bottom_x.d), _slab_anchor(m, m.bottom_y.d)
    yb, xb = ly * 0.42, lx * 0.42
    g.line(-ax, yb, lx + ax, yb, "THEP")
    g.text(lx * 0.7, yb + th * 0.3, f"(1) Ø{m.bottom_x.d}a{m.bottom_x.s}", th, "THEP", "center")
    g.line(lx * 0.7, FIRST, lx * 0.7, ly - FIRST, "KICH_THUOC")
    g.line(xb, -ay, xb, ly + ay, "THEP")
    g.text(xb + th * 0.3, ly * 0.72, f"(2) Ø{m.bottom_y.d}a{m.bottom_y.s}", th, "THEP")
    g.line(FIRST, ly * 0.72 - th * 0.4, lx - FIRST, ly * 0.72 - th * 0.4, "KICH_THUOC")

    # Thép mũ tại giữa mỗi cạnh
    reach, back = _slab_top_reach(m), bw - cv
    label = f"(3) Ø{m.top.d}a{m.top.s}"
    g.line(lx / 2, -back, lx / 2, reach, "THEP")
    g.line(lx / 2, ly + back, lx / 2, ly - reach, "THEP")
    g.line(-back, ly / 2, reach, ly / 2, "THEP")
    g.line(lx + back, ly / 2, lx - reach, ly / 2, "THEP")
    g.text(lx / 2 + th * 0.3, reach * 0.5, label, th * 0.8, "THEP")
    g.text(lx / 2 + th * 0.3, ly - reach * 0.6, label, th * 0.8, "THEP")
    g.text(reach * 0.2, ly / 2 + th * 0.3, label, th * 0.8, "THEP")
    g.text(lx - reach * 0.2, ly / 2 + th * 0.3, label, th * 0.8, "THEP", "right")

    g.dim_h(0, lx, -bw - th * 1.5, height=th)
    g.dim_v(-bw - th * 1.5, 0, ly, height=th)
    g.text(lx / 2, ly + bw + th * 1.5, f"SÀN {m.name} ({lx}x{ly}, dày {t}) — SL: {m.count}", th * 1.3, "CHU", "center")

    # Mặt cắt 1-1 theo phương X
    sec = Drawing()
    hb = max(2.5 * t, 300)
    sec.rect(-bw, 0, lx + 2 * bw, t)
    for x in (-bw, lx):
        sec.rect(x, -hb, bw, hb)
    y1 = cv + m.bottom_x.d / 2
    sec.line(-ax, y1, lx + ax, y1, "THEP")
    y2 = cv + m.bottom_x.d + m.bottom_y.d / 2
    for x in spread(bar_count(lx, m.bottom_y.s), FIRST, lx - FIRST):
        sec.circle(x, y2, m.bottom_y.d / 2 + 2)
    yt = t - cv - m.top.d / 2
    for x0, x1 in ((-back, reach), (lx + back, lx - reach)):
        sec.polyline([(x0, cv), (x0, yt), (x1, yt), (x1, cv)], "THEP")
    sec.text(lx / 2, -th * 1.8, "MẶT CẮT 1-1", th, "CHU", "center")
    sec.dim_v(lx + bw + th, 0, t, height=th * 0.8)
    g.merge(sec, dy=-bw - th * 5 - t)
    return g


def slab_quantities(m: SlabInput):
    return m.lx * m.ly * m.t / 1e9, m.lx * m.ly / 1e6


# --------------------------------------------------------------------------- móng

class FootingInput(BaseModel):
    type: Literal["footing"] = "footing"
    name: str = "M1"
    count: int = Field(1, ge=1, le=500)
    a: int = Field(1800, ge=500, le=8000, description="Cạnh móng theo X (mm)")
    b: int = Field(1800, ge=500, le=8000, description="Cạnh móng theo Y (mm)")
    h: int = Field(500, ge=200, le=2500, description="Chiều cao đế móng (mm)")
    cover: int = Field(50, ge=25, le=100)
    lean: int = Field(100, ge=0, le=300, description="Chiều dày bê tông lót (mm)")
    mesh_x: Mesh = Mesh(d=12, s=150)
    mesh_y: Mesh = Mesh(d=12, s=150)
    col_b: int = Field(300, ge=150, le=2000, description="Cổ móng / cột theo X (mm)")
    col_h: int = Field(300, ge=150, le=2000, description="Cổ móng / cột theo Y (mm)")
    neck: int = Field(600, ge=0, le=5000, description="Chiều cao cổ móng (mm)")
    nx: int = Field(3, ge=2, le=12)
    ny: int = Field(3, ge=2, le=12)
    d: int = 18
    stirrup: Stirrup = Stirrup(d=8, s1=150, s2=200)

    @model_validator(mode="after")
    def check(self):
        if self.d not in DIAMETERS:
            raise ValueError(f"Đường kính thép {self.d} không có trong {DIAMETERS}")
        if self.col_b >= self.a or self.col_h >= self.b:
            raise ValueError("Cổ móng phải nhỏ hơn kích thước đế móng")
        return self


def _footing_hook(m: FootingInput, d):
    return min(HOOK * d, m.h - 2 * m.cover)


def _starter_foot(m: FootingInput):
    return max(15 * m.d, 150)


def _neck_stirrups(m: FootingInput):
    """Đai cổ móng: rải đều bước s1 suốt cổ móng, thêm 2 đai giữ thép chờ trong đế móng."""
    if m.neck <= 0:
        return 2
    return bar_count(m.neck, m.stirrup.s1) + 2


def footing_schedule(m: FootingInput):
    cv = m.cover
    rows = []
    for mark, mesh, along, across, axis in (("1", m.mesh_x, m.a, m.b, "X"), ("2", m.mesh_y, m.b, m.a, "Y")):
        length = along - 2 * cv + 2 * _footing_hook(m, mesh.d)
        rows.append(_row(mark, m.name, "Móc 2 đầu", mesh.d, length, bar_count(across, mesh.s, cv), m.count,
                         f"Lưới đáy theo {axis}, a{mesh.s}"))
    embed = m.h - cv - m.mesh_x.d - m.mesh_y.d
    starter = embed + m.neck + LAP * m.d + _starter_foot(m)
    rows.append(_row("3", m.name, "Thép chờ, chân bẻ", m.d, starter, 2 * m.nx + 2 * m.ny - 4, m.count,
                     f"Chờ nối chồng {LAP}d"))
    s = m.stirrup
    rows.append(_row("4", m.name, "Đai kín", s.d, stirrup_length(m.col_b, m.col_h, 25, s.d), _neck_stirrups(m),
                     m.count, f"Cổ móng a{s.s1}"))
    return rows


def footing_drawing(m: FootingInput):
    g = Drawing()
    a, b, h, cv, neck = m.a, m.b, m.h, m.cover, m.neck
    th = max(60, a / 25)
    x0 = (a - m.col_b) / 2
    x1 = x0 + m.col_b

    # Mặt cắt 1-1 theo X
    if m.lean:
        g.rect(-100, -m.lean, a + 200, m.lean)
    g.rect(0, 0, a, h)
    g.polyline([(x0, h), (x0, h + neck + 300)])
    g.polyline([(x1, h), (x1, h + neck + 300)])
    g.line(x0 - 50, h + neck, x1 + 50, h + neck, "TRUC")

    hk = _footing_hook(m, m.mesh_x.d)
    yx = cv + m.mesh_x.d / 2
    g.polyline([(cv, yx + hk), (cv, yx), (a - cv, yx), (a - cv, yx + hk)], "THEP")
    g.text(a * 0.25, yx + th * 0.4, f"(1) Ø{m.mesh_x.d}a{m.mesh_x.s}", th, "THEP", "center")
    yy = cv + m.mesh_x.d + m.mesh_y.d / 2
    for x in spread(bar_count(a, m.mesh_y.s, cv), cv + m.mesh_y.d, a - cv - m.mesh_y.d):
        g.circle(x, yy, m.mesh_y.d / 2 + 2)
    g.text(a * 0.75, yy + th * 0.6, f"(2) Ø{m.mesh_y.d}a{m.mesh_y.s}", th, "THEP", "center")

    yf = yy + m.mesh_y.d / 2 + m.d / 2
    top = h + neck + LAP * m.d
    foot = _starter_foot(m)
    for x, sign in ((x0 + 25 + m.stirrup.d + m.d / 2, -1), (x1 - 25 - m.stirrup.d - m.d / 2, 1)):
        g.polyline([(x + sign * foot, yf), (x, yf), (x, top)], "THEP")
    g.text(x1 + th * 0.5, h + neck + LAP * m.d / 2, f"(3) {2 * m.nx + 2 * m.ny - 4}Ø{m.d}", th, "THEP")

    ys = [h - cv - 100, cv + m.mesh_x.d + m.mesh_y.d + 100]
    if neck > 0:
        ys += spread(bar_count(neck, m.stirrup.s1), h + FIRST, h + neck - FIRST)
    for y in ys:
        g.line(x0 + 25, y, x1 - 25, y, "THEP_DAI")
    if neck > 0:
        g.text(x0 - th * 0.5, h + neck / 2, f"(4) Ø{m.stirrup.d}a{m.stirrup.s1}", th * 0.8, "THEP_DAI", "right")

    g.dim_h(0, a, -m.lean - th * 1.5, height=th)
    g.dim_v(-th * 2, 0, h, height=th)
    if neck > 0:
        g.dim_v(-th * 2, h, h + neck, height=th)
    g.text(a / 2, -m.lean - th * 4, "MẶT CẮT 1-1", th, "CHU", "center")
    g.text(a / 2, top + th * 1.5, f"MÓNG {m.name} ({a}x{b}x{h}) — SL: {m.count}", th * 1.2, "CHU", "center")

    # Mặt bằng lưới thép
    plan = Drawing()
    plan.rect(0, 0, a, b)
    plan.rect((a - m.col_b) / 2, (b - m.col_h) / 2, m.col_b, m.col_h)
    for y in spread(bar_count(b, m.mesh_x.s, cv), cv, b - cv):
        plan.line(cv, y, a - cv, y, "THEP")
    for x in spread(bar_count(a, m.mesh_y.s, cv), cv, a - cv):
        plan.line(x, cv, x, b - cv, "THEP")
    plan.dim_h(0, a, -th * 1.2, height=th)
    plan.dim_v(-th * 1.2, 0, b, height=th)
    plan.text(a / 2, -th * 3.5, "MẶT BẰNG LƯỚI THÉP", th, "CHU", "center")
    g.merge(plan, dx=a + th * 8, dy=0)
    return g


def footing_quantities(m: FootingInput):
    concrete = (m.a * m.b * m.h + m.col_b * m.col_h * m.neck) / 1e9
    formwork = (2 * (m.a + m.b) * m.h + 2 * (m.col_b + m.col_h) * m.neck) / 1e6
    return concrete, formwork


def footing_lean_concrete(m: FootingInput):
    return (m.a + 200) * (m.b + 200) * m.lean / 1e9

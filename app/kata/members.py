"""Triển khai cấu kiện dầm / cột: bố trí thép, bản vẽ và bảng thống kê thép.

Quy ước cấu tạo (đơn giản hoá, kỹ sư cần kiểm tra lại theo TCVN 5574:2018 và hồ sơ thiết kế):
- Neo thép dưới vào gối: LA_BOTTOM·d; móc thép tại gối biên: HOOK·d.
- Thép mũ (tăng cường gối) vươn L/4 nhịp thông thuỷ mỗi bên.
- Đai dầm: đoạn gia cường L/4 ở hai đầu nhịp với bước s1, giữa nhịp bước s2.
- Đai cột: đoạn gia cường max(b, h, H/6, 500) ở chân và đỉnh cột.
- Thép dài hơn cây thép tiêu chuẩn 11,7 m được nối chồng LAP·d.
"""
import math
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, model_validator

from .drawing import Drawing

STOCK_LENGTH = 11700  # mm, chiều dài cây thép thương phẩm
LA_BOTTOM = 25
HOOK = 15
LAP = 40
STEEL_DENSITY = 7850  # kg/m3
DIAMETERS = (6, 8, 10, 12, 14, 16, 18, 20, 22, 25, 28, 32)


def unit_weight(d):
    """Khối lượng thép tròn (kg/m)."""
    return STEEL_DENSITY * math.pi * d * d / 4 / 1e6


def with_laps(length, d):
    """Cộng thêm chiều dài nối chồng khi thanh dài hơn cây thép tiêu chuẩn."""
    laps = max(math.ceil(length / STOCK_LENGTH) - 1, 0)
    return length + laps * LAP * d, laps


def spread(n, start, end):
    """Vị trí n thanh chia đều trong đoạn [start, end]."""
    if n == 1:
        return [(start + end) / 2]
    return [start + i * (end - start) / (n - 1) for i in range(n)]


def stirrup_length(b, h, cover, ds):
    """Chiều dài cắt thép đai kín, móc 135° mỗi đầu lấy max(10ds, 75)."""
    return 2 * ((b - 2 * cover) + (h - 2 * cover)) + 2 * max(10 * ds, 75)


def stirrup_positions(x0, x1, zone, s1, s2, first=50):
    """Vị trí đai trong đoạn [x0, x1]: dày ở hai đầu (zone), thưa ở giữa."""
    length = x1 - x0
    zone = min(zone, length / 2)
    n_end = int((zone - first) // s1) + 1 if zone > first else 1
    left = [x0 + first + i * s1 for i in range(n_end)]
    right = [x1 - first - i * s1 for i in range(n_end)]
    a, b = left[-1], right[-1]
    mid = []
    if b - a > s2:
        n_gap = math.ceil((b - a) / s2)
        step = (b - a) / n_gap
        mid = [a + i * step for i in range(1, n_gap)]
    return sorted(set(round(p, 1) for p in left + mid + right))


class Bars(BaseModel):
    n: int = Field(ge=1, le=20)
    d: int

    @model_validator(mode="after")
    def check_d(self):
        if self.d not in DIAMETERS:
            raise ValueError(f"Đường kính thép {self.d} không có trong {DIAMETERS}")
        return self


class Stirrup(BaseModel):
    d: int = 8
    s1: int = Field(100, ge=50, le=400, description="Bước đai vùng gia cường")
    s2: int = Field(200, ge=50, le=500, description="Bước đai vùng giữa")


class BeamInput(BaseModel):
    type: Literal["beam"] = "beam"
    name: str = "D1"
    count: int = Field(1, ge=1, le=500, description="Số cấu kiện giống nhau")
    b: int = Field(220, ge=100, le=2000)
    h: int = Field(400, ge=150, le=3000)
    cover: int = Field(25, ge=15, le=75)
    spans: List[int] = Field([4500], min_length=1, max_length=12, description="Nhịp thông thuỷ (mm)")
    supports: List[int] = Field([220], min_length=1, description="Bề rộng các gối/cột (mm); 1 giá trị = mọi gối")
    bottom: Bars = Bars(n=2, d=18)
    top: Bars = Bars(n=2, d=16)
    top_add: Optional[Bars] = Bars(n=2, d=16)
    stirrup: Stirrup = Stirrup()

    @model_validator(mode="after")
    def check(self):
        if len(self.supports) == 1:
            self.supports = self.supports * (len(self.spans) + 1)
        if len(self.supports) != len(self.spans) + 1:
            raise ValueError("Số gối phải bằng số nhịp + 1")
        if any(s < 500 for s in self.spans):
            raise ValueError("Nhịp phải ≥ 500 mm")
        if any(c < 100 for c in self.supports):
            raise ValueError("Bề rộng gối phải ≥ 100 mm")
        return self


class ColumnInput(BaseModel):
    type: Literal["column"] = "column"
    name: str = "C1"
    count: int = Field(1, ge=1, le=500)
    b: int = Field(300, ge=150, le=2000)
    h: int = Field(300, ge=150, le=2000)
    height: int = Field(3300, ge=1000, le=12000, description="Chiều cao tầng (mm)")
    cover: int = Field(25, ge=15, le=75)
    nx: int = Field(3, ge=2, le=12, description="Số thanh trên cạnh b (kể cả góc)")
    ny: int = Field(3, ge=2, le=12, description="Số thanh trên cạnh h (kể cả góc)")
    d: int = 18
    stirrup: Stirrup = Stirrup()

    @model_validator(mode="after")
    def check(self):
        if self.d not in DIAMETERS:
            raise ValueError(f"Đường kính thép {self.d} không có trong {DIAMETERS}")
        return self


def _row(mark, name, shape, d, length, n_per, count, note=""):
    length = round(length)
    total_n = n_per * count
    total_m = length * total_n / 1000
    return {
        "mark": mark,
        "member": name,
        "shape": shape,
        "d": d,
        "length": length,
        "n_per_member": n_per,
        "count": count,
        "n_total": total_n,
        "total_length_m": round(total_m, 2),
        "weight_kg": round(total_m * unit_weight(d), 2),
        "note": note,
    }


# --------------------------------------------------------------------------- dầm

def beam_layout(m: BeamInput):
    """Toạ độ các gối theo trục x, gốc tại mép trái gối đầu tiên."""
    faces = []  # (mép trái gối, mép phải gối)
    x = 0
    for i, c in enumerate(m.supports):
        faces.append((x, x + c))
        x += c + (m.spans[i] if i < len(m.spans) else 0)
    return faces, x


def beam_schedule(m: BeamInput):
    faces, total = beam_layout(m)
    cv, rows = m.cover, []
    n_sp = len(m.spans)

    # 1. Thép chịu lực dưới — mỗi nhịp một thanh, neo vào gối
    d = m.bottom.d
    for j in range(n_sp):
        x0, x1 = _bottom_bar_extent(m, faces, total, j)
        hooks = sum(1 for x in (x0, x1) if x in (cv, total - cv)) * HOOK * d
        cut, laps = with_laps(x1 - x0 + hooks, d)
        rows.append(_row(f"1.{j + 1}", m.name, "Thẳng" + (", móc" if hooks else ""), d, cut,
                         m.bottom.n, m.count, f"Nhịp {j + 1}" + (f", {laps} mối nối" if laps else "")))

    # 2. Thép chịu lực trên — chạy suốt, móc xuống ở hai đầu
    d = m.top.d
    cut, laps = with_laps(total - 2 * cv + 2 * HOOK * d, d)
    rows.append(_row("2", m.name, "Móc 2 đầu", d, cut, m.top.n, m.count,
                     "Chạy suốt" + (f", {laps} mối nối" if laps else "")))

    # 3. Thép mũ tại gối
    if m.top_add:
        d = m.top_add.d
        for i in range(len(faces)):
            x0, x1 = _top_add_extent(m, faces, total, i)
            hooks = sum(1 for x in (x0, x1) if x in (cv, total - cv)) * HOOK * d
            rows.append(_row(f"3.{i + 1}", m.name, "Thép mũ" + (", móc" if hooks else ""), d,
                             x1 - x0 + hooks, m.top_add.n, m.count, f"Gối {i + 1}"))

    # 4. Thép đai
    s = m.stirrup
    n = sum(len(_beam_stirrups(m, faces, j)) for j in range(n_sp))
    rows.append(_row("4", m.name, "Đai kín", s.d, stirrup_length(m.b, m.h, cv, s.d), n, m.count,
                     f"a{s.s1}/a{s.s2}"))
    return rows


def _bottom_bar_extent(m, faces, total, j):
    la = LA_BOTTOM * m.bottom.d
    left = max(faces[j][1] - la, m.cover)
    right = min(faces[j + 1][0] + la, total - m.cover)
    return left, right


def _top_add_extent(m, faces, total, i):
    l, r = faces[i]
    left_span = m.spans[i - 1] if i > 0 else 0
    right_span = m.spans[i] if i < len(m.spans) else 0
    x0 = l - left_span / 4 if left_span else m.cover
    x1 = r + right_span / 4 if right_span else total - m.cover
    return x0, x1


def _beam_stirrups(m, faces, j):
    x0, x1 = faces[j][1], faces[j + 1][0]
    return stirrup_positions(x0, x1, (x1 - x0) / 4, m.stirrup.s1, m.stirrup.s2)


def beam_drawing(m: BeamInput):
    faces, total = beam_layout(m)
    g = Drawing()
    cv, h = m.cover, m.h
    th = max(60, h / 7)

    # Bê tông: dầm và cột tại gối (vẽ cắt ngắn)
    g.rect(0, 0, total, h)
    for l, r in faces:
        g.line(l, -h * 0.8, l, 0)
        g.line(r, -h * 0.8, r, 0)
        g.line(l, h, l, h + h * 0.5)
        g.line(r, h, r, h + h * 0.5)
        g.line((l + r) / 2, -h, (l + r) / 2, h * 1.7, "TRUC")

    # Thép dưới
    y = cv + m.bottom.d / 2
    for j in range(len(m.spans)):
        x0, x1 = _bottom_bar_extent(m, faces, total, j)
        yj = y + (m.bottom.d if j % 2 else 0)  # lệch nhẹ để thấy đoạn chồng tại gối
        g.line(x0, yj, x1, yj, "THEP")
        for x in (x0, x1):
            if x in (cv, total - cv):
                g.line(x, yj, x, yj + HOOK * m.bottom.d, "THEP")
        g.text((faces[j][1] + faces[j + 1][0]) / 2, yj + th * 0.4, f"(1) {m.bottom.n}Ø{m.bottom.d}", th, "THEP", "center")

    # Thép trên chạy suốt
    yt = h - cv - m.top.d / 2
    hk = HOOK * m.top.d
    g.polyline([(cv, yt - hk), (cv, yt), (total - cv, yt), (total - cv, yt - hk)], "THEP")
    g.text(total / 2, h + th * 0.6, f"(2) {m.top.n}Ø{m.top.d}", th, "THEP", "center")

    # Thép mũ
    if m.top_add:
        ya = yt - m.top.d - 25
        hk = HOOK * m.top_add.d
        for i in range(len(faces)):
            x0, x1 = _top_add_extent(m, faces, total, i)
            pts = [(x0, ya), (x1, ya)]
            if x0 == cv:
                pts.insert(0, (x0, ya - hk))
            if x1 == total - cv:
                pts.append((x1, ya - hk))
            g.polyline(pts, "THEP")
            g.text((x0 + x1) / 2, ya - th * 1.3, f"(3) {m.top_add.n}Ø{m.top_add.d}", th * 0.8, "THEP", "center")

    # Thép đai
    s = m.stirrup
    for j in range(len(m.spans)):
        x0, x1 = faces[j][1], faces[j + 1][0]
        for x in _beam_stirrups(m, faces, j):
            g.line(x, cv, x, h - cv, "THEP_DAI")
        z = (x1 - x0) / 4
        g.text(x0 + z / 2, -th * 1.6, f"Ø{s.d}a{s.s1}", th * 0.8, "THEP_DAI", "center")
        g.text((x0 + x1) / 2, -th * 1.6, f"Ø{s.d}a{s.s2}", th * 0.8, "THEP_DAI", "center")
        g.text(x1 - z / 2, -th * 1.6, f"Ø{s.d}a{s.s1}", th * 0.8, "THEP_DAI", "center")
        g.dim_h(x0, x1, -h * 0.8 - th * 2, height=th)

    g.dim_h(0, total, -h * 0.8 - th * 4.5, height=th)
    g.dim_v(-th * 1.5, 0, h, height=th)
    g.text(total / 2, h * 1.7 + th * 1.5, f"DẦM {m.name} ({m.b}x{m.h}) — SL: {m.count}", th * 1.4, "CHU", "center")

    # Mặt cắt gối (1-1) và giữa nhịp (2-2)
    sy = -h * 0.8 - th * 7 - h
    top_sup = [m.top] + ([m.top_add] if m.top_add else [])
    for k, (label, tops) in enumerate((("1-1 (GỐI)", top_sup), ("2-2 (NHỊP)", [m.top]))):
        sec = section(m.b, m.h, cv, m.stirrup.d, tops, [m.bottom], th)
        sec.text(m.b / 2, -th * 2, f"MẶT CẮT {label}", th, "CHU", "center")
        g.merge(sec, dx=k * (m.b + th * 12), dy=sy)
    return g


def section(b, h, cv, ds, top_layers, bottom_layers, th):
    """Mặt cắt chữ nhật với các lớp thép trên/dưới."""
    g = Drawing()
    g.rect(0, 0, b, h)
    g.rect(cv, cv, b - 2 * cv, h - 2 * cv, "THEP_DAI")
    inner = cv + ds

    def layer(bars, y):
        r = bars.d / 2
        for x in spread(bars.n, inner + r, b - inner - r):
            g.circle(x, y, r)

    y = h - inner
    for bars in top_layers:
        layer(bars, y - bars.d / 2)
        g.text(b + th * 0.5, y - bars.d, f"{bars.n}Ø{bars.d}", th * 0.8, "THEP")
        y -= bars.d + 25
    y = inner
    for bars in bottom_layers:
        layer(bars, y + bars.d / 2)
        g.text(b + th * 0.5, y, f"{bars.n}Ø{bars.d}", th * 0.8, "THEP")
        y += bars.d + 25
    g.dim_h(0, b, -th * 0.8, height=th * 0.8)
    g.dim_v(-th * 0.8, 0, h, height=th * 0.8)
    return g


# --------------------------------------------------------------------------- cột

def column_bars(m: ColumnInput):
    return 2 * m.nx + 2 * m.ny - 4


def _column_stirrups(m):
    zone = max(m.b, m.h, m.height / 6, 500)
    return stirrup_positions(0, m.height, zone, m.stirrup.s1, m.stirrup.s2), zone


def column_schedule(m: ColumnInput):
    cut, laps = with_laps(m.height + LAP * m.d, m.d)
    s = m.stirrup
    pos, _ = _column_stirrups(m)
    n_ties = sum(1 for k in (m.nx, m.ny) if k > 3)  # đai móc / đai phụ khi cạnh có > 3 thanh
    rows = [
        _row("1", m.name, "Thẳng", m.d, cut, column_bars(m), m.count,
             f"Nối chồng {LAP}d" + (f", {laps} mối nối thêm" if laps else "")),
        _row("2", m.name, "Đai kín", s.d, stirrup_length(m.b, m.h, m.cover, s.d), len(pos), m.count,
             f"a{s.s1}/a{s.s2}"),
    ]
    if n_ties:
        tie = max(m.b, m.h) - 2 * m.cover + 2 * max(10 * s.d, 75)
        rows.append(_row("3", m.name, "Đai móc", s.d, tie, len(pos) * n_ties, m.count, "Giằng thanh giữa"))
    return rows


def column_drawing(m: ColumnInput):
    g = Drawing()
    b, H, cv = m.b, m.height, m.cover
    th = max(60, b / 5)
    lap = LAP * m.d

    g.rect(0, 0, b, H)
    g.line(-b * 0.8, 0, b * 1.8, 0, "TRUC")
    g.line(-b * 0.8, H, b * 1.8, H, "TRUC")
    # Thép dọc: đoạn chờ nối chồng phía trên, bẻ lệch vào trong
    for x, sign in ((cv + m.d / 2, 1), (b - cv - m.d / 2, -1)):
        g.polyline([(x, 0), (x, H - 150), (x + sign * m.d, H), (x + sign * m.d, H + lap)], "THEP")
    g.text(b + th * 0.5, H + lap / 2, f"(1) {column_bars(m)}Ø{m.d}", th, "THEP")
    g.dim_v(b + th * 4, H, H + lap, f"{lap}", height=th * 0.8)

    pos, zone = _column_stirrups(m)
    for y in pos:
        g.line(cv, y, b - cv, y, "THEP_DAI")
    s = m.stirrup
    g.text(-th * 0.5, zone / 2, f"Ø{s.d}a{s.s1}", th * 0.8, "THEP_DAI", "right")
    g.text(-th * 0.5, H / 2, f"Ø{s.d}a{s.s2}", th * 0.8, "THEP_DAI", "right")
    g.text(-th * 0.5, H - zone / 2, f"Ø{s.d}a{s.s1}", th * 0.8, "THEP_DAI", "right")
    g.dim_v(-th * 6, 0, H, height=th)
    g.text(b / 2, H + lap + th * 1.5, f"CỘT {m.name} ({m.b}x{m.h}) — SL: {m.count}", th * 1.2, "CHU", "center")

    # Mặt cắt cột
    sec = Drawing()
    sec.rect(0, 0, m.b, m.h)
    sec.rect(cv, cv, m.b - 2 * cv, m.h - 2 * cv, "THEP_DAI")
    inner, r = cv + s.d + m.d / 2, m.d / 2
    xs = spread(m.nx, inner, m.b - inner)
    ys = spread(m.ny, inner, m.h - inner)
    pts = {(x, ys[0]) for x in xs} | {(x, ys[-1]) for x in xs} | {(xs[0], y) for y in ys} | {(xs[-1], y) for y in ys}
    for x, y in pts:
        sec.circle(x, y, r)
    sec.dim_h(0, m.b, -th * 0.8, height=th * 0.8)
    sec.dim_v(-th * 0.8, 0, m.h, height=th * 0.8)
    sec.text(m.b / 2, -th * 2.5, "MẶT CẮT 1-1", th, "CHU", "center")
    g.merge(sec, dx=b + th * 10, dy=H / 2 - m.h / 2)
    return g


def beam_quantities(m: BeamInput):
    length = sum(m.spans)
    return m.b * m.h * length / 1e9, (m.b + 2 * m.h) * length / 1e6


def column_quantities(m: ColumnInput):
    return m.b * m.h * m.height / 1e9, 2 * (m.b + m.h) * m.height / 1e6

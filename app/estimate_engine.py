"""Dự toán / QS engine: BOQ (khối lượng) × định mức × giá → dự toán.

Pure Python (no database / web), testable on its own.

Model
-----
* Tài nguyên (resource): vật liệu (VL), nhân công (NC), máy thi công (M), with a price.
* Định mức (norm): hao phí tài nguyên cho 1 đơn vị định mức (e.g. per m3, per 100m2).
* Ánh xạ (mapping): BOQ work item → norm code. Looked up by exact item key
  ("BT_COT|B25"), then by work-item code ("BT_COT").
* Items without a norm may use a direct unit price (đơn giá nhập trực tiếp, bucket K).

Cost structure (layout of TT 11/2021/TT-BXD; every rate is editable):
    T  = VL + NC + M + K                  chi phí trực tiếp
    GT = C + LT + TT  (each = T × rate)   chi phí gián tiếp
    TL = (T + GT) × rate                  thu nhập chịu thuế tính trước
    G  = T + GT + TL                      giá trị dự toán trước thuế
    GTGT = G × VAT;  Gxd = G + GTGT
    DP = Gxd × rate;  Tổng = Gxd + DP
"""
from __future__ import annotations

import io
import re
from collections import OrderedDict
from dataclasses import dataclass, field

from app.boq_engine import BoqError, _num, wbs_parent

KINDS = OrderedDict([("VL", "Vật liệu"), ("NC", "Nhân công"), ("M", "Máy thi công")])

# key -> (name, default %, base). Defaults are a starting point only: check them
# against TT 11/2021 Phụ lục 3 for the project type before issuing an estimate.
DEFAULT_RATES = OrderedDict([
    ("C", ("Chi phí chung", 6.5)),
    ("LT", ("Chi phí nhà tạm để ở và điều hành thi công", 1.1)),
    ("TT", ("Chi phí một số công việc không xác định được khối lượng từ thiết kế", 2.5)),
    ("TL", ("Thu nhập chịu thuế tính trước", 5.5)),
    ("VAT", ("Thuế giá trị gia tăng", 10.0)),
    ("DP", ("Chi phí dự phòng", 0.0)),
])


@dataclass
class Resource:
    code: str
    name: str
    unit: str
    kind: str
    price: float = 0.0

    def to_dict(self) -> dict:
        return {"code": self.code, "name": self.name, "unit": self.unit,
                "kind": self.kind, "price": self.price}


@dataclass
class Norm:
    code: str
    name: str
    unit: str
    items: list = field(default_factory=list)  # [(resource_code, consumption)]

    def to_dict(self) -> dict:
        return {"code": self.code, "name": self.name, "unit": self.unit,
                "items": [{"resource": r, "qty": q} for r, q in self.items]}


@dataclass
class Library:
    resources: "OrderedDict[str, Resource]" = field(default_factory=OrderedDict)
    norms: "OrderedDict[str, Norm]" = field(default_factory=OrderedDict)
    mapping: dict = field(default_factory=dict)  # BOQ item key/code -> norm code

    def to_dict(self) -> dict:
        return {"resources": [r.to_dict() for r in self.resources.values()],
                "norms": [n.to_dict() for n in self.norms.values()],
                "mapping": dict(self.mapping)}

    @classmethod
    def from_dict(cls, d: dict) -> "Library":
        lib = cls()
        for r in d.get("resources", []):
            res = make_resource(r.get("code"), r.get("name"), r.get("unit"), r.get("kind"),
                                r.get("price", 0))
            lib.resources[res.code] = res
        for n in d.get("norms", []):
            norm = Norm(str(n["code"]).strip(), str(n.get("name") or n["code"]).strip(),
                        str(n.get("unit") or "").strip())
            for it in n.get("items", []):
                norm.items.append((str(it["resource"]).strip(), _num(it["qty"], "Hao phí")))
            lib.norms[norm.code] = norm
        lib.mapping = {str(k): str(v) for k, v in (d.get("mapping") or {}).items() if v}
        return lib


def make_resource(code, name, unit, kind, price=0) -> Resource:
    code = str(code or "").strip()
    if not code:
        raise BoqError("Mã tài nguyên không được trống")
    kind = str(kind or "").strip().upper()
    if kind not in KINDS:
        raise BoqError(f"Tài nguyên {code}: loại phải là VL, NC hoặc M (đang là '{kind}')")
    price = _num(price if price not in (None, "") else 0, f"Đơn giá {code}")
    if price < 0:
        raise BoqError(f"Đơn giá {code} không được âm")
    return Resource(code, str(name or code).strip(), str(unit or "").strip(), kind, price)


# ---------------------------------------------------------------------------
# Units: "100m2" norm vs "m2" BOQ item → factor 0.01
# ---------------------------------------------------------------------------

_UNIT_ALIASES = {"m³": "m3", "m²": "m2", "tấn": "tan", "t": "tan", "tan": "tan",
                 "công": "cong", "ca": "ca", "cái": "cai", "bộ": "bo"}


def _split_unit(unit: str) -> tuple[float, str]:
    text = str(unit or "").strip().lower().replace(" ", "")
    m = re.match(r"^(\d+(?:[.,]\d+)?)(.*)$", text)
    mult = 1.0
    if m and m.group(2):
        mult = float(m.group(1).replace(",", "."))
        text = m.group(2)
    return mult, _UNIT_ALIASES.get(text, text)


def unit_factor(item_unit: str, norm_unit: str) -> float | None:
    """Norm units per 1 BOQ unit, or None when the base units differ."""
    a_mult, a_base = _split_unit(item_unit)
    b_mult, b_base = _split_unit(norm_unit)
    if a_base != b_base:
        return None
    return a_mult / b_mult


# ---------------------------------------------------------------------------
# Sample library (định mức MẪU) — illustrative only
# ---------------------------------------------------------------------------

SAMPLE_NOTE = ("Thư viện MẪU để chạy thử quy trình. Hao phí và đơn giá chỉ mang tính minh hoạ — "
               "thay bằng định mức áp dụng (TT 12/2021/TT-BXD …) và giá công bố/khảo sát "
               "trước khi phát hành dự toán.")

_SAMPLE_RESOURCES = [
    ("XM40", "Xi măng PCB40", "kg", "VL", 1750),
    ("CAT_V", "Cát vàng", "m3", "VL", 450000),
    ("CAT_M", "Cát mịn", "m3", "VL", 300000),
    ("DA12", "Đá dăm 1x2", "m3", "VL", 420000),
    ("DA46", "Đá dăm 4x6", "m3", "VL", 380000),
    ("NUOC", "Nước", "lít", "VL", 15),
    ("THEP10", "Thép tròn D≤10mm", "kg", "VL", 15500),
    ("THEP18", "Thép tròn D≤18mm", "kg", "VL", 15200),
    ("DAYTHEP", "Dây thép buộc", "kg", "VL", 22000),
    ("QUEHAN", "Que hàn", "kg", "VL", 30000),
    ("GO_VK", "Gỗ ván khuôn", "m3", "VL", 4500000),
    ("GO_CHONG", "Gỗ đà nẹp, cây chống", "m3", "VL", 4000000),
    ("DINH", "Đinh", "kg", "VL", 25000),
    ("GACH_D", "Gạch đặc 6,5×10,5×22", "viên", "VL", 1400),
    ("SON", "Sơn nước", "kg", "VL", 120000),
    ("GACH_LAT", "Gạch lát 600×600", "m2", "VL", 220000),
    ("NC30", "Nhân công bậc 3,0/7", "công", "NC", 300000),
    ("NC35", "Nhân công bậc 3,5/7", "công", "NC", 320000),
    ("NC40", "Nhân công bậc 4,0/7", "công", "NC", 345000),
    ("M_DAO", "Máy đào ≤0,8m3", "ca", "M", 3200000),
    ("M_TRON", "Máy trộn bê tông 250L", "ca", "M", 350000),
    ("M_DAM", "Máy đầm dùi 1,5kW", "ca", "M", 260000),
    ("M_VUA", "Máy trộn vữa 80L", "ca", "M", 280000),
    ("M_CAT", "Máy cắt uốn cốt thép 5kW", "ca", "M", 300000),
    ("M_HAN", "Máy hàn 23kW", "ca", "M", 420000),
    ("M_VT", "Vận thăng 0,8T", "ca", "M", 600000),
]

_CONCRETE = [("XM40", 380), ("CAT_V", 0.46), ("DA12", 0.86), ("NUOC", 185),
             ("M_TRON", 0.095), ("M_DAM", 0.18)]
_FORMWORK = [("GO_VK", 0.0079), ("GO_CHONG", 0.0067), ("DINH", 0.12)]


def _rebar(steel, nc, weld=True, hoist=True):
    items = [(steel, 1020), ("DAYTHEP", 14.28), ("NC35", nc), ("M_CAT", 0.32)]
    if weld:
        items += [("QUEHAN", 4.6), ("M_HAN", 1.1)]
    if hoist:
        items.append(("M_VT", 0.04))
    return items


# (work-item code, norm code, name, unit, items)
_SAMPLE_NORMS = [
    ("DAO", "MAU.DAO", "Đào đất hố móng bằng máy, sửa thủ công", "m3",
     [("M_DAO", 0.0035), ("NC30", 0.03)]),
    ("BTL", "MAU.BTL", "Bê tông lót móng đá 4x6", "m3",
     [("XM40", 200), ("CAT_V", 0.53), ("DA46", 0.94), ("NUOC", 170), ("NC30", 1.18),
      ("M_TRON", 0.095), ("M_DAM", 0.089)]),
    ("BT_MONG", "MAU.BT.MONG", "Bê tông móng đá 1x2", "m3", _CONCRETE + [("NC35", 1.64)]),
    ("BT_COT", "MAU.BT.COT", "Bê tông cột đá 1x2", "m3",
     _CONCRETE + [("NC35", 3.04), ("M_VT", 0.11)]),
    ("BT_DAM", "MAU.BT.DAM", "Bê tông dầm đá 1x2", "m3",
     _CONCRETE + [("NC35", 2.56), ("M_VT", 0.11)]),
    ("BT_SAN", "MAU.BT.SAN", "Bê tông sàn đá 1x2", "m3",
     _CONCRETE + [("NC35", 1.58), ("M_VT", 0.11)]),
    ("VK_MONG", "MAU.VK.MONG", "Ván khuôn gỗ móng", "m2", _FORMWORK + [("NC40", 0.30)]),
    ("VK_COT", "MAU.VK.COT", "Ván khuôn gỗ cột", "m2", _FORMWORK + [("NC40", 0.34)]),
    ("VK_DAM", "MAU.VK.DAM", "Ván khuôn gỗ dầm", "m2", _FORMWORK + [("NC40", 0.38)]),
    ("VK_SAN", "MAU.VK.SAN", "Ván khuôn gỗ sàn", "m2", _FORMWORK + [("NC40", 0.31)]),
    ("CT_MONG", "MAU.CT.MONG", "Cốt thép móng", "tấn", _rebar("THEP18", 8.34, hoist=False)),
    ("CT_COT", "MAU.CT.COT", "Cốt thép cột", "tấn", _rebar("THEP18", 10.2)),
    ("CT_DAM", "MAU.CT.DAM", "Cốt thép dầm", "tấn", _rebar("THEP18", 9.9)),
    ("CT_SAN", "MAU.CT.SAN", "Cốt thép sàn", "tấn", _rebar("THEP10", 14.6, weld=False)),
    ("XAY", "MAU.XAY", "Xây tường gạch đặc, vữa XM M75", "m3",
     [("GACH_D", 550), ("XM40", 71), ("CAT_M", 0.32), ("NUOC", 75), ("NC35", 1.67),
      ("M_VUA", 0.036)]),
    ("TRAT", "MAU.TRAT", "Trát tường dày 15mm, vữa XM M75", "m2",
     [("XM40", 5.0), ("CAT_M", 0.019), ("NUOC", 4), ("NC40", 0.2), ("M_VUA", 0.003)]),
    ("SON", "MAU.SON", "Sơn tường 1 nước lót, 2 nước phủ", "m2", [("SON", 0.35), ("NC35", 0.066)]),
    ("LAT", "MAU.LAT", "Lát nền gạch 600×600", "m2",
     [("GACH_LAT", 1.02), ("XM40", 9), ("CAT_M", 0.025), ("NUOC", 6), ("NC40", 0.17)]),
]


def sample_library() -> Library:
    lib = Library()
    for code, name, unit, kind, price in _SAMPLE_RESOURCES:
        lib.resources[code] = Resource(code, name, unit, kind, price)
    for item_code, code, name, unit, items in _SAMPLE_NORMS:
        lib.norms[code] = Norm(code, f"{name} (định mức mẫu)", unit, list(items))
        lib.mapping[item_code] = code
    return lib


def merge_library(base: Library, extra: Library) -> Library:
    """Add/replace resources, norms and mappings from ``extra`` into ``base``."""
    out = Library(OrderedDict(base.resources), OrderedDict(base.norms), dict(base.mapping))
    out.resources.update(extra.resources)
    out.norms.update(extra.norms)
    out.mapping.update(extra.mapping)
    return out


def resolve_norm(lib: Library, item: str, code: str) -> str | None:
    norm = lib.mapping.get(item) or lib.mapping.get(code)
    return norm if norm in lib.norms else None


# ---------------------------------------------------------------------------
# Estimate computation
# ---------------------------------------------------------------------------


def rates_with_defaults(rates: dict | None) -> "OrderedDict[str, float]":
    rates = rates or {}
    out = OrderedDict()
    for key, (name, default) in DEFAULT_RATES.items():
        v = rates.get(key, default)
        out[key] = _num(default if v in (None, "") else v, name)
        if out[key] < 0:
            raise BoqError(f"Tỷ lệ {name} không được âm")
    return out


def cost_summary(direct: dict, rates: dict) -> list[dict]:
    """direct = {"VL", "NC", "M", "K"} sums. Returns the cost table rows."""
    r = rates_with_defaults(rates)
    T = direct["VL"] + direct["NC"] + direct["M"] + direct["K"]
    C, LT, TT = T * r["C"] / 100, T * r["LT"] / 100, T * r["TT"] / 100
    GT = C + LT + TT
    TL = (T + GT) * r["TL"] / 100
    G = T + GT + TL
    VAT = G * r["VAT"] / 100
    Gxd = G + VAT
    DP = Gxd * r["DP"] / 100
    rows = [
        ("VL", "Chi phí vật liệu", "Σ KL × đơn giá VL", None, direct["VL"]),
        ("NC", "Chi phí nhân công", "Σ KL × đơn giá NC", None, direct["NC"]),
        ("M", "Chi phí máy thi công", "Σ KL × đơn giá M", None, direct["M"]),
        ("K", "Công tác đơn giá nhập trực tiếp", "Σ KL × đơn giá", None, direct["K"]),
        ("T", "Chi phí trực tiếp", "VL + NC + M + K", None, T),
        ("C", DEFAULT_RATES["C"][0], "T × tỷ lệ", r["C"], C),
        ("LT", DEFAULT_RATES["LT"][0], "T × tỷ lệ", r["LT"], LT),
        ("TT", DEFAULT_RATES["TT"][0], "T × tỷ lệ", r["TT"], TT),
        ("GT", "Chi phí gián tiếp", "C + LT + TT", None, GT),
        ("TL", DEFAULT_RATES["TL"][0], "(T + GT) × tỷ lệ", r["TL"], TL),
        ("G", "Giá trị dự toán xây dựng trước thuế", "T + GT + TL", None, G),
        ("GTGT", DEFAULT_RATES["VAT"][0], "G × tỷ lệ", r["VAT"], VAT),
        ("Gxd", "Giá trị dự toán xây dựng sau thuế", "G + GTGT", None, Gxd),
        ("DP", DEFAULT_RATES["DP"][0], "Gxd × tỷ lệ", r["DP"], DP),
        ("TONG", "TỔNG CỘNG", "Gxd + DP", None, Gxd + DP),
    ]
    return [{"key": k, "name": n, "formula": f, "rate": rt, "value": v} for k, n, f, rt, v in rows]


def estimate(summary: list[dict], lib: Library, direct_prices: dict | None = None,
             rates: dict | None = None) -> dict:
    """Price BOQ items (output of boq_engine.summarize) with norms and resource prices."""
    direct_prices = direct_prices or {}
    items, warnings = [], []
    res_totals: "OrderedDict[str, dict]" = OrderedDict()
    direct = {"VL": 0.0, "NC": 0.0, "M": 0.0, "K": 0.0}

    for it in summary:
        row = {k: it[k] for k in ("cell", "wbs", "hang_muc", "group", "item", "code", "name",
                                  "unit", "qty")}
        row.update({"norm": None, "norm_name": "", "norm_unit": "", "factor": None,
                    "dg": {"VL": 0.0, "NC": 0.0, "M": 0.0, "K": 0.0}, "analysis": []})
        norm_code = resolve_norm(lib, it["item"], it["code"])
        if norm_code:
            norm = lib.norms[norm_code]
            factor = unit_factor(it["unit"], norm.unit)
            if factor is None:
                warnings.append(f"{it['wbs']} {it['name']}: đơn vị BOQ '{it['unit']}' khác đơn vị "
                                f"định mức {norm_code} '{norm.unit}' — chưa tính giá.")
                norm_code = None
            else:
                row.update({"norm": norm_code, "norm_name": norm.name, "norm_unit": norm.unit,
                            "factor": factor})
                for rcode, cons in norm.items:
                    res = lib.resources.get(rcode)
                    if res is None:
                        warnings.append(f"Định mức {norm_code}: thiếu tài nguyên '{rcode}' "
                                        f"trong thư viện (tính giá 0).")
                        res = Resource(rcode, rcode, "", "VL", 0.0)
                    part = cons * res.price * factor
                    haophi = cons * it["qty"] * factor
                    row["dg"][res.kind] += part
                    row["analysis"].append({"resource": rcode, "name": res.name, "unit": res.unit,
                                            "kind": res.kind, "cons": cons, "price": res.price,
                                            "haophi": haophi, "part": part})
                    t = res_totals.setdefault(rcode, {**res.to_dict(), "haophi": 0.0})
                    t["haophi"] += haophi
        if not norm_code:
            price = float(direct_prices.get(it["item"], 0) or 0)
            row["dg"]["K"] = price
            if not price:
                warnings.append(f"{it['wbs']} {it['name']}: chưa có định mức hoặc đơn giá.")
        row["tt"] = {k: v * it["qty"] for k, v in row["dg"].items()}
        row["unit_price"] = sum(row["dg"].values())
        row["total"] = sum(row["tt"].values())
        for k in direct:
            direct[k] += row["tt"][k]
        items.append(row)

    resources = list(res_totals.values())
    for r in resources:
        r["amount"] = r["haophi"] * r["price"]
    order = list(KINDS)
    resources.sort(key=lambda r: (order.index(r["kind"]), r["code"]))
    return {"items": items, "resources": resources, "direct": direct,
            "costs": cost_summary(direct, rates or {}), "warnings": warnings,
            "rates": rates_with_defaults(rates)}


# ---------------------------------------------------------------------------
# Library Excel (import / export)
# ---------------------------------------------------------------------------


def library_workbook(lib: Library) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill

    wb = Workbook()
    head = Font(bold=True, color="FFFFFF")
    fill = PatternFill("solid", fgColor="1F2937")

    def sheet(ws, headers, widths):
        ws.append(headers)
        for c, w in zip(ws[1], widths):
            c.font, c.fill = head, fill
            ws.column_dimensions[c.column_letter].width = w
        ws.freeze_panes = "A2"

    ws = wb.active
    ws.title = "TaiNguyen"
    sheet(ws, ["Mã TN", "Tên tài nguyên", "Đơn vị", "Loại (VL/NC/M)", "Đơn giá (VNĐ)"],
          [12, 36, 10, 14, 16])
    for r in lib.resources.values():
        ws.append([r.code, r.name, r.unit, r.kind, r.price])

    wn = wb.create_sheet("DinhMuc")
    sheet(wn, ["Mã ĐM", "Tên công tác", "Đơn vị ĐM", "Mã TN", "Hao phí"], [16, 44, 10, 12, 12])
    for n in lib.norms.values():
        for i, (rcode, qty) in enumerate(n.items):
            wn.append([n.code, n.name if i == 0 else None, n.unit if i == 0 else None, rcode, qty])

    wm = wb.create_sheet("AnhXa")
    sheet(wm, ["Công tác BOQ (mã hoặc mã|mác)", "Mã ĐM"], [32, 18])
    for k, v in lib.mapping.items():
        wm.append([k, v])
    note = wb.create_sheet("GhiChu")
    for line in [
        "TaiNguyen: mỗi dòng một tài nguyên. Loại: VL = vật liệu, NC = nhân công, M = máy.",
        "DinhMuc: mỗi dòng một tài nguyên của định mức; Tên/Đơn vị chỉ cần ở dòng đầu.",
        "Đơn vị ĐM có thể là '100m2', '100m3' … — hệ thống tự quy đổi về đơn vị BOQ.",
        "AnhXa: công tác BOQ (VD: BT_COT hoặc BT_COT|B25) → mã định mức.",
        SAMPLE_NOTE,
    ]:
        note.append([line])
    note.column_dimensions["A"].width = 120
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def import_library(data: bytes) -> tuple[Library, list[str]]:
    from openpyxl import load_workbook

    try:
        wb = load_workbook(io.BytesIO(data), data_only=True)
    except Exception as exc:
        raise BoqError(f"Không đọc được file Excel: {exc}") from None
    lib, errors = Library(), []

    if "TaiNguyen" in wb.sheetnames:
        for i, row in enumerate(wb["TaiNguyen"].iter_rows(min_row=2, values_only=True), start=2):
            row = list(row) + [None] * 5
            if row[0] in (None, ""):
                continue
            try:
                res = make_resource(*row[:5])
                lib.resources[res.code] = res
            except BoqError as exc:
                errors.append(f"TaiNguyen dòng {i}: {exc}")

    if "DinhMuc" in wb.sheetnames:
        current = None
        for i, row in enumerate(wb["DinhMuc"].iter_rows(min_row=2, values_only=True), start=2):
            row = list(row) + [None] * 5
            code = str(row[0]).strip() if row[0] not in (None, "") else (current.code if current else "")
            if not code or row[3] in (None, ""):
                continue
            norm = lib.norms.get(code)
            if norm is None:
                norm = lib.norms[code] = Norm(code, str(row[1] or code).strip(), str(row[2] or "").strip())
            elif row[1]:
                norm.name = str(row[1]).strip()
            if row[2] and not norm.unit:
                norm.unit = str(row[2]).strip()
            current = norm
            try:
                qty = _num(row[4], "Hao phí")
                if qty < 0:
                    raise BoqError("Hao phí không được âm")
                norm.items.append((str(row[3]).strip(), qty))
            except BoqError as exc:
                errors.append(f"DinhMuc dòng {i}: {exc}")

    if "AnhXa" in wb.sheetnames:
        for row in wb["AnhXa"].iter_rows(min_row=2, values_only=True):
            row = list(row) + [None, None]
            if row[0] not in (None, "") and row[1] not in (None, ""):
                lib.mapping[str(row[0]).strip()] = str(row[1]).strip()

    if not (lib.resources or lib.norms or lib.mapping):
        raise BoqError("File không có sheet TaiNguyen / DinhMuc / AnhXa hợp lệ")
    return lib, errors


# ---------------------------------------------------------------------------
# Excel dự toán (live formulas)
# ---------------------------------------------------------------------------


def export_estimate(project: dict, est: dict) -> bytes:
    """Workbook where every money figure is a formula chained back to resource prices.

    Edit a price in TongHop_VT or a rate in TongHop_ChiPhi → the whole estimate updates.
    """
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    thin = Side(style="thin", color="9CA3AF")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    head_font, head_fill = Font(bold=True, color="FFFFFF"), PatternFill("solid", fgColor="1F2937")
    item_fill = PatternFill("solid", fgColor="F3F4F6")
    hm_fill, grp_fill = PatternFill("solid", fgColor="CBD5E1"), PatternFill("solid", fgColor="E5E7EB")
    center = Alignment(horizontal="center", vertical="center", wrap_text=True)
    wrap = Alignment(wrap_text=True, vertical="center")
    QF, MF, NF = "#,##0.000", "#,##0", "#,##0.0000"

    def header(ws, row, titles, widths):
        for i, t in enumerate(titles, start=1):
            c = ws.cell(row=row, column=i, value=t)
            c.font, c.fill, c.alignment, c.border = head_font, head_fill, center, border
            ws.column_dimensions[get_column_letter(i)].width = widths[i - 1]
        ws.row_dimensions[row].height = 32
        ws.freeze_panes = ws.cell(row=row + 1, column=1)

    def title(ws, text, ncols):
        ws.cell(row=1, column=1, value=text).font = Font(bold=True, size=14)
        ws.cell(row=2, column=1, value=f"Công trình: {project.get('name', '')}   ·   "
                                       f"Mã: {project.get('code', '')}").font = Font(italic=True)
        ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
        ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=ncols)

    def put(ws, r, values, fmt=None, font=None, fill=None, ncols=None):
        for col, v in enumerate(values, start=1):
            c = ws.cell(row=r, column=col, value=v)
            c.border = border
            if fmt and col in fmt:
                c.number_format = fmt[col]
            if font:
                c.font = font
            if fill:
                c.fill = fill
        for col in range(len(values) + 1, (ncols or 0) + 1):
            c = ws.cell(row=r, column=col)
            c.border = border
            if fill:
                c.fill = fill

    wb = Workbook()
    ws_cost = wb.active
    ws_cost.title = "TongHop_ChiPhi"
    ws_dt = wb.create_sheet("DuToan")
    ws_pt = wb.create_sheet("PhanTich_DonGia")
    ws_vt = wb.create_sheet("TongHop_VT")

    # --- TongHop_VT: resource prices (the one place to edit prices) --------
    title(ws_vt, "BẢNG TỔNG HỢP VẬT LIỆU, NHÂN CÔNG, MÁY THI CÔNG", 7)
    header(ws_vt, 4, ["Mã TN", "Tên tài nguyên", "Đơn vị", "Loại", "Tổng hao phí",
                      "Đơn giá (VNĐ)", "Thành tiền (VNĐ)"], [12, 36, 9, 7, 16, 16, 18])
    r = 5
    first_vt = r
    for res in est["resources"]:
        put(ws_vt, r, [res["code"], res["name"], res["unit"], res["kind"],
                       f"=SUMIF(PhanTich_DonGia!$C:$C,$A{r},PhanTich_DonGia!$I:$I)",
                       res["price"], f"=E{r}*F{r}"], fmt={5: QF, 6: MF, 7: MF})
        ws_vt.cell(row=r, column=6).fill = PatternFill("solid", fgColor="FEF9C3")
        r += 1
    last_vt = max(r - 1, first_vt)
    r += 1
    for kind, label in KINDS.items():
        put(ws_vt, r, [None, f"Cộng {label.lower()}", None, kind, None, None,
                       f"=SUMIF(D{first_vt}:D{last_vt},D{r},G{first_vt}:G{last_vt})"],
            fmt={7: MF}, font=Font(bold=True))
        r += 1
    ws_vt.cell(row=r + 1, column=2, value="Ô vàng là đơn giá: sửa tại đây, toàn bộ dự toán tự cập nhật.") \
        .font = Font(italic=True, color="6B7280")

    # --- PhanTich_DonGia: one block per BOQ item --------------------------
    title(ws_pt, "BẢNG PHÂN TÍCH ĐƠN GIÁ CHI TIẾT", 12)
    header(ws_pt, 4, ["WBS", "Mã ĐM", "Mã TN", "Nội dung", "Đơn vị", "Loại", "Định mức",
                      "Đơn giá TN", "Hao phí / KL", "ĐG thành phần", "Hệ số ĐV", "Mã cell"],
           [14, 14, 10, 40, 9, 6, 12, 14, 14, 15, 9, 26])
    item_rows: dict[str, int] = {}
    r = 5
    for it in est["items"]:
        if not it["norm"]:
            continue
        ir = r
        item_rows[it["cell"]] = ir
        put(ws_pt, ir, [it["wbs"], it["norm"], None, f"{it['name']} — {it['norm_name']}",
                        it["unit"], None, None, None, it["qty"], f"=SUM(J{ir + 1}:J{ir + len(it['analysis'])})",
                        it["factor"], it["cell"]],
            fmt={9: QF, 10: MF, 11: NF}, font=Font(bold=True), fill=item_fill)
        r += 1
        for a in it["analysis"]:
            put(ws_pt, r, [None, None, a["resource"], a["name"], a["unit"], a["kind"], a["cons"],
                           f'=IFERROR(VLOOKUP($C{r},TongHop_VT!$A:$F,6,FALSE),0)',
                           f"=G{r}*$I${ir}*$K${ir}", f"=G{r}*H{r}*$K${ir}", None, it["cell"]],
                fmt={7: NF, 8: MF, 9: QF, 10: MF})
            r += 1

    # --- DuToan: priced BOQ, unit prices pulled from PhanTich -------------
    title(ws_dt, "BẢNG DỰ TOÁN CHI TIẾT", 16)
    header(ws_dt, 4, ["STT", "WBS (Cell)", "Mã ĐM", "Nội dung công việc", "Đơn vị", "Khối lượng",
                      "ĐG Vật liệu", "ĐG Nhân công", "ĐG Máy", "ĐG nhập trực tiếp",
                      "TT Vật liệu", "TT Nhân công", "TT Máy", "TT trực tiếp", "Thành tiền", "Mã cell"],
           [6, 14, 14, 40, 8, 13, 13, 13, 12, 14, 15, 15, 14, 14, 16, 24])
    r = 5
    first_dt = r
    seen: set[str] = set()
    stt = 0
    money = {c: MF for c in range(7, 16)}
    money[6] = QF
    for it in est["items"]:
        for level, label, fill in ((100, it["hang_muc"], hm_fill), (300, it["group"], grp_fill)):
            code = wbs_parent(it["wbs"], level) if it["wbs"] else label
            if code not in seen:
                seen.add(code)
                put(ws_dt, r, [None, code, None, label.upper()], font=Font(bold=True), fill=fill, ncols=16)
                r += 1
        stt += 1
        ir = item_rows.get(it["cell"])
        qty = f"=PhanTich_DonGia!I{ir}" if ir else it["qty"]

        def dg(kind):
            return (f'=SUMIFS(PhanTich_DonGia!$J:$J,PhanTich_DonGia!$L:$L,$P{r},'
                    f'PhanTich_DonGia!$F:$F,"{kind}")') if ir else 0

        put(ws_dt, r, [stt, it["wbs"], it["norm"] or "", it["name"], it["unit"], qty,
                       dg("VL"), dg("NC"), dg("M"), None if ir else it["dg"]["K"],
                       f"=F{r}*G{r}", f"=F{r}*H{r}", f"=F{r}*I{r}", f"=F{r}*J{r}",
                       f"=SUM(K{r}:N{r})", it["cell"]], fmt=money)
        ws_dt.cell(row=r, column=4).alignment = wrap
        if not ir:
            ws_dt.cell(row=r, column=10).fill = PatternFill("solid", fgColor="FEF9C3")
        r += 1
    last_dt = max(r - 1, first_dt)
    total_dt = r
    put(ws_dt, r, [None, None, None, "TỔNG CỘNG", None, None, None, None, None, None]
        + [f"=SUM({c}{first_dt}:{c}{last_dt})" for c in "KLMNO"] + [None],
        fmt=money, font=Font(bold=True))

    # --- TongHop_ChiPhi: cost summary with editable rates -----------------
    title(ws_cost, "BẢNG TỔNG HỢP DỰ TOÁN CHI PHÍ XÂY DỰNG", 6)
    header(ws_cost, 4, ["STT", "Khoản mục chi phí", "Ký hiệu", "Cách tính", "Tỷ lệ (%)",
                        "Giá trị (VNĐ)"], [6, 58, 9, 20, 10, 20])
    rows = {}
    r = 5
    src = {"VL": f"=DuToan!K{total_dt}", "NC": f"=DuToan!L{total_dt}",
           "M": f"=DuToan!M{total_dt}", "K": f"=DuToan!N{total_dt}"}
    for i, c in enumerate(est["costs"], start=1):
        rows[c["key"]] = r
        r += 1

    def ref(k):
        return f"F{rows[k]}"

    formulas = {
        **src,
        "T": f"={ref('VL')}+{ref('NC')}+{ref('M')}+{ref('K')}",
        "C": f"={ref('T')}*E{rows['C']}/100",
        "LT": f"={ref('T')}*E{rows['LT']}/100",
        "TT": f"={ref('T')}*E{rows['TT']}/100",
        "GT": f"={ref('C')}+{ref('LT')}+{ref('TT')}",
        "TL": f"=({ref('T')}+{ref('GT')})*E{rows['TL']}/100",
        "G": f"={ref('T')}+{ref('GT')}+{ref('TL')}",
        "GTGT": f"={ref('G')}*E{rows['GTGT']}/100",
        "Gxd": f"={ref('G')}+{ref('GTGT')}",
        "DP": f"={ref('Gxd')}*E{rows['DP']}/100",
        "TONG": f"={ref('Gxd')}+{ref('DP')}",
    }
    bold_keys = {"T", "GT", "G", "Gxd", "TONG"}
    for i, c in enumerate(est["costs"], start=1):
        rr = rows[c["key"]]
        put(ws_cost, rr, [i, c["name"], c["key"], c["formula"], c["rate"], formulas[c["key"]]],
            fmt={5: "0.00", 6: MF}, font=Font(bold=True) if c["key"] in bold_keys else None)
        if c["rate"] is not None:
            ws_cost.cell(row=rr, column=5).fill = PatternFill("solid", fgColor="FEF9C3")
    note_r = r + 1
    for line in ["Ô vàng có thể sửa (tỷ lệ %, đơn giá tài nguyên); mọi giá trị là công thức.",
                 "Tỷ lệ mặc định chỉ để khởi tạo — kiểm tra theo TT 11/2021/TT-BXD và loại công trình.",
                 *(["Cảnh báo: " + w for w in est["warnings"][:20]])]:
        ws_cost.cell(row=note_r, column=2, value=line).font = Font(italic=True, color="6B7280")
        note_r += 1

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()

"""Bộ vẽ hình học đơn giản: dựng một lần, xuất ra SVG (xem trên web) và DXF (mở bằng AutoCAD).

Toạ độ tính bằng mm, trục y hướng lên giống AutoCAD.
"""
from dataclasses import dataclass, field
from html import escape

# Màu theo bảng màu AutoCAD (ACI) và màu tương ứng trên SVG
LAYERS = {
    "BETONG": (7, "#1f2937"),
    "THEP": (1, "#dc2626"),
    "THEP_DAI": (3, "#16a34a"),
    "KICH_THUOC": (4, "#0e7490"),
    "CHU": (2, "#111827"),
    "TRUC": (8, "#9ca3af"),
}


@dataclass
class Drawing:
    entities: list = field(default_factory=list)

    def line(self, x1, y1, x2, y2, layer="BETONG"):
        self.entities.append(("LINE", layer, (x1, y1, x2, y2)))

    def polyline(self, pts, layer="BETONG"):
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            self.line(x1, y1, x2, y2, layer)

    def rect(self, x, y, w, h, layer="BETONG"):
        self.polyline([(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)], layer)

    def circle(self, x, y, r, layer="THEP"):
        self.entities.append(("CIRCLE", layer, (x, y, r)))

    def text(self, x, y, s, height=60, layer="CHU", align="left"):
        self.entities.append(("TEXT", layer, (x, y, str(s), height, align)))

    def dim_h(self, x1, x2, y, label=None, height=60):
        """Đường kích thước nằm ngang có ghi giá trị."""
        t = height * 0.4
        self.line(x1, y, x2, y, "KICH_THUOC")
        self.line(x1, y - t, x1, y + t, "KICH_THUOC")
        self.line(x2, y - t, x2, y + t, "KICH_THUOC")
        self.text((x1 + x2) / 2, y + t, label if label is not None else round(x2 - x1), height, "KICH_THUOC", "center")

    def dim_v(self, x, y1, y2, label=None, height=60):
        t = height * 0.4
        self.line(x, y1, x, y2, "KICH_THUOC")
        self.line(x - t, y1, x + t, y1, "KICH_THUOC")
        self.line(x - t, y2, x + t, y2, "KICH_THUOC")
        self.text(x - t, (y1 + y2) / 2, label if label is not None else round(y2 - y1), height, "KICH_THUOC", "right")

    def merge(self, other, dx=0, dy=0):
        for kind, layer, g in other.entities:
            if kind == "LINE":
                g = (g[0] + dx, g[1] + dy, g[2] + dx, g[3] + dy)
            else:
                g = (g[0] + dx, g[1] + dy) + tuple(g[2:])
            self.entities.append((kind, layer, g))

    def bbox(self):
        xs, ys = [], []
        for kind, _, g in self.entities:
            if kind == "LINE":
                xs += [g[0], g[2]]
                ys += [g[1], g[3]]
            elif kind == "CIRCLE":
                xs += [g[0] - g[2], g[0] + g[2]]
                ys += [g[1] - g[2], g[1] + g[2]]
            else:
                x, y, s, h, align = g
                w = len(s) * h * 0.6
                x0 = {"left": x, "center": x - w / 2, "right": x - w}[align]
                xs += [x0, x0 + w]
                ys += [y, y + h]
        if not xs:
            return 0, 0, 1, 1
        return min(xs), min(ys), max(xs), max(ys)

    def to_svg(self, margin=150):
        x0, y0, x1, y1 = self.bbox()
        x0, y0, x1, y1 = x0 - margin, y0 - margin, x1 + margin, y1 + margin
        w, h = x1 - x0, y1 - y0
        stroke = max(w, h) / 900
        out = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.0f} {-y1:.0f} {w:.0f} {h:.0f}" '
            f'class="kata-svg" preserveAspectRatio="xMidYMid meet">'
        ]
        for kind, layer, g in self.entities:
            color = LAYERS[layer][1]
            if kind == "LINE":
                sw = stroke * (1.8 if layer in ("THEP", "BETONG") else 1)
                out.append(
                    f'<line x1="{g[0]:.1f}" y1="{-g[1]:.1f}" x2="{g[2]:.1f}" y2="{-g[3]:.1f}" '
                    f'stroke="{color}" stroke-width="{sw:.2f}"/>'
                )
            elif kind == "CIRCLE":
                out.append(f'<circle cx="{g[0]:.1f}" cy="{-g[1]:.1f}" r="{g[2]:.1f}" fill="{color}"/>')
            else:
                x, y, s, th, align = g
                anchor = {"left": "start", "center": "middle", "right": "end"}[align]
                out.append(
                    f'<text x="{x:.1f}" y="{-y:.1f}" font-size="{th:.0f}" fill="{color}" '
                    f'text-anchor="{anchor}" font-family="sans-serif">{escape(s)}</text>'
                )
        out.append("</svg>")
        return "".join(out)

    def to_dxf(self):
        """DXF ASCII R12 — AutoCAD, ZWCAD, GstarCAD, LibreCAD đều mở được."""
        o = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009", "9", "$DWGCODEPAGE", "3", "ANSI_1258",
             "0", "ENDSEC", "0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", str(len(LAYERS))]
        for name, (aci, _) in LAYERS.items():
            o += ["0", "LAYER", "2", name, "70", "0", "62", str(aci), "6", "CONTINUOUS"]
        o += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]
        for kind, layer, g in self.entities:
            if kind == "LINE":
                o += ["0", "LINE", "8", layer, "10", f"{g[0]:.2f}", "20", f"{g[1]:.2f}", "30", "0",
                      "11", f"{g[2]:.2f}", "21", f"{g[3]:.2f}", "31", "0"]
            elif kind == "CIRCLE":
                o += ["0", "CIRCLE", "8", layer, "10", f"{g[0]:.2f}", "20", f"{g[1]:.2f}", "30", "0",
                      "40", f"{g[2]:.2f}"]
            else:
                x, y, s, th, align = g
                h_align = {"left": 0, "center": 1, "right": 2}[align]
                o += ["0", "TEXT", "8", layer, "10", f"{x:.2f}", "20", f"{y:.2f}", "30", "0",
                      "40", f"{th:.1f}", "1", _dxf_text(s)]
                if h_align:
                    o += ["72", str(h_align), "11", f"{x:.2f}", "21", f"{y:.2f}", "31", "0"]
        o += ["0", "ENDSEC", "0", "EOF"]
        return "\n".join(o) + "\n"


def _dxf_text(s):
    """Mã hoá ký tự ngoài ASCII theo dạng \\U+XXXX để DXF R12 hiển thị đúng tiếng Việt."""
    return "".join(c if ord(c) < 128 else f"\\U+{ord(c):04X}" for c in s)

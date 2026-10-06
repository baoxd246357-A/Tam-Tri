import pytest
from fastapi.testclient import TestClient

from app.kata.members import (
    BeamInput, Bars, ColumnInput, beam_schedule, column_schedule, stirrup_positions,
    unit_weight, with_laps,
)
from app.main import app

client = TestClient(app)


def test_unit_weight_matches_table():
    # Bảng tra: Ø10 = 0.617 kg/m, Ø18 = 1.998 kg/m
    assert unit_weight(10) == pytest.approx(0.617, abs=1e-3)
    assert unit_weight(18) == pytest.approx(1.998, abs=1e-3)


def test_with_laps_adds_lap_per_joint():
    assert with_laps(11000, 16) == (11000, 0)
    assert with_laps(20000, 16) == (20000 + 40 * 16, 1)


def test_stirrups_dense_at_ends_and_within_span():
    pos = stirrup_positions(0, 4000, 1000, 100, 200)
    assert pos[0] == 50 and pos[-1] == 3950
    gaps = [b - a for a, b in zip(pos, pos[1:])]
    assert max(gaps) <= 200 and gaps[0] == 100
    assert pos == sorted(pos)


def test_beam_schedule_single_span():
    m = BeamInput(name="D1", b=220, h=400, cover=25, spans=[4500], supports=[220],
                  bottom=Bars(n=2, d=18), top=Bars(n=2, d=16), top_add=None)
    rows = {r["mark"]: r for r in beam_schedule(m)}
    total = 220 + 4500 + 220
    # Thép dưới bị chặn tại mép gối biên -> có móc hai đầu
    assert rows["1.1"]["length"] == total - 2 * 25 + 2 * 15 * 18
    assert rows["2"]["length"] == total - 2 * 25 + 2 * 15 * 16
    assert rows["4"]["length"] == 2 * (170 + 350) + 2 * 80
    assert rows["2"]["weight_kg"] == pytest.approx(rows["2"]["length"] * 2 / 1000 * unit_weight(16), abs=0.01)


def test_beam_multi_span_top_add_and_count():
    m = BeamInput(name="D2", count=3, spans=[4000, 4000], supports=[300], top_add=Bars(n=2, d=16))
    rows = {r["mark"]: r for r in beam_schedule(m)}
    # Thép mũ gối giữa = L/4 + c + L/4
    assert rows["3.2"]["length"] == 1000 + 300 + 1000
    assert rows["1.1"]["count"] == 3 and rows["1.1"]["n_total"] == 6


def test_beam_rejects_mismatched_supports():
    with pytest.raises(ValueError):
        BeamInput(spans=[4000, 4000], supports=[220, 220])


def test_column_schedule():
    m = ColumnInput(b=300, h=400, height=3300, nx=3, ny=4, d=20)
    rows = column_schedule(m)
    assert rows[0]["n_per_member"] == 2 * 3 + 2 * 4 - 4
    assert rows[0]["length"] == 3300 + 40 * 20
    assert any(r["shape"] == "Đai móc" for r in rows)


PAYLOAD = {
    "project": "Test",
    "members": [
        {"type": "beam", "name": "D1", "spans": [4500, 3600], "supports": [220]},
        {"type": "column", "name": "C1"},
    ],
}


def test_calc_api():
    r = client.post("/api/v1/kata/calc", json=PAYLOAD)
    assert r.status_code == 200
    data = r.json()
    assert len(data["members"]) == 2
    assert data["members"][0]["svg"].startswith("<svg")
    s = data["summary"]
    assert s["steel_total_kg"] == pytest.approx(sum(m["steel_kg"] for m in data["members"]), abs=0.05)
    assert s["concrete_m3"] > 0


def test_calc_api_validation_error():
    bad = {"members": [{"type": "beam", "spans": [4000], "bottom": {"n": 2, "d": 17}}]}
    assert client.post("/api/v1/kata/calc", json=bad).status_code == 422


def test_dxf_export_is_valid_ascii_dxf():
    r = client.post("/api/v1/kata/export.dxf", json=PAYLOAD)
    assert r.status_code == 200
    text = r.content.decode("ascii")
    assert text.startswith("0\nSECTION") and text.rstrip().endswith("EOF")
    assert "LINE" in text and "CIRCLE" in text
    # Tiếng Việt được mã hoá \U+XXXX
    assert "\\U+1EB6" in text or "\\U+" in text


def test_csv_export():
    r = client.post("/api/v1/kata/export.csv", json=PAYLOAD)
    assert r.status_code == 200
    body = r.content.decode("utf-8")
    assert body.startswith("\ufeff") and "Tổng thép (kg)" in body


def test_kata_page():
    r = client.get("/kata")
    assert r.status_code == 200 and "Triển khai bản vẽ kết cấu" in r.text


def test_beam_default_supports_expand_to_all_spans():
    m = BeamInput(spans=[4000, 3000, 5000])
    assert m.supports == [220, 220, 220, 220]


# --------------------------------------------------------------------------- sàn, móng

from app.kata.slab_footing import (  # noqa: E402
    FootingInput, Mesh, SlabInput, bar_count, footing_schedule, slab_schedule,
)


def test_bar_count_keeps_spacing_within_limit():
    assert bar_count(3000, 200) == 16  # (3000 - 100) / 200 = 14.5 -> 15 khoảng
    assert bar_count(1800, 150, 50) == 13  # 11.3 -> 12 khoảng


def test_slab_schedule():
    m = SlabInput(lx=3600, ly=4200, t=100, cover=15, bw=220,
                  bottom_x=Mesh(d=8, s=200), bottom_y=Mesh(d=8, s=200), top=Mesh(d=8, s=200))
    rows = {r["mark"]: r for r in slab_schedule(m)}
    # Neo vào dầm max(10d, bw/2) = 110
    assert rows["1"]["length"] == 3600 + 2 * 110
    assert rows["1"]["n_per_member"] == bar_count(4200, 200)
    assert rows["2"]["length"] == 4200 + 2 * 110
    # Thép mũ: L_ngắn/4 + (bw - cover) + 2 chân (t - 2cover)
    assert rows["3.1"]["length"] == 900 + 205 + 2 * 70
    assert rows["3.1"]["n_per_member"] == 2 * bar_count(3600, 200)
    assert rows["4.1"]["d"] == 6


def test_footing_schedule():
    m = FootingInput(a=2000, b=1600, h=500, cover=50, mesh_x=Mesh(d=12, s=150), mesh_y=Mesh(d=12, s=150),
                     neck=600, nx=3, ny=3, d=18)
    rows = {r["mark"]: r for r in footing_schedule(m)}
    assert rows["1"]["length"] == 2000 - 100 + 2 * 15 * 12
    assert rows["1"]["n_per_member"] == bar_count(1600, 150, 50)
    assert rows["2"]["length"] == 1600 - 100 + 2 * 15 * 12
    assert rows["3"]["n_per_member"] == 8
    assert rows["3"]["length"] == (500 - 50 - 24) + 600 + 40 * 18 + 15 * 18


def test_footing_hook_limited_by_height():
    m = FootingInput(h=300, cover=50, mesh_x=Mesh(d=20, s=150))
    rows = {r["mark"]: r for r in footing_schedule(m)}
    assert rows["1"]["length"] == 1800 - 100 + 2 * 200


def test_footing_rejects_neck_larger_than_base():
    with pytest.raises(ValueError):
        FootingInput(a=600, b=600, col_b=600, col_h=300)


def test_api_all_member_types_and_lean_concrete():
    payload = {"members": [
        {"type": "beam", "spans": [4000]},
        {"type": "column"},
        {"type": "slab", "count": 4},
        {"type": "footing", "count": 2},
    ]}
    data = client.post("/api/v1/kata/calc", json=payload).json()
    assert [m["type"] for m in data["members"]] == ["beam", "column", "slab", "footing"]
    footing = data["members"][3]
    assert footing["lean_concrete_m3"] == pytest.approx(2000 * 2000 * 100 / 1e9 * 2, abs=1e-3)
    assert data["summary"]["lean_concrete_m3"] == footing["lean_concrete_m3"]
    slab = data["members"][2]
    assert slab["concrete_m3"] == pytest.approx(3.6 * 4.2 * 0.1 * 4, abs=1e-3)
    assert all(m["svg"].startswith("<svg") for m in data["members"])
    assert client.post("/api/v1/kata/export.dxf", json=payload).status_code == 200

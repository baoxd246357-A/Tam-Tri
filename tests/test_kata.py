import math

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
    assert body.startswith("﻿") and "Tổng thép (kg)" in body


def test_kata_page():
    r = client.get("/kata")
    assert r.status_code == 200 and "Triển khai bản vẽ kết cấu" in r.text


def test_beam_default_supports_expand_to_all_spans():
    m = BeamInput(spans=[4000, 3000, 5000])
    assert m.supports == [220, 220, 220, 220]

"""Thống kê học tập thuần Python (không gọi AI) — dùng cho báo cáo tuần và kiểm thử."""
from collections import defaultdict
from datetime import date, datetime, timedelta

from . import rules


def week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def weekly_summary(level: str, logs: list, tasks: list, today: date | None = None) -> dict:
    """logs/tasks: danh sách dict. Trả số liệu 7 ngày gần nhất tính đến `today`."""
    today = today or date.today()
    since = today - timedelta(days=6)

    def in_week(v):
        d = v if isinstance(v, date) and not isinstance(v, datetime) else v.date()
        return since <= d <= today

    wl = [l for l in logs if in_week(l["created_at"])]
    per_subject = defaultdict(lambda: {"minutes": 0, "und": []})
    per_day = defaultdict(int)
    for l in wl:
        s = per_subject[l["subject"]]
        s["minutes"] += l["minutes"]
        s["und"].append(l["understanding"])
        per_day[l["created_at"].date().isoformat()] += l["minutes"]

    subjects = []
    for name, s in sorted(per_subject.items(), key=lambda kv: -kv[1]["minutes"]):
        avg = round(sum(s["und"]) / len(s["und"]), 1) if s["und"] else 0
        subjects.append({"subject": name, "minutes": s["minutes"], "avg_understanding": avg,
                         "weak": avg < rules.WEAK_UNDERSTANDING_BELOW})

    limit = rules.DAILY_MINUTES_SOFT_LIMIT.get(level, rules.DEFAULT_SOFT_LIMIT)
    over = sorted(d for d, m in per_day.items() if m > limit)

    due_tasks = [t for t in tasks if t["due"]]
    overdue = [t for t in due_tasks if not t["done"] and t["due"] < today.isoformat()]

    return {
        "from": since.isoformat(), "to": today.isoformat(),
        "total_minutes": sum(l["minutes"] for l in wl),
        "study_days": len(per_day),
        "subjects": subjects,
        "weak_subjects": [s["subject"] for s in subjects if s["weak"]],
        "days_over_limit": over, "daily_limit": limit,
        "tasks_open": sum(1 for t in tasks if not t["done"]),
        "tasks_done": sum(1 for t in tasks if t["done"]),
        "tasks_overdue": [t["title"] for t in overdue],
    }


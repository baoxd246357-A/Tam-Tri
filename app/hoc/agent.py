"""Trợ lý học tập dạng lệnh tiếng Việt — dùng chung cho khung chat trên web và nhóm Zalo.

Không gọi AI/API ngoài: hiểu một bộ lệnh cố định (không phân biệt hoa thường, có dấu hay không dấu).
handle(db, chat_id, text) → câu trả lời (str) hoặc None nếu tin không phải lệnh.
"""
import re
import unicodedata
from datetime import date, timedelta

from . import rules, stats
from .db import ChatState, Learner, StudyLog, Task

LEVEL_WORDS = {"tieuhoc": "tieu_hoc", "thcs": "thcs", "thpt": "thpt", "daihoc": "dai_hoc"}

HELP = """🤖 Trợ lý học tập — lệnh:
• thêm Bin thcs lớp 7  — thêm thành viên (tieuhoc/thcs/thpt/daihoc; tên nhiều từ: Minh_Anh)
• đổi Bin Minh lớp 6  — đổi tên (và lớp) thành viên; cấp học tự suy ra từ lớp
• chọn Bin  — chọn bé mặc định cho nhóm này
• việc Bin Bài tập Toán trang 45 hạn 25/10  — giao việc (hạn: dd/mm, hôm nay, mai)
• ds [Bin]  — danh sách việc  |  xong 3  — đánh dấu xong việc số 3
• học Bin Toán 45 hiểu 4  — ghi buổi học 45 phút, mức hiểu 1-5
• báo cáo [Bin]  — báo cáo 7 ngày  |  bé  — danh sách thành viên
Bỏ tên bé nếu nhóm đã chọn hoặc chỉ có một bé."""


def norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.replace("đ", "d").replace("Đ", "D"))
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def parse_due(words: list[str], today: date | None = None):
    """Tìm 'hạn <ngày>' ở cuối câu. Trả (due_iso, words_còn_lại, lỗi)."""
    today = today or date.today()
    nw = [norm(w) for w in words]
    for i, w in enumerate(nw):
        if w in ("han", "den") and i + 1 < len(nw):
            j, val = i + 1, nw[i + 1]
            used = 2
            if val == "hom" and j + 1 < len(nw) and nw[j + 1] == "nay":
                return today.isoformat(), words[:i] + words[i + 3:], None
            if val == "ngay" and j + 1 < len(nw) and nw[j + 1] == "mai":
                return (today + timedelta(days=1)).isoformat(), words[:i] + words[i + 3:], None
            if val in ("mai", "ngaymai"):
                return (today + timedelta(days=1)).isoformat(), words[:i] + words[i + 2:], None
            m = re.fullmatch(r"(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?", val)
            if m:
                d, mo, y = int(m[1]), int(m[2]), m[3]
                y = int(y) + 2000 if y and len(y) == 2 else int(y) if y else today.year
                try:
                    due = date(y, mo, d)
                except ValueError:
                    return None, words, f"Ngày '{words[i+1]}' không hợp lệ"
                if not m[3] and due < today:
                    due = date(y + 1, mo, d)
                return due.isoformat(), words[:i] + words[i + 2:], None
            return None, words, f"Không hiểu hạn '{words[i+1]}' — dùng dd/mm, hôm nay hoặc mai"
    return "", words, None


def _find_learner(db, words: list[str]):
    """Nếu từ đầu tiên là tên một bé thì tách ra. Trả (Learner|None, words_còn_lại)."""
    if not words:
        return None, words
    first = norm(words[0])
    for l in db.query(Learner):
        if norm(l.name) == first or norm(l.name).replace(" ", "_") == first:
            return l, words[1:]
    return None, words


def infer_level(grade: str):
    """'lớp 4' → tieu_hoc, 'lớp 6-9' → thcs, 'lớp 10-12' → thpt; không có số thì None."""
    m = re.search(r"\d+", grade or "")
    if not m:
        return None
    n = int(m[0])
    return "tieu_hoc" if 1 <= n <= 5 else "thcs" if 6 <= n <= 9 else "thpt" if 10 <= n <= 12 else None


def _clean_name(word: str) -> str:
    """Tên một từ khi gõ lệnh; dùng dấu gạch dưới cho tên nhiều từ (Minh_Anh → Minh Anh)."""
    return word.replace("_", " ").strip()


def _target(db, chat_id, words):
    """Xác định bé: tên trong câu → bé đã chọn cho chat → bé duy nhất. Trả (learner, words, lỗi)."""
    l, rest = _find_learner(db, words)
    if l:
        return l, rest, None
    st = db.get(ChatState, chat_id)
    if st and st.learner_id and (l := db.get(Learner, st.learner_id)):
        return l, words, None
    all_ = db.query(Learner).all()
    if len(all_) == 1:
        return all_[0], words, None
    if not all_:
        return None, words, "Chưa có thành viên nào. Gõ: thêm Bin thcs lớp 7"
    return None, words, "Bé nào? Thêm tên bé vào lệnh hoặc gõ: chọn " + "/".join(x.name for x in all_)


def _fmt_task(t: Task, names: dict) -> str:
    mark = "✅" if t.done else "⬜"
    late = " ⚠️trễ" if (not t.done and t.due and t.due < date.today().isoformat()) else ""
    due = f" · hạn {t.due[8:10]}/{t.due[5:7]}" if t.due else ""
    return f"{mark} #{t.id} {t.title}{due}{late} ({names.get(t.learner_id, '?')})"


def _subject(word_list: list[str]):
    """Tìm tên môn ở đầu danh sách từ. Trả (môn|None, số_từ_dùng)."""
    for n in (2, 1):
        if len(word_list) >= n:
            cand = norm(" ".join(word_list[:n]))
            for s in rules.SUBJECTS:
                if norm(s) == cand:
                    return s, n
    return None, 0


def handle(db, chat_id: str, text: str) -> str | None:
    text = (text or "").strip()
    if not text:
        return None
    words = text.lstrip("/").split()
    if not words:
        return None
    cmd, args = norm(words[0]), words[1:]
    if args and cmd + norm(args[0]) in ("baocao", "danhsach", "thanhvien", "hoanthanh", "doiten", "suaten"):
        cmd, args = cmd + norm(args[0]), args[1:]

    if cmd in ("menu", "help", "giup", "huongdan", "?", "start"):
        return HELP

    if cmd in ("them", "add"):
        if not args:
            return "Cú pháp: thêm Bin thcs lớp 7"
        name, level = _clean_name(args[0]), None
        rest = args[1:]
        if rest and norm(rest[0]) in LEVEL_WORDS:
            level, rest = LEVEL_WORDS[norm(rest[0])], rest[1:]
        grade = " ".join(rest)
        level = level or infer_level(grade) or "thcs"
        if any(norm(l.name) == norm(name) for l in db.query(Learner)):
            return f"Đã có {name} rồi."
        l = Learner(name=name, level=level, grade=grade)
        db.add(l)
        db.commit()
        if db.query(Learner).count() == 1:
            db.merge(ChatState(chat_id=chat_id, learner_id=l.id))
            db.commit()
        return f"✅ Đã thêm {l.name} ({rules.LEVELS[level].split(' (')[0]}{', ' + grade if grade else ''})."

    if cmd in ("doi", "doiten", "suaten", "sua", "rename"):
        old, rest = _find_learner(db, args)
        if not old:
            return "Cú pháp: đổi Bin Minh  (tên cũ rồi tên mới; tên nhiều từ dùng gạch dưới: Minh_Anh). Gõ 'bé' để xem danh sách."
        if not rest:
            return "Thiếu tên mới. Cú pháp: đổi Bin Minh"
        new = _clean_name(rest[0])
        if any(l.id != old.id and norm(l.name) == norm(new) for l in db.query(Learner)):
            return f"Đã có bạn tên {new} rồi."
        extra = rest[1:]
        level = None
        if extra and norm(extra[0]) in LEVEL_WORDS:
            level, extra = LEVEL_WORDS[norm(extra[0])], extra[1:]
        was, old.name = old.name, new
        if extra:
            old.grade = " ".join(extra)
            level = level or infer_level(old.grade)
        if level:
            old.level = level
        db.commit()
        return f"✏️ Đã đổi tên {was} → {new}" + (f" ({old.grade})" if extra else "") + "."

    if cmd in ("be", "thanhvien", "ds-be"):
        ls = db.query(Learner).order_by(Learner.id).all()
        return "\n".join(f"• {l.name} — {l.grade or l.level}" for l in ls) or "Chưa có thành viên."

    if cmd in ("chon", "dung"):
        l, _ = _find_learner(db, args)
        if not l:
            return "Không thấy bé đó. Gõ 'bé' để xem danh sách."
        db.merge(ChatState(chat_id=chat_id, learner_id=l.id))
        db.commit()
        return f"👍 Nhóm này đang theo dõi {l.name}."

    if cmd in ("viec", "giao", "bt", "baitap"):
        l, rest, err = _target(db, chat_id, args)
        if err:
            return err
        if not rest:
            return _list(db, l)
        due, rest, err = parse_due(rest)
        if err:
            return err
        subj, _ = _subject(rest)
        title = " ".join(rest).strip()
        if not title:
            return "Thiếu nội dung việc."
        t = Task(learner_id=l.id, title=title, subject=subj or "Khác", due=due)
        db.add(t)
        db.commit()
        return f"📝 Đã giao cho {l.name}: #{t.id} {title}" + (f" · hạn {due[8:10]}/{due[5:7]}" if due else "")

    if cmd in ("ds", "danhsach", "list"):
        l, _, err = _target(db, chat_id, args)
        return err or _list(db, l)

    if cmd in ("xong", "done", "hoanthanh"):
        if not args or not args[0].lstrip("#").isdigit():
            return "Cú pháp: xong 3"
        t = db.get(Task, int(args[0].lstrip("#")))
        if not t:
            return "Không có việc đó."
        t.done = 1
        db.commit()
        return f"✅ Xong: {t.title}"

    if cmd in ("hoc", "study"):
        l, rest, err = _target(db, chat_id, args)
        if err:
            return err
        subj, n = _subject(rest)
        rest = rest[n:]
        if not subj or not rest or not rest[0].isdigit():
            return "Cú pháp: học Bin Toán 45 hiểu 4  (môn + số phút, hiểu 1-5 là tuỳ chọn)"
        minutes, und = int(rest[0]), 3
        for i, w in enumerate(rest[1:], 1):
            if norm(w) == "hieu" and i + 1 < len(rest) and rest[i + 1].isdigit():
                und = int(rest[i + 1])
        if not 1 <= minutes <= 720 or not 1 <= und <= 5:
            return "Số phút 1-720, mức hiểu 1-5."
        db.add(StudyLog(learner_id=l.id, subject=subj, minutes=minutes, understanding=und))
        db.commit()
        return f"⏱️ Đã ghi {l.name}: {subj} {minutes} phút (hiểu {und}/5)."

    if cmd in ("baocao", "tuan", "report"):
        l, _, err = _target(db, chat_id, args)
        return err or report_text(db, l)

    return None


def _list(db, l: Learner) -> str:
    ts = db.query(Task).filter_by(learner_id=l.id).order_by(Task.done, Task.due).limit(15).all()
    names = {l.id: l.name}
    return f"📋 Việc của {l.name}:\n" + ("\n".join(_fmt_task(t, names) for t in ts) or "Không có việc nào.")


def report_text(db, l: Learner) -> str:
    logs = [{"subject": x.subject, "minutes": x.minutes, "understanding": x.understanding,
             "created_at": x.created_at} for x in db.query(StudyLog).filter_by(learner_id=l.id)]
    tasks = [{"title": x.title, "due": x.due, "done": x.done} for x in db.query(Task).filter_by(learner_id=l.id)]
    s = stats.weekly_summary(l.level, logs, tasks)
    out = [f"📊 {l.name} · {s['from'][5:]} → {s['to'][5:]}",
           f"⏱️ {s['total_minutes']} phút / {s['study_days']} ngày học",
           f"📝 {s['tasks_done']} xong · {s['tasks_open']} còn mở"]
    if s["tasks_overdue"]:
        out.append("⚠️ Trễ: " + ", ".join(s["tasks_overdue"]))
    for x in s["subjects"]:
        out.append(f"• {x['subject']}: {x['minutes']}′, hiểu {x['avg_understanding']}" + (" ⚠️" if x["weak"] else ""))
    if s["days_over_limit"]:
        out.append(f"🌙 Học quá {s['daily_limit']} phút: " + ", ".join(d[5:] for d in s["days_over_limit"]))
    return "\n".join(out)

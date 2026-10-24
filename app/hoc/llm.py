"""Hỏi đáp học tập qua API tương thích OpenAI (CentriX hoặc nhà cung cấp khác). Chỉ chạy khi đặt đủ biến môi trường:
LLM_API_KEY và LLM_BASE_URL (vd https://agent.cetrix.app/v1); LLM_MODEL tuỳ chọn — để trống thì tự chọn model từ GET /models.
Không đặt khóa → bot vẫn chạy bằng luật như cũ.
Chỉ gửi câu hỏi và cấp học; không gửi tên bé hay dữ liệu học tập."""
import logging
import os

import httpx

log = logging.getLogger("tamtri.llm")

SYSTEM = ("Bạn là gia sư thân thiện cho học sinh Việt Nam ({level}). Trả lời bằng tiếng Việt, ngắn gọn (tối đa khoảng 8 dòng), "
          "giải thích từng bước dễ hiểu và gợi ý để bé tự làm, đừng chỉ đưa đáp số. "
          "Nếu câu hỏi không liên quan học tập hoặc không phù hợp với trẻ em thì nhẹ nhàng từ chối.")


# Thứ tự ưu tiên khi tự chọn: model nhanh, rẻ, đủ tốt cho hỏi đáp bài tập.
PREFER = ("haiku", "gpt-4o-mini", "gpt-4.1-mini", "gemini-2.5-flash", "flash", "mini", "sonnet", "gpt-4o", "gpt")
SKIP = ("embed", "image", "vision-only", "tts", "whisper", "audio", "moderation", "rerank", "dall", "video")
_auto: dict[str, str] = {}


def configured() -> bool:
    return all(os.getenv(k) for k in ("LLM_API_KEY", "LLM_BASE_URL"))


def pick_model(ids: list[str]) -> str | None:
    ids = [i for i in ids if i and not any(w in i.lower() for w in SKIP)]
    for pref in PREFER:
        hit = sorted((i for i in ids if pref in i.lower()), reverse=True)   # bản mới (số lớn) lên trước
        if hit:
            return hit[0]
    return ids[0] if ids else None


def model(transport=None) -> str | None:
    """LLM_MODEL nếu đã đặt, nếu không thì tự chọn từ danh sách model của nhà cung cấp (nhớ lại sau lần đầu)."""
    if os.getenv("LLM_MODEL"):
        return os.environ["LLM_MODEL"]
    base = os.environ["LLM_BASE_URL"].rstrip("/")
    if base in _auto:
        return _auto[base]
    try:
        r = httpx.Client(timeout=20, transport=transport).get(
            base + "/models", headers={"Authorization": f"Bearer {os.environ['LLM_API_KEY']}"})
        r.raise_for_status()
        m = pick_model([x.get("id", "") for x in r.json().get("data", [])])
    except Exception as e:  # noqa: BLE001
        log.warning("LLM không lấy được danh sách model: %s", str(e)[:200])
        return None
    if m:
        _auto[base] = m
        log.info("LLM tự chọn model: %s", m)
    return m


def ask(question: str, level_desc: str = "", transport=None) -> str | None:
    """Trả lời của gia sư AI, hoặc None nếu chưa cấu hình / lỗi."""
    if not configured():
        return None
    name = model(transport)
    if not name:
        return None
    url = os.environ["LLM_BASE_URL"].rstrip("/") + "/chat/completions"
    body = {"model": name, "max_tokens": 600, "messages": [
        {"role": "system", "content": SYSTEM.format(level=level_desc or "học sinh")},
        {"role": "user", "content": question[:1500]}]}
    try:
        r = httpx.Client(timeout=40, transport=transport).post(
            url, json=body, headers={"Authorization": f"Bearer {os.environ['LLM_API_KEY']}"})
        r.raise_for_status()
        text = (r.json()["choices"][0]["message"]["content"] or "").strip()
        return ("🎓 " + text[:1800]) if text else None
    except Exception as e:  # noqa: BLE001
        log.warning("LLM lỗi: %s", str(e)[:200])     # không log header/key
        return None

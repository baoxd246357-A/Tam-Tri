"""Hỏi đáp học tập qua API tương thích OpenAI (CentriX hoặc nhà cung cấp khác). Chỉ chạy khi đặt đủ biến môi trường:
LLM_API_KEY, LLM_BASE_URL (vd https://agent.cetrix.app/v1), LLM_MODEL. Không đặt → bot vẫn chạy bằng luật như cũ.
Chỉ gửi câu hỏi và cấp học; không gửi tên bé hay dữ liệu học tập."""
import logging
import os

import httpx

log = logging.getLogger("tamtri.llm")

SYSTEM = ("Bạn là gia sư thân thiện cho học sinh Việt Nam ({level}). Trả lời bằng tiếng Việt, ngắn gọn (tối đa khoảng 8 dòng), "
          "giải thích từng bước dễ hiểu và gợi ý để bé tự làm, đừng chỉ đưa đáp số. "
          "Nếu câu hỏi không liên quan học tập hoặc không phù hợp với trẻ em thì nhẹ nhàng từ chối.")


def configured() -> bool:
    return all(os.getenv(k) for k in ("LLM_API_KEY", "LLM_BASE_URL", "LLM_MODEL"))


def ask(question: str, level_desc: str = "", transport=None) -> str | None:
    """Trả lời của gia sư AI, hoặc None nếu chưa cấu hình / lỗi."""
    if not configured():
        return None
    url = os.environ["LLM_BASE_URL"].rstrip("/") + "/chat/completions"
    body = {"model": os.environ["LLM_MODEL"], "max_tokens": 600, "messages": [
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

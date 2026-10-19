"""Gọi Gemini cho gia sư AI. Dùng lại ai_client của kiểu QBcons: retry khi quá tải, JSON có schema."""
import json
import os
import re
import time

from fastapi import HTTPException
from google import genai
from google.genai import types

from . import rules


def get_client():
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="GEMINI_API_KEY chưa được cấu hình")
    return genai.Client(api_key=key)


def _clean(text: str) -> str:
    text = (text or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    return text


_RETRY = ("429", "500", "502", "503", "504", "UNAVAILABLE", "RESOURCE_EXHAUSTED",
          "TOO MANY REQUESTS", "RATE LIMIT", "HIGH DEMAND", "TIMEOUT", "TIMED OUT")


def _with_retry(call, attempts=4):
    delays = [2, 4, 8]
    for i in range(attempts):
        try:
            return call()
        except Exception as exc:
            if i >= attempts - 1 or not any(m in str(exc).upper() for m in _RETRY):
                raise
            time.sleep(delays[i])


TUTOR_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "subject": {"type": "STRING"},
        "topic": {"type": "STRING"},
        "problem": {"type": "STRING"},
        "hint": {"type": "STRING"},
        "steps": {"type": "ARRAY", "items": {"type": "STRING"}},
        "answer": {"type": "STRING"},
        "mistakes": {"type": "ARRAY", "items": {"type": "STRING"}},
        "concepts_to_review": {"type": "ARRAY", "items": {"type": "STRING"}},
        "practice": {"type": "ARRAY", "items": {"type": "STRING"}},
        "encouragement": {"type": "STRING"},
        "confidence": {"type": "NUMBER"},
    },
    "required": ["subject", "topic", "problem", "hint", "steps", "answer", "mistakes",
                 "concepts_to_review", "practice", "encouragement", "confidence"],
}


def tutor(learner: dict, subject: str, text: str, hint_level: int, image: tuple | None):
    """image: (bytes, mime) hoặc None. Trả (dict, raw)."""
    client = get_client()
    model = os.getenv("GEMINI_MODEL", "gemini-3.7-flash")
    ladder = "\n".join(f"  {i}. {s}" for i, s in enumerate(rules.HINT_LADDER, 1))
    prompt = f"""
Bạn là gia sư AI cho gia đình Việt Nam. Người học: {learner.get("name")}, {learner.get("grade") or "chưa rõ lớp"}.
Cách giải thích theo cấp học: {rules.LEVELS.get(learner.get("level"), rules.LEVELS["thcs"])}
Mục tiêu của người học: {learner.get("goal") or "không nêu"}.
Môn (người học chọn): {subject}. Câu hỏi/ghi chú: {text or "(chỉ có ảnh)"}

Nguyên tắc:
- Chỉ dựa vào những gì đọc được trong ảnh/câu hỏi. Chữ mờ hoặc thiếu đề thì nói rõ, KHÔNG bịa đề.
- Mục tiêu là giúp người học hiểu, không chép đáp án. Thang gợi ý:
{ladder}
- Mức gợi ý hiện tại = {hint_level}. Chỉ điền "answer" và "steps" đầy đủ khi mức >= 4.
  Ở mức thấp hơn: "hint" là phần chính, "steps" tối đa theo mức, "answer" để chuỗi rỗng.
- Nếu ảnh là bài làm của người học: tìm lỗi sai thật sự trong "mistakes", giải thích vì sao sai.
  Không có lỗi thì để mảng rỗng. Đừng khen chung chung nếu chưa kiểm tra.
- "practice": 2-3 câu tương tự, dễ hơn hoặc bằng, để luyện lại.
- "confidence" 0-1: mức chắc chắn của bạn về đọc đề và lời giải. Môn tính toán chưa kiểm lại thì hạ xuống.
- Viết tiếng Việt, thân thiện, đúng tầm người học. Công thức viết dạng chữ dễ đọc.
Trả về DUY NHẤT JSON đúng schema.
"""
    contents = [prompt]
    if image:
        contents.append(types.Part.from_bytes(data=image[0], mime_type=image[1]))
    resp = _with_retry(lambda: client.models.generate_content(
        model=model, contents=contents,
        config=types.GenerateContentConfig(
            response_mime_type="application/json", response_schema=TUTOR_SCHEMA),
    ))
    raw = resp.text
    return json.loads(_clean(raw)), raw


def weekly_note(learner: dict, summary: dict) -> str:
    """Nhận xét ngắn cho phụ huynh dựa trên số liệu đã tính (AI không tự thêm số)."""
    client = get_client()
    model = os.getenv("GEMINI_MODEL", "gemini-3.7-flash")
    prompt = f"""
Viết nhận xét tuần cho phụ huynh về {learner.get("name")} ({learner.get("grade") or ""}), tiếng Việt, tối đa 120 từ.
Chỉ dùng số liệu dưới đây, không thêm số liệu mới, không phán xét, nêu 1 điểm tốt và 1-2 việc nên làm tuần tới.
Số liệu: {json.dumps(summary, ensure_ascii=False)}
"""
    resp = _with_retry(lambda: client.models.generate_content(model=model, contents=[prompt]))
    return (resp.text or "").strip()

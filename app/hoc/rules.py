"""Bảng quy tắc học tập — phụ huynh chỉnh ở đây, không cần sửa code.

Tương tự bảng thông số kết cấu của QBcons: giá trị tạm, `REVIEWED = False` cho đến khi
phụ huynh đọc lại, chỉnh theo con mình rồi đặt `REVIEWED = True`.
"""

REVIEWED = False

SUBJECTS = [
    "Toán", "Ngữ văn", "Tiếng Anh", "Vật lý", "Hóa học", "Sinh học",
    "Lịch sử", "Địa lý", "Tin học", "Khác",
]

# Cấp học → mô tả cách giải thích cho đúng tầm
LEVELS = {
    "tieu_hoc": "Tiểu học (lớp 1-5): câu ngắn, ví dụ đời thường, nhiều khích lệ, tránh thuật ngữ.",
    "thcs": "THCS (lớp 6-9): giải thích khái niệm, gợi ý từng bước, có ví dụ tương tự.",
    "thpt": "THPT (lớp 10-12): lập luận chặt chẽ, nêu công thức/định lý liên quan, chú ý thi cử.",
    "dai_hoc": "Đại học/người lớn: ngắn gọn, nêu nguồn khái niệm, cho hướng tự kiểm tra.",
}

# Cảnh báo thời lượng học liên tục (phút/ngày) theo cấp
DAILY_MINUTES_SOFT_LIMIT = {"tieu_hoc": 120, "thcs": 180, "thpt": 240, "dai_hoc": 360}
DEFAULT_SOFT_LIMIT = 180

# Môn bị coi là "cần chú ý" nếu điểm tự đánh giá/độ hiểu trung bình dưới ngưỡng (1-5)
WEAK_UNDERSTANDING_BELOW = 3.0

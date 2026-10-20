"""CSDL cho module học tập.

Mặc định SQLite (data/hoc.db) — trên Render gói Free file này mất khi app ngủ/deploy lại.
Đặt biến DATABASE_URL (Postgres, VD Neon/Supabase) để dữ liệu được giữ lâu dài.
"""
import os
from datetime import datetime
from pathlib import Path

from sqlalchemy import Column, DateTime, Float, Integer, String, Text, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

BASE = Path(__file__).resolve().parent.parent.parent
DATA = BASE / "data"
UPLOADS = DATA / "hoc_uploads"
UPLOADS.mkdir(parents=True, exist_ok=True)



def normalize_db_url(url: str) -> str:
    """postgres:// (kiểu Heroku/Neon cũ) → postgresql+psycopg2:// để SQLAlchemy nhận."""
    url = url.strip()
    for old in ("postgres://", "postgresql://"):
        if url.startswith(old):
            return "postgresql+psycopg2://" + url[len(old):]
    return url


def make_engine(url: str | None = None):
    url = normalize_db_url(url or os.getenv("DATABASE_URL", ""))
    if not url:
        return create_engine(f"sqlite:///{DATA / 'hoc.db'}", connect_args={"check_same_thread": False})
    # pool_pre_ping/recycle: Postgres miễn phí tự ngắt kết nối khi rảnh
    return create_engine(url, pool_pre_ping=True, pool_recycle=300)


engine = make_engine()
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class Learner(Base):
    __tablename__ = "hoc_learners"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    level = Column(String(20), default="thcs")
    grade = Column(String(20), default="")
    goal = Column(String(255), default="")
    created_at = Column(DateTime, default=datetime.utcnow)


class StudyLog(Base):
    __tablename__ = "hoc_logs"
    id = Column(Integer, primary_key=True)
    learner_id = Column(Integer, nullable=False)
    subject = Column(String(50), default="Khác")
    minutes = Column(Integer, default=0)
    understanding = Column(Integer, default=3)          # 1-5 tự đánh giá
    note = Column(Text, default="")
    created_at = Column(DateTime, default=datetime.utcnow)


class Task(Base):
    __tablename__ = "hoc_tasks"
    id = Column(Integer, primary_key=True)
    learner_id = Column(Integer, nullable=False)
    title = Column(String(255), nullable=False)
    subject = Column(String(50), default="Khác")
    due = Column(String(10), default="")                # YYYY-MM-DD
    done = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)


class ChatState(Base):
    """Nhớ mỗi cuộc chat/nhóm Zalo đang 'chọn' bé nào."""
    __tablename__ = "hoc_chat_state"
    chat_id = Column(String(100), primary_key=True)
    learner_id = Column(Integer)


class ReminderSub(Base):
    """Chat/nhóm Zalo đăng ký nhận nhắc việc hằng ngày."""
    __tablename__ = "hoc_reminders"
    chat_id = Column(String(100), primary_key=True)
    last_sent = Column(String(10), default="")          # YYYY-MM-DD (giờ VN) lần nhắc gần nhất


Base.metadata.create_all(engine)

"""CSDL SQLite riêng cho module học tập (data/hoc.db)."""
from datetime import datetime
from pathlib import Path

from sqlalchemy import Column, DateTime, Float, Integer, String, Text, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

BASE = Path(__file__).resolve().parent.parent.parent
DATA = BASE / "data"
UPLOADS = DATA / "hoc_uploads"
UPLOADS.mkdir(parents=True, exist_ok=True)

engine = create_engine(
    f"sqlite:///{DATA / 'hoc.db'}", connect_args={"check_same_thread": False}
)
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


Base.metadata.create_all(engine)

"""Tên thương hiệu dùng chung cho toàn app. Đổi tên: sửa APP_NAME ở đây hoặc đặt biến môi trường APP_NAME."""
import os
import re

APP_NAME = os.getenv("APP_NAME", "QBcons")
APP_SLUG = re.sub(r"[^a-z0-9]+", "_", APP_NAME.lower()).strip("_") or "app"

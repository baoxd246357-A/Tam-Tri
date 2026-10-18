# Cài MCP AutoCAD (AutoCAD 2027) cho Claude Desktop

Chạy **trên Windows** (không phải WSL), cần `git`, `uv` (script hỏi cài bằng winget nếu thiếu).

```
install.bat
```

Script làm: kiểm tra yêu cầu → clone `gpt2nndk/autocad-mcp-nndk` → `uv sync` → tạo `C:\temp` →
ghi (có sao lưu `.bak`) mục `autocad-mcp` vào `%APPDATA%\Claude\claude_desktop_config.json` →
thử khởi động server. Tham số: `-InstallDir`, `-IpcDir`, `-Backend auto|file_ipc|ezdxf`, `-Timeout`.

**Không cần khóa API** cho MCP này.

Việc phải làm tay sau đó:
1. AutoCAD → `APPLOAD` → nạp `lisp-code\mcp_dispatch.lsp` (phải thấy `=== MCP Dispatch v3.1 loaded ===`).
2. Thoát hẳn rồi mở lại Claude Desktop.
3. Hỏi Claude: "gọi system status" → `backend: file_ipc` là thành công.

**Bảo mật:** công cụ `execute_lisp` chạy AutoLISP tùy ý. Đọc `mcp_dispatch.lsp` và `src\autocad_mcp` trước khi nạp.

Sự cố: xem mục "Sự cố thường gặp" trong hướng dẫn (hết thời gian → tăng `-Timeout`; báo `ezdxf` → chưa nạp LISP;
đổi `-IpcDir` → sửa `*mcp-ipc-dir*` trong LISP; dùng tên layer không dấu).

"""Cau noi: giao dien web <-> model CentriX (OpenAI-compatible) <-> MCP AutoCAD (stdio)."""
import json, os, sys
from contextlib import AsyncExitStack, asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from openai import AsyncOpenAI

HERE = Path(__file__).parent
MAX_STEPS, MAX_RESULT = 12, 8000

SYSTEM = """Ban la tro ly shop drawing dang dieu khien AutoCAD qua cac cong cu MCP.
Quy tac: ve tung lo nho; sau moi lo doi chieu bang entity count theo layer; dung ten layer KHONG DAU;
neu ve sai thi dung drawing undo; don vi mm; tra loi ngan gon bang tieng Viet; khong doan so lieu, hay goi cong cu de kiem tra."""


def load_env():
    p = HERE / ".env"
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


load_env()
CFG = {
    "key": os.environ.get("CETRIX_API_KEY", ""),
    "base": os.environ.get("CETRIX_BASE_URL", "https://agent.cetrix.app/v1"),
    "model": os.environ.get("CETRIX_MODEL", ""),
    "py": os.environ.get("MCP_PYTHON", sys.executable),
    "lisp": os.environ.get("ALLOW_EXECUTE_LISP", "false").lower() == "true",
}
state = {}


@asynccontextmanager
async def lifespan(app):
    if not CFG["key"] or not CFG["model"]:
        print("THIEU CETRIX_API_KEY hoac CETRIX_MODEL trong .env")
    async with AsyncExitStack() as stack:
        params = StdioServerParameters(
            command=CFG["py"], args=["-m", "autocad_mcp"],
            env={**os.environ,
                 "AUTOCAD_MCP_BACKEND": os.environ.get("AUTOCAD_MCP_BACKEND", "auto"),
                 "AUTOCAD_MCP_IPC_TIMEOUT": os.environ.get("AUTOCAD_MCP_IPC_TIMEOUT", "30")})
        r, w = await stack.enter_async_context(stdio_client(params))
        sess = await stack.enter_async_context(ClientSession(r, w))
        await sess.initialize()
        tools = (await sess.list_tools()).tools
        if not CFG["lisp"]:
            tools = [t for t in tools if t.name != "execute_lisp"]
        state["sess"] = sess
        state["tools"] = [{"type": "function", "function": {
            "name": t.name, "description": t.description or "",
            "parameters": t.inputSchema or {"type": "object", "properties": {}}}} for t in tools]
        state["llm"] = AsyncOpenAI(api_key=CFG["key"] or "missing", base_url=CFG["base"])
        print(f"MCP san sang: {len(tools)} cong cu. Mo http://127.0.0.1:8765")
        yield


app = FastAPI(lifespan=lifespan)


@app.get("/")
def index():
    return FileResponse(HERE / "index.html")


@app.get("/api/status")
def status():
    return {"model": CFG["model"], "tools": [t["function"]["name"] for t in state.get("tools", [])],
            "key_set": bool(CFG["key"]), "execute_lisp": CFG["lisp"]}


async def call_tool(name, args):
    if name not in {t["function"]["name"] for t in state["tools"]}:
        return f"Cong cu '{name}' khong duoc phep."
    res = await state["sess"].call_tool(name, args)
    text = "\n".join(c.text for c in res.content if getattr(c, "type", "") == "text") or "(khong co ket qua)"
    if res.isError:
        text = "LOI: " + text
    return text[:MAX_RESULT]


@app.post("/api/chat")
async def chat(body: dict):
    if not CFG["key"] or not CFG["model"]:
        raise HTTPException(400, "Chua dat CETRIX_API_KEY / CETRIX_MODEL trong .env")
    history = body.get("messages", [])
    new = []
    for _ in range(MAX_STEPS):
        resp = await state["llm"].chat.completions.create(
            model=CFG["model"], tools=state["tools"],
            messages=[{"role": "system", "content": SYSTEM}] + history + new)
        msg = resp.choices[0].message
        entry = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            entry["tool_calls"] = [{"id": c.id, "type": "function",
                                    "function": {"name": c.function.name, "arguments": c.function.arguments}}
                                   for c in msg.tool_calls]
        new.append(entry)
        if not msg.tool_calls:
            return {"new": new}
        for c in msg.tool_calls:
            try:
                out = await call_tool(c.function.name, json.loads(c.function.arguments or "{}"))
            except Exception as e:  # tra loi loi cho model tu sua
                out = f"LOI: {e}"
            new.append({"role": "tool", "tool_call_id": c.id, "name": c.function.name, "content": out})
    new.append({"role": "assistant", "content": "Dung lai: vuot so buoc toi da. Hay kiem tra ban ve roi yeu cau tiep."})
    return {"new": new}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)

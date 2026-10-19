const $ = (s) => document.querySelector(s);
const esc = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
let who = null;

async function api(url, opt) {
  const r = await fetch(url, opt);
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.detail || r.statusText);
  return j;
}
const fd = (form) => new FormData(form);
const withWho = (f) => { f.append("learner_id", who); return f; };
const need = () => { if (!who) { alert("Hãy thêm thành viên trước"); return false; } return true; };

async function loadLearners(select) {
  const ls = await api("/api/v1/hoc/learners");
  $("#who").innerHTML = ls.map((l) => `<option value="${l.id}">${esc(l.name)}${l.grade ? " · " + esc(l.grade) : ""}</option>`).join("");
  if (select) $("#who").value = select;
  who = $("#who").value || null;
  refresh();
}

async function refresh() {
  if (!who) return;
  const ts = await api(`/api/v1/hoc/learners/${who}/tasks`);
  const today = new Date().toISOString().slice(0, 10);
  $("#tasks").innerHTML = ts.map((t) => `<li class="${t.done ? "done" : ""}${!t.done && t.due && t.due < today ? " late" : ""}">
    <input type="checkbox" data-task="${t.id}" ${t.done ? "checked" : ""}><span>${esc(t.title)} <small>${esc(t.subject)} ${esc(t.due)}</small></span></li>`).join("") || "<li>Chưa có việc.</li>";
}

$("#who").onchange = () => { who = $("#who").value; refresh(); };
$("#learnerForm").onsubmit = async (e) => {
  e.preventDefault();
  try { const l = await api("/api/v1/hoc/learners", { method: "POST", body: fd(e.target) }); e.target.reset(); loadLearners(l.id); } catch (x) { alert(x.message); }
};
$("#taskForm").onsubmit = async (e) => {
  e.preventDefault(); if (!need()) return;
  try { await api("/api/v1/hoc/tasks", { method: "POST", body: withWho(fd(e.target)) }); e.target.reset(); refresh(); } catch (x) { alert(x.message); }
};
$("#logForm").onsubmit = async (e) => {
  e.preventDefault(); if (!need()) return;
  try { await api("/api/v1/hoc/logs", { method: "POST", body: withWho(fd(e.target)) }); e.target.reset(); alert("Đã lưu"); } catch (x) { alert(x.message); }
};
$("#weeklyBtn").onclick = async () => {
  if (!need()) return; $("#weekly").textContent = "Đang tổng hợp…";
  try {
    const r = await api(`/api/v1/hoc/learners/${who}/weekly`); const s = r.summary;
    $("#weekly").innerHTML = `<p>${esc(s.from)} → ${esc(s.to)}</p>
      <table class="kv"><tr><td>Tổng thời gian</td><td><b>${s.total_minutes} phút</b> / ${s.study_days} ngày</td></tr>
      <tr><td>Việc</td><td>${s.tasks_done} xong · ${s.tasks_open} còn mở${s.tasks_overdue.length ? ` · <span class="bad">trễ: ${s.tasks_overdue.map(esc).join(", ")}</span>` : ""}</td></tr>
      ${s.days_over_limit.length ? `<tr><td>Học quá ${s.daily_limit} phút</td><td class="bad">${s.days_over_limit.join(", ")}</td></tr>` : ""}
      <tr><td>Môn</td><td>${s.subjects.map((x) => `${esc(x.subject)} ${x.minutes}′ (hiểu ${x.avg_understanding})${x.weak ? " ⚠️" : ""}`).join("<br>") || "—"}</td></tr></table>`;
  } catch (x) { $("#weekly").textContent = x.message; }
};
document.addEventListener("change", async (e) => {
  if (e.target.dataset.task) { await api(`/api/v1/hoc/tasks/${e.target.dataset.task}/toggle`, { method: "POST" }); refresh(); }
});

function say(cls, t) { const d = document.createElement("div"); d.className = "msg " + cls; d.textContent = t; $("#chatlog").append(d); d.scrollIntoView({ block: "end" }); }
async function send(text) {
  say("me", text);
  try {
    const f = new FormData(); f.append("text", text);
    say("bot", (await api("/api/v1/hoc/agent", { method: "POST", body: f })).reply);
    loadLearners(who);
  } catch (x) { say("bot", "Lỗi: " + x.message); }
}
$("#chatForm").onsubmit = (e) => { e.preventDefault(); const t = $("#chatText").value.trim(); if (t) { $("#chatText").value = ""; send(t); } };
document.querySelectorAll("[data-cmd]").forEach((b) => (b.onclick = () => send(b.dataset.cmd)));
say("bot", "Chào! Mình là trợ lý học tập của cả nhà. Gõ menu để xem lệnh.");
loadLearners();

const $ = (s) => document.querySelector(s);
const esc = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const li = (a) => (a && a.length ? `<ul>${a.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>` : "");
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

function renderAnswer(q) {
  const a = q.ai;
  if (!a || a.error) return `<div class="ans low">Lỗi AI: ${esc(a && a.error)}</div>`;
  const low = q.needs_review ? " low" : "";
  const warn = q.needs_review ? `<p class="bad">AI chưa chắc (${Math.round(q.confidence * 100)}%) — nhờ phụ huynh/thầy cô xem lại.</p>` : "";
  const more = q.hint_level < 4 ? `<button data-hint="${q.id}">Em vẫn chưa ra → gợi ý sâu hơn</button>` : "";
  return `<div class="ans${low}">
    <span class="chip">${esc(a.subject)}</span><span class="chip">${esc(a.topic)}</span><span class="chip">mức gợi ý ${q.hint_level}/4</span>
    ${warn}
    <h4>Đề hiểu là</h4><p>${esc(a.problem)}</p>
    <h4>💡 Gợi ý</h4><p>${esc(a.hint)}</p>
    ${a.steps && a.steps.length ? `<h4>Các bước</h4><ol>${a.steps.map((s) => `<li>${esc(s)}</li>`).join("")}</ol>` : ""}
    ${a.answer ? `<h4>Đáp án</h4><p>${esc(a.answer)}</p>` : ""}
    ${a.mistakes && a.mistakes.length ? `<h4>⚠️ Lỗi cần sửa</h4>${li(a.mistakes)}` : ""}
    ${a.concepts_to_review && a.concepts_to_review.length ? `<h4>📖 Ôn lại</h4>${li(a.concepts_to_review)}` : ""}
    ${a.practice && a.practice.length ? `<h4>✏️ Luyện thêm</h4>${li(a.practice)}` : ""}
    <p>${esc(a.encouragement)}</p>
    <div class="row">${more}
      <button data-rev="OK" data-q="${q.id}" ${q.parent_review === "OK" ? "disabled" : ""}>👍 Phụ huynh: đúng</button>
      <button data-rev="WRONG" data-q="${q.id}" ${q.parent_review === "WRONG" ? "disabled" : ""}>👎 Sai</button></div>
  </div>`;
}

async function refresh() {
  if (!who) return;
  const [qs, ts] = await Promise.all([api(`/api/v1/hoc/learners/${who}/questions`), api(`/api/v1/hoc/learners/${who}/tasks`)]);
  $("#history").innerHTML = qs.map((q) => `<div><small>${esc(q.created_at.slice(0, 16).replace("T", " "))} · ${esc(q.subject)} · ${esc(q.text.slice(0, 60))}</small>${renderAnswer(q)}</div>`).join("") || "<p>Chưa có câu hỏi.</p>";
  const today = new Date().toISOString().slice(0, 10);
  $("#tasks").innerHTML = ts.map((t) => `<li class="${t.done ? "done" : ""}${!t.done && t.due && t.due < today ? " late" : ""}">
    <input type="checkbox" data-task="${t.id}" ${t.done ? "checked" : ""}><span>${esc(t.title)} <small>${esc(t.subject)} ${esc(t.due)}</small></span></li>`).join("") || "<li>Chưa có việc.</li>";
}

$("#who").onchange = () => { who = $("#who").value; refresh(); };
$("#learnerForm").onsubmit = async (e) => {
  e.preventDefault();
  try { const l = await api("/api/v1/hoc/learners", { method: "POST", body: fd(e.target) }); e.target.reset(); loadLearners(l.id); } catch (x) { alert(x.message); }
};
$("#askForm").onsubmit = async (e) => {
  e.preventDefault(); if (!need()) return;
  const b = $("#askBtn"); b.disabled = true; b.textContent = "Gia sư đang đọc…";
  try {
    const q = await api("/api/v1/hoc/questions", { method: "POST", body: withWho(fd(e.target)) });
    $("#answer").innerHTML = renderAnswer(q); e.target.reset(); refresh();
  } catch (x) { $("#answer").innerHTML = `<div class="ans low">${esc(x.message)}</div>`; }
  b.disabled = false; b.textContent = "Hỏi gia sư";
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
    const r = await api(`/api/v1/hoc/learners/${who}/weekly?note=true`); const s = r.summary;
    $("#weekly").innerHTML = `<p>${esc(s.from)} → ${esc(s.to)}</p>
      <table class="kv"><tr><td>Tổng thời gian</td><td><b>${s.total_minutes} phút</b> / ${s.study_days} ngày</td></tr>
      <tr><td>Việc</td><td>${s.tasks_done} xong · ${s.tasks_open} còn mở${s.tasks_overdue.length ? ` · <span class="bad">trễ: ${s.tasks_overdue.map(esc).join(", ")}</span>` : ""}</td></tr>
      <tr><td>Câu hỏi AI</td><td>${s.questions} (${s.questions_need_review} cần phụ huynh xem)</td></tr>
      ${s.days_over_limit.length ? `<tr><td>Học quá ${s.daily_limit} phút</td><td class="bad">${s.days_over_limit.join(", ")}</td></tr>` : ""}
      <tr><td>Môn</td><td>${s.subjects.map((x) => `${esc(x.subject)} ${x.minutes}′ (hiểu ${x.avg_understanding})${x.weak ? " ⚠️" : ""}`).join("<br>") || "—"}</td></tr></table>
      ${r.ai_note ? `<div class="ans"><h4>Nhận xét AI</h4><p>${esc(r.ai_note)}</p></div>` : r.ai_note_error ? `<small>Không tạo được nhận xét AI: ${esc(r.ai_note_error)}</small>` : ""}`;
  } catch (x) { $("#weekly").textContent = x.message; }
};
document.addEventListener("click", async (e) => {
  const t = e.target;
  try {
    if (t.dataset.hint) { t.disabled = true; t.textContent = "Đang nghĩ…"; await api(`/api/v1/hoc/questions/${t.dataset.hint}/hint`, { method: "POST" }); refresh(); $("#answer").innerHTML = ""; }
    if (t.dataset.rev) { const f = new FormData(); f.append("verdict", t.dataset.rev); await api(`/api/v1/hoc/questions/${t.dataset.q}/review`, { method: "POST", body: f }); refresh(); }
  } catch (x) { alert(x.message); }
});
document.addEventListener("change", async (e) => {
  if (e.target.dataset.task) { await api(`/api/v1/hoc/tasks/${e.target.dataset.task}/toggle`, { method: "POST" }); refresh(); }
});
loadLearners();

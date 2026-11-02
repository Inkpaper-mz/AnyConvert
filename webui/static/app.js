const S = {
  target: "mp4",
  category: "视频",
  groups: {},
  targets: {},
  engines: {},
  options: { resolution: "original", width: 0, height: 0, quality: "balanced", fps: 0, audio_kbps: 192, codec: "h264" },
  workers: 3,
  jobs: [],
  uploading: 0,
};

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const STATUS = { queued: "等待", running: "转换中", done: "完成", failed: "失败", cancelled: "已取消" };
const RES_LABEL = { original: "保持原始", "2160": "4K", "1080": "1080p", "720": "720p", "480": "480p", "360": "360p", custom: "自定义" };

async function api(path, options = {}) {
  const response = await fetch(path, options);
  return response.json();
}

function toast(message, kind = "") {
  const node = document.createElement("div");
  node.className = `toast ${kind}`;
  node.textContent = message;
  $("toasts").appendChild(node);
  setTimeout(() => node.remove(), kind === "error" ? 6000 : 3200);
}

/* ---------------- 初始化 ---------------- */

async function init() {
  const state = await api("/api/state");
  S.groups = state.groups;
  S.targets = state.targets;
  S.engines = state.engines;
  S.options = state.options;
  S.workers = state.max_workers;
  $("workers").value = String(S.workers);

  renderEngines();
  renderCats();
  selectTarget(S.groups[S.category][0]);
  bindEvents();
  syncOptionsUI();
  poll();
  setInterval(poll, 700);
}

function renderEngines() {
  const box = $("engines");
  box.innerHTML = "";
  const labels = { ffmpeg: "FFmpeg", libreoffice: "LibreOffice", ocr: "OCR" };
  for (const [key, label] of Object.entries(labels)) {
    const info = S.engines[key] || { available: false };
    const pill = document.createElement("span");
    pill.className = `pill ${info.available ? "" : "off"}`;
    pill.innerHTML = `<i></i>${label}${info.bundled ? " · 自带" : ""}`;
    pill.title = info.path || "未就绪";
    box.appendChild(pill);
  }
}

function renderCats() {
  const box = $("cats");
  box.innerHTML = "";
  Object.keys(S.groups).forEach((name, index) => {
    const button = document.createElement("button");
    button.className = `cat ${index === 0 ? "active" : ""}`;
    button.textContent = name;
    button.onclick = () => {
      document.querySelectorAll(".cat").forEach((node) => node.classList.remove("active"));
      button.classList.add("active");
      S.category = name;
      renderFormats();
      selectTarget(S.groups[name][0]);
    };
    box.appendChild(button);
  });
  S.category = Object.keys(S.groups)[0];
  renderFormats();
}

function renderFormats() {
  const box = $("formats");
  box.innerHTML = "";
  (S.groups[S.category] || []).forEach((target) => {
    const button = document.createElement("button");
    button.className = `fmt ${target === S.target ? "active" : ""}`;
    button.innerHTML = `${target.toUpperCase()}<small>${S.targets[target] ? S.targets[target].sources : ""} 种源</small>`;
    button.onclick = () => selectTarget(target);
    box.appendChild(button);
  });
}

function selectTarget(target) {
  S.target = target;
  document.querySelectorAll(".fmt").forEach((node) => {
    node.classList.toggle("active", node.textContent.toLowerCase().startsWith(target));
  });
  const meta = S.targets[target];
  $("dropTarget").textContent = `目标 .${target} · ${meta ? meta.sources : "?"} 种源格式`;
}

/* ---------------- 上传 ---------------- */

function uploadFiles(files) {
  const list = Array.from(files || []);
  if (!list.length) return;
  S.uploading += list.length;
  updateButtons();
  let finished = 0;
  list.forEach((file) => {
    const params = new URLSearchParams({
      name: file.name,
      target: S.target,
      codec: S.options.codec,
      resolution: S.options.resolution,
      width: S.options.width || 0,
      height: S.options.height || 0,
      quality: S.options.quality,
      fps: S.options.fps || 0,
      audio_kbps: S.options.audio_kbps,
    });
    if ($("sizeToggle").checked) {
      params.set("target_bytes", String(Math.round(Number($("sizeValue").value) * 1024 * 1024)));
    }
    const xhr = new XMLHttpRequest();
    xhr.open("POST", `/api/upload?${params.toString()}`);
    xhr.onload = () => {
      try {
        const data = JSON.parse(xhr.responseText);
        if (!data.ok) toast(data.error || "这个文件不支持该目标格式", "error");
      } catch {
        toast("上传失败", "error");
      }
      finished += 1;
      if (finished === list.length) {
        S.uploading -= list.length;
        poll();
        setTimeout(() => { if (!S.uploading) start(); }, 120);
      }
    };
    xhr.onerror = () => { toast("网络错误，上传失败", "error"); S.uploading -= 1; };
    xhr.send(file);
  });
}

/* ---------------- 任务列表 ---------------- */

function poll() {
  api("/api/jobs").then((data) => {
    S.jobs = data.jobs || [];
    renderJobs(data.stats || {});
  }).catch(() => {});
}

function renderJobs(stats) {
  const box = $("jobs");
  const empty = $("empty");
  empty.style.display = S.jobs.length ? "none" : "block";
  box.querySelectorAll(".job").forEach((node) => node.remove());

  S.jobs.slice().reverse().forEach((job) => {
    const card = document.createElement("div");
    card.className = "job";
    const percent = Math.round((job.progress || 0) * 100);
    const actions = job.status === "done"
      ? `<a class="button-link" href="/api/download/${job.id}">下载</a><button data-reveal="${job.id}">打开目录</button>`
      : "";
    card.innerHTML = `
      <div>
        <div class="name" title="${esc(job.name)}">${esc(job.name)}</div>
        <div class="sub">${job.status === "failed" ? esc(job.error || "失败") : (job.output || "→ ." + job.target)}</div>
      </div>
      <span class="chip ${job.status}">${STATUS[job.status] || job.status}</span>
      <div class="bar"><i style="width:${percent}%"></i></div>
      <div class="sub">${job.status === "running" ? `${percent}% · ${Math.round(job.elapsed || 0)}s` : (job.status === "done" ? `${percent}%` : "")}</div>
      <div class="actions">${actions}</div>`;
    box.appendChild(card);
  });

  $("stats").textContent = `共 ${stats.total || 0} 个 · 完成 ${stats.done || 0} · 失败 ${stats.failed || 0} · 并行 ${stats.running || 0}/${S.workers}`;
  updateButtons(stats);
}

function updateButtons(stats = null) {
  const current = stats || { queued: S.jobs.filter((job) => job.status === "queued").length, running: S.jobs.filter((job) => job.status === "running").length };
  $("startBtn").disabled = !current.queued || S.uploading > 0;
  $("cancelBtn").disabled = !(current.queued || current.running);
}

async function start() {
  await api("/api/start", { method: "POST" });
  poll();
}

/* ---------------- 设置 ---------------- */

function syncOptionsUI() {
  const options = S.options;
  $("optResolution").value = options.resolution;
  $("optWidth").value = options.width || 1920;
  $("optHeight").value = options.height || 1080;
  $("optQuality").value = options.quality;
  $("optFps").value = String(options.fps || 0);
  $("optAudio").value = String(options.audio_kbps);
  $("optCodec").value = options.codec;
  $("customSizeRow").style.display = options.resolution === "custom" ? "flex" : "none";

  const res = options.resolution === "custom" ? `${options.width}×${options.height}` : (RES_LABEL[options.resolution] || "保持原始");
  const quality = { high: "高质量", balanced: "标准", small: "小体积" }[options.quality] || "标准";
  const fps = options.fps ? `${options.fps}fps` : "原始帧率";
  const codec = { h264: "H.264", h265: "H.265", av1: "AV1" }[options.codec] || "H.264";
  $("summaryBtn").textContent = `${res} · ${quality} · ${fps} · ${options.audio_kbps}k · ${codec}`;
}

function openSettings() {
  syncOptionsUI();
  $("settingsModal").classList.add("show");
}

async function saveOptions() {
  const resolution = $("optResolution").value;
  const values = {
    resolution,
    width: resolution === "custom" ? Number($("optWidth").value) : 0,
    height: resolution === "custom" ? Number($("optHeight").value) : 0,
    quality: $("optQuality").value,
    fps: Number($("optFps").value),
    audio_kbps: Number($("optAudio").value),
    codec: $("optCodec").value,
  };
  const data = await api("/api/options", { method: "POST", body: JSON.stringify(values) });
  S.options = data.options;
  syncOptionsUI();
  $("settingsModal").classList.remove("show");
  toast("设置已保存", "ok");
}

/* ---------------- 工具箱 ---------------- */

let toolName = null;

function openTools() {
  $("toolsModal").classList.add("show");
  $("toolResult").innerHTML = "";
}

async function runTool(name) {
  toolName = name;
  $("toolInput").value = "";
  $("toolInput").click();
}

async function handleToolFiles(files) {
  if (!files.length || !toolName) return;
  const tokens = [];
  for (const file of files) {
    const response = await fetch(`/api/temp?name=${encodeURIComponent(file.name)}`, { method: "POST", body: file });
    const data = await response.json();
    if (data.ok) tokens.push(data.token);
  }
  if (!tokens.length) { toast("上传失败", "error"); return; }

  const body = { files: tokens, level: Number($("zipLevel").value) };
  const response = await fetch(`/api/tool/${toolName}`, { method: "POST", body: JSON.stringify(body) });
  const data = await response.json();
  if (!data.ok) { $("toolResult").innerHTML = `<span style="color:var(--err)">${esc(data.error)}</span>`; return; }
  $("toolResult").innerHTML = `完成：<a href="${data.download}" download>${esc(data.name)}</a>`;
  toast("处理完成，点击链接下载", "ok");
}

/* ---------------- 事件 ---------------- */

function bindEvents() {
  $("pickBtn").onclick = () => $("fileInput").click();
  $("pickFolderBtn").onclick = () => $("folderInput").click();
  $("fileInput").onchange = (event) => uploadFiles(event.target.files);
  $("folderInput").onchange = (event) => uploadFiles(event.target.files);

  const drop = $("drop");
  ["dragenter", "dragover"].forEach((type) => drop.addEventListener(type, (event) => {
    event.preventDefault(); drop.classList.add("drag");
  }));
  ["dragleave", "drop"].forEach((type) => drop.addEventListener(type, (event) => {
    event.preventDefault(); drop.classList.remove("drag");
  }));
  drop.addEventListener("drop", (event) => uploadFiles(event.dataTransfer.files));

  $("startBtn").onclick = start;
  $("cancelBtn").onclick = async () => { await api("/api/cancel", { method: "POST" }); poll(); };
  $("settingsBtn").onclick = openSettings;
  $("summaryBtn").onclick = openSettings;
  $("saveOptions").onclick = saveOptions;
  $("toolsBtn").onclick = openTools;
  $("toolInput").onchange = (event) => handleToolFiles(event.target.files);
  document.querySelectorAll(".tool").forEach((node) => node.onclick = () => runTool(node.dataset.tool));

  document.querySelectorAll("[data-close]").forEach((node) => node.onclick = () => {
    document.querySelectorAll(".modal").forEach((modal) => modal.classList.remove("show"));
  });
  document.querySelectorAll(".modal").forEach((modal) => modal.addEventListener("click", (event) => {
    if (event.target === modal) modal.classList.remove("show");
  }));

  $("sizeToggle").onchange = (event) => {
    $("sizeValue").disabled = !event.target.checked;
    $("downscale").disabled = !event.target.checked;
  };
  $("preset").onchange = (event) => {
    const value = event.target.value;
    if (!value) return;
    const [target, size] = value.split(":");
    const category = Object.keys(S.groups).find((name) => S.groups[name].includes(target));
    if (category) document.querySelectorAll(".cat").forEach((node) => {
      if (node.textContent === category) node.click();
    });
    if (size) {
      $("sizeToggle").checked = true;
      $("sizeValue").disabled = false;
      $("downscale").disabled = false;
      $("sizeValue").value = size;
    }
  };
  $("workers").onchange = async (event) => {
    const data = await api("/api/workers", { method: "POST", body: JSON.stringify({ value: Number(event.target.value) }) });
    S.workers = data.max_workers;
    poll();
  };

  document.addEventListener("click", async (event) => {
    const reveal = event.target.closest("[data-reveal]");
    if (reveal) await api(`/api/reveal/${reveal.dataset.reveal}`, { method: "POST" });
  });
}

init().then(() => {
  if (location.hash === "#settings") openSettings();
  if (location.hash === "#tools") openTools();
});

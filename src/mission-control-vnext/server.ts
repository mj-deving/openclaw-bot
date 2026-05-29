type CommandResult = {
  ok: boolean;
  code: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
};

const port = Number(process.env.MC_VNEXT_PORT || "31879");
const host = process.env.MC_VNEXT_HOST || "127.0.0.1";
const operatorToken = process.env.MC_VNEXT_OPERATOR_TOKEN || "";
const openclawBin = process.env.OPENCLAW_BIN || "openclaw";
const commandPath = [
  "/home/openclaw/.bun/bin",
  "/home/openclaw/.npm-global/bin",
  "/home/openclaw/.local/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
].join(":");

const childEnv: Record<string, string> = {
  PATH: commandPath,
  HOME: process.env.HOME || "/home/openclaw",
  USER: process.env.USER || "openclaw",
  LOGNAME: process.env.LOGNAME || process.env.USER || "openclaw",
  SHELL: process.env.SHELL || "/bin/bash",
  LANG: process.env.LANG || "C.UTF-8",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function redact(text: string): string {
  return text
    .replace(/(sk-|e2b_|or-|op_)[A-Za-z0-9._-]{12,}/g, "$1[redacted]")
    .replace(/([A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD)[A-Z0-9_]*=)[^\s"'`]+/gi, "$1[redacted]")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, "Bearer [redacted]");
}

async function runCommand(command: string, args: string[], timeoutMs = 12000): Promise<CommandResult> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn([command, ...args], {
      env: childEnv,
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch (error) {
    return {
      ok: false,
      code: null,
      stdout: "",
      stderr: redact(error instanceof Error ? error.message : String(error)),
      timedOut: false,
    };
  }
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    proc.kill("SIGTERM");
  }, timeoutMs);
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout as ReadableStream<Uint8Array>).text(),
    new Response(proc.stderr as ReadableStream<Uint8Array>).text(),
    proc.exited,
  ]);
  clearTimeout(timer);
  const cleanedStdout = redact(stdout.trim());
  const cleanedStderr = redact(stderr.trim());
  return {
    ok: code === 0,
    code,
    stdout: cleanedStdout,
    stderr: cleanedStderr || (timedOut ? `command timed out after ${timeoutMs}ms` : ""),
    timedOut,
  };
}

async function getStatus() {
  const [service, enabled, version, config, controlUi, cron] = await Promise.all([
    runCommand("systemctl", ["is-active", "openclaw"], 5000),
    runCommand("systemctl", ["is-enabled", "openclaw"], 5000),
    runCommand(openclawBin, ["--version"], 5000),
    runCommand(openclawBin, ["config", "validate"], 8000),
    fetch("http://127.0.0.1:18789/", { signal: AbortSignal.timeout(5000) })
      .then((response) => ({ ok: response.ok, status: response.status }))
      .catch((error) => ({ ok: false, status: 0, error: String(error) })),
    runCommand(openclawBin, ["cron", "list", "--json"], 10000),
  ]);

  const cronList = parseList(cron.stdout, "jobs");

  return {
    service: service.stdout || service.stderr,
    enabled: enabled.stdout || enabled.stderr,
    version: version.stdout || version.stderr,
    config: {
      ok: config.ok,
      output: config.stdout || config.stderr,
    },
    controlUi,
    cron: {
      ok: cron.ok,
      count: cronList.length,
      error: cron.ok ? null : cron.stderr || cron.stdout,
    },
    checkedAt: new Date().toISOString(),
  };
}

function parseList(text: string, preferredKey?: string): unknown[] {
  try {
    const parsed = JSON.parse(text || "[]");
    if (Array.isArray(parsed)) return parsed;
    if (preferredKey && parsed && typeof parsed === "object" && Array.isArray((parsed as Record<string, unknown>)[preferredKey])) {
      return (parsed as Record<string, unknown>)[preferredKey] as unknown[];
    }
    return [];
  } catch {
    return [];
  }
}

function parseObject(text: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(text || "{}");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function readString(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function extractAgentReply(payload: Record<string, unknown>, fallback: string): string {
  const direct = payload.reply || payload.message || payload.output;
  if (typeof direct === "string" && direct.trim()) return direct;

  const result = payload.result;
  if (result && typeof result === "object" && !Array.isArray(result)) {
    const resultRecord = result as Record<string, unknown>;
    const payloads = resultRecord.payloads;
    if (Array.isArray(payloads)) {
      const text = payloads
        .map((item) => item && typeof item === "object" ? (item as Record<string, unknown>).text : null)
        .filter((text): text is string => typeof text === "string" && text.trim().length > 0)
        .join("\n\n");
      if (text) return text;
    }
  }

  return fallback;
}

function cronIdFromBody(body: Record<string, unknown>): string | null {
  const id = readString(body.id).trim();
  return /^[A-Za-z0-9._:-]{8,120}$/.test(id) ? id : null;
}

function summarizeJournalJson(text: string): string {
  const counts = new Map<string, number>();
  let total = 0;
  let lastAt = "";
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      const entry = JSON.parse(line) as Record<string, unknown>;
      const priority = readString(entry.PRIORITY, "unknown");
      counts.set(priority, (counts.get(priority) || 0) + 1);
      const timestamp = readString(entry.__REALTIME_TIMESTAMP);
      if (timestamp) lastAt = new Date(Number(timestamp) / 1000).toISOString();
      total += 1;
    } catch {
      // Do not expose raw log lines; malformed entries only affect counts.
      total += 1;
      counts.set("unparsed", (counts.get("unparsed") || 0) + 1);
    }
  }
  const byPriority = [...counts.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([priority, count]) => `priority ${priority}: ${count}`)
    .join("\n");
  return [
    `warning entries: ${total}`,
    lastAt ? `last entry: ${lastAt}` : "last entry: none",
    byPriority || "priority summary: none",
    "raw log messages withheld from dashboard",
  ].join("\n");
}

function isAuthorized(request: Request): boolean {
  if (!operatorToken) return false;
  const auth = request.headers.get("authorization") || "";
  return auth === `Bearer ${operatorToken}`;
}

function requireAuth(request: Request): Response | null {
  if (isAuthorized(request)) return null;
  return json({ error: "unauthorized" }, 401);
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

const html = String.raw`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mission Control vNext</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0b0d0c;
      --panel: #151816;
      --panel-2: #1d221f;
      --line: #343b36;
      --text: #f1f3ee;
      --muted: #a3aea5;
      --green: #65d46e;
      --amber: #f0b84f;
      --red: #ff6b62;
      --blue: #7db7ff;
      --ink: #090b0a;
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      background:
        linear-gradient(90deg, rgba(255,255,255,.035) 1px, transparent 1px),
        linear-gradient(rgba(255,255,255,.025) 1px, transparent 1px),
        var(--bg);
      background-size: 32px 32px;
      color: var(--text);
      font-family: "IBM Plex Mono", "Cascadia Code", "Fira Code", monospace;
      letter-spacing: 0;
    }
    button, input, textarea { font: inherit; }
    button {
      border: 1px solid var(--line);
      background: var(--panel-2);
      color: var(--text);
      min-height: 38px;
      padding: 0 12px;
      cursor: pointer;
    }
    button:hover { border-color: var(--blue); }
    button.primary { background: var(--green); color: var(--ink); border-color: var(--green); }
    button.danger { border-color: var(--red); color: var(--red); }
    input, textarea {
      width: 100%;
      background: #090b0a;
      border: 1px solid var(--line);
      color: var(--text);
      padding: 10px;
      resize: vertical;
    }
    .app {
      min-height: 100vh;
      display: grid;
      grid-template-columns: 280px 1fr;
    }
    aside {
      border-right: 1px solid var(--line);
      background: rgba(9, 11, 10, .92);
      padding: 18px;
      position: sticky;
      top: 0;
      height: 100vh;
    }
    main { padding: 18px; }
    h1, h2, h3 { margin: 0; font-weight: 700; }
    h1 { font-size: 20px; line-height: 1.2; }
    h2 { font-size: 14px; color: var(--muted); text-transform: uppercase; margin-bottom: 10px; }
    .brand { display: grid; gap: 8px; margin-bottom: 24px; }
    .tag { color: var(--green); font-size: 12px; }
    .nav { display: grid; gap: 8px; }
    .nav button { text-align: left; }
    .grid {
      display: grid;
      grid-template-columns: repeat(12, 1fr);
      gap: 12px;
    }
    .panel {
      border: 1px solid var(--line);
      background: rgba(21, 24, 22, .94);
      padding: 14px;
      min-height: 112px;
    }
    .span-3 { grid-column: span 3; }
    .span-4 { grid-column: span 4; }
    .span-6 { grid-column: span 6; }
    .span-8 { grid-column: span 8; }
    .span-12 { grid-column: span 12; }
    .kv { display: grid; gap: 8px; }
    .row { display: flex; justify-content: space-between; gap: 12px; border-bottom: 1px solid rgba(255,255,255,.06); padding: 6px 0; }
    .row:last-child { border-bottom: 0; }
    .muted { color: var(--muted); }
    .ok { color: var(--green); }
    .warn { color: var(--amber); }
    .bad { color: var(--red); }
    .list { display: grid; gap: 8px; max-height: 420px; overflow: auto; }
    .item { border: 1px solid rgba(255,255,255,.08); padding: 10px; background: rgba(0,0,0,.18); }
    .item header { display: flex; justify-content: space-between; gap: 12px; align-items: start; margin-bottom: 8px; }
    .item h3 { font-size: 13px; overflow-wrap: anywhere; }
    .pill { color: var(--ink); background: var(--muted); padding: 3px 7px; font-size: 11px; white-space: nowrap; }
    .pill.ok { background: var(--green); color: var(--ink); }
    .pill.warn { background: var(--amber); color: var(--ink); }
    .item-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }
    .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-bottom: 12px; }
    .chat { display: grid; gap: 10px; }
    .messages { min-height: 260px; max-height: 420px; overflow: auto; display: grid; gap: 8px; align-content: start; }
    .msg { border: 1px solid rgba(255,255,255,.08); padding: 10px; white-space: pre-wrap; }
    .msg.user { border-color: rgba(125,183,255,.45); }
    .msg.agent { border-color: rgba(101,212,110,.45); }
    pre { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; color: var(--muted); }
    .hidden { display: none !important; }
    .login {
      max-width: 560px;
      margin: 10vh auto;
      border: 1px solid var(--line);
      background: rgba(21, 24, 22, .96);
      padding: 22px;
      display: grid;
      gap: 14px;
    }
    @media (max-width: 900px) {
      .app { grid-template-columns: 1fr; }
      aside { position: static; height: auto; }
      .span-3, .span-4, .span-6, .span-8 { grid-column: span 12; }
    }
  </style>
</head>
<body>
  <div id="login" class="login">
    <h1>Mission Control vNext</h1>
    <p class="muted">Operator token required.</p>
    <input id="token" type="password" autocomplete="current-password" placeholder="operator token" />
    <button class="primary" id="saveToken">Unlock</button>
    <pre id="loginError"></pre>
  </div>

  <div id="app" class="app hidden">
    <aside>
      <div class="brand">
        <div class="tag">GREGOR / PRIVATE GATEWAY</div>
        <h1>Mission Control vNext</h1>
        <div class="muted" id="checkedAt">not checked</div>
      </div>
      <div class="nav">
        <button data-view="overview">Overview</button>
        <button data-view="chat">Chat</button>
        <button data-view="sessions">Sessions</button>
        <button data-view="cron">Cron</button>
        <button data-view="providers">Providers</button>
        <button data-view="diagnostics">Diagnostics</button>
        <button class="danger" id="lock">Lock</button>
      </div>
    </aside>
    <main>
      <section id="overview" class="view">
        <div class="toolbar"><button class="primary" id="refresh">Refresh</button></div>
        <div class="grid">
          <div class="panel span-3"><h2>Service</h2><div id="service" class="kv"></div></div>
          <div class="panel span-3"><h2>Gateway</h2><div id="gateway" class="kv"></div></div>
          <div class="panel span-3"><h2>Cron</h2><div id="cronSummary" class="kv"></div></div>
          <div class="panel span-3"><h2>Policy</h2><div class="kv"><div class="row"><span>Secrets</span><span class="ok">redacted</span></div><div class="row"><span>API</span><span>internal</span></div></div></div>
          <div class="panel span-12"><h2>Capabilities</h2><div id="caps" class="list"></div></div>
        </div>
      </section>
      <section id="chat" class="view hidden">
        <div class="panel chat">
          <h2>Chat</h2>
          <div class="kv" id="selectedSession"></div>
          <div id="messages" class="messages"></div>
          <textarea id="prompt" rows="4" placeholder="Send to Gregor main agent"></textarea>
          <button class="primary" id="send">Send</button>
        </div>
      </section>
      <section id="sessions" class="view hidden">
        <div class="toolbar"><button class="primary" id="refreshSessions">Refresh Sessions</button></div>
        <div id="sessionList" class="list"></div>
      </section>
      <section id="cron" class="view hidden">
        <div class="toolbar"><button class="primary" id="refreshCron">Refresh Cron</button></div>
        <div id="cronList" class="list"></div>
      </section>
      <section id="providers" class="view hidden">
        <div class="toolbar"><button class="primary" id="refreshProviders">Refresh Providers</button></div>
        <div id="providerList" class="list"></div>
      </section>
      <section id="diagnostics" class="view hidden">
        <div class="toolbar"><button class="primary" id="refreshLogs">Refresh Logs</button></div>
        <div class="panel"><h2>Recent Warnings</h2><pre id="logs"></pre></div>
      </section>
    </main>
  </div>

  <script>
    const state = { token: localStorage.getItem("mc_vnext_token") || "", status: null, selectedSessionId: "" };
    const $ = (id) => document.getElementById(id);
    const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
    const fmtDate = (ms) => ms ? new Date(ms).toLocaleString() : "unknown";
    const api = async (path, options = {}) => {
      const response = await fetch(path, {
        ...options,
        headers: {
          ...(options.headers || {}),
          authorization: "Bearer " + state.token,
          "content-type": "application/json",
        },
      });
      if (response.status === 401) throw new Error("unauthorized");
      return response.json();
    };
    const row = (k, v, cls = "") => '<div class="row"><span class="muted">' + esc(k) + '</span><span class="' + cls + '">' + esc(v) + '</span></div>';
    function showApp() { $("login").classList.add("hidden"); $("app").classList.remove("hidden"); }
    function showLogin() { $("app").classList.add("hidden"); $("login").classList.remove("hidden"); }
    function renderSelectedSession() { $("selectedSession").innerHTML = row("session", state.selectedSessionId || "main/default"); }
    async function loadOverview() {
      const [status, caps] = await Promise.all([api("/api/status"), api("/api/capabilities")]);
      state.status = status;
      $("checkedAt").textContent = status.checkedAt || "checked";
      $("service").innerHTML = row("unit", status.service, status.service === "active" ? "ok" : "bad") + row("enabled", status.enabled) + row("version", status.version);
      $("gateway").innerHTML = row("Control UI", status.controlUi?.status || 0, status.controlUi?.ok ? "ok" : "bad") + row("config", status.config?.ok ? "valid" : "invalid", status.config?.ok ? "ok" : "bad");
      $("cronSummary").innerHTML = row("list", status.cron?.ok ? "ok" : "fail", status.cron?.ok ? "ok" : "bad") + row("entries", status.cron?.count ?? "unknown");
      $("caps").innerHTML = (caps.capabilities || []).slice(0, 60).map((cap) => '<div class="item">' + esc(cap.id || cap.name || JSON.stringify(cap)) + '</div>').join("");
    }
    async function loadSessions() {
      const data = await api("/api/sessions");
      $("sessionList").innerHTML = (data.sessions || []).map((s) => {
        const title = s.key || s.sessionId || "unknown";
        return '<div class="item"><header><h3>' + esc(title) + '</h3><span class="pill">' + esc(s.kind || "session") + '</span></header>' +
          row("updated", fmtDate(s.updatedAt)) +
          row("model", [s.modelProvider, s.model].filter(Boolean).join("/") || "unknown") +
          row("tokens", s.totalTokens ?? "unknown") +
          row("runtime", s.agentRuntime?.id || "unknown") +
          '<button data-session-id="' + esc(s.sessionId || "") + '">Select</button>' +
          '</div>';
      }).join("");
      document.querySelectorAll("[data-session-id]").forEach((button) => button.addEventListener("click", () => {
        state.selectedSessionId = button.dataset.sessionId || "";
        renderSelectedSession();
        document.querySelectorAll(".view").forEach((view) => view.classList.add("hidden"));
        $("chat").classList.remove("hidden");
      }));
    }
    async function loadCron() {
      const data = await api("/api/cron");
      $("cronList").innerHTML = (data.cron || []).map((c) => {
        const id = c.uuid || c.id || c.name || "unknown";
        const enabled = c.enabled !== false;
        return '<div class="item"><header><h3>' + esc(c.name || id) + '</h3><span class="pill ' + (enabled ? "ok" : "warn") + '">' + (enabled ? "enabled" : "disabled") + '</span></header>' +
          row("id", id) +
          row("schedule", c.schedule?.expr || c.schedule?.kind || "unknown") +
          row("last", c.state?.lastStatus || c.status || "unknown") +
          row("next", fmtDate(c.state?.nextRunAtMs)) +
          '<div class="item-actions"><button data-cron-action="run" data-cron-id="' + esc(id) + '">Run</button><button data-cron-action="enable" data-cron-id="' + esc(id) + '">Enable</button><button data-cron-action="disable" data-cron-id="' + esc(id) + '">Disable</button></div>' +
          '<pre>' + esc(JSON.stringify(c, null, 2)) + '</pre></div>';
      }).join("");
      document.querySelectorAll("[data-cron-action]").forEach((button) => button.addEventListener("click", () => {
        const action = button.dataset.cronAction || "";
        const id = button.dataset.cronId || "";
        if (id && action) cronAction(id, action);
      }));
    }
    async function cronAction(id, action) {
      await api("/api/cron/" + action, { method: "POST", body: JSON.stringify({ id }) });
      await loadCron();
      await loadOverview();
    }
    async function loadProviders() {
      const data = await api("/api/providers");
      const auth = data.status?.auth || {};
      const providers = auth.providers || auth.oauth?.providers || [];
      $("providerList").innerHTML = providers.map((p) => {
        const name = p.provider || "provider";
        const status = p.status || p.effective?.kind || "configured";
        const labels = p.profiles?.labels || (p.profiles || []).map((profile) => profile.label || profile.profileId);
        return '<div class="item"><header><h3>' + esc(name) + '</h3><span class="pill ok">' + esc(status) + '</span></header>' +
          row("effective", p.effective?.kind || "profile") +
          row("detail", p.effective?.detail || "redacted") +
          '<pre>' + esc((labels || []).join("\\n") || "no labels") + '</pre></div>';
      }).join("") || '<div class="item">No provider details available.</div>';
    }
    async function loadLogs() {
      const data = await api("/api/logs");
      $("logs").textContent = data.logs || "No warning entries.";
    }
    async function sendChat() {
      const text = $("prompt").value.trim();
      if (!text) return;
      $("messages").insertAdjacentHTML("beforeend", '<div class="msg user">' + esc(text) + '</div>');
      $("prompt").value = "";
      const data = await api("/api/chat", { method: "POST", body: JSON.stringify({ message: text, sessionId: state.selectedSessionId }) });
      $("messages").insertAdjacentHTML("beforeend", '<div class="msg agent">' + esc(data.reply || data.output || JSON.stringify(data, null, 2)) + '</div>');
    }
    document.querySelectorAll("[data-view]").forEach((button) => button.addEventListener("click", () => {
      document.querySelectorAll(".view").forEach((view) => view.classList.add("hidden"));
      $(button.dataset.view).classList.remove("hidden");
    }));
    $("saveToken").onclick = async () => {
      state.token = $("token").value.trim();
      localStorage.setItem("mc_vnext_token", state.token);
      try { await loadOverview(); showApp(); } catch (error) { $("loginError").textContent = String(error); }
    };
    $("lock").onclick = () => { localStorage.removeItem("mc_vnext_token"); state.token = ""; showLogin(); };
    $("refresh").onclick = loadOverview;
    $("refreshSessions").onclick = loadSessions;
    $("refreshCron").onclick = loadCron;
    $("refreshProviders").onclick = loadProviders;
    $("refreshLogs").onclick = loadLogs;
    $("send").onclick = sendChat;
    renderSelectedSession();
    if (state.token) loadOverview().then(showApp).catch(showLogin);
  </script>
</body>
</html>`;

Bun.serve({
  hostname: host,
  port,
  idleTimeout: 180,
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/healthz" || url.pathname === "/health") {
      return json({ ok: true });
    }
    if (url.pathname === "/") {
      return new Response(html, {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store",
          "x-content-type-options": "nosniff",
          "referrer-policy": "no-referrer",
          "x-frame-options": "DENY",
        },
      });
    }
    const auth = requireAuth(request);
    if (auth) return auth;
    if (url.pathname === "/api/status") return json(await getStatus());
    if (url.pathname === "/api/capabilities") {
      const result = await runCommand(openclawBin, ["capability", "list", "--json"], 12000);
      const capabilities = parseList(result.stdout);
      return json({ ok: result.ok, capabilities, error: result.ok ? null : result.stderr || result.stdout });
    }
    if (url.pathname === "/api/cron") {
      const result = await runCommand(openclawBin, ["cron", "list", "--json"], 12000);
      const cron = parseList(result.stdout, "jobs");
      return json({ ok: result.ok, cron, error: result.ok ? null : result.stderr || result.stdout });
    }
    if (url.pathname === "/api/sessions") {
      const result = await runCommand(openclawBin, ["sessions", "--json", "--limit", "25"], 45000);
      const payload = parseObject(result.stdout);
      const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
      return json({ ok: result.ok, sessions, totalCount: payload.totalCount ?? sessions.length, error: result.ok ? null : result.stderr || result.stdout });
    }
    if (url.pathname === "/api/providers") {
      const result = await runCommand(openclawBin, ["capability", "model", "auth", "status", "--json"], 30000);
      const status = parseObject(result.stdout);
      return json({ ok: result.ok, status, error: result.ok ? null : result.stderr || result.stdout });
    }
    if (url.pathname.startsWith("/api/cron/") && request.method === "POST") {
      const action = url.pathname.split("/").pop() || "";
      if (!["run", "enable", "disable"].includes(action)) return json({ error: "unsupported cron action" }, 404);
      const body = await readJson(request);
      const id = cronIdFromBody(body);
      if (!id) return json({ error: "valid cron id required" }, 400);
      const args = action === "run"
        ? ["cron", "run", id, "--timeout", "30000"]
        : ["cron", action, id, "--timeout", "30000"];
      const result = await runCommand(openclawBin, args, 45000);
      return json({ ok: result.ok, output: result.stdout, error: result.ok ? null : result.stderr || result.stdout });
    }
    if (url.pathname === "/api/logs") {
      const result = await runCommand("journalctl", ["-u", "openclaw", "--since", "30 minutes ago", "-p", "warning", "--no-pager", "--output=json"], 12000);
      return json({ ok: result.ok, logs: result.ok ? summarizeJournalJson(result.stdout) : "diagnostics unavailable; raw logs withheld" });
    }
    if (url.pathname === "/api/chat" && request.method === "POST") {
      const body = await readJson(request);
      const message = String(body.message || "").slice(0, 8000).trim();
      const sessionId = String(body.sessionId || "").trim();
      if (!message) return json({ error: "message required" }, 400);
      const args = ["agent", "--agent", "main", "--json", "--timeout", "120", "--message", message];
      if (sessionId) args.push("--session-id", sessionId);
      const result = await runCommand(openclawBin, args, 140000);
      let reply = result.stdout;
      try {
        const parsed = JSON.parse(result.stdout);
        reply = extractAgentReply(parsed, result.stdout);
      } catch {
        // Keep raw redacted output.
      }
      return json({ ok: result.ok, reply, output: result.stdout, error: result.ok ? null : result.stderr });
    }
    return json({ error: "not found" }, 404);
  },
});

console.log(`Mission Control vNext listening on http://${host}:${port}`);

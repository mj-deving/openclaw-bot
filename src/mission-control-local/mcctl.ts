#!/usr/bin/env bun

import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { connect, createServer } from "node:net";
import { dirname, resolve } from "node:path";
import { homedir } from "node:os";

type Transport = "ssh-openclaw" | "mission-control" | "disabled";

type Target = {
  name: string;
  transport: Transport;
  description: string;
  host?: string;
  openclawBin?: string;
  url?: string;
  tokenRemotePath?: string;
  openclawConfigRemotePath?: string;
  disabledReason?: string;
};

type CommandResult = {
  ok: boolean;
  code: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
};

type TargetConfig = {
  targets?: Record<string, Partial<Target>>;
};

type ClawxStatus = {
  ok: boolean;
  tunnel: { ok: boolean; port: number };
  hostApi: { ok: boolean; port: number; status?: number; authorized: boolean; error?: string };
  handshake: { ok: boolean; signed: boolean; protocol: number; error?: string };
};

const defaultTargets: Record<string, Target> = {
  gregor: {
    name: "gregor",
    transport: "disabled",
    description: "Primary OpenClaw gateway target, configured locally.",
    disabledReason: "Configure gregor in .mcctl.local.json or set MCCTL_GREGOR_HOST and MCCTL_GREGOR_OPENCLAW_BIN.",
  },
  "mission-control": {
    name: "mission-control",
    transport: "disabled",
    description: "Mission Control web facade, configured locally.",
    disabledReason: "Configure mission-control in .mcctl.local.json or set MCCTL_MISSION_CONTROL_URL.",
  },
  hermes: {
    name: "hermes",
    transport: "disabled",
    description: "Future local/host runtime target placeholder.",
    disabledReason: "Hermes runtime is not ported into this control plane yet.",
  },
};

function loadConfig(): TargetConfig {
  const path = process.env.MCCTL_CONFIG || ".mcctl.local.json";
  if (!existsSync(path)) return {};
  return JSON.parse(readFileSync(path, "utf8")) as TargetConfig;
}

function buildTargets(): Record<string, Target> {
  const config = loadConfig();
  const merged: Record<string, Target> = { ...defaultTargets };
  for (const [name, override] of Object.entries(config.targets || {})) {
    const base = merged[name] || {
      name,
      transport: "disabled" as Transport,
      description: "Local target.",
      disabledReason: "Target is not configured.",
    };
    const target = { ...base, ...override, name };
    if (target.transport !== "disabled" && !override.disabledReason) target.disabledReason = undefined;
    merged[name] = target;
  }
  if (process.env.MCCTL_GREGOR_HOST) {
    const base = merged.gregor || {
      name: "gregor",
      transport: "disabled" as Transport,
      description: "Primary OpenClaw gateway target.",
    };
    merged.gregor = {
      ...base,
      name: "gregor",
      description: base.description || "Primary OpenClaw gateway target.",
      transport: "ssh-openclaw",
      host: process.env.MCCTL_GREGOR_HOST,
      openclawBin: process.env.MCCTL_GREGOR_OPENCLAW_BIN || "openclaw",
      openclawConfigRemotePath: process.env.MCCTL_GREGOR_OPENCLAW_CONFIG_REMOTE_PATH || base.openclawConfigRemotePath,
      disabledReason: undefined,
    };
  }
  if (process.env.MCCTL_MISSION_CONTROL_URL) {
    const base = merged["mission-control"] || {
      name: "mission-control",
      transport: "disabled" as Transport,
      description: "Mission Control web facade.",
    };
    merged["mission-control"] = {
      ...base,
      name: "mission-control",
      description: base.description || "Mission Control web facade.",
      transport: "mission-control",
      url: process.env.MCCTL_MISSION_CONTROL_URL,
      host: process.env.MCCTL_MISSION_CONTROL_HOST,
      tokenRemotePath: process.env.MCCTL_MISSION_CONTROL_TOKEN_REMOTE_PATH,
      disabledReason: undefined,
    };
  }
  return merged;
}

const targets = buildTargets();

const remoteNodeScript = String.raw`
const { spawnSync } = require("node:child_process");
const payload = JSON.parse(Buffer.from(process.env.MCCTL_PAYLOAD || "", "base64url").toString("utf8"));
const env = { ...process.env, PATH: ["/usr/local/bin", "/usr/bin", "/bin"].join(":") };
const result = spawnSync(payload.command, payload.args || [], { encoding: "utf8", env });
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
process.exit(result.status ?? 1);
`;

function redact(text: string): string {
  return text
    .replace(/(sk-|e2b_|or-|op_)[A-Za-z0-9._-]{12,}/g, "$1[redacted]")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, "Bearer [redacted]")
    .replace(/([A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD)[A-Z0-9_]*=)[^\s"'`]+/gi, "$1[redacted]");
}

function json(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}

function fail(message: string, code = 1): never {
  console.error(message);
  process.exit(code);
}

function parseArgs(argv: string[]): { positional: string[]; flags: Record<string, string | boolean> } {
  const positional: string[] = [];
  const flags: Record<string, string | boolean> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg) continue;
    if (arg === "--") {
      positional.push(...argv.slice(index + 1));
      break;
    }
    if (!arg.startsWith("-")) {
      positional.push(arg);
      continue;
    }
    const [rawKey, inlineValue] = arg.replace(/^-+/, "").split("=", 2);
    const key = rawKey || "";
    if (!key) continue;
    if (inlineValue !== undefined) {
      flags[key] = inlineValue;
      continue;
    }
    const next = argv[index + 1];
    if (next && !next.startsWith("-") && !["json", "deliver", "all-agents", "show", "help"].includes(key)) {
      flags[key] = next;
      index += 1;
    } else {
      flags[key] = true;
    }
  }
  if (flags.m && !flags.message) flags.message = flags.m;
  if (flags.h) flags.help = true;
  return { positional, flags };
}

function flagString(flags: Record<string, string | boolean>, key: string): string | undefined {
  const value = flags[key];
  return typeof value === "string" ? value : undefined;
}

function flagNumber(flags: Record<string, string | boolean>, key: string, fallback: number): number {
  const value = flagString(flags, key);
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function expandHome(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return `${homedir()}${path.slice(1)}`;
  return path;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}

function targetOrFail(name: string | undefined): Target {
  const target = targets[name || ""];
  if (!target) fail(`unknown target: ${name || "(missing)"}`);
  if (target.transport === "disabled") fail(`${target.name} disabled: ${target.disabledReason || "not configured"}`);
  return target;
}

function splitTargetAgent(spec: string | undefined): { targetName: string; agentId: string } {
  const [targetName, agentId] = (spec || "gregor/main").split("/", 2);
  return { targetName: targetName || "gregor", agentId: agentId || "main" };
}

async function runProcess(command: string[], stdin?: string, timeoutMs = 120000, redactOutput = true): Promise<CommandResult> {
  const proc = Bun.spawn(command, {
    stdin: stdin ? "pipe" : "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  if (stdin && proc.stdin) {
    proc.stdin.write(stdin);
    proc.stdin.end();
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
  return {
    ok: code === 0,
    code,
    stdout: redactOutput ? redact(stdout.trim()) : stdout.trim(),
    stderr: (redactOutput ? redact(stderr.trim()) : stderr.trim()) || (timedOut ? `command timed out after ${timeoutMs}ms` : ""),
    timedOut,
  };
}

async function runRemote(target: Target, command: string, args: string[], timeoutMs = 120000, redactOutput = true): Promise<CommandResult> {
  if (!target.host) fail(`target ${target.name} has no ssh host`);
  const payload = Buffer.from(JSON.stringify({ command, args })).toString("base64url");
  return runProcess(["ssh", target.host, "env", `MCCTL_PAYLOAD=${payload}`, "node", "-"], remoteNodeScript, timeoutMs, redactOutput);
}

async function runOpenClaw(target: Target, args: string[], timeoutMs = 120000): Promise<CommandResult> {
  if (target.transport !== "ssh-openclaw") fail(`target ${target.name} is not an OpenClaw SSH target`);
  return runRemote(target, target.openclawBin || "openclaw", args, timeoutMs);
}

async function isLocalPortOpen(port: number, host = "127.0.0.1", timeoutMs = 1000): Promise<boolean> {
  return await new Promise((resolveCheck) => {
    const socket = connect({ port, host });
    const done = (open: boolean) => {
      socket.destroy();
      resolveCheck(open);
    };
    socket.setTimeout(timeoutMs);
    socket.once("connect", () => done(true));
    socket.once("timeout", () => done(false));
    socket.once("error", () => done(false));
  });
}

async function isLocalPortFree(port: number, host = "127.0.0.1"): Promise<boolean> {
  return await new Promise((resolveCheck) => {
    const server = createServer();
    server.once("error", () => resolveCheck(false));
    server.listen(port, host, () => {
      server.close(() => resolveCheck(true));
    });
  });
}

async function fetchGregorGatewayToken(target: Target): Promise<string> {
  if (target.transport !== "ssh-openclaw") fail(`${target.name} is not an OpenClaw SSH target`);
  const remotePath = target.openclawConfigRemotePath || "~/.openclaw/openclaw.json";
  const script = `const fs=require('node:fs');const os=require('node:os');let p=${JSON.stringify(remotePath)};if(p==='~')p=os.homedir();else if(p.startsWith('~/'))p=os.homedir()+p.slice(1);const cfg=JSON.parse(fs.readFileSync(p,'utf8'));const token=cfg?.gateway?.auth?.token;if(typeof token!=='string'||!token)process.exit(2);process.stdout.write(token);`;
  const result = await runRemote(target, "node", ["-e", script], 20000, false);
  if (!result.ok || !result.stdout) fail(result.stderr || "gateway token lookup failed", result.code || 1);
  return result.stdout;
}

function parseJsonOutput<T>(result: CommandResult, fallback: T): T {
  if (!result.stdout) return fallback;
  try {
    return JSON.parse(result.stdout) as T;
  } catch {
    return fallback;
  }
}

function help(): void {
  console.log(`mcctl - local Mission Control router

Usage:
  bun run mcctl -- <command> [target] [options]
  bun run src/mission-control-local/mcctl.ts <command> [target] [options]

Commands:
  targets [--json]
  ask <target[/agent]> <message...> [--json] [--session-id id] [--session-key key] [--deliver] [--timeout seconds]
  sessions <target> [--json] [--agent id] [--all-agents] [--limit n] [--active minutes]
  agents <target> [--json]
  tasks <target> [--json] [--runtime name] [--status name]
  trace <target> [--json]
  open mission-control
  token mission-control --show
  clawx configure [gregor] [--settings path] [--port n]
  clawx tunnel [gregor] [--local-port n] [--remote-port n]
  clawx launch [--bin path] [-- <args...>]
  clawx status [gregor] [--port n] [--host-api-port n] [--host-api-token token]

Targets:
  gregor              SSH -> OpenClaw CLI on VPS
  mission-control     vNext web facade
  hermes              disabled placeholder

Defaults are private. Use --deliver only when you intend to post to a channel.`);
}

async function commandTargets(asJson: boolean): Promise<void> {
  const rows = Object.values(targets).map((target) => ({
    name: target.name,
    transport: target.transport,
    description: target.description,
    host: target.host,
    url: target.url,
    disabledReason: target.disabledReason,
  }));
  if (asJson) return json({ ok: true, targets: rows });
  for (const target of rows) {
    console.log(`${target.name}: ${target.transport}${target.disabledReason ? ` (${target.disabledReason})` : ""}`);
  }
}

async function commandAsk(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const { targetName, agentId } = splitTargetAgent(positional[0]);
  const target = targetOrFail(targetName);
  const message = flagString(flags, "message") || positional.slice(1).join(" ").trim();
  if (!message) fail("ask requires a message");
  const args = ["agent", "--agent", agentId, "--json", "--timeout", String(flagNumber(flags, "timeout", 120)), "--message", message];
  const sessionId = flagString(flags, "session-id");
  const sessionKey = flagString(flags, "session-key");
  if (sessionId) args.push("--session-id", sessionId);
  if (sessionKey) args.push("--session-key", sessionKey);
  if (flags.deliver) args.push("--deliver");
  const result = await runOpenClaw(target, args, (flagNumber(flags, "timeout", 120) + 20) * 1000);
  const parsed = parseJsonOutput<Record<string, unknown>>(result, {});
  if (asJson) return json({ ok: result.ok, target: target.name, agentId, delivered: Boolean(flags.deliver), result: parsed, stderr: result.stderr || null });
  if (!result.ok) fail(result.stderr || result.stdout || "ask failed", result.code || 1);
  const resultRecord = parsed.result && typeof parsed.result === "object" ? parsed.result as Record<string, unknown> : {};
  const payloads = Array.isArray(resultRecord.payloads) ? resultRecord.payloads : [];
  const text = payloads
    .map((item) => item && typeof item === "object" ? (item as Record<string, unknown>).text : null)
    .filter((item): item is string => typeof item === "string")
    .join("\n\n");
  console.log(text || result.stdout);
}

async function commandSessions(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  const args = ["sessions", "--json", "--limit", flagString(flags, "limit") || "25"];
  const agent = flagString(flags, "agent");
  const active = flagString(flags, "active");
  if (agent) args.push("--agent", agent);
  if (flags["all-agents"]) args.push("--all-agents");
  if (active) args.push("--active", active);
  const result = await runOpenClaw(target, args, 60000);
  const parsed = parseJsonOutput<Record<string, unknown>>(result, {});
  if (asJson) return json({ ok: result.ok, target: target.name, ...parsed, stderr: result.stderr || null });
  if (!result.ok) fail(result.stderr || result.stdout || "sessions failed", result.code || 1);
  const sessions = Array.isArray(parsed.sessions) ? parsed.sessions : [];
  for (const session of sessions) {
    const row = session as Record<string, unknown>;
    console.log(`${row.sessionId || "unknown"}  ${row.key || "unknown"}  ${row.kind || "session"}  ${row.modelProvider || ""}/${row.model || ""}`);
  }
}

async function commandAgents(positional: string[], asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  const result = await runOpenClaw(target, ["agents", "list", "--json"], 60000);
  const parsed = parseJsonOutput<unknown[]>(result, []);
  if (asJson) return json({ ok: result.ok, target: target.name, agents: parsed, stderr: result.stderr || null });
  if (!result.ok) fail(result.stderr || result.stdout || "agents failed", result.code || 1);
  for (const agent of parsed) {
    const row = agent as Record<string, unknown>;
    console.log(`${row.id || "unknown"}  ${row.identityName || ""}  ${row.model || ""}${row.isDefault ? "  default" : ""}`);
  }
}

async function commandTasks(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  const args = ["tasks", "list", "--json"];
  const runtime = flagString(flags, "runtime");
  const status = flagString(flags, "status");
  if (runtime) args.push("--runtime", runtime);
  if (status) args.push("--status", status);
  const result = await runOpenClaw(target, args, 60000);
  const parsed = parseJsonOutput<Record<string, unknown>>(result, {});
  if (asJson) return json({ ok: result.ok, target: target.name, ...parsed, stderr: result.stderr || null });
  if (!result.ok) fail(result.stderr || result.stdout || "tasks failed", result.code || 1);
  const tasks = Array.isArray(parsed.tasks) ? parsed.tasks : [];
  for (const task of tasks.slice(0, 30)) {
    const row = task as Record<string, unknown>;
    console.log(`${row.status || "unknown"}  ${row.runtime || "runtime"}  ${row.runId || row.taskId || "unknown"}  ${row.label || row.task || ""}`);
  }
}

async function commandTrace(positional: string[], asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  const [agentsResult, sessionsResult, tasksResult] = await Promise.all([
    runOpenClaw(target, ["agents", "list", "--json"], 60000),
    runOpenClaw(target, ["sessions", "--json", "--all-agents", "--limit", "50"], 60000),
    runOpenClaw(target, ["tasks", "list", "--json"], 60000),
  ]);
  const agents = parseJsonOutput<unknown[]>(agentsResult, []);
  const sessionPayload = parseJsonOutput<Record<string, unknown>>(sessionsResult, {});
  const taskPayload = parseJsonOutput<Record<string, unknown>>(tasksResult, {});
  const sessions = Array.isArray(sessionPayload.sessions) ? sessionPayload.sessions as Record<string, unknown>[] : [];
  const tasks = Array.isArray(taskPayload.tasks) ? taskPayload.tasks as Record<string, unknown>[] : [];
  const sessionByKey = new Map(sessions.map((session) => [String(session.key || ""), session]));
  const runs = tasks.slice(0, 50).map((task) => {
    const key = String(task.childSessionKey || task.ownerKey || task.requesterSessionKey || "");
    const session = sessionByKey.get(key);
    return {
      taskId: task.taskId,
      runId: task.runId,
      runtime: task.runtime,
      status: task.status,
      agentId: task.agentId,
      ownerKey: task.ownerKey,
      requesterSessionKey: task.requesterSessionKey,
      childSessionKey: task.childSessionKey,
      parentFlowId: task.parentFlowId,
      label: task.label,
      task: task.task,
      terminalSummary: task.terminalSummary,
      error: task.error,
      sessionId: session?.sessionId || null,
      sessionKind: session?.kind || null,
      model: [session?.modelProvider, session?.model].filter(Boolean).join("/") || null,
    };
  });
  const trace = {
    ok: agentsResult.ok && sessionsResult.ok && tasksResult.ok,
    target: target.name,
    agents,
    sessions: { totalCount: sessionPayload.totalCount ?? sessions.length, sessions },
    tasks: { count: taskPayload.count ?? tasks.length, tasks },
    runs,
    errors: [agentsResult, sessionsResult, tasksResult].map((result) => result.stderr).filter(Boolean),
  };
  if (asJson) return json(trace);
  for (const run of runs.slice(0, 30)) {
    console.log(`${run.status || "unknown"}  ${run.runtime || "runtime"}  ${run.runId || run.taskId || "unknown"}  ${run.childSessionKey || run.ownerKey || ""}`);
  }
}

async function commandOpen(positional: string[], asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "mission-control");
  if (target.transport !== "mission-control") fail(`${target.name} is not a Mission Control target`);
  const payload = {
    ok: true,
    target: target.name,
    url: target.url,
    tokenCommand: "bun run mcctl -- token mission-control --show",
  };
  if (asJson) return json(payload);
  console.log(target.url);
  console.log("token: bun run mcctl -- token mission-control --show");
}

async function commandToken(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "mission-control");
  if (target.transport !== "mission-control") fail(`${target.name} has no operator token`);
  if (!flags.show) {
    const payload = { ok: false, message: "refusing to print token without --show", command: "bun run mcctl -- token mission-control --show" };
    if (asJson) return json(payload);
    fail(`${payload.message}\n${payload.command}`, 2);
  }
  if (!target.tokenRemotePath) fail(`${target.name} has no tokenRemotePath configured`);
  const script = `const fs=require('node:fs');const p=${JSON.stringify(target.tokenRemotePath)};const line=fs.readFileSync(p,'utf8').split(/\\n/).find(l=>l.startsWith('MC_VNEXT_OPERATOR_TOKEN='));if(!line)process.exit(2);console.log(line.slice('MC_VNEXT_OPERATOR_TOKEN='.length));`;
  const result = await runRemote(target, "sudo", ["node", "-e", script], 20000);
  if (asJson) return json({ ok: result.ok, target: target.name, token: result.ok ? result.stdout : null, stderr: result.stderr || null });
  if (!result.ok) fail(result.stderr || "token lookup failed", result.code || 1);
  console.log(result.stdout);
}

function getClawxSettingsPath(flags: Record<string, string | boolean>): string {
  return resolve(expandHome(flagString(flags, "settings") || process.env.CLAWX_SETTINGS_PATH || "~/.config/clawx/settings.json"));
}

async function commandClawxConfigure(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  if (target.transport !== "ssh-openclaw") fail(`${target.name} is not an OpenClaw SSH target`);
  const port = flagNumber(flags, "port", 18789);
  const settingsPath = getClawxSettingsPath(flags);
  const token = await fetchGregorGatewayToken(target);
  let existing: Record<string, unknown> = {};
  if (existsSync(settingsPath)) {
    try {
      existing = JSON.parse(readFileSync(settingsPath, "utf8")) as Record<string, unknown>;
    } catch {
      existing = {};
    }
  }
  const nextSettings = {
    ...existing,
    gatewayAutoStart: false,
    gatewayExternalMode: true,
    gatewayPort: port,
    gatewayToken: token,
  };
  mkdirSync(dirname(settingsPath), { recursive: true });
  writeFileSync(settingsPath, `${JSON.stringify(nextSettings, null, 2)}\n`, { mode: 0o600 });
  try {
    chmodSync(settingsPath, 0o600);
  } catch {
    // best effort on non-POSIX filesystems
  }
  const payload = {
    ok: true,
    target: target.name,
    settingsPath,
    gatewayAutoStart: false,
    gatewayExternalMode: true,
    gatewayPort: port,
    tokenStored: true,
  };
  if (asJson) return json(payload);
  console.log(`settings: ${settingsPath}`);
  console.log(`gatewayPort: ${port}`);
  console.log("gatewayAutoStart: false");
  console.log("gatewayExternalMode: true");
  console.log("tokenStored: true");
}

async function commandClawxTunnel(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  if (!target.host) fail(`${target.name} has no ssh host`);
  const localPort = flagNumber(flags, "local-port", 18789);
  const remotePort = flagNumber(flags, "remote-port", 18789);
  if (!(await isLocalPortFree(localPort))) {
    fail(`local port ${localPort} is already in use`);
  }
  const forward = `127.0.0.1:${localPort}:127.0.0.1:${remotePort}`;
  const result = await runProcess(["ssh", "-f", "-N", "-L", forward, target.host], undefined, 15000);
  if (!result.ok) fail(result.stderr || result.stdout || "ssh tunnel failed", result.code || 1);
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (await isLocalPortOpen(localPort)) {
      const payload = { ok: true, target: target.name, localPort, remotePort };
      if (asJson) return json(payload);
      console.log(`tunnel: 127.0.0.1:${localPort} -> ${target.host}:127.0.0.1:${remotePort}`);
      return;
    }
    await sleep(250);
  }
  fail(`ssh tunnel started but local port ${localPort} did not open`);
}

function resolveClawxLaunchBin(flags: Record<string, string | boolean>): string {
  const explicit = flagString(flags, "bin") || process.env.CLAWX_BIN || process.env.CLAWX_APPIMAGE;
  if (explicit) return expandHome(explicit);
  const candidates = [
    "/home/USER/projects/oss/ClawX/releases/linux-unpacked/clawx",
    "/home/USER/projects/oss/ClawX/release/linux-unpacked/clawx",
    "/home/USER/projects/oss/ClawX/dist/linux-unpacked/clawx",
  ];
  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) fail("ClawX binary not found; pass --bin or set CLAWX_BIN");
  return found;
}

async function commandClawxLaunch(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const bin = resolveClawxLaunchBin(flags);
  const proc = Bun.spawn([bin, ...positional], {
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
    env: process.env,
  });
  const maybeUnref = proc as typeof proc & { unref?: () => void };
  maybeUnref.unref?.();
  const payload = { ok: true, bin, pid: proc.pid };
  if (asJson) return json(payload);
  console.log(`launched: ${bin}`);
  console.log(`pid: ${proc.pid}`);
}

async function requestHostSignedFrame(
  hostApiPort: number,
  hostApiToken: string,
  nonce: string,
): Promise<{ connectId: string; frame: Record<string, unknown> }> {
  const response = await fetch(`http://127.0.0.1:${hostApiPort}/api/gateway/connect-frame`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${hostApiToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      nonce,
      client: {
        id: "gateway-client",
        displayName: "mcctl ClawX status",
        version: "1.0.0",
        platform: "linux",
        mode: "ui",
      },
      caps: [],
    }),
  });
  if (!response.ok) {
    throw new Error(`Host API connect-frame HTTP ${response.status}`);
  }
  return await response.json() as { connectId: string; frame: Record<string, unknown> };
}

function buildTokenOnlyConnectFrame(token: string): { connectId: string; frame: Record<string, unknown> } {
  const connectId = `connect-${Date.now()}`;
  return {
    connectId,
    frame: {
      type: "req",
      id: connectId,
      method: "connect",
      params: {
        minProtocol: 4,
        maxProtocol: 4,
        client: {
          id: "gateway-client",
          displayName: "mcctl ClawX status",
          version: "1.0.0",
          platform: "linux",
          mode: "ui",
        },
        auth: { token },
        caps: [],
        role: "operator",
        scopes: ["operator.read", "operator.write", "operator.admin"],
      },
    },
  };
}

async function runProtocolHandshake(options: {
  port: number;
  target: Target;
  hostApiPort: number;
  hostApiToken?: string;
}): Promise<ClawxStatus["handshake"]> {
  return await new Promise((resolveHandshake) => {
    const ws = new WebSocket(`ws://127.0.0.1:${options.port}/ws`);
    let connectId = "";
    let settled = false;
    const finish = (result: ClawxStatus["handshake"]) => {
      if (settled) return;
      settled = true;
      try {
        ws.close();
      } catch {
        // ignore close failures
      }
      resolveHandshake(result);
    };
    const timer = setTimeout(() => {
      finish({ ok: false, signed: Boolean(options.hostApiToken), protocol: 4, error: "handshake timeout" });
    }, 12000);

    ws.addEventListener("message", (event) => {
      void (async () => {
        try {
          const message = JSON.parse(String(event.data)) as Record<string, unknown>;
          if (message.type === "event" && message.event === "connect.challenge") {
            const nonce = typeof (message.payload as Record<string, unknown> | undefined)?.nonce === "string"
              ? String((message.payload as Record<string, unknown>).nonce)
              : "";
            if (!nonce) {
              clearTimeout(timer);
              finish({ ok: false, signed: Boolean(options.hostApiToken), protocol: 4, error: "missing challenge nonce" });
              return;
            }
            const connectFrame = options.hostApiToken
              ? await requestHostSignedFrame(options.hostApiPort, options.hostApiToken, nonce)
              : buildTokenOnlyConnectFrame(await fetchGregorGatewayToken(options.target));
            connectId = connectFrame.connectId;
            ws.send(JSON.stringify(connectFrame.frame));
            return;
          }
          if (message.type === "res" && message.id === connectId) {
            clearTimeout(timer);
            if (message.ok === false || message.error) {
              finish({
                ok: false,
                signed: Boolean(options.hostApiToken),
                protocol: 4,
                error: redact(typeof message.error === "string" ? message.error : JSON.stringify(message.error || "connect failed")),
              });
              return;
            }
            finish({ ok: true, signed: Boolean(options.hostApiToken), protocol: 4 });
          }
        } catch (error) {
          clearTimeout(timer);
          finish({
            ok: false,
            signed: Boolean(options.hostApiToken),
            protocol: 4,
            error: redact(error instanceof Error ? error.message : String(error)),
          });
        }
      })();
    });
    ws.addEventListener("error", () => {
      clearTimeout(timer);
      finish({ ok: false, signed: Boolean(options.hostApiToken), protocol: 4, error: "websocket error" });
    });
  });
}

async function probeHostApi(port: number, token?: string): Promise<ClawxStatus["hostApi"]> {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/api/gateway/status`, {
      headers: token ? { Authorization: `Bearer ${token}` } : undefined,
    });
    return {
      ok: response.status === 401 || response.ok,
      port,
      status: response.status,
      authorized: response.ok,
    };
  } catch (error) {
    return {
      ok: false,
      port,
      authorized: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

async function commandClawxStatus(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const target = targetOrFail(positional[0] || "gregor");
  const port = flagNumber(flags, "port", 18789);
  const hostApiPort = flagNumber(flags, "host-api-port", 13210);
  const hostApiToken = flagString(flags, "host-api-token") || process.env.CLAWX_HOST_API_TOKEN;
  const tunnelOpen = await isLocalPortOpen(port);
  const hostApi = await probeHostApi(hostApiPort, hostApiToken);
  const handshake = tunnelOpen
    ? await runProtocolHandshake({ port, target, hostApiPort, hostApiToken })
    : { ok: false, signed: Boolean(hostApiToken), protocol: 4, error: "local tunnel closed" };
  const status: ClawxStatus = {
    ok: tunnelOpen && hostApi.ok && handshake.ok,
    tunnel: { ok: tunnelOpen, port },
    hostApi,
    handshake,
  };
  if (asJson) {
    json(status);
    if (!status.ok) process.exit(1);
    return;
  }
  console.log(`tunnel: ${status.tunnel.ok ? "ok" : "closed"} 127.0.0.1:${port}`);
  console.log(`hostApi: ${status.hostApi.ok ? "ok" : "down"} ${status.hostApi.authorized ? "authorized" : "unauthorized"} status=${status.hostApi.status ?? "n/a"}`);
  console.log(`handshake: ${status.handshake.ok ? "ok" : "failed"} protocol=${status.handshake.protocol} signed=${status.handshake.signed}`);
  if (status.handshake.error) console.log(`handshakeError: ${status.handshake.error}`);
  if (!status.ok) process.exit(1);
}

async function commandClawx(positional: string[], flags: Record<string, string | boolean>, asJson: boolean): Promise<void> {
  const subcommand = positional.shift();
  switch (subcommand) {
    case "configure":
      return commandClawxConfigure(positional, flags, asJson);
    case "tunnel":
      return commandClawxTunnel(positional, flags, asJson);
    case "launch":
      return commandClawxLaunch(positional, flags, asJson);
    case "status":
      return commandClawxStatus(positional, flags, asJson);
    default:
      fail(`unknown clawx command: ${subcommand || "(missing)"}`);
  }
}

async function main(): Promise<void> {
  const { positional, flags } = parseArgs(Bun.argv.slice(2));
  const command = positional.shift();
  const asJson = Boolean(flags.json);
  if (!command || flags.help) return help();
  switch (command) {
    case "targets":
      return commandTargets(asJson);
    case "ask":
      return commandAsk(positional, flags, asJson);
    case "sessions":
      return commandSessions(positional, flags, asJson);
    case "agents":
      return commandAgents(positional, asJson);
    case "tasks":
      return commandTasks(positional, flags, asJson);
    case "trace":
      return commandTrace(positional, asJson);
    case "open":
      return commandOpen(positional, asJson);
    case "token":
      return commandToken(positional, flags, asJson);
    case "clawx":
      return commandClawx(positional, flags, asJson);
    default:
      fail(`unknown command: ${command}`);
  }
}

main().catch((error) => fail(error instanceof Error ? error.message : String(error)));

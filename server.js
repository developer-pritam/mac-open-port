#!/usr/bin/env node
// Local dashboard for listening TCP ports on macOS: who owns them, who launched them, and a way to stop them.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');

const PORT = Number(process.env.PORT) || 7777;
const HOST = '127.0.0.1';
const INDEX = path.join(__dirname, 'public', 'index.html');

function run(cmd, args) {
  return new Promise((resolve) => {
    // lsof exits 1 when nothing matches; treat that as empty output rather than an error.
    execFile(cmd, args, { maxBuffer: 32 * 1024 * 1024 }, (err, stdout) => resolve(stdout || ''));
  });
}

// lsof -F output: one field per line, prefixed by a type char. p/c/L start a process, f/n describe a file.
async function listeners() {
  const out = await run('lsof', ['-nP', '-iTCP', '-sTCP:LISTEN', '-F', 'pcLn']);
  const rows = [];
  let cur = null;
  for (const line of out.split('\n')) {
    const t = line[0];
    const v = line.slice(1);
    if (t === 'p') cur = { pid: Number(v) };
    else if (t === 'c' && cur) cur.name = v;
    else if (t === 'L' && cur) cur.user = v;
    else if (t === 'n' && cur) {
      const i = v.lastIndexOf(':');
      const port = Number(v.slice(i + 1));
      if (Number.isInteger(port)) rows.push({ ...cur, address: v.slice(0, i), port });
    }
  }
  return rows;
}

async function processTable() {
  const [meta, args, comms] = await Promise.all([
    run('ps', ['-axo', 'pid=,ppid=,etime=,pcpu=,rss=,user=']),
    run('ps', ['-axww', '-o', 'pid=,args=']),
    run('ps', ['-ax', '-o', 'pid=,comm=']),
  ]);
  const procs = new Map();
  for (const line of meta.split('\n')) {
    const m = line.trim().split(/\s+/);
    if (m.length < 6) continue;
    procs.set(Number(m[0]), {
      pid: Number(m[0]), ppid: Number(m[1]), etime: m[2], cpu: Number(m[3]), rssKb: Number(m[4]), user: m[5],
    });
  }
  for (const [text, key] of [[args, 'args'], [comms, 'exe']]) {
    for (const line of text.split('\n')) {
      const m = line.match(/^\s*(\d+)\s(.*)$/);
      const p = m && procs.get(Number(m[1]));
      if (p) p[key] = m[2];
    }
  }
  return procs;
}

async function cwds(pids) {
  if (!pids.length) return new Map();
  const out = await run('lsof', ['-a', '-d', 'cwd', '-p', pids.join(','), '-Fpn']);
  const map = new Map();
  let pid = null;
  for (const line of out.split('\n')) {
    if (line[0] === 'p') pid = Number(line.slice(1));
    else if (line[0] === 'n' && pid) map.set(pid, line.slice(1));
  }
  return map;
}

// Ordered by specificity: the nearest ancestor that matches any rule decides who launched the process.
const LAUNCHERS = [
  { kind: 'agent', label: 'Claude Code', test: (exe, args) => /(^|\/)claude$/.test(exe) || /claude-code|@anthropic-ai\/claude/.test(args) },
  { kind: 'agent', label: 'Codex', test: (exe, args) => /(^|\/)codex$/.test(exe) || /@openai\/codex/.test(args) },
  { kind: 'agent', label: 'Gemini CLI', test: (exe, args) => /(^|\/)gemini$/.test(exe) || /@google\/gemini-cli/.test(args) },
  { kind: 'agent', label: 'Aider', test: (exe) => /(^|\/)aider$/.test(exe) },
  { kind: 'agent', label: 'Cursor Agent', test: (exe) => /(^|\/)cursor-agent$/.test(exe) },
  { kind: 'editor', label: 'Cursor', test: (exe) => /Cursor\.app/.test(exe) },
  { kind: 'editor', label: 'Windsurf', test: (exe) => /Windsurf\.app/.test(exe) },
  { kind: 'editor', label: 'VS Code', test: (exe) => /Visual Studio Code.*\.app|Code - Insiders\.app/.test(exe) },
  { kind: 'editor', label: 'Zed', test: (exe) => /Zed\.app/.test(exe) },
  { kind: 'editor', label: 'JetBrains IDE', test: (exe) => /(IntelliJ|WebStorm|PyCharm|GoLand|Rider|CLion|DataGrip|PhpStorm|RubyMine)[^/]*\.app/.test(exe) },
  { kind: 'terminal', label: 'Terminal', test: (exe) => /Terminal\.app/.test(exe) },
  { kind: 'terminal', label: 'iTerm2', test: (exe) => /iTerm\.app/.test(exe) },
  { kind: 'terminal', label: 'Warp', test: (exe) => /Warp\.app/.test(exe) },
  { kind: 'terminal', label: 'Ghostty', test: (exe) => /Ghostty\.app|(^|\/)ghostty$/.test(exe) },
  { kind: 'terminal', label: 'kitty', test: (exe) => /kitty\.app|(^|\/)kitty$/.test(exe) },
  { kind: 'terminal', label: 'Alacritty', test: (exe) => /Alacritty\.app/.test(exe) },
  { kind: 'terminal', label: 'WezTerm', test: (exe) => /WezTerm\.app|wezterm-gui$/.test(exe) },
  { kind: 'terminal', label: 'tmux', test: (exe) => /(^|\/)tmux$/.test(exe) },
  { kind: 'container', label: 'Docker', test: (exe) => /Docker\.app|com\.docker|(^|\/)(docker|vpnkit|com\.docker\.backend)$/.test(exe) },
  { kind: 'container', label: 'OrbStack', test: (exe) => /OrbStack\.app/.test(exe) },
];

// When the launching shell has exited (common for servers an agent starts in the background), the process is
// re-parented to launchd and the chain is lost — but the environment it inherited still says where it came from.
const TERMINALS = {
  Apple_Terminal: 'Terminal', 'iTerm.app': 'iTerm2', WarpTerminal: 'Warp', ghostty: 'Ghostty',
  WezTerm: 'WezTerm', tmux: 'tmux', Hyper: 'Hyper', Tabby: 'Tabby', kitty: 'kitty', alacritty: 'Alacritty',
};
const ENV_RULES = [
  { kind: 'agent', label: 'Claude Code', test: (e) => e.CLAUDECODE === '1' || 'CLAUDE_CODE_ENTRYPOINT' in e },
  { kind: 'agent', label: 'Codex', test: (e) => ['CODEX_SANDBOX', 'CODEX_SANDBOX_NETWORK_DISABLED', 'CODEX_MANAGED_BY_NPM', 'CODEX_THREAD_ID'].some((k) => k in e) },
  { kind: 'agent', label: 'Gemini CLI', test: (e) => e.GEMINI_CLI === '1' },
  { kind: 'agent', label: 'Cursor Agent', test: (e) => e.CURSOR_AGENT === '1' },
  { kind: 'editor', label: 'Cursor', test: (e) => 'CURSOR_TRACE_ID' in e || /todesktop|cursor/i.test(e.__CFBundleIdentifier || '') },
  { kind: 'editor', label: 'Windsurf', test: (e) => /windsurf|codeium/i.test(e.__CFBundleIdentifier || '') },
  { kind: 'editor', label: 'VS Code', test: (e) => e.TERM_PROGRAM === 'vscode' || 'VSCODE_PID' in e || 'VSCODE_IPC_HOOK' in e || e.__CFBundleIdentifier === 'com.microsoft.VSCode' },
  { kind: 'terminal', label: (e) => TERMINALS[e.TERM_PROGRAM], test: (e) => e.TERM_PROGRAM in TERMINALS },
];

// `ps -E` appends the environment to the command line; only works for processes owned by the current user.
async function environments(pids) {
  if (!pids.length) return new Map();
  const out = await run('ps', ['-Eww', '-o', 'pid=,command=', '-p', pids.join(',')]);
  const map = new Map();
  for (const line of out.split('\n')) {
    const m = line.match(/^\s*(\d+)\s(.*)$/);
    if (!m) continue;
    const env = {};
    for (const [, k, v] of m[2].matchAll(/(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)=(\S*)/g)) env[k] = v;
    map.set(Number(m[1]), env);
  }
  return map;
}

function inheritedEnv(pid, procs, envMap) {
  for (let p = procs.get(pid), hops = 0; p && hops < 20; p = procs.get(p.ppid), hops++) {
    const env = envMap.get(p.pid);
    if (env && Object.keys(env).length) return env;
  }
  return undefined;
}

function launchedBy(pid, procs, env) {
  const chain = [];
  const self = procs.get(pid);
  let p = self && procs.get(self.ppid);
  const seen = new Set();
  while (p && p.pid !== 1 && !seen.has(p.pid)) {
    seen.add(p.pid);
    chain.push({ pid: p.pid, name: path.basename(p.exe || '?') });
    for (const rule of LAUNCHERS) {
      if (rule.test(p.exe || '', p.args || '')) return { kind: rule.kind, label: rule.label, chain, source: 'parent process' };
    }
    p = procs.get(p.ppid);
  }
  for (const rule of ENV_RULES) {
    if (env && rule.test(env)) {
      const label = typeof rule.label === 'function' ? rule.label(env) : rule.label;
      return { kind: rule.kind, label, chain, source: 'inherited environment variables' };
    }
  }
  if (self && self.ppid === 1) {
    const exe = self.exe || '';
    if (/^\/(System|usr\/(libexec|sbin))\//.test(exe)) return { kind: 'system', label: 'macOS', chain, source: 'system path' };
    // A GUI app listening on its own (ControlCenter, Spotify, …), started by launchd rather than from a shell.
    const app = (exe.match(/([^/]+)\.app\/Contents\/MacOS\//) || [])[1];
    if (app) return { kind: 'app', label: app, chain, source: 'app bundle' };
    return { kind: 'service', label: 'Background service', chain, source: 'launchd' };
  }
  return { kind: 'other', label: 'Other', chain, source: 'unknown' };
}

async function snapshot() {
  const [rows, procs] = await Promise.all([listeners(), processTable()]);
  const pids = [...new Set(rows.map((r) => r.pid))];
  // Include ancestors: some servers (e.g. next-server) rewrite their process title, which wipes their own env from ps.
  const envPids = new Set(pids);
  for (const pid of pids) {
    for (let p = procs.get(pid); p && p.ppid > 1 && !envPids.has(p.ppid); p = procs.get(p.ppid)) envPids.add(p.ppid);
  }
  const [cwdMap, envMap] = await Promise.all([cwds(pids), environments([...envPids])]);

  // Collapse IPv4/IPv6 duplicates of the same pid+port into one row with several addresses.
  const byKey = new Map();
  for (const r of rows) {
    const key = `${r.pid}:${r.port}`;
    if (!byKey.has(key)) byKey.set(key, { pid: r.pid, port: r.port, addresses: [] });
    const entry = byKey.get(key);
    if (!entry.addresses.includes(r.address)) entry.addresses.push(r.address);
  }

  const ports = [...byKey.values()].map((e) => {
    const p = procs.get(e.pid) || {};
    const exe = p.exe || '';
    return {
      ...e,
      exposed: e.addresses.some((a) => a === '*' || a === '0.0.0.0' || a === '[::]'),
      name: path.basename(exe) || '?',
      exe,
      args: p.args || '',
      user: p.user || '',
      ppid: p.ppid,
      uptimeSec: etimeToSec(p.etime),
      cpu: p.cpu ?? null,
      memMb: p.rssKb ? Math.round(p.rssKb / 1024) : null,
      cwd: cwdMap.get(e.pid) || '',
      launchedBy: launchedBy(e.pid, procs, inheritedEnv(e.pid, procs, envMap)),
      self: e.pid === process.pid,
    };
  });
  ports.sort((a, b) => a.port - b.port);
  return { ports, generatedAt: Date.now(), dashboardPid: process.pid };
}

async function stop(pid, force) {
  if (!Number.isInteger(pid) || pid <= 1) throw httpError(400, 'Invalid pid');
  if (pid === process.pid) throw httpError(400, "That's this dashboard — stop it with Ctrl+C in its terminal.");
  // Only processes that currently own a listening port can be stopped from here.
  const owned = (await listeners()).some((r) => r.pid === pid);
  if (!owned) throw httpError(404, `pid ${pid} is no longer listening on any port`);
  try {
    process.kill(pid, force ? 'SIGKILL' : 'SIGTERM');
  } catch (err) {
    if (err.code === 'EPERM') throw httpError(403, `Permission denied — pid ${pid} belongs to another user. Try: sudo kill ${force ? '-9 ' : ''}${pid}`);
    if (err.code === 'ESRCH') throw httpError(404, `pid ${pid} already exited`);
    throw err;
  }
  // Give it a moment to release the port so the UI can report whether it actually went away.
  for (let i = 0; i < 15; i++) {
    await new Promise((r) => setTimeout(r, 100));
    try { process.kill(pid, 0); } catch { return { pid, exited: true }; }
  }
  return { pid, exited: false };
}

// ps etime is [[dd-]hh:]mm:ss
function etimeToSec(etime) {
  const m = (etime || '').match(/^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$/);
  if (!m) return null;
  const [, d = 0, h = 0, min, s] = m;
  return ((+d * 24 + +h) * 60 + +min) * 60 + +s;
}

function httpError(status, message) {
  return Object.assign(new Error(message), { status });
}

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => { data += c; if (data.length > 1e5) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch { reject(httpError(400, 'Bad JSON')); } });
  });
}

const allowedHosts = new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`]);

const server = http.createServer(async (req, res) => {
  try {
    // Blocks DNS-rebinding: a page on another domain can't reach us even if it resolves to 127.0.0.1.
    if (!allowedHosts.has(req.headers.host)) return send(res, 403, { error: 'Forbidden host' });

    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
      return send(res, 200, fs.readFileSync(INDEX), 'text/html; charset=utf-8');
    }
    if (req.method === 'GET' && req.url === '/api/ports') {
      return send(res, 200, await snapshot());
    }
    if (req.method === 'POST' && req.url === '/api/kill') {
      // Cross-site forms can't set custom headers or a JSON content type without a preflight we never answer.
      const origin = req.headers.origin;
      if (origin && !allowedHosts.has(origin.replace(/^https?:\/\//, ''))) return send(res, 403, { error: 'Forbidden origin' });
      if (req.headers['x-port-dashboard'] !== '1') return send(res, 403, { error: 'Missing header' });
      const { pids, force } = await readJson(req);
      const list = Array.isArray(pids) ? pids.map(Number) : [];
      const results = [];
      for (const pid of list) {
        try { results.push({ ok: true, ...(await stop(pid, !!force)) }); }
        catch (err) { results.push({ ok: false, pid, error: err.message }); }
      }
      return send(res, 200, { results });
    }
    send(res, 404, { error: 'Not found' });
  } catch (err) {
    send(res, err.status || 500, { error: err.message });
  }
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use. Run with PORT=7778 npm start (or free ${PORT}: lsof -nP -iTCP:${PORT} -sTCP:LISTEN).`);
    process.exit(1);
  }
  throw err;
});

server.listen(PORT, HOST, () => {
  const url = `http://localhost:${PORT}`;
  console.log(`Port dashboard running at ${url}  (Ctrl+C to stop)`);
  if (!process.env.NO_OPEN) execFile('open', [url]);
});

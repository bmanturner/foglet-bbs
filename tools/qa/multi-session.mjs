// Multi-session SSH/TUI driver for FOG-256 (C8) live harness scenarios.
//
// Wraps ssh2 + @xterm/headless so a scenario can spin up N concurrent sessions
// against the Foglet SSH daemon, drive each one with key/text input, and snap
// screen text for assertions. Designed to be embedded by tools/qa/c8-suite.mjs
// and the per-scenario scripts; not a CLI on its own.

import xterm from '@xterm/headless';
import { Client } from 'ssh2';

const { Terminal } = xterm;

const SPECIAL_KEYS = new Map([
  ['enter', '\r'],
  ['return', '\r'],
  ['escape', '\x1b'],
  ['esc', '\x1b'],
  ['tab', '\t'],
  ['shift-tab', '\x1b[Z'],
  ['backspace', '\x7f'],
  ['space', ' '],
  ['up', '\x1b[A'],
  ['down', '\x1b[B'],
  ['right', '\x1b[C'],
  ['left', '\x1b[D'],
  ['home', '\x1b[H'],
  ['end', '\x1b[F'],
  ['pageup', '\x1b[5~'],
  ['pagedown', '\x1b[6~'],
  ['delete', '\x1b[3~']
]);

export function keyBytes(name) {
  const normalized = String(name).trim().toLowerCase();
  if (SPECIAL_KEYS.has(normalized)) return SPECIAL_KEYS.get(normalized);
  if (/^ctrl-[a-z]$/.test(normalized)) {
    return String.fromCharCode(normalized.charCodeAt(5) - 96);
  }
  if (normalized.length === 1) return normalized;
  throw new Error(`unknown key: ${name}`);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function createTerminalWriter(term) {
  let pending = Promise.resolve();

  const write = data => {
    const text = data.toString('utf8');

    pending = pending.then(
      () =>
        new Promise(resolve => {
          term.write(text, resolve);
        })
    );

    return pending;
  };

  return { write, flush: () => pending };
}

export class Session {
  constructor({ name, host = '127.0.0.1', port = 2222, username, password, width = 100, height = 30, readyMs = 350 }) {
    this.name = name || username || 'session';
    this.host = host;
    this.port = port;
    this.username = username;
    this.password = password;
    this.width = width;
    this.height = height;
    this.readyMs = readyMs;
    this.term = new Terminal({ cols: width, rows: height, allowProposedApi: true });
    this.terminalWriter = createTerminalWriter(this.term);
    this.conn = null;
    this.stream = null;
  }

  async open() {
    this.conn = new Client();
    await new Promise((resolve, reject) => {
      this.conn.once('ready', resolve);
      this.conn.once('error', reject);
      this.conn.connect({
        host: this.host,
        port: this.port,
        username: this.username,
        password: this.password,
        readyTimeout: 10_000,
        tryKeyboard: true,
        algorithms: {
          serverHostKey: ['ssh-ed25519', 'rsa-sha2-512', 'rsa-sha2-256'],
          cipher: [
            'aes256-gcm@openssh.com',
            'aes128-gcm@openssh.com',
            'chacha20-poly1305@openssh.com',
            'aes256-ctr',
            'aes192-ctr',
            'aes128-ctr'
          ]
        }
      });
    });

    this.stream = await new Promise((resolve, reject) => {
      this.conn.shell({ term: 'xterm-256color', cols: this.width, rows: this.height }, (err, stream) => {
        if (err) return reject(err);
        stream.on('data', data => this.terminalWriter.write(data));
        stream.stderr.on('data', data => this.terminalWriter.write(data));
        resolve(stream);
      });
    });

    await sleep(this.readyMs);
    await this.flush();
    return this;
  }

  async flush() {
    await this.terminalWriter.flush();
  }

  async key(name) {
    this.stream.write(keyBytes(name));
    await sleep(this.readyMs);
    await this.flush();
  }

  async type(text) {
    this.stream.write(text);
    await sleep(this.readyMs);
    await this.flush();
  }

  async wait(ms) {
    await sleep(ms);
    await this.flush();
  }

  async resize(cols, rows) {
    this.term.resize(cols, rows);
    this.stream.setWindow(rows, cols, rows * 16, cols * 8);
    await sleep(this.readyMs);
    await this.flush();
  }

  screen() {
    const lines = [];
    for (let row = 0; row < this.term.rows; row += 1) {
      const line = this.term.buffer.active.getLine(row);
      lines.push(line ? line.translateToString(true) : '');
    }
    while (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
    return lines.join('\n');
  }

  // Wait until predicate(screen) returns truthy or timeout (ms) elapses.
  async waitFor(predicate, { timeoutMs = 4000, pollMs = 150 } = {}) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      await this.flush();
      const s = this.screen();
      if (predicate(s)) return s;
      await sleep(pollMs);
    }
    await this.flush();
    throw new Error(`waitFor timed out after ${timeoutMs}ms\n--- last screen (${this.name}) ---\n${this.screen()}`);
  }

  async login(handle, password) {
    await this.waitFor(s => /L Login/i.test(s), { timeoutMs: 4000 });
    await this.type('L');
    await this.waitFor(s => /Identify yourself/i.test(s) || /Handle:/i.test(s));
    await this.type(handle);
    await this.key('tab');
    await this.type(password);
    await this.key('enter');
    await this.waitFor(s => /Foglet ▸ Home/.test(s) || /Boards.*\[B\]/.test(s), { timeoutMs: 6000 });
  }

  async openBoards() {
    await this.type('B');
    await this.waitFor(s => /Foglet ▸ Boards/.test(s));
  }

  async openBoardByName(targetName) {
    await this.openBoards();
    // Find target row by repeatedly pressing j and snapping screen.
    // Cursor (▌) in screen marks current row.
    for (let i = 0; i < 40; i += 1) {
      const s = this.screen();
      const hit = s.split('\n').find(line => line.includes('▌') && line.includes(targetName));
      if (hit) {
        await this.key('enter');
        await this.waitFor(scr => new RegExp(`Foglet ▸ ${escapeRe(targetName)}`).test(scr), { timeoutMs: 6000 });
        return;
      }
      await this.type('j');
    }
    throw new Error(`could not navigate to board "${targetName}"\n--- last screen (${this.name}) ---\n${this.screen()}`);
  }

  async leaveBoard() {
    await this.type('Q');
    await this.waitFor(s => /Foglet ▸ Boards/.test(s) || /Foglet ▸ Home/.test(s));
  }

  async close() {
    try { this.stream && this.stream.end(); } catch {}
    try { this.conn && this.conn.end(); } catch {}
  }
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Parse the CHAT count from "1 THREADS   2 CHAT (N)" tab strip on a board screen.
// Returns null if the tab strip is not present.
export function chatCount(screen) {
  const match = /CHAT\s*\((\d+)\)/i.exec(screen);
  return match ? Number.parseInt(match[1], 10) : null;
}

export function hasTabStrip(screen) {
  return /THREADS\s+.*CHAT\s*\(\d+\)/i.test(screen);
}

export function hasEphemeralNotice(screen) {
  return /Ephemeral chat —|messages? fade|not (durably )?saved|disappear/i.test(screen);
}

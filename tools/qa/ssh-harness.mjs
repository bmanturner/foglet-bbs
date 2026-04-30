#!/usr/bin/env node

import fs from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import xterm from '@xterm/headless';
import { Client } from 'ssh2';

const { Terminal } = xterm;

const DEFAULTS = {
  host: '127.0.0.1',
  port: 2222,
  username: 'qa',
  width: 100,
  height: 30,
  readyMs: 350
};

const SPECIAL_KEYS = new Map([
  ['enter', '\r'],
  ['return', '\r'],
  ['escape', '\x1b'],
  ['esc', '\x1b'],
  ['tab', '\t'],
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

function parseArgs(argv) {
  const opts = { ...DEFAULTS, script: null, command: null };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];

    if (arg === '--help' || arg === '-h') {
      opts.command = 'help';
    } else if (arg === '--host') {
      opts.host = argv[++i];
    } else if (arg === '--port') {
      opts.port = Number.parseInt(argv[++i], 10);
    } else if (arg === '--user' || arg === '--username') {
      opts.username = argv[++i];
    } else if (arg === '--password') {
      opts.password = argv[++i];
    } else if (arg === '--private-key') {
      opts.privateKey = fs.readFileSync(argv[++i], 'utf8');
    } else if (arg === '--width') {
      opts.width = Number.parseInt(argv[++i], 10);
    } else if (arg === '--height') {
      opts.height = Number.parseInt(argv[++i], 10);
    } else if (arg === '--ready-ms') {
      opts.readyMs = Number.parseInt(argv[++i], 10);
    } else if (arg === '--script') {
      opts.script = argv[++i];
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  return opts;
}

function usage() {
  return `Usage: rtk npm run ssh:harness -- [options]

Connects to the Foglet SSH daemon, keeps a headless terminal buffer, and lets QA
print the current screen or send key presses.

Options:
  --host HOST          SSH host, default 127.0.0.1
  --port PORT          SSH port, default 2222
  --user HANDLE        SSH username/handle, default qa
  --password PASSWORD  Optional password for servers requiring password auth
  --private-key PATH   Optional private key path
  --width COLS         PTY width, default 100
  --height ROWS        PTY height, default 30
  --script PATH        Run newline-delimited harness commands, then exit

Commands:
  screen               Print the current terminal screen as plain text
  key NAME             Send a key: enter, escape, tab, up, down, left, right
  key ctrl-c           Send a Ctrl key chord
  type TEXT            Send literal text
  resize COLSxROWS     Resize the PTY and terminal buffer
  wait MS              Wait for async renders
  quit                 Close the SSH session
`;
}

function connect(opts) {
  const conn = new Client();

  return new Promise((resolve, reject) => {
    conn.once('ready', () => resolve(conn));
    conn.once('error', reject);

    conn.connect({
      host: opts.host,
      port: opts.port,
      username: opts.username,
      password: opts.password,
      privateKey: opts.privateKey,
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
}

function openShell(conn, opts, term) {
  return new Promise((resolve, reject) => {
    conn.shell(
      {
        term: 'xterm-256color',
        cols: opts.width,
        rows: opts.height
      },
      (err, stream) => {
        if (err) {
          reject(err);
          return;
        }

        stream.on('data', data => {
          term.write(data.toString('utf8'));
        });

        stream.stderr.on('data', data => {
          term.write(data.toString('utf8'));
        });

        resolve(stream);
      }
    );
  });
}

function screenText(term) {
  const lines = [];

  for (let row = 0; row < term.rows; row += 1) {
    const line = term.buffer.active.getLine(row);
    lines.push(line ? line.translateToString(true) : '');
  }

  while (lines.length > 0 && lines[lines.length - 1] === '') {
    lines.pop();
  }

  return lines.join('\n');
}

function keyBytes(name) {
  const normalized = name.trim().toLowerCase();

  if (SPECIAL_KEYS.has(normalized)) {
    return SPECIAL_KEYS.get(normalized);
  }

  if (/^ctrl-[a-z]$/.test(normalized)) {
    return String.fromCharCode(normalized.charCodeAt(5) - 96);
  }

  if (normalized.length === 1) {
    return normalized;
  }

  throw new Error(`unknown key: ${name}`);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runCommand(command, context) {
  const trimmed = command.trim();

  if (trimmed === '' || trimmed.startsWith('#')) {
    return true;
  }

  if (trimmed === 'screen') {
    console.log('--- screen ---');
    console.log(screenText(context.term));
    console.log('--- end screen ---');
    return true;
  }

  if (trimmed.startsWith('key ')) {
    context.stream.write(keyBytes(trimmed.slice(4)));
    await sleep(context.readyMs);
    return true;
  }

  if (trimmed.startsWith('type ')) {
    context.stream.write(trimmed.slice(5));
    await sleep(context.readyMs);
    return true;
  }

  if (trimmed.startsWith('resize ')) {
    const match = /^resize\s+(\d+)x(\d+)$/i.exec(trimmed);

    if (!match) {
      throw new Error('resize expects COLSxROWS, for example: resize 120x40');
    }

    const cols = Number.parseInt(match[1], 10);
    const rows = Number.parseInt(match[2], 10);
    context.term.resize(cols, rows);
    context.stream.setWindow(rows, cols, rows * 16, cols * 8);
    await sleep(context.readyMs);
    return true;
  }

  if (trimmed.startsWith('wait ')) {
    const ms = Number.parseInt(trimmed.slice(5), 10);
    await sleep(ms);
    return true;
  }

  if (trimmed === 'quit' || trimmed === 'exit') {
    return false;
  }

  throw new Error(`unknown command: ${trimmed}`);
}

async function runScript(path, context) {
  const commands = fs.readFileSync(path, 'utf8').split(/\r?\n/);

  for (const command of commands) {
    const keepGoing = await runCommand(command, context);

    if (!keepGoing) {
      break;
    }
  }
}

async function runRepl(context) {
  const rl = createInterface({ input, output, prompt: 'foglet-ssh> ' });

  console.log('Connected. Type "screen", "key enter", "type text", "resize 120x40", or "quit".');
  rl.prompt();

  for await (const line of rl) {
    try {
      const keepGoing = await runCommand(line, context);

      if (!keepGoing) {
        break;
      }
    } catch (error) {
      console.error(`error: ${error.message}`);
    }

    rl.prompt();
  }

  rl.close();
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.command === 'help') {
    console.log(usage());
    return;
  }

  const term = new Terminal({
    cols: opts.width,
    rows: opts.height,
    allowProposedApi: true
  });

  const conn = await connect(opts);
  const stream = await openShell(conn, opts, term);
  const context = { conn, stream, term, readyMs: opts.readyMs };

  await sleep(opts.readyMs);

  try {
    if (opts.script) {
      await runScript(opts.script, context);
    } else {
      await runRepl(context);
    }
  } finally {
    stream.end();
    conn.end();
  }
}

main().catch(error => {
  console.error(`foglet SSH harness failed: ${error.message}`);
  process.exitCode = 1;
});

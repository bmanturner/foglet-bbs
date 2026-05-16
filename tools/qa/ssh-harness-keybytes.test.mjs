import assert from 'node:assert/strict';
import { keyBytes, createTerminalWriter, ensurePrivateKey } from './ssh-harness.mjs';

assert.equal(keyBytes('shift-tab'), '\x1b[Z');
assert.equal(keyBytes('Shift-Tab'), '\x1b[Z');

const writes = [];
const term = {
  write(text, callback) {
    writes.push(`start:${text}`);
    setTimeout(() => {
      writes.push(`finish:${text}`);
      callback();
    }, text === 'first' ? 15 : 0);
  }
};

const writer = createTerminalWriter(term);
const first = writer.write('first');
const second = writer.write('second');
await writer.flush();
await Promise.all([first, second]);
assert.deepEqual(writes, ['start:first', 'finish:first', 'start:second', 'finish:second']);

const withGeneratedKey = ensurePrivateKey({ username: 'qa' });
assert.equal(withGeneratedKey.username, 'qa');
assert.match(withGeneratedKey.privateKey, /BEGIN (RSA )?PRIVATE KEY/);

const existingKey = '-----BEGIN PRIVATE KEY-----\nexisting\n-----END PRIVATE KEY-----';
assert.equal(ensurePrivateKey({ privateKey: existingKey }).privateKey, existingKey);

console.log('ssh harness key mapping, terminal flush, and generated auth key tests passed');

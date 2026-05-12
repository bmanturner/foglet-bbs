import assert from 'node:assert/strict';
import { keyBytes, createTerminalWriter } from './ssh-harness.mjs';

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

console.log('ssh harness key mapping and terminal flush tests passed');

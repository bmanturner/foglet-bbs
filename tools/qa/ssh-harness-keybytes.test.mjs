import assert from 'node:assert/strict';
import { keyBytes } from './ssh-harness.mjs';

assert.equal(keyBytes('shift-tab'), '\x1b[Z');
assert.equal(keyBytes('Shift-Tab'), '\x1b[Z');

console.log('ssh harness key mapping tests passed');

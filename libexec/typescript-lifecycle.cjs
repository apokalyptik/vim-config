// Container-only preload. A requested TS parent exit must wait for the child
// process handles to close. This adds no processes or signals. The bundled
// TS shutdown callback performs its normal cleanup before the exit request.
'use strict';
const childProcess = require('node:child_process');
const children = new Set();
const originalExit = process.exit.bind(process);
let requested = false;
let exitCode;
let hold;

function finish() {
  if (!requested || children.size) return;
  if (hold) clearInterval(hold);
  originalExit(exitCode);
}

function track(child) {
  children.add(child);
  child.once('close', () => { children.delete(child); finish(); });
  return child;
}

for (const name of ['fork', 'spawn']) {
  const original = childProcess[name];
  childProcess[name] = function (...args) { return track(Reflect.apply(original, this, args)); };
}
require('node:module').syncBuiltinESMExports();

process.exit = function (code) {
  requested = true;
  if (exitCode === undefined || (code !== undefined && Number(code) !== 0)) {
    exitCode = code === undefined ? process.exitCode : code;
  }
  if (children.size && !hold) hold = setInterval(finish, 25);
  finish();
};

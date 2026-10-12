'use strict';
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const code = fs.readFileSync(path.join(__dirname, '../charts/image-service/files/load-apparmor.cjs'), 'utf8');
const source = fs.readFileSync(path.join(__dirname, '../charts/image-service/files/apparmor.profile'));
const hash = crypto.createHash('sha256').update(source).digest('hex');
function run(state) {
  let status = 0;
  let exited = false;
  const calls = [];
  let sentinel = state.sentinel;
  let loaded = state.loaded || false;
  const regular = {uid: state.uid ?? 0, mode: state.mode ?? 0o400, isFile: () => true};
  const fake = {
    constants: fs.constants,
    lstatSync: () => ({uid: 0, mode: state.directoryMode ?? 0o755, isDirectory: () => !state.directorySymlink}),
    readFileSync: (file) => file === '/apparmor-source/apparmor.profile' ? source :
      typeof file === 'string' && file.endsWith('/profiles') ? (loaded ? 'codex-image-service-v1 (' + (state.complain ? 'complain' : 'enforce') + ')\n' : '') : sentinel,
    openSync: (file, flags, mode) => {
      assert(flags & fs.constants.O_NOFOLLOW);
      if (state.symlink) throw Object.assign(new Error('symlink'), {code: 'ELOOP'});
      if (flags & fs.constants.O_CREAT) { assert(flags & fs.constants.O_EXCL); assert.equal(mode, 0o400); calls.push('create'); return 9; }
      if (sentinel === undefined) throw Object.assign(new Error('absent'), {code: 'ENOENT'});
      return 8;
    },
    fstatSync: () => regular,
    closeSync: () => {},
    writeFileSync: (fd, value) => { sentinel = value; calls.push('write'); },
    fsyncSync: () => calls.push('sync'),
  };
  try {
    vm.runInNewContext(code, {
      require: name => name === 'node:fs' ? fake : name === 'node:crypto' ? crypto : {
        execFileSync: (binary, args) => {
          assert.equal(binary, '/usr/sbin/apparmor_parser');
          assert(args.includes('--skip-cache'));
          assert(!args.includes('--replace'));
          if (args.includes('--names')) return state.wrongName ? 'unrelated' : 'codex-image-service-v1';
          calls.push('add');
          if (state.addFailure) throw new Error('kernel refusal');
          loaded = true;
          return '';
        },
      },
      process: {argv: ['node', 'loader', state.hash || hash], exit: value => { if (!exited) status = value; exited = true; throw 'exit'; }},
      console: {log: () => {}, error: () => {}},
    });
  } catch (error) { if (error !== 'exit') throw error; }
  return {status, calls, sentinel};
}
assert.deepEqual(run({}).calls, ['add', 'create', 'write', 'sync']);
assert.equal(run({}).sentinel, hash + '\n');
assert.deepEqual(run({loaded: true, sentinel: hash + '\n'}).calls, []);
assert.equal(run({loaded: true, sentinel: hash + '\n'}).status, 0);
assert.deepEqual(run({sentinel: hash + '\n'}).calls, ['add']); // Node reboot: kernel state lost.
for (const state of [
  {loaded: true}, {loaded: true, sentinel: 'conflict\n'}, {sentinel: 'conflict\n'},
  {loaded: true, sentinel: hash + '\n', complain: true}, {symlink: true},
  {directorySymlink: true}, {directoryMode: 0o777}, {sentinel: hash + '\n', uid: 1000},
  {sentinel: hash + '\n', mode: 0o666}, {wrongName: true}, {hash: '0'.repeat(64)},
]) {
  const result = run(state);
  assert.equal(result.status, 1, JSON.stringify(state));
  assert(!result.calls.includes('add'), 'Conflict mutated kernel policy');
}
const refusal = run({addFailure: true});
assert.equal(refusal.status, 1);
assert.equal(refusal.sentinel, undefined);
console.log('AppArmor loader add/restart/reboot/conflict/no-follow tests passed');

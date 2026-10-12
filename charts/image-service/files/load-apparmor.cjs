'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const name = 'codex-image-service-v1';
const source = '/apparmor-source/apparmor.profile';
const directory = '/profiles';
const sentinel = `${directory}/${name}.sha256`;
const securityfs = '/apparmor-policy';
const expected = process.argv[2];
function fail(message) { throw new Error(message); }
function trusted(stat, directory = false) {
  if (stat.uid !== 0 || (stat.mode & 0o022) || !(directory ? stat.isDirectory() : stat.isFile()))
    fail('Untrusted node provisioning state');
}
function readSentinel() {
  let fd;
  try { fd = fs.openSync(sentinel, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  try { trusted(fs.fstatSync(fd)); return fs.readFileSync(fd, 'utf8'); }
  finally { fs.closeSync(fd); }
}
function enforcing() {
  const lines = fs.readFileSync(`${securityfs}/profiles`, 'utf8').trim().split('\n');
  const matches = lines.filter(line => line.startsWith(`${name} `));
  if (matches.length && (matches.length !== 1 || matches[0] !== `${name} (enforce)`))
    fail('Existing policy is not uniquely enforcing');
  return matches.length === 1;
}
function parser(...args) {
  return execFileSync('/usr/sbin/apparmor_parser', ['--subdomainfs', securityfs, '--kernel-features', `${securityfs}/features`, '--skip-cache', '--jobs', '1', ...args, source], {encoding: 'utf8'}).trim();
}
try {
  if (!/^[a-f0-9]{64}$/.test(expected || '') || crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex') !== expected)
    fail('Policy source hash mismatch');
  trusted(fs.lstatSync(directory), true);
  if (parser('--names') !== name) fail('Unexpected policy names');
  const state = readSentinel();
  if (state !== null && state !== `${expected}\n`) fail('Conflicting node policy sentinel');
  if (enforcing()) {
    if (state === null) fail('Existing policy lacks trusted provisioning state');
    console.log('Verified enforcing policy and trusted source sentinel');
    process.exit(0);
  }
  // Add is atomic in the kernel and refuses a concurrent existing name. Never replace.
  parser('--add');
  if (!enforcing()) fail('Loaded policy is not enforcing');
  if (state === null) {
    const fd = fs.openSync(sentinel, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o400);
    try { fs.writeFileSync(fd, `${expected}\n`); fs.fsyncSync(fd); }
    finally { fs.closeSync(fd); }
  }
  console.log('Added fixed enforcing policy and recorded trusted source sentinel');
} catch (error) { console.error(error.message); process.exit(1); }

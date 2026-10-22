// Disposable Linux QEMU supervisor. Reads the original procfs while its child
// mount namespace has no procfs. No network or host/user projects are used.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawn } = require('node:child_process');

const cgroupRoot = '/sys/fs/cgroup';
const node = '/opt/vim-tools/bin/node';
const cases = [
  { name: 'raw-v1', executable: '/opt/vim-tools/bin/gopls-resource-v1', raw: true },
  { name: 'serial-env-v1', executable: '/opt/vim-tools/bin/gopls-resource-v1' },
  { name: 'launcher-current' },
];
if (process.env.VIM_QEMU_ADDITIONAL_LSPS === '1') cases.push(
  { name: 'php-env-only', client: '/usr/bin/php-resources-client.cjs', launcher: '/opt/vim-config/bin/language-server-env-only', baseline: true },
  { name: 'php-current', client: '/usr/bin/php-resources-client.cjs' },
  { name: 'php-default-diagnostics-current', client: '/usr/bin/php-resources-client.cjs', phpDefaults: true },
  { name: 'typescript-current', client: '/usr/bin/node-resources-client.cjs' },
);
const read = name => { try { return fs.readFileSync(name, 'utf8').trim(); } catch { return ''; } };
const integers = name => read(name).split(/\s+/).filter(Boolean).map(Number);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

function status(pid) {
  const text = read(`/proc/${pid}/status`);
  if (!text) return null;
  const item = key => new RegExp(`^${key}:\\s*(.+)$`, 'm').exec(text)?.[1] || '';
  return { pid, name: item('Name'), threads: Number(item('Threads')), uid: Number(item('Uid').split(/\s+/)[0]),
    rssKiB: Number(item('VmRSS').split(/\s+/)[0]) || 0, state: item('State')[0], ppid: Number(item('PPid')),
    allowedCPUs: item('Cpus_allowed_list') };
}

async function runCase(spec, cap) {
  const label = spec.name + (cap ? `-cap${cap}` : '');
  const group = `${cgroupRoot}/vim-go-${label}`;
  fs.mkdirSync(group);
  if (cap) fs.writeFileSync(`${group}/pids.max`, String(cap));
  const env = { ...process.env, VIM_QEMU_GOPLS_WORKSPACE: `/home/tester/resource-${label}`,
    VIM_QEMU_GOPLS_ROOTS: '3', VIM_QEMU_GOPLS_RESOURCE_EVENTS: '1', VIM_QEMU_GOPLS_WORKING_ONLY: '1',
    VIM_QEMU_GOPLS_TIMEOUT: '240' };
  if (spec.executable) env.VIM_QEMU_GOPLS_EXECUTABLE = spec.executable;
  else delete env.VIM_QEMU_GOPLS_EXECUTABLE;
  if (spec.launcher) env.VIM_QEMU_LSP_LAUNCHER = spec.launcher;
  else delete env.VIM_QEMU_LSP_LAUNCHER;
  if (spec.phpDefaults) env.VIM_QEMU_PHP_DEFAULT_DIAGNOSTICS = '1';
  else delete env.VIM_QEMU_PHP_DEFAULT_DIAGNOSTICS;
  if (spec.raw) env.VIM_QEMU_GOPLS_RAW = '1';
  else delete env.VIM_QEMU_GOPLS_RAW;
  const clientScript = spec.client || '/usr/bin/gopls-no-proc.cjs';
  const child = spawn('/usr/bin/unshare', ['--mount', '--fork', '--propagation', 'private', '--', '/bin/sh', '-c',
    `umount /proc && exec /bin/busybox su -s /bin/sh tester -c "exec /opt/vim-tools/bin/node --v8-pool-size=1 ${clientScript}"`],
    { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '', pending = '', clientPid = 0, serverPid = 0, attached = false, attachError;
  let maxTasks = 0, maxProcesses = 0, maxGoCommands = 0, maxRSSKiB = 0, maxClientThreads = 0;
  let peakGoCommandSnapshot = [];
  let maxUserTasks = 0, maxUserProcesses = 0, maxObserverThreads = 0, peakTaskSnapshot = [];
  let observedServerPolicy = {};
  let samples = 0;
  child.stdout.on('data', chunk => {
    output += chunk;
    pending += chunk;
    const lines = pending.split('\n');
    pending = lines.pop();
    for (const line of lines) {
      const client = /^GOPLS_RESOURCE_CLIENT_PID=(\d+)$/.exec(line);
      const server = /^GOPLS_RESOURCE_CHILD_PID=(\d+)$/.exec(line);
      if (client) clientPid = Number(client[1]);
      if (server) serverPid = Number(server[1]);
    }
  });
  child.stderr.on('data', chunk => { output += chunk; });
  const sample = () => {
    samples++;
    if (serverPid && !attached && !attachError && status(serverPid)?.state === 'T') {
      try {
        fs.writeFileSync(`${group}/cgroup.procs`, String(serverPid));
        attached = true;
        process.kill(serverPid, 'SIGCONT');
      } catch (error) { attachError = error; process.kill(serverPid, 'SIGCONT'); }
    }
    const pids = integers(`${group}/cgroup.procs`);
    const tasks = Number(read(`${group}/pids.current`));
    const processes = pids.map(status).filter(Boolean);
    if (serverPid && processes.some(item => item.pid === serverPid)) {
      const permitted = new Set(['VIM_CONFIG_PROFILE', 'VIM_CONFIG_LOW_RESOURCE', 'GOMAXPROCS', 'GOFLAGS', 'GOMEMLIMIT',
        'RAYON_NUM_THREADS', 'TOKIO_WORKER_THREADS', 'UV_THREADPOOL_SIZE', 'NODE_OPTIONS']);
      const policy = Object.fromEntries(read(`/proc/${serverPid}/environ`).split('\0')
        .map(item => item.split(/=(.*)/s)).filter(item => permitted.has(item[0])).map(item => [item[0], item[1]]));
      if (Object.hasOwn(policy, 'VIM_CONFIG_PROFILE')) observedServerPolicy = policy;
    }
    if (tasks > maxTasks) {
      maxTasks = tasks;
      peakTaskSnapshot = processes.map(item => {
        let threadNames = {};
        try {
          for (const tid of fs.readdirSync(`/proc/${item.pid}/task`)) {
            const name = read(`/proc/${item.pid}/task/${tid}/comm`);
            if (name) threadNames[name] = (threadNames[name] || 0) + 1;
          }
        } catch { /* Process can exit between cgroup and task-directory reads. */ }
        return { ...item, threadNames };
      });
    }
    maxProcesses = Math.max(maxProcesses, processes.length);
    // cgroup.procs and status are live reads, not an atomic snapshot. Confirm
    // each candidate remains alive after the first pass: all survivors then
    // overlapped at the boundary between the two passes. Ignore zombies.
    // A newly forked compiler can briefly retain its parent's "go" comm before
    // exec. Direct gopls children identify CLI invocations without counting it.
    const commands = processes.filter(item => item.name === 'go' && item.ppid === serverPid && item.state !== 'Z')
      .filter(item => { const again = status(item.pid); return again?.name === 'go' && again.state !== 'Z'; });
    if (commands.length > maxGoCommands) {
      maxGoCommands = commands.length;
      peakGoCommandSnapshot = commands.map(item => ({ ...item, command: read(`/proc/${item.pid}/cmdline`).replace(/\0/g, ' ') }));
    }
    maxRSSKiB = Math.max(maxRSSKiB, processes.reduce((sum, item) => sum + item.rssKiB, 0));
    if (clientPid) maxClientThreads = Math.max(maxClientThreads, status(clientPid)?.threads || 0);
    maxObserverThreads = Math.max(maxObserverThreads, status(process.pid)?.threads || 0);
    if (samples % 5 === 0) {
      const user = fs.readdirSync('/proc').filter(name => /^\d+$/.test(name)).map(Number).map(status)
        .filter(item => item?.uid === 1000);
      maxUserTasks = Math.max(maxUserTasks, user.reduce((sum, item) => sum + item.threads, 0));
      maxUserProcesses = Math.max(maxUserProcesses, user.length);
    }
  };
  const interval = setInterval(sample, 5);
  const started = Date.now();
  let timedOut = false;
  const watchdog = setTimeout(() => { timedOut = true; child.kill('SIGKILL'); }, 300000);
  let exit;
  try { exit = await new Promise((resolve, reject) => { child.once('close', (code, signal) => resolve({ code, signal })); child.once('error', reject); }); }
  finally { clearInterval(interval); clearTimeout(watchdog); sample(); }
  const events = read(`${group}/pids.events`);
  const eventMax = Number(/^max (\d+)$/m.exec(events)?.[1] || 0);
  const kernelPeak = read(`${group}/pids.peak`);
  const result = { name: label, exit, attached, timedOut, milliseconds: Date.now() - started,
    visibleCPUs: require('node:os').availableParallelism(), sampledPeakTasks: maxTasks,
    kernelPeakTasks: kernelPeak ? Number(kernelPeak) : null, sampledPeakProcesses: maxProcesses,
    sampledPeakConcurrentGoCommands: maxGoCommands, sampledPeakRSSKiB: maxRSSKiB,
    sampledPeakClientThreads: maxClientThreads, sampledPeakObserverThreads: maxObserverThreads,
    sampledPeakTesterTasks: maxUserTasks, sampledPeakTesterProcesses: maxUserProcesses,
    sampleIntervalTargetMilliseconds: 5, meanSampleIntervalMilliseconds: (Date.now() - started) / samples,
    samples, pidsMax: cap || null, pidsEventsMax: eventMax,
    workloadMarkers: output.split('\n').map(line => line.trim()).filter(line =>
      /^(VIM_LSP_RESOURCE_CLIENT_PASS|NODE_RESOURCE_SEMANTIC_DEFINITION_COMPLETION_PASS|GOPLS_NO_PROC_(WRAPPER_STDLIB|DIRECT_STDLIB|CONTENT_HASH)_PASS)/.test(line)),
    observedServerPolicy, peakTaskSnapshot, peakGoCommandSnapshot };
  console.log('GOPLS_RESOURCE_RESULT ' + JSON.stringify(result));
  const sentinel = spec.client ? 'VIM_LSP_RESOURCE_CLIENT_PASS' : 'VIM_GOPLS_NO_PROC_REGRESSION_PASS';
  if (exit.code !== 0 || !attached || attachError || timedOut || !output.includes(sentinel)) {
    console.error(output.slice(-16384));
    throw new Error(`${label}: failed workload or observer attachment; ${attachError || ''}`);
  }
  assert.equal(eventMax, 0, `${label}: cgroup denied a process/thread creation`);
  assert.equal(integers(`${group}/cgroup.procs`).length, 0, `${label}: server tree leaked`);
  fs.rmdirSync(group);
  return result;
}

async function main() {
  assert.equal(process.getuid(), 0);
  assert.match(read(`${cgroupRoot}/cgroup.controllers`), /\bpids\b/);
  fs.writeFileSync(`${cgroupRoot}/cgroup.subtree_control`, '+pids');
  const requested = (process.env.VIM_QEMU_RESOURCE_FAMILIES || '').split(',').filter(Boolean);
  let ran = 0;
  for (const spec of cases) {
    const family = spec.name.startsWith('php-') ? 'php' : spec.name.startsWith('typescript-') ? 'typescript' : 'go';
    if (requested.length && !requested.includes(family)) continue;
    if (process.env.VIM_QEMU_RESOURCE_CURRENT_ONLY === '1' && !spec.name.endsWith('-current')) continue;
    ran++;
    const current = await runCase(spec);
    if (!spec.name.endsWith('-current')) continue;
    assert.equal(current.observedServerPolicy.VIM_CONFIG_LOW_RESOURCE, '1', 'real launcher must select low-resource policy');
    if (!spec.client) {
      assert.equal(current.observedServerPolicy.GOMAXPROCS, '1', 'real launcher must cap Go scheduling');
      assert.equal(current.sampledPeakConcurrentGoCommands, 1, 'low-resource mode must serialize Go CLI processes across module views');
    }
    assert.ok((current.kernelPeakTasks || current.sampledPeakTasks) <= 18, 'this fixture must leave seven tasks for Vim/SSH and other helpers');
    // A quota rerun makes hidden transient task creation visible in pids.events.
    // It only describes this workload; it is not a bound for arbitrary projects.
    await runCase(spec, 18);
  }
  assert.ok(ran, 'no resource workloads selected');
  console.log('VIM_GOPLS_RESOURCE_REGRESSION_PASS');
}
main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });

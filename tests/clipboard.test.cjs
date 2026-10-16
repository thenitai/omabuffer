const { test } = require("node:test")
const assert = require("node:assert/strict")
const { spawn } = require("node:child_process")
const path = require("node:path")
const fs = require("node:fs")
const os = require("node:os")
const reader = path.join(__dirname, "../scripts/read-clipboard.py")
const python = "/usr/bin/python3"
const maxBytes = 64 * 1024

function start(source, args = []) {
  // Run the production entrypoint with a fake provider, never the user's clipboard.
  const launcher = 'import runpy,sys; m=runpy.run_path(sys.argv[1]); sys.exit(m["main"]([sys.executable,"-c",sys.argv[2],*sys.argv[3:]]))'
  const child = spawn(python, ["-I", "-c", launcher, reader, source, ...args])
  const result = new Promise((resolve, reject) => {
    const out = [], err = []
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("Clipboard helper did not finish")) }, 4000)
    child.stdout.on("data", chunk => out.push(chunk))
    child.stderr.on("data", chunk => err.push(chunk))
    child.on("error", reject)
    child.on("close", code => {
      clearTimeout(timer)
      resolve({ code, out: Buffer.concat(out), err: Buffer.concat(err).toString() })
    })
  })
  return { child, result }
}
const run = (source, args) => start(source, args).result
const cleanFailure = (result, code) => {
  assert.equal(result.code, code)
  assert.equal(result.out.length, 0, "partial clipboard data must not reach QML")
  assert.equal(result.err, "", "provider errors may contain sensitive clipboard data")
}

test("clipboard preserves Unicode, whitespace, newlines and literal markup", async () => {
  const text = "  <b>Hello 🌍</b>\nnext line\n"
  const result = await run(`import sys; sys.stdout.buffer.write(${JSON.stringify(text)}.encode())`)
  assert.equal(result.code, 0)
  assert.equal(result.out.toString(), text)
  assert.equal(result.err, "")
})

test("empty clipboard is successful without inserting text", async () => {
  const result = await run("")
  assert.equal(result.code, 0)
  assert.equal(result.out.length, 0)
})

test("exact byte limit is accepted", async () => {
  const result = await run(`import sys; sys.stdout.buffer.write(b'x' * ${maxBytes})`)
  assert.equal(result.code, 0)
  assert.equal(result.out.length, maxBytes)
})

for (const stream of ["stdout", "stderr"]) {
  test(`oversized newline-free ${stream} is discarded`, async () => {
    cleanFailure(await run(`import sys,time; sys.${stream}.buffer.write(b'x' * ${maxBytes + 1}); sys.${stream}.flush(); time.sleep(30)`), 125)
  })
}

test("stdout and stderr share one aggregate cap", async () => {
  cleanFailure(await run("import sys; sys.stdout.buffer.write(b'x' * 40000); sys.stderr.buffer.write(b'y' * 40000)"), 125)
})

test("limit counts UTF-8 bytes, not characters", async () => {
  cleanFailure(await run("import sys; sys.stdout.buffer.write('🌍'.encode() * 20000)"), 125)
})

test("nonzero exit discards partial data and provider error text", async () => {
  cleanFailure(await run("import sys; print('partial secret'); print('sensitive error', file=sys.stderr); sys.exit(7)"), 126)
})

test("missing clipboard executable fails without output", async () => {
  const launcher = 'import runpy,sys; sys.exit(runpy.run_path(sys.argv[1])["main"](["/nonexistent/omabuffer-wl-paste"]))'
  const child = spawn(python, ["-I", "-c", launcher, reader])
  const output = []
  child.stdout.on("data", chunk => output.push(chunk))
  child.stderr.on("data", chunk => output.push(chunk))
  const code = await new Promise(resolve => child.on("close", resolve))
  assert.equal(code, 126)
  assert.equal(Buffer.concat(output).length, 0)
})

test("silent provider hits the total deadline", async () => {
  const started = Date.now()
  cleanFailure(await run("import time; time.sleep(30)"), 124)
  assert.ok(Date.now() - started < 3000)
})

test("continuous trickle cannot reset the total deadline", async () => {
  const started = Date.now()
  cleanFailure(await run("import sys,time\nwhile True:\n sys.stdout.write('x'); sys.stdout.flush(); time.sleep(0.1)"), 124)
  assert.ok(Date.now() - started < 3000)
})

test("closing output pipes cannot bypass the process deadline", async () => {
  cleanFailure(await run("import os,time; os.close(1); os.close(2); time.sleep(30)"), 124)
})

function isRunning(pid) {
  try { return fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1][0] !== "Z" }
  catch (error) { if (error.code === "ENOENT") return false; throw error }
}

for (const cancel of [false, true]) {
  test(`${cancel ? "cancellation" : "deadline"} kills a TERM-ignoring provider and its descendant`, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omabuffer-clipboard-"))
    try {
      const pidFile = path.join(dir, "pids")
      const source = "import os,signal,subprocess,sys,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); open(sys.argv[1],'w').write(str(os.getpid())+' '+str(child.pid)); print('partial',flush=True); time.sleep(30)"
      const { child, result } = start(source, [pidFile])
      for (let i = 0; i < 100 && !fs.existsSync(pidFile); i++) await new Promise(resolve => setTimeout(resolve, 10))
      assert.ok(fs.existsSync(pidFile))
      const pids = fs.readFileSync(pidFile, "utf8").split(" ").map(Number)
      if (cancel) child.kill("SIGTERM")
      cleanFailure(await result, cancel ? 143 : 124)
      for (let i = 0; i < 100 && pids.some(isRunning); i++) await new Promise(resolve => setTimeout(resolve, 10))
      assert.ok(pids.every(pid => !isRunning(pid)), "provider process group still running")
    } finally {
      fs.rmSync(dir, { recursive: true, force: true })
    }
  })
}

test("exited provider with a descendant holding pipes is bounded", async () => {
  cleanFailure(await run("import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); print('partial')"), 124)
})

const { test } = require("node:test")
const assert = require("node:assert/strict")
const { spawn } = require("node:child_process")
const path = require("node:path")
const fs = require("node:fs")
const wrapper = path.join(__dirname, "../scripts/buffer-cli.cjs")
const run = (source, input = "") => new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [wrapper, process.execPath, "-e", source])
  const out = []
  const err = []
  const timer = setTimeout(() => { child.kill(); reject(new Error("Wrapper did not finish")) }, 35000)
  child.stdout.on("data", chunk => out.push(chunk))
  child.stderr.on("data", chunk => err.push(chunk))
  child.on("error", reject)
  child.on("close", code => { clearTimeout(timer); resolve({ code, out: Buffer.concat(out).toString(), err: Buffer.concat(err).toString() }) })
  child.stdin.end(input)
})

test("successful JSON and stdin preserved", async () => {
  const result = await run('process.stdin.pipe(process.stdout)', '{"text":"hello 🌍"}')
  assert.deepEqual(result, { code: 0, out: '{"text":"hello 🌍"}', err: "" })
})
test("auth exit and structured error preserved", async () => {
  const result = await run('process.stderr.write(JSON.stringify({error:"AUTH_ERROR"})); process.exitCode=4')
  assert.equal(result.code, 4)
  assert.equal(JSON.parse(result.err).error, "AUTH_ERROR")
})
for (const stream of ["stdout", "stderr"]) {
  test(`oversized newline-free ${stream} discarded`, async () => {
    const result = await run(`process.${stream}.write("x".repeat(1024*1024+1)); setInterval(()=>{},1000)`)
    assert.equal(result.code, 125)
    assert.equal(result.out, "")
    assert.match(JSON.parse(result.err).message, /output limit/)
    assert.ok(result.err.length < 300)
  })
}
test("combined stdout and stderr cap enforced", async () => {
  const result = await run('process.stdout.write("x".repeat(600000)); process.stderr.write("y".repeat(600000))')
  assert.equal(result.code, 125)
  assert.equal(result.out, "")
})
test("exact output cap accepted", async () => {
  const result = await run('process.stdout.write("x".repeat(1024*1024))')
  assert.equal(result.code, 0)
  assert.equal(result.out.length, 1024*1024)
})
test("stalled request and descendant killed at deadline", async () => {
  const started = Date.now()
  const result = await run('require("node:child_process").spawn(process.execPath,["-e","setInterval(()=>{},1000)"],{stdio:"inherit"}); setInterval(()=>{},1000)')
  assert.equal(result.code, 124)
  assert.equal(result.out, "")
  assert.match(JSON.parse(result.err).message, /timed out/)
  assert.ok(Date.now()-started < 34000)
})
test("all four API calls use bounded wrapper", () => {
  const qml = fs.readFileSync(path.join(__dirname, "../Buffer.qml"), "utf8")
  for (const command of ["account", "channels", "dailyPostingLimits", "posts"]) assert.ok(qml.includes(`root.cliCommand.concat(["${command}"`))
  assert.ok(!qml.includes('command = [root.cliPath'))
})

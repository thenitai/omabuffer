const { test } = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync, spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const resolver = path.join(__dirname, "../scripts/resolve-cli.sh")
const timeout = execFileSync("sh", ["-c", "command -v timeout"], { encoding: "utf8" }).trim()

function resolve(t, launcher) {
  // Spaces and shell metacharacters in the executable path must stay literal.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "buffer resolve $ "))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  fs.symlinkSync(timeout, path.join(dir, "timeout"))
  if (launcher) fs.writeFileSync(path.join(dir, "buffer"), launcher, { mode: 0o755 })
  return {
    cli: path.join(dir, "buffer"),
    result: spawnSync("/bin/sh", [resolver], {
      env: { PATH: dir }, encoding: "utf8", timeout: 8000
    })
  }
}

test("working CLI is probed with --version and its exact path is returned", t => {
  const { cli, result } = resolve(t, '#!/bin/sh\n[ "$#" -eq 1 ] && [ "$1" = "--version" ] || exit 2\nprintf "1.2.0\\n"\n')
  assert.equal(result.status, 0)
  assert.equal(result.stdout, cli + "\n")
  assert.equal(result.stderr, "")
})

test("missing CLI does not resolve", t => {
  const { result } = resolve(t)
  assert.equal(result.status, 1)
  assert.equal(result.stdout, "")
  assert.equal(result.stderr, "")
})

test("stale mise shim is rejected even though command lookup finds it", t => {
  const { result } = resolve(t, '#!/bin/sh\nprintf "misleading stdout\\n"\nprintf "mise ERROR No version is set for shim: buffer\\n" >&2\nexit 1\n')
  assert.equal(result.status, 1)
  assert.equal(result.stdout, "")
  assert.equal(result.stderr, "")
})

test("a stalled CLI probe is killed and does not resolve", t => {
  const started = Date.now()
  const { result } = resolve(t, `#!${process.execPath}\nprocess.on("SIGTERM", () => {}); setInterval(() => {}, 1000)\n`)
  assert.equal(result.error, undefined)
  assert.equal(result.status, 1)
  assert.equal(result.stdout, "")
  assert.equal(result.stderr, "")
  assert.ok(Date.now() - started < 8000)
})

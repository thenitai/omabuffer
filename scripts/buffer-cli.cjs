// Keep API-backed CLI output outside the persistent shell until it is bounded.
const { spawn } = require("node:child_process")
const MAX_BYTES = 1024 * 1024
const DEADLINE_MS = 30000
const [cli, ...args] = process.argv.slice(2)
const child = spawn(cli, args, { detached: true, stdio: ["pipe", "pipe", "pipe"] })
const output = [[], []]
let bytes = 0
let finished = false

const finish = (code, message) => {
  if (finished) return
  finished = true
  clearTimeout(deadline)
  // Include descendants that may still hold pipes open after the CLI exits.
  if (child.pid) {
    try { process.kill(-child.pid, "SIGKILL") } catch (error) { if (error.code !== "ESRCH") child.kill("SIGKILL") }
  }
  process.stdin.unpipe(child.stdin)
  process.stdin.destroy()
  child.stdin.destroy()
  child.stdout.destroy()
  child.stderr.destroy()
  if (message) process.stderr.write(JSON.stringify({ error: "CLI_REQUEST_FAILED", message }))
  else {
    process.stdout.write(Buffer.concat(output[0]))
    process.stderr.write(Buffer.concat(output[1]))
  }
  process.exitCode = code
}
const deadline = setTimeout(() => finish(124, "Buffer request timed out after 30 seconds. For a post, check Buffer before retrying; it may have been accepted."), DEADLINE_MS)

child.on("error", () => finish(126, "Could not start the Buffer CLI."))
child.on("close", (code) => finish(code === null ? 125 : code))
child.stdin.on("error", () => {}) // Early CLI exits may close stdin before the payload is written.
process.stdin.pipe(child.stdin)
for (const [index, stream] of [child.stdout, child.stderr].entries()) {
  stream.on("data", (chunk) => {
    if (finished) return
    bytes += chunk.length
    if (bytes > MAX_BYTES) return finish(125, "Buffer response exceeded the 1 MiB output limit. For a post, check Buffer before retrying; it may have been accepted.")
    output[index].push(chunk)
  })
}
process.on("SIGTERM", () => finish(143, "Buffer request cancelled."))
process.on("SIGINT", () => finish(130, "Buffer request cancelled."))

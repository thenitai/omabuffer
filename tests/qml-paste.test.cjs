const { test } = require("node:test")
const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

test("Qt paste event routes and asynchronous editing behavior", () => {
  const stage = fs.mkdtempSync(path.join(os.tmpdir(), "omabuffer-qml-"))
  try {
    const root = path.join(__dirname, "..")
    for (const file of ["BoundedPaste.qml", "Composer.qml", "Setup.qml", "BufferApi.js"])
      fs.copyFileSync(path.join(root, file), path.join(stage, file))
    fs.mkdirSync(path.join(stage, "scripts"))
    fs.mkdirSync(path.join(stage, "tests/qml"), { recursive: true })
    fs.copyFileSync(path.join(__dirname, "qml/tst_paste.qml"), path.join(stage, "tests/qml/tst_paste.qml"))
    // The real reader processes a deterministic fake provider. The test never
    // requests or changes the user's Wayland clipboard.
    fs.writeFileSync(path.join(stage, "scripts/read-clipboard.py"),
      `import runpy,sys\nreader=runpy.run_path(${JSON.stringify(path.join(root, "scripts/read-clipboard.py"))})\nsource="import sys,time; time.sleep(0.2); sys.stdout.buffer.write(sys.argv[1].encode())"\ntext="primary" if sys.argv[1] == "primary" else "clip 🌍\\n<b>x</b>"\nsys.exit(reader["main"]([sys.executable,"-c",source,text]))\n`)
    for (const name of ["Commons", "Ui"])
      fs.symlinkSync(`/usr/share/omarchy/shell/${name}`, path.join(stage, name))
    fs.writeFileSync(path.join(stage, "shell.qml"), 'import QtQuick\nimport Quickshell\nShellRoot { Window { visible: true; width: 640; height: 900; Loader { anchors.fill: parent; source: "tests/qml/tst_paste.qml" } } }\n')
    // Quickshell modules are statically linked into its executable, so host
    // QtTest there instead of qmltestrunner. This window stays offscreen.
    const result = spawnSync("quickshell", ["--no-color", "--path", path.join(stage, "shell.qml")], {
      env: { ...process.env, WAYLAND_DISPLAY: "", QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "", QT_QUICK_CONTROLS_STYLE: "Basic", QSG_RHI_BACKEND: "software" },
      encoding: "utf8", timeout: 30000
    })
    assert.equal(result.error, undefined, String(result.error))
    assert.equal(result.status, 0, result.stdout + result.stderr)
    assert.match(result.stdout + result.stderr, /0 failed, 0 skipped/)
    assert.ok(!/QWARN|QFATAL|\bWARN\b|\bERROR\b/.test(result.stdout + result.stderr), result.stdout + result.stderr)
    console.log(result.stdout.trim())
  } finally {
    fs.rmSync(stage, { recursive: true, force: true })
  }
})

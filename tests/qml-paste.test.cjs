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
    for (const file of ["BoundedPaste.qml", "ClipboardSafeField.qml", "Composer.qml", "Setup.qml", "BufferApi.js"])
      fs.copyFileSync(path.join(root, file), path.join(stage, file))
    fs.mkdirSync(path.join(stage, "scripts"))
    fs.mkdirSync(path.join(stage, "tests/qml"), { recursive: true })
    fs.copyFileSync(path.join(__dirname, "qml/tst_paste.qml"), path.join(stage, "tests/qml/tst_paste.qml"))
    const probeDir = path.join(stage, "tests/qml/ClipboardTest")
    fs.mkdirSync(probeDir)
    fs.writeFileSync(path.join(probeDir, "qmldir"), "module ClipboardTest\nplugin clipboardprobe\n")
    const probeSource = path.join(__dirname, "qml/clipboard-probe.cpp")
    const flags = spawnSync("pkg-config", ["--cflags", "--libs", "Qt6Qml", "Qt6Gui"], { encoding: "utf8" })
    assert.equal(flags.status, 0, flags.stderr)
    const qtFlags = flags.stdout.trim().split(/\s+/)
    const moc = spawnSync("/usr/lib/qt6/moc", [...qtFlags.filter(flag => flag.startsWith("-I")),
      probeSource, "-o", path.join(stage, "clipboard-probe.moc")], { encoding: "utf8" })
    assert.equal(moc.status, 0, moc.stderr)
    const build = spawnSync("g++", ["-shared", "-fPIC", "-std=c++17", "-I" + stage,
      probeSource, "-o", path.join(probeDir, "libclipboardprobe.so"), ...qtFlags], { encoding: "utf8" })
    assert.equal(build.status, 0, build.stderr)
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
      env: { ...process.env, WAYLAND_DISPLAY: "", QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "", QT_QUICK_CONTROLS_STYLE: "Basic", QSG_RHI_BACKEND: "software", QML_IMPORT_PATH: path.join(stage, "tests/qml") },
      encoding: "utf8", timeout: 30000
    })
    assert.equal(result.error, undefined, String(result.error) + "\n" + result.stdout + result.stderr)
    assert.equal(result.status, 0, result.stdout + result.stderr)
    assert.match(result.stdout + result.stderr, /0 failed, 0 skipped/)
    assert.ok(!/QWARN|QFATAL|\bWARN\b|\bERROR\b/.test(result.stdout + result.stderr), result.stdout + result.stderr)
    console.log(result.stdout.trim())
  } finally {
    fs.rmSync(stage, { recursive: true, force: true })
  }
})

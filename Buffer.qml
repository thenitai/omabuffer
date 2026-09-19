import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Buffer.js" as Buffer
import "ShortcutModel.js" as ShortcutModel

// Buffer composer overlay. Summoned with a Hyprland binding:
//   omarchy-shell shell toggle thenitai.omabuffer
//
// Posts text to a Buffer channel through the `buffer` CLI (npm:
// @bufferapp/cli) — added to the channel's queue or published immediately.
// The API key is stored 0600 and handed to the CLI through its environment,
// never on the command line. A daily posting-limit check runs before every
// post so a used-up channel is reported instead of failing on the server.

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // ---- styling (menu surface tokens, same language as omarchy.menu) -------
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color errorColor: Color.urgent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.space(20)
  property int contentSpacing: Style.space(14)
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int cardMaxHeight: Math.max(Style.space(200), panel.height - Style.gapsOut * 2)

  // ---- state ----------------------------------------------------------------
  readonly property string stateDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy-buffer"
  readonly property string pluginDir: {
    var s = Qt.resolvedUrl("Buffer.js").toString()
    s = s.substring(0, s.lastIndexOf("/") + 1)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    return decodeURIComponent(s)
  }
  property bool storageReady: false
  property bool setupMode: false
  property bool savingSetup: false
  property bool prefsLoaded: false
  property bool keyLoaded: false

  // CLI presence (resolved through a login shell so mise/npm paths work)
  property string cliPath: ""
  property bool cliChecked: false

  property string apiKey: ""
  property string lastOrgId: ""
  property string channelId: ""
  property string mode: Buffer.MODE_QUEUE

  property bool channelsLoaded: false
  property bool channelsLoading: false

  readonly property bool configured: storageReady && cliPath !== "" && apiKey !== ""

  property string statusText: ""
  property bool statusIsError: false
  property bool sending: false

  property string linkCardUrl: ""

  // ---- global shortcut (registered at runtime via hyprctl eval) -----------
  property string shortcut: ""
  property string shortcutRegistered: ""
  property string shortcutCandidate: ""
  property bool shortcutPersist: false
  property bool shortcutBusy: false
  property bool shortcutOk: true
  property string shortcutMessage: ""
  readonly property string shortcutOwner: "buffer:" + Date.now() + ":"
    + Math.random().toString(36).slice(2)

  function applyShortcut(value, persist) {
    if (root.shortcutBusy) return
    var parsed = ShortcutModel.parse(value)
    root.shortcutOk = false
    if (String(value || "").trim() !== "" && !parsed) {
      root.shortcutMessage = "Use modifiers and a key, for example SUPER + SHIFT + P."
      return
    }
    root.shortcutCandidate = parsed ? parsed.text : ""
    root.shortcutPersist = persist === true
    root.shortcutMessage = ""
    root.shortcutBusy = true
    shortcutBindsProc.running = true
  }

  function checkShortcutBindings(text, code) {
    if (code !== 0 || !text.trim()) {
      root.shortcutBusy = false
      root.shortcutMessage = "Could not read Hyprland's shortcuts."
      return
    }
    var list = ShortcutModel.bindings(text)
    var conflict = ShortcutModel.conflict(list, ShortcutModel.parse(root.shortcutCandidate))
    if (conflict) {
      root.shortcutBusy = false
      root.shortcutMessage = root.shortcutCandidate + " is already assigned to "
        + (conflict.description || "another action") + "."
      return
    }
    shortcutRegisterProc.command = ["hyprctl", "eval",
      ShortcutModel.registerCode(list, root.shortcutRegistered, root.shortcutCandidate, root.shortcutOwner)]
    shortcutRegisterProc.running = true
  }

  function savePrefs() {
    prefsView.setText(JSON.stringify({
      channelId: root.channelId,
      mode: root.mode,
      shortcut: root.shortcut
    }))
  }

  onSetupModeChanged: if (setupMode && !root.cliPath) root.resolveCli()

  function resolveCli() {
    if (cliResolveProc.running) return
    cliResolveProc.running = true
  }

  onShortcutChanged: shortcutApplyLater.restart()

  Component.onDestruction: {
    if (root.shortcutRegistered)
      Quickshell.execDetached(["hyprctl", "eval",
        ShortcutModel.releaseCode(root.shortcutRegistered, root.shortcutOwner)])
  }

  ListModel { id: channelsModel }

  // ---- lifecycle ---------------------------------------------------------------

  function applyFocusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var target = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === target) {
        panel.screen = screens[i]
        return
      }
  }

  function open(payloadJson) {
    root.applyFocusedScreen()
    root.opened = true
    if (!root.cliChecked) root.resolveCli()
    root.ensureChannels()
    Qt.callLater(root.focusDefault)
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function dismiss() {
    if (root.sending) return
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "thenitai.omabuffer")
  }

  function focusDefault() {
    if (!root.configured || root.setupMode) setup.keyField.forceActiveFocus()
    else composer.textAreaItem.forceActiveFocus()
  }

  // ---- status -------------------------------------------------------------------

  function flash(msg, isError) {
    statusText = msg
    statusIsError = !!isError
    statusClearTimer.restart()
  }

  function setStatus(msg) {
    statusText = msg
    statusIsError = false
    statusClearTimer.stop()
  }

  function clearStatus() {
    statusText = ""
  }

  // ---- account & channels -----------------------------------------------------------

  function setupError(msg) {
    setup.statusText = msg
    setup.statusError = true
  }

  function saveCredentials(key) {
    if (root.savingSetup) return
    if (!key) return setupError("Enter your Buffer API key")
    if (!root.cliPath) return setupError("Install the Buffer CLI first — npm install -g @bufferapp/cli")
    root.savingSetup = true
    setup.statusText = "Verifying…"
    setup.statusError = false
    root.verifyKey(key, function(err, orgId) {
      root.savingSetup = false
      if (err) {
        if (err.isAuth)
          return setupError("That API key was rejected. Create a fresh one at publish.buffer.com → Settings → API.")
        return setupError(err.message || "Could not reach Buffer")
      }
      root.apiKey = key
      root.lastOrgId = orgId
      root.channelsLoaded = false
      writeFileProc.writeSecret("api-key", key, null)
      root.savePrefs()
      setup.statusText = ""
      root.setupMode = false
      root.flash("Signed in ✓", false)
      root.ensureChannels()
      Qt.callLater(root.focusDefault)
    })
  }

  function verifyKey(key, cb) {
    accountProc.start(key, function(res, orgId) {
      if (!res.ok) return cb({ message: res.message, isAuth: res.isAuth }, "")
      if (!orgId) return cb({ message: "No organization found for this account", isAuth: false }, "")
      cb(null, orgId)
    })
  }

  function hasChannel(id) {
    for (var i = 0; i < channelsModel.count; i++)
      if (channelsModel.get(i).id === id) return true
    return false
  }

  function ensureChannels() {
    if (!root.configured || root.channelsLoaded || root.channelsLoading) return
    root.channelsLoading = true
    if (root.lastOrgId === "") {
      root.setStatus("Connecting…")
      root.verifyKey(root.apiKey, function(err, orgId) {
        if (err) {
          root.channelsLoading = false
          return root.channelsFailed(err)
        }
        root.lastOrgId = orgId
        root.fetchChannels()
      })
    } else {
      root.fetchChannels()
    }
  }

  function fetchChannels() {
    root.setStatus("Loading channels…")
    channelsProc.start(function(res) {
      root.channelsLoading = false
      if (!res.ok) return root.channelsFailed(res)
      channelsModel.clear()
      var items = Buffer.extractChannels(res.json)
      for (var i = 0; i < items.length; i++) {
        var ch = items[i]
        if (ch.isDisconnected) continue
        channelsModel.append({
          id: String(ch.id || ""),
          name: String(ch.name || ""),
          displayName: String(ch.displayName || ""),
          service: String(ch.service || ""),
          avatar: String(ch.avatar || "")
        })
      }
      if (channelsModel.count > 0) {
        if (!root.channelId || !root.hasChannel(root.channelId))
          root.channelId = channelsModel.get(0).id
      } else {
        root.channelId = ""
      }
      root.channelsLoaded = true
      root.clearStatus()
    })
  }

  function channelsFailed(err) {
    if (err && err.isAuth) {
      root.setupMode = true
      root.clearStatus()
      setup.statusText = "Your Buffer API key was rejected. Enter a new one."
      setup.statusError = true
      if (root.opened) Qt.callLater(root.focusDefault)
      return
    }
    root.flash(err && err.message ? err.message : "Could not load channels", true)
  }

  // ---- posting pipeline ------------------------------------------------------------------

  function selectedChannel() {
    for (var i = 0; i < channelsModel.count; i++) {
      var ch = channelsModel.get(i)
      if (ch.id === root.channelId) return ch
    }
    return null
  }

  function startPost() {
    if (root.sending || root.channelsLoading) return
    if (!root.configured) {
      root.setupMode = true
      flash("Add your Buffer API key first", true)
      return
    }
    var ch = root.selectedChannel()
    var text = composer.text
    var v = Buffer.validate(text, ch ? ch.service : "", !!ch)
    if (v) return root.flash(v, true)
    root.sending = true
    root.setStatus("Checking daily limit…")
    limitProc.start(ch.id, function(res, limitJson) {
      if (!res.ok && res.isAuth) {
        root.sending = false
        return root.channelsFailed(res)
      }
      if (res.ok && Buffer.limitReached(limitJson, ch.id)) {
        root.sending = false
        return root.flash(Buffer.limitMessage(limitJson, ch.id), true)
      }
      // Limit unknown (query failed, e.g. older plan) — post anyway; the
      // server enforces limits authoritatively and reports a typed error.
      root.setStatus("Sending…")
      var input = Buffer.buildPostInput(ch.id, root.mode, text, ch.service, root.linkCardUrl)
      postProc.start(JSON.stringify(input), function(res2) {
        if (!res2.ok) {
          root.sending = false
          if (res2.isAuth) return root.channelsFailed(res2)
          return root.flash(res2.message || "Post failed", true)
        }
        root.postSuccess()
      })
    })
  }

  function postSuccess() {
    root.sending = false
    var queued = root.mode === Buffer.MODE_QUEUE
    root.flash(queued ? "Added to queue ✓" : "Posted ✓", false)
    Quickshell.execDetached(["notify-send", "Buffer",
      queued ? "Added to your queue ✓" : "Published now ✓"])
    postDoneTimer.restart()
  }

  function clearDraftAndClose() {
    composer.clearDraft()
    root.linkCardUrl = ""
    root.clearStatus()
    root.dismiss()
  }

  // ---- processes ---------------------------------------------------------------------------

  Process {
    id: initStorage
    command: ["sh", "-c",
      "umask 077; mkdir -p \"$1\" && chmod 700 \"$1\" && touch \"$1/prefs.json\" \"$1/api-key\" && chmod 600 \"$1/api-key\"",
      "buffer-storage", root.stateDir]
    running: true
    onExited: function(code) {
      if (code === 0) root.storageReady = true
      else console.warn("omabuffer: could not initialize state directory")
    }
  }

  // Locates the buffer CLI through a login shell so npm/mise paths resolve.
  Process {
    id: cliResolveProc
    command: ["sh", "-lc", "command -v buffer 2>/dev/null || true"]
    stdout: StdioCollector {
      id: cliResolveOut
      waitForEnd: true
    }
    onExited: function(code) {
      var text = cliResolveOut.text.trim()
      var last = ""
      if (text) {
        var lines = text.split("\n")
        last = lines[lines.length - 1].trim()
      }
      root.cliChecked = true
      root.cliPath = last.indexOf("/") === 0 ? last : ""
    }
  }

  // Generic 0600 secret writer (API key). Queued.
  Process {
    id: writeFileProc
    property string payload: ""
    property var onDone: null
    property var writeQueue: []
    stdinEnabled: true
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
    onExited: function(code) {
      stdinEnabled = true
      var f = onDone
      onDone = null
      if (f) f(code)
      var next = writeQueue.shift()
      if (next) writeSecret(next.file, next.content, next.cb)
    }
    function writeSecret(fileName, content, cb) {
      if (running) {
        writeQueue.push({ file: fileName, content: content, cb: cb })
        return
      }
      payload = content
      onDone = cb
      command = ["sh", "-c",
        "umask 077; cat > \"$1.new\" && chmod 600 \"$1.new\" && mv -f \"$1.new\" \"$1\"",
        "buffer-write", root.stateDir + "/" + fileName]
      running = true
    }
  }

  // `buffer account` — key verification and organization lookup.
  Process {
    id: accountProc
    property var cb: null
    property string key: ""
    command: ["true"]
    stdout: StdioCollector {
      id: accountOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: accountErr
      waitForEnd: true
    }
    // qmllint disable incompatible-type
    environment: ({
      "BUFFER_API_KEY": accountProc.key
    })
    // qmllint enable incompatible-type
    onExited: function(code) {
      var f = accountProc.cb
      accountProc.cb = null
      if (!f) return
      var res = Buffer.parseResult(code, accountOut.text, accountErr.text)
      if (!res.ok) return f(res, "")
      var acc = Buffer.extractAccount(res.json)
      f(res, acc.organizationId)
    }
    function start(key, callback) {
      if (running) return callback({ ok: false, message: "busy", isAuth: false }, "")
      accountProc.key = key
      accountProc.cb = callback
      command = [root.cliPath, "account", "--output", "json", "--quiet"]
      running = true
    }
  }

  // `buffer channels list` — the channel picker data.
  Process {
    id: channelsProc
    property var cb: null
    command: ["true"]
    stdout: StdioCollector {
      id: channelsOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: channelsErr
      waitForEnd: true
    }
    // qmllint disable incompatible-type
    environment: ({
      "BUFFER_API_KEY": root.apiKey
    })
    // qmllint enable incompatible-type
    onExited: function(code) {
      var f = channelsProc.cb
      channelsProc.cb = null
      if (f) f(Buffer.parseResult(code, channelsOut.text, channelsErr.text))
    }
    function start(callback) {
      if (running) return callback({ ok: false, message: "busy", isAuth: false })
      channelsProc.cb = callback
      command = [root.cliPath, "channels", "list", "--organization-id", root.lastOrgId,
        "--fields", "id,name,displayName,service,avatar,isDisconnected",
        "--output", "json", "--quiet"]
      running = true
    }
  }

  // `buffer dailyPostingLimits list` — pre-flight usage check before posting.
  Process {
    id: limitProc
    property var cb: null
    command: ["true"]
    stdout: StdioCollector {
      id: limitOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: limitErr
      waitForEnd: true
    }
    // qmllint disable incompatible-type
    environment: ({
      "BUFFER_API_KEY": root.apiKey
    })
    // qmllint enable incompatible-type
    onExited: function(code) {
      var f = limitProc.cb
      limitProc.cb = null
      var res = Buffer.parseResult(code, limitOut.text, limitErr.text)
      if (f) f(res, res.ok ? res.json : null)
    }
    function start(channelId, callback) {
      if (running) return callback({ ok: false, message: "busy", isAuth: false }, null)
      limitProc.cb = callback
      command = [root.cliPath, "dailyPostingLimits", "list", "--channel-ids", channelId,
        "--output", "json", "--quiet"]
      running = true
    }
  }

  // `buffer posts create --input -` — the post itself, payload via stdin.
  Process {
    id: postProc
    property var cb: null
    property string payload: ""
    stdinEnabled: true
    command: ["true"]
    stdout: StdioCollector {
      id: postOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: postErr
      waitForEnd: true
    }
    // qmllint disable incompatible-type
    environment: ({
      "BUFFER_API_KEY": root.apiKey
    })
    // qmllint enable incompatible-type
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
    onExited: function(code) {
      stdinEnabled = true
      var f = postProc.cb
      postProc.cb = null
      if (f) f(Buffer.parseResult(code, postOut.text, postErr.text))
    }
    function start(json, callback) {
      if (running) return callback({ ok: false, message: "busy", isAuth: false })
      postProc.payload = json
      postProc.cb = callback
      command = [root.cliPath, "posts", "create", "--input", "-",
        "--output", "json", "--quiet"]
      running = true
    }
  }

  // ---- global shortcut processes --------------------------------------------

  Process {
    id: shortcutBindsProc
    command: ["hyprctl", "binds"]
    stdout: StdioCollector {
      id: shortcutBindsOut
      waitForEnd: true
    }
    onExited: function(code) {
      root.checkShortcutBindings(shortcutBindsOut.text, code)
    }
  }

  Process {
    id: shortcutRegisterProc
    command: ["true"]
    stdout: StdioCollector {
      id: shortcutRegisterOut
      waitForEnd: true
    }
    onExited: function(code) {
      root.shortcutBusy = false
      if (code !== 0 || shortcutRegisterOut.text.trim() !== "ok") {
        root.shortcutMessage = "Could not apply the shortcut. Check your Hyprland configuration."
        return
      }
      root.shortcutRegistered = root.shortcutCandidate
      root.shortcutOk = true
      if (root.shortcutPersist) {
        root.shortcutMessage = root.shortcutCandidate ? "Shortcut saved." : "Shortcut disabled."
        root.shortcut = root.shortcutCandidate
        root.savePrefs()
      } else {
        root.shortcutMessage = ""
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") shortcutApplyLater.restart()
    }
  }

  Timer {
    id: shortcutApplyLater
    interval: 250
    onTriggered: {
      if (root.shortcutBusy) restart()
      else root.applyShortcut(root.shortcut, false)
    }
  }

  // ---- persisted state -------------------------------------------------------------------------

  FileView {
    id: prefsView
    path: root.storageReady ? root.stateDir + "/prefs.json" : ""
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        if (data && typeof data === "object") {
          root.channelId = String(data.channelId || "")
          root.mode = data.mode === Buffer.MODE_NOW ? Buffer.MODE_NOW : Buffer.MODE_QUEUE
          root.shortcut = String(data.shortcut || ShortcutModel.DEFAULT)
        }
      } catch (e) {}
      root.prefsLoaded = true
    }
  }

  FileView {
    id: keyView
    path: root.storageReady ? root.stateDir + "/api-key" : ""
    onLoaded: {
      root.apiKey = (text() || "").trim()
      root.keyLoaded = true
    }
  }

  // ---- timers ------------------------------------------------------------------------------------

  Timer {
    id: statusClearTimer
    interval: 4000
    onTriggered: root.clearStatus()
  }

  Timer {
    id: postDoneTimer
    interval: 700
    onTriggered: root.clearDraftAndClose()
  }

  // ---- window --------------------------------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "thenitai-omabuffer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardMaxHeight,
        card.contentTopInset + card.contentBottomInset + cardColumn.implicitHeight)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: function(mouse) {} }

      Column {
        id: cardColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset
        spacing: root.contentSpacing

        Text {
          visible: root.configured && !root.setupMode
          text: "Buffer"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          visible: root.statusText !== ""
          width: parent.width
          text: root.statusText
          textFormat: Text.PlainText
          color: root.statusIsError ? root.errorColor : root.foreground
          opacity: root.statusIsError ? 1 : 0.62
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Setup {
          id: setup
          visible: !root.configured || root.setupMode
          width: parent.width
          foreground: root.foreground
          errorColor: root.errorColor
          fontFamily: root.fontFamily
          contentSpacing: root.contentSpacing
          busy: root.savingSetup
          canGoBack: root.configured
          signedIn: root.configured
          cliMissing: root.cliChecked && root.cliPath === ""
          currentKey: root.apiKey
          shortcutValue: root.shortcut
          shortcutBusy: root.shortcutBusy
          shortcutOk: root.shortcutOk
          shortcutMessage: root.shortcutMessage
          onShortcutApply: function(value) { root.applyShortcut(value, true) }
          onSaved: function(key) { root.saveCredentials(key) }
          onBackRequested: {
            root.setupMode = false
            Qt.callLater(root.focusDefault)
          }
          onDismissRequested: function() {
            if (root.configured) {
              root.setupMode = false
              Qt.callLater(root.focusDefault)
            } else root.dismiss()
          }
        }

        Composer {
          id: composer
          visible: root.configured && !root.setupMode
          width: parent.width
          channelsModel: channelsModel
          channelId: root.channelId
          mode: root.mode
          linkCardUrl: root.linkCardUrl
          sending: root.sending
          checking: root.channelsLoading
          foreground: root.foreground
          errorColor: root.errorColor
          fontFamily: root.fontFamily
          contentSpacing: root.contentSpacing
          onPostRequested: root.startPost()
          onDismissRequested: root.dismiss()
          onSettingsRequested: {
            root.setupMode = true
            Qt.callLater(root.focusDefault)
          }
          onChannelPicked: function(id) {
            if (id !== root.channelId) {
              root.channelId = id
              root.savePrefs()
            }
          }
          onModePicked: function(m) {
            if (m !== root.mode) {
              root.mode = m
              root.savePrefs()
            }
          }
          onLinkCardRequested: root.linkCardUrl = composer.cardUrl
          onClearLinkCardRequested: root.linkCardUrl = ""
        }
      }
    }
  }
}

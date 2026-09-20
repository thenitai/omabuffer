// Structural tests for the QML cache lifecycle and settings wiring.

const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const overlay = fs.readFileSync(path.join(root, "Buffer.qml"), "utf8")
const setup = fs.readFileSync(path.join(root, "Setup.qml"), "utf8")

let failed = 0
function ok(name, value) {
  if (value) console.log("PASS", name)
  else { failed++; console.log("FAIL", name) }
}

ok("prefs persist channel cache", overlay.includes("data.channelCache = {")
  && overlay.includes("organizationId: root.lastOrgId")
  && overlay.includes("channels: root.cachedChannels"))
ok("prefs hydrate channel cache", overlay.includes("Buffer.parseChannelCache(data.channelCache, Date.now())")
  && overlay.includes("root.applyChannels(cache.channels)"))
ok("ready transition retries first-open load", overlay.includes("onChannelStateReadyChanged: if (channelStateReady && root.opened && !root.savingSetup) root.ensureChannels(false)"))
ok("fresh cache skips remote refresh", overlay.includes("Buffer.isChannelCacheFresh(root.channelsCachedAt, Date.now())"))
ok("credential replacement invalidates cache", overlay.includes("if (keyChanged) root.invalidateChannelCache()"))
ok("refresh failure retains cache", !/function channelsFailed\(err\)[\s\S]*?root\.invalidateChannelCache\(\)/.test(overlay)
  && !/function channelsFailed\(err\)[\s\S]*?root\.channelsLoaded = false/.test(overlay))
ok("background refresh does not block posting", overlay.includes("checking: root.channelsLoading && !root.channelsLoaded")
  && !/function startPost\(\) \{\s*if \(root\.channelsLoading\)/.test(overlay))
ok("settings exposes refresh control", setup.includes("signal channelRefreshRequested()")
  && setup.includes('text: setup.channelRefreshBusy ? "Refreshing…" : "Refresh channels"'))
ok("settings refresh is wired", overlay.includes("onChannelRefreshRequested: root.ensureChannels(true)"))

console.log(failed === 0 ? "\nALL TESTS PASSED" : "\n" + failed + " TESTS FAILED")
process.exit(failed === 0 ? 0 : 1)

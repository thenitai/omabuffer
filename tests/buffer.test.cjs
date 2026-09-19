// Offline unit tests for the pure functions in Buffer.js.
// Run with: node tests/buffer.test.cjs

const fs = require("fs")
const path = require("path")

let src = fs.readFileSync(path.join(__dirname, "..", "Buffer.js"), "utf8")
src = src.replace(/\.pragma library\n/, "")
const Buffer = eval("(function(){" + src + "; return {MODE_QUEUE, MODE_NOW, DEFAULT_MODE, CHAR_LIMITS, DEFAULT_CHAR_LIMIT, LINK_CARD_SERVICES, supportsLinkCard, charLimit, extractUrls, firstUrl, hostOf, graphemeCount, charCount, buildPostInput, validate, parseResult, extractAccount, extractChannels, limitEntry, limitReached, limitMessage}})()")

let failed = 0
function eq(name, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) console.log("PASS", name)
  else { failed++; console.log("FAIL", name, "\n  got: ", g, "\n  want:", w) }
}

// modes
eq("default mode is queue", Buffer.DEFAULT_MODE, "addToQueue")

// link card services
eq("link card linkedin", Buffer.supportsLinkCard("linkedin"), true)
eq("link card bluesky", Buffer.supportsLinkCard("bluesky"), true)
eq("link card case-insensitive", Buffer.supportsLinkCard("LinkedIn"), true)
eq("no link card twitter", Buffer.supportsLinkCard("twitter"), false)
eq("no link card empty", Buffer.supportsLinkCard(""), false)

// char limits
eq("limit twitter", Buffer.charLimit("twitter"), 280)
eq("limit linkedin", Buffer.charLimit("linkedin"), 3000)
eq("limit bluesky", Buffer.charLimit("bluesky"), 300)
eq("limit default", Buffer.charLimit("unknown-service"), 5000)

// extractUrls
const urls = Buffer.extractUrls("go to https://example.com/x?y=1, and http://a.b/c.")
eq("extractUrls count", urls.length, 2)
eq("extractUrls trim", urls[0].url, "https://example.com/x?y=1")
eq("firstUrl", Buffer.firstUrl("see https://buffer.com/now ok"), "https://buffer.com/now")
eq("firstUrl none", Buffer.firstUrl("no links here"), "")

// graphemeCount
eq("graphemes ascii", Buffer.graphemeCount("hello"), 5)
eq("graphemes zwj family", Buffer.graphemeCount("👨‍👩‍👧‍👦"), 1)

// charCount: UTF-16 code units on most networks (emoji = 2)
eq("count linkedin ascii", Buffer.charCount("hello", "linkedin"), 5)
eq("count linkedin emoji", Buffer.charCount("🚀 ok", "linkedin"), 5)
// bluesky counts graphemes
eq("count bluesky emoji", Buffer.charCount("🚀 ok", "bluesky"), 4)
// linkedin counts every URL as 24
// "a https://example.com/x b" = 1+1+23+1+1 = 27 raw; URL (23 chars) becomes 24 → 28
eq("count linkedin url", Buffer.charCount("a https://example.com/x b", "linkedin"), 28)
// twitter counts every URL as 23
eq("count twitter url", Buffer.charCount("a https://example.com/x b", "twitter"), 27)
// utf-16 networks: plain length
eq("count facebook plain", Buffer.charCount("café", "facebook"), 4)

// buildPostInput
const input = Buffer.buildPostInput("ch1", "addToQueue", "Hello world", "linkedin", "")
eq("post input queue", input, {
  channelId: "ch1", schedulingType: "automatic", mode: "addToQueue",
  text: "Hello world", source: "thenitai.omabuffer"
})
eq("post input now", Buffer.buildPostInput("ch1", "shareNow", "Hi", "twitter", "").mode, "shareNow")
eq("post input mode fallback", Buffer.buildPostInput("ch1", "bogus", "Hi", "twitter", "").mode, "addToQueue")
const withCard = Buffer.buildPostInput("ch1", "addToQueue", "see https://example.com", "linkedin", "https://example.com")
eq("post input link card", withCard.metadata, { linkedin: { linkAttachment: { url: "https://example.com" } } })
const cardBsky = Buffer.buildPostInput("ch1", "addToQueue", "x", "Bluesky", "https://example.com")
eq("post input card case-insensitive service", cardBsky.metadata, { bluesky: { linkAttachment: { url: "https://example.com" } } })
eq("post input no card on twitter", Buffer.buildPostInput("ch1", "addToQueue", "x", "twitter", "https://example.com").metadata, undefined)
eq("post input no card url", Buffer.buildPostInput("ch1", "addToQueue", "x", "linkedin", "").metadata, undefined)

// validate
eq("validate empty", Buffer.validate("", "twitter", true), "Write something first")
eq("validate no channel", Buffer.validate("hi", "twitter", false), "Pick a channel first")
eq("validate over twitter", Buffer.validate("x".repeat(281), "twitter", true), "Over the 280 character limit for this channel")
eq("validate ok", Buffer.validate("hi", "twitter", true), "")

// parseResult
eq("parse success", Buffer.parseResult(0, '{"id":"5"}', ""),
  { ok: true, json: { id: "5" }, message: "", isAuth: false, code: 0 })
eq("parse auth error", Buffer.parseResult(4, "", '{"error":"AUTH_ERROR","code":4,"message":"Access token is not valid"}'),
  { ok: false, json: { error: "AUTH_ERROR", code: 4, message: "Access token is not valid" }, message: "Access token is not valid", isAuth: true, code: 4 })
eq("parse api error", Buffer.parseResult(3, "", '{"error":"API_ERROR","code":3,"message":"LinkedIn posts cannot exceed 3000 characters."}').message,
  "LinkedIn posts cannot exceed 3000 characters.")
eq("parse non-json error", Buffer.parseResult(2, "", "Usage: buffer posts create ...").message, "Usage: buffer posts create ...")
eq("parse empty error", Buffer.parseResult(1, "", "").message, "buffer CLI exited with code 1")

// extractAccount
eq("extract account", Buffer.extractAccount({ id: "a1", email: "x@y.z", organizations: [{ id: "org1" }] }),
  { id: "a1", email: "x@y.z", organizationId: "org1" })
eq("extract account empty", Buffer.extractAccount({}), { id: "", email: "", organizationId: "" })

// extractChannels
eq("extract channels items", Buffer.extractChannels({ items: [{ id: "c1" }, { id: "c2" }] }), [{ id: "c1" }, { id: "c2" }])
eq("extract channels array", Buffer.extractChannels([{ id: "c1" }]), [{ id: "c1" }])
eq("extract channels empty", Buffer.extractChannels({}), [])

// daily posting limits
const limitJson = { channelId: "ch1", sent: 4, scheduled: 6, limit: 10, isAtLimit: true }
eq("limit reached", Buffer.limitReached(limitJson, "ch1"), true)
eq("limit other channel", Buffer.limitReached([{ channelId: "ch2", isAtLimit: true }], "ch1"), false)
eq("limit not reached", Buffer.limitReached({ channelId: "ch1", isAtLimit: false }, "ch1"), false)
eq("limit message", Buffer.limitMessage(limitJson, "ch1"),
  "Daily posting limit reached for this channel — 10/10 posts today")
eq("limit message mixed", Buffer.limitMessage({ channelId: "ch1", sent: 2, scheduled: 3, limit: 10, isAtLimit: false }, "ch1"),
  "Daily posting limit reached for this channel — 5/10 posts today")

console.log(failed === 0 ? "\nALL TESTS PASSED" : "\n" + failed + " TESTS FAILED")
process.exit(failed === 0 ? 0 : 1)

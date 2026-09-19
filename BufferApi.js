// Buffer CLI helpers for thenitai.omabuffer.
//
// All network access happens through the `buffer` CLI (npm: @bufferapp/cli),
// so this library is pure: input construction, validation, counting and
// parsing of the CLI's JSON output. The CLI prints success data (unwrapped
// from the GraphQL response) to stdout and error objects as
// {"error": "...", "code": n, "message": "..."} on stderr.
.pragma library

var MODE_QUEUE = "addToQueue"
var MODE_NOW = "shareNow"
var DEFAULT_MODE = MODE_QUEUE

// Buffer's per-network post text limits (developers.buffer.com/guides/
// character-limits.html). Most networks count UTF-16 code units, so
// string.length in JS is the right measure; the exceptions are handled in
// charCount() below. The server validates authoritatively — these power the
// live counter only.
var CHAR_LIMITS = {
  twitter: 280,
  linkedin: 3000,
  bluesky: 300,
  facebook: 5000,
  instagram: 2196,
  threads: 500,
  mastodon: 500,
  pinterest: 500,
  tiktok: 4000,
  youtube: 5000,
  google: 4000
}
var DEFAULT_CHAR_LIMIT = 5000

// Services whose metadata supports linkAttachment (the link card). Buffer
// fetches the page server-side from the URL, including the image. X/Twitter
// unfurls links natively, so no card is needed there.
var LINK_CARD_SERVICES = ["bluesky", "linkedin", "facebook", "threads", "substack"]

function supportsLinkCard(service) {
  return LINK_CARD_SERVICES.indexOf(String(service || "").toLowerCase()) !== -1
}

function charLimit(service) {
  var s = String(service || "").toLowerCase()
  return CHAR_LIMITS[s] || DEFAULT_CHAR_LIMIT
}

// ---- URL extraction ---------------------------------------------------------

function extractUrls(text) {
  var t = String(text || "")
  var out = []
  var re = /https?:\/\/[^\s<>"')\]]+/g
  var m
  while ((m = re.exec(t)) !== null) {
    var url = m[0]
    while (/[.,;:!?]+$/.test(url)) url = url.slice(0, -1)
    if (url.length > 3) {
      out.push({ url: url, start: m.index, end: m.index + url.length })
      if (out.length >= 5) break
    }
  }
  return out
}

function firstUrl(text) {
  var urls = extractUrls(text)
  return urls.length > 0 ? urls[0].url : ""
}

function hostOf(url) {
  var m = String(url || "").match(/^https?:\/\/([^\/?#]+)/i)
  return m ? m[1] : String(url || "")
}

// ---- counting ---------------------------------------------------------------

function graphemeCount(text) {
  var t = String(text || "")
  if (typeof Intl !== "undefined" && Intl.Segmenter) {
    var seg = new Intl.Segmenter(undefined, { granularity: "grapheme" })
    var segs = seg.segment(t)
    var iter = typeof segs[Symbol.iterator] === "function" ? segs[Symbol.iterator]() : segs
    var n = 0
    var r = iter.next()
    while (!r.done) {
      n++
      r = iter.next()
    }
    return n
  }
  return Array.from(t).length
}

// How Buffer counts characters for a service. JS string.length is UTF-16
// code units, which is exactly what most networks use (emoji outside the
// BMP already count as 2). Bluesky counts graphemes; X counts URLs as 23
// and LinkedIn as 24 code units whatever their real length.
function charCount(text, service) {
  var t = String(text || "")
  var s = String(service || "").toLowerCase()
  if (s === "bluesky") return graphemeCount(t)
  var total = t.length
  var perUrl = s === "twitter" ? 23 : (s === "linkedin" ? 24 : 0)
  if (perUrl) {
    var urls = extractUrls(t)
    for (var i = 0; i < urls.length; i++) total += perUrl - urls[i].url.length
  }
  return total
}

// ---- input construction ------------------------------------------------------

// The JSON object piped to `buffer posts create --input -`. One call per
// channel; the link card is attached only where the service supports it.
function buildPostInput(channelId, mode, text, service, cardUrl) {
  var input = {
    channelId: String(channelId || ""),
    schedulingType: "automatic",
    mode: mode === MODE_NOW ? MODE_NOW : MODE_QUEUE,
    text: String(text || ""),
    source: "thenitai.omabuffer"
  }
  if (cardUrl && supportsLinkCard(service)) {
    var metadata = {}
    metadata[String(service).toLowerCase()] = { linkAttachment: { url: cardUrl } }
    input.metadata = metadata
  }
  return input
}

// Smallest remaining allowance across the selected channels' services —
// drives the live counter for a multi-channel post.
function minRemaining(text, services) {
  var t = String(text || "")
  if (!services || !services.length)
    return DEFAULT_CHAR_LIMIT - charCount(t, "")
  var min = null
  for (var i = 0; i < services.length; i++) {
    var r = charLimit(services[i]) - charCount(t, services[i])
    if (min === null || r < min) min = r
  }
  return min
}

// Validates the text against every selected channel's counting rules.
function validateMulti(text, services) {
  if (!String(text || "").trim()) return "Write something first"
  if (!services || !services.length) return "Pick a channel first"
  for (var i = 0; i < services.length; i++) {
    if (charCount(text, services[i]) > charLimit(services[i]))
      return "Over the " + charLimit(services[i]) + " character limit for this channel"
  }
  return ""
}

// ---- CLI output parsing --------------------------------------------------------

// buffer CLI contract: success data on stdout (exit 0), error object
// {"error", "code", "message"} on stderr otherwise. Auth errors are
// exit code 4 / error "AUTH_ERROR".
function parseResult(exitCode, stdoutText, stderrText) {
  var out = String(stdoutText || "").trim()
  var err = String(stderrText || "").trim()
  var outJson = null
  var errJson = null
  if (out) { try { outJson = JSON.parse(out) } catch (e) {} }
  if (err) { try { errJson = JSON.parse(err) } catch (e) {} }

  if (exitCode === 0) return { ok: true, json: outJson, message: "", isAuth: false, code: 0 }

  var message = ""
  if (errJson && errJson.message) message = String(errJson.message)
  else if (errJson && errJson.error) message = String(errJson.error)
  else if (err) message = err
  else if (outJson && outJson.message) message = String(outJson.message)
  else message = "buffer CLI exited with code " + exitCode

  return {
    ok: false,
    json: errJson || outJson,
    message: message,
    isAuth: exitCode === 4 || (errJson ? errJson.error === "AUTH_ERROR" : false),
    code: exitCode
  }
}

// `buffer account --output json` → {id, email, organizations: [{id}]}
function extractAccount(json) {
  var data = json || {}
  return {
    id: String(data.id || ""),
    email: String(data.email || ""),
    organizationId: (data.organizations && data.organizations[0] && data.organizations[0].id) || ""
  }
}

// `buffer channels list --output json` → {items: [{...}], pageInfo: {...}}
function extractChannels(json) {
  var data = json || {}
  if (Array.isArray(data)) return data
  if (Array.isArray(data.items)) return data.items
  if (data.channels && Array.isArray(data.channels.items)) return data.channels.items
  if (Array.isArray(data.channels)) return data.channels
  return []
}

// `buffer dailyPostingLimits list --channel-ids <id> --output json` →
// {channelId, sent, scheduled, limit, isAtLimit} per channel (an array when
// more than one channel was requested).
function limitEntry(limitJson, channelId) {
  var d = limitJson
  if (Array.isArray(d)) {
    for (var i = 0; i < d.length; i++)
      if (!channelId || String(d[i].channelId || "") === String(channelId)) return d[i]
    return null
  }
  return d && typeof d === "object" ? d : null
}

function limitReached(limitJson, channelId) {
  var d = limitEntry(limitJson, channelId)
  return !!(d && d.isAtLimit === true)
}

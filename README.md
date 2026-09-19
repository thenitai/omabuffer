# omabuffer

Post to Buffer from anywhere on Omarchy. Hit a global shortcut, pick a
channel, type, Enter — queued or published immediately through the
official Buffer CLI. A tiny composer overlay for the Omarchy Quattro shell.

## Features

- **Bar icon and global shortcut** composer overlay — summon from either, Esc closes
- **Any connected channel** — pick from your Buffer channels with one click;
  the choice is remembered
- **Queue or publish now** — add to the channel's Buffer queue or post
  immediately, one toggle
- **Link cards** — paste a URL and attach a link card; Buffer fetches the
  page (including its image) when the post goes out. Supported on Bluesky,
  LinkedIn, Facebook and Threads; X/Twitter unfurls links natively
- **Daily limit check** — before every post the channel's daily posting
  limit is checked and a used-up channel is reported up front
- **Per-channel character counter** — counts the way each network counts
  (Bluesky graphemes, LinkedIn URLs as 24, X URLs as 23)

## Install

```sh
omarchy plugin add https://github.com/thenitai/omabuffer.git --enable
```

During installation you are asked where to place the bar icon — left,
center or right (the right side is the preselected default). To move it
later:

```sh
omarchy plugin enable thenitai.omabuffer --section center
```

Then install the Buffer CLI (Node 18 or later):

```sh
npm install -g @bufferapp/cli
```

## Setup

1. Create an API key at **publish.buffer.com → Settings → API**.
2. Click the Buffer bar icon or press the composer shortcut — the first run
   shows the setup form. Paste the API key and hit *Save & verify*.
3. Pick the channel to post to directly in the composer.

The API key is stored in `~/.config/omarchy-buffer/api-key` (directory mode
`0700`, the key file `0600`) and is handed to the Buffer CLI through its
`BUFFER_API_KEY` environment variable — never through the command line —
so it never shows up in a process list.

## Global shortcut

The composer opens with **SUPER + ALT + B** by default. The plugin registers
it with Hyprland at runtime (via `hyprctl eval`), so no manual binding is
needed; it is re-applied whenever the shell starts or Hyprland reloads its
config.

Change it in the plugin's **Settings** view: type a combo like
`SUPER + SHIFT + P` and hit *Apply*. Combos already assigned to another
Hyprland action are rejected with the conflicting action's name, and
leaving the field empty disables the shortcut. The choice persists across
restarts.

## Bar icon

The Buffer icon on the bar opens (or closes) the composer — a discoverable
fallback for when the global shortcut is disabled or unavailable. Its
section is chosen during installation; see above for how to move it later.

## Keyboard

| Key | Action |
| --- | --- |
| `Esc` | Close (draft is kept) |
| `Ctrl+Enter` | Post |
| `Ctrl+V` | Paste clipboard text at the cursor |
| `Ctrl+A/C/X/Z` | Standard text editing |
| `Super+A/V/C/X/Z` | Same, for Super-mapped system shortcuts — requires the triggering Hyprland bind to opt in with `{ allow_input_capture = true }` |
| Click outside | Close |

## CLI notes

Everything goes through the `buffer` CLI (`@bufferapp/cli` on npm), which
wraps Buffer's public GraphQL API:

- `buffer account` — API key verification and organization lookup
- `buffer channels list` — the channel picker
- `buffer dailyPostingLimits list` — pre-flight check before each post
- `buffer posts create --input -` — the post itself, with the payload piped
  through stdin (nothing user-typed ever appears in `argv`)

Errors are surfaced from the CLI's structured JSON output; auth failures
(issued or expired keys) reopen the setup form, mutation errors (for
example the server-side limit check) are shown inline.

Not implemented (yet): images and video (Buffer requires media to live at
a public URL), threads, reply/quote behavior, scheduled-at times, drafts
and ideas.

## Remove

```sh
omarchy plugin remove thenitai.omabuffer
rm -rf ~/.config/omarchy-buffer   # API key and preferences
```

Revoke the API key in publish.buffer.com settings when you're done.

## License

MIT

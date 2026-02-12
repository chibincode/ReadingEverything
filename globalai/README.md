# Agent Pulse Board (MVP)

A local-first dashboard to monitor `Codex`, `Cursor`, and `Lovable` in one view.

## What this MVP does

- Tracks per-agent status: `Running`, `Waiting You`, `Blocked`, `Idle`, `Done`
- Auto-marks `Running` as `Blocked` after timeout (default: 30 minutes)
- Highlights only actionable cards (`Waiting You` + `Blocked`)
- Stores data in browser LocalStorage
- Imports and exports board state as JSON
- Optional browser notifications for actionable states

## Run

No build is required.

1. Open `index.html` directly, or serve the folder:

```bash
python3 -m http.server 5173
```

2. Open [http://localhost:5173](http://localhost:5173)

## PWA / app-like window

- In Chrome: use "Install app" (or "Open as window")
- In Safari: add to Dock from Share menu

## Status logic

- `Waiting You` if manually set to waiting
- `Running` if manually set and not timed out
- `Blocked` if manually set, or auto-timeout from running
- `Idle` / `Done` as manually set

## Next step after MVP

Add provider adapters so statuses update automatically:

- Lovable browser-extension parser
- Codex event feed adapter
- Cursor extension/event adapter

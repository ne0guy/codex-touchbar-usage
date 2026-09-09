# ZCode Touch Bar

This source checkout extends the native helper with a ZCode panel. Existing
Codex rendering, quota interpretation, reset cards, and token labels are preserved.
Previously published release archives do not include this extension.

## Display

- Focus Codex / ChatGPT: the existing Codex panel.
- Focus ZCode (`dev.zcode.app`): GLM or OpenCode Go balance and today's local tokens.
- Focus another app: the system Touch Bar is restored.
- Tap the ZCode panel to see all five quota windows and today / cumulative tokens.
  Tap again to return. Codex has no new tap behavior.

The title follows the most recently completed request found in ZCode's logs,
not the selected conversation or the provider dropdown. A request running in
another ZCode conversation can therefore change the title. Switching providers
before any request is logged does not immediately change it.

Go displays rolling and monthly balances; weekly balance remains visible in the
summary. GLM displays the five-hour and weekly balances, with Go's rolling balance
as a secondary reference. All percentages are remaining balances. Dates use the
Mac's local timezone and `MM/dd HH:mm`.

## Sources and credentials

- Go: `GET https://opencode.ai/zen/go/v1/usage`.
- GLM: `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`.
- Credentials are read from `~/.zcode/v2/config.json` for each attempt.
  Go is discovered by its service URL or exact normalized provider name; there
  is no installation-specific UUID. Go can fall back to
  `~/.local/share/opencode/auth.json`.
- API keys are never included in process arguments, logs, or helper caches.
- The helper only queries usage endpoints; it never sends model prompts.

GLM's window mapping follows the installed ZCode renderer: `unit=3, number=5`
for five hours and `unit=6` for weekly usage. Both `TOKENS_LIMIT` and
`CREDIT_LIMIT` types are supported.

## Local token statistics

The helper reads `~/.zcode/cli/rollout/model-io-sess_*.jsonl` incrementally.
`response.usage.totalTokens` is the request total; cache-read tokens are not
added again. Records are grouped by local completion date. Cumulative tokens
represent retained local logs, not an official account lifetime total.

Initial history loading is split into bounded passes. Until initialization
finishes, token labels show an ellipsis. Normal scans run every 15 seconds.
Partial trailing records are retried after further data arrives.
Caches contain statistics, request identifiers, and file positions only,
never prompts or response content.

ZCode caches are separate from Codex:

- `~/.codex/touchbar-usage/zcode-stats-cache.json`
- `~/.codex/touchbar-usage/zcode-usage-cache.json`

## Refresh and diagnostics

Remote refresh normally runs every 30 seconds while ZCode is frontmost.
Each source independently backs off after failures: 60, 120, then 300 seconds.
Unavailable quota is shown as `--%`; the other source continues updating.
Zero usage is valid, and rolling-window usage is allowed to decrease.

Switching apps displays cached content immediately. Brief focus changes do not
start new network work. Old tasks are cancelled and late UI results are discarded.

Print a ZCode snapshot:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --zcode-once-json
```

Read local data without network:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --zcode-once-json --no-remote
```

On a fresh cache, one diagnostic invocation may only complete part of the
initial history scan; inspect `statsReady`. The running helper continues
initialization in the background while ZCode is focused.

## Installation and rollback

Install this source checkout with `./scripts/install_touchbar_helper.sh`.
It uses the existing app path and LaunchAgent. No second helper is installed.
Reinstall the previous release to roll back; Codex's cache format is unchanged.
ZCode caches can remain unused after rollback.

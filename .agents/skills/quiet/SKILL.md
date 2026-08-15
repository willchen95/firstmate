---
name: quiet
description: >-
  Keep firstmate silent until the final captain-facing reply for the current session.
  Use when the captain invokes /quiet, or says "stay quiet", "no chatter", or "silent until done".
  Turn off with /quiet off or "talk normally".
user-invocable: true
metadata:
  internal: true
---

# quiet

Session-scoped silence for captain chat.
This skill owns when firstmate may speak to the captain while quiet is on; Calm owns built-in tool-row presentation separately.

## On and off

- **On:** `/quiet`, or natural language such as "stay quiet", "no chatter", or "silent until done".
- **Off:** `/quiet off`, or "talk normally".
- Quiet lasts for the rest of this session until turned off.
- Do not write flags, files, or config for it.

## While quiet is on

1. Run tools as usual.
2. Do not send mid-turn captain-facing messages: no progress chatter, no "checking…", no "need the URL…", no partial status.
3. Send exactly one captain-facing reply at the end of the turn, after tool work for that turn is done.
4. Truth still beats silence: that final reply must still report a real blocker, needed credential, failed action, or other captain-needed outcome from the turn.
5. Section 9 captain etiquette still applies to that final reply.

## Honest limit

Pi Calm can hide built-in tool rows; MCP and custom tool rows (including lean-ctx `ctx_*`) stay visible because Pi does not expose a renderer wrap for them.
Never claim those rows are hidden.
Do not wrap MCP tools, add a CLI, or change Calm's hide contract to fake silence.

## Confirmations

When turning quiet on or off, one short captain-facing sentence is enough (for example that quiet is on until `/quiet off`, or that normal talk is restored).

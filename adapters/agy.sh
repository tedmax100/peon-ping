#!/bin/bash
# peon-ping adapter for Google Antigravity CLI (agy)
# Translates Antigravity lifecycle hooks into peon.sh stdin JSON.
#
# Setup: Add to ~/.gemini/config/hooks.json (global) or .agents/hooks.json (project):
# {
#   "peon-ping": {
#     "SessionStart": [
#       { "command": "bash /path/to/peon-ping/adapters/agy.sh SessionStart" }
#     ],
#     "PreInvocation": [
#       { "command": "bash /path/to/peon-ping/adapters/agy.sh PreInvocation" }
#     ],
#     "PostToolUse": [
#       {
#         "matcher": "*",
#         "hooks": [
#           { "command": "bash /path/to/peon-ping/adapters/agy.sh PostToolUse" }
#         ]
#       }
#     ],
#     "Stop": [
#       { "command": "bash /path/to/peon-ping/adapters/agy.sh Stop" }
#     ]
#   }
# }

set -euo pipefail

# Path to peon.sh - handles both local git checkout and installed locations
PEON_DIR="${CLAUDE_PEON_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ ! -f "$PEON_DIR/peon.sh" ] && PEON_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/peon-ping"

AGY_EVENT_ARG="${1:-}"

# Parse context payload from stdin and map to CESP event
MAPPED_RESULT="$(
  _AGY_EVENT_ARG="$AGY_EVENT_ARG" python3 -c '
import json
import os
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

event = os.environ.get("_AGY_EVENT_ARG") or data.get("hookEventName", "")

is_pre_tool = (event == "PreToolUse")
mapped_event = None
error_text = ""
tool_name = ""

if event == "SessionStart":
    mapped_event = "SessionStart"
elif event == "PreInvocation":
    mapped_event = "UserPromptSubmit"
elif event == "Stop":
    mapped_event = "Stop"
elif event == "PostToolUse":
    error = data.get("error")
    if error:
        mapped_event = "PostToolUseFailure"
        error_text = str(error)
        tool_call = data.get("toolCall")
        if isinstance(tool_call, dict):
            tool_name = str(tool_call.get("name", "Bash"))
        else:
            tool_name = "Bash"

payload_str = ""
if mapped_event:
    conv_id = str(data.get("conversationId") or os.getpid())
    sid = "antigravity-" + (conv_id[:8] if len(conv_id) >= 8 else conv_id)
    payload = {
        "hook_event_name": mapped_event,
        "notification_type": "",
        "cwd": str(data.get("cwd") or os.environ.get("PWD") or "/"),
        "session_id": sid,
        "permission_mode": "",
        "source": "antigravity",
    }
    if mapped_event == "PostToolUseFailure":
        payload["tool_name"] = tool_name or "Bash"
        payload["error"] = error_text
    payload_str = json.dumps(payload)

# First line: PreToolUse flag ("1" or "0")
# Remaining: JSON payload for peon.sh (if any)
print("1" if is_pre_tool else "0")
if payload_str:
    print(payload_str)
' 2>/dev/null
)" || MAPPED_RESULT=""

IS_PRE_TOOL="0"
MAPPED_JSON=""

if [ -n "$MAPPED_RESULT" ]; then
  IS_PRE_TOOL="$(echo "$MAPPED_RESULT" | head -n 1)"
  MAPPED_JSON="$(echo "$MAPPED_RESULT" | sed -n '2,$p')"
fi

# Dispatch to peon.sh if an event was mapped and peon.sh exists
if [ -n "$MAPPED_JSON" ] && [ -f "$PEON_DIR/peon.sh" ]; then
  printf '%s' "$MAPPED_JSON" | bash "$PEON_DIR/peon.sh" >/dev/null 2>&1 || true
fi

# Output required contract response back to agy
if [ "$IS_PRE_TOOL" = "1" ]; then
  echo '{"decision": "allow"}'
else
  echo "{}"
fi

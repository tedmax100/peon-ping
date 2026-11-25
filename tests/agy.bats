#!/usr/bin/env bats

load setup.bash

setup() {
  setup_test_env
  cp "$PEON_SH" "$TEST_DIR/peon.sh"
  ADAPTER_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/adapters/agy.sh"
}

teardown() {
  teardown_test_env
}

@test "agy adapter: SessionStart triggers greeting" {
  export CLAUDE_PEON_DIR="$TEST_DIR"
  run bash "$ADAPTER_SH" SessionStart <<'JSON'
{
  "conversationId": "test-session-12345678",
  "cwd": "/tmp/test",
  "hookEventName": "SessionStart"
}
JSON
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]

  sleep 0.5
  afplay_was_called
  sound=$(afplay_sound)
  [[ "$sound" == *"/packs/peon/sounds/Hello"* ]]
}

@test "agy adapter: Stop triggers completion" {
  export CLAUDE_PEON_DIR="$TEST_DIR"
  run bash "$ADAPTER_SH" Stop <<'JSON'
{
  "conversationId": "test-session-12345678",
  "cwd": "/tmp/test",
  "hookEventName": "Stop"
}
JSON
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]

  sleep 0.5
  afplay_was_called
  sound=$(afplay_sound)
  [[ "$sound" == *"/packs/peon/sounds/Done"* ]]
}

@test "agy adapter: PostToolUse without error is silent" {
  export CLAUDE_PEON_DIR="$TEST_DIR"
  run bash "$ADAPTER_SH" PostToolUse <<'JSON'
{
  "conversationId": "test-session-12345678",
  "cwd": "/tmp/test",
  "hookEventName": "PostToolUse",
  "toolCall": {"name": "run_command"}
}
JSON
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]

  sleep 0.5
  ! afplay_was_called
}

@test "agy adapter: PostToolUse with error plays error sound" {
  export CLAUDE_PEON_DIR="$TEST_DIR"
  run bash "$ADAPTER_SH" PostToolUse <<'JSON'
{
  "conversationId": "test-session-12345678",
  "cwd": "/tmp/test",
  "hookEventName": "PostToolUse",
  "error": "command failed with exit code 1",
  "toolCall": {"name": "run_command"}
}
JSON
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]

  sleep 0.5
  afplay_was_called
  sound=$(afplay_sound)
  [[ "$sound" == *"/packs/peon/sounds/Error"* ]]
}

@test "agy adapter: PreToolUse returns allow decision" {
  export CLAUDE_PEON_DIR="$TEST_DIR"
  run bash "$ADAPTER_SH" PreToolUse <<'JSON'
{
  "conversationId": "test-session-12345678",
  "cwd": "/tmp/test",
  "hookEventName": "PreToolUse",
  "toolCall": {"name": "run_command"}
}
JSON
  [ "$status" -eq 0 ]
  [ "$output" = '{"decision": "allow"}' ]
}

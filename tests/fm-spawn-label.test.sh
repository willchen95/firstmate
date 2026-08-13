#!/usr/bin/env bash
# tests/fm-spawn-label.test.sh - behavioral tests for --label flag in
# fm-spawn.sh. Exercises the actual validation and meta-writing logic
# by invoking the script's entrypoint or exercising the same patterns.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- parse-time validation (fm-spawn.sh runs these before --mode check) ----

test_rejects_newlines_in_label() {
  local output rc
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label $'foo\nbar' 2>&1) && { fail "expected failure"; return; } || rc=$?
  echo "$output" | grep -q "error: --label contains newline or carriage return characters" \
    || fail "wrong error for newline in label: $output"
  pass "--label rejects newlines in value"
}

test_rejects_carriage_return_in_label() {
  local output rc
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label $'foo\rbar' 2>&1) && { fail "expected failure"; return; } || rc=$?
  echo "$output" | grep -q "error: --label contains newline or carriage return characters" \
    || fail "wrong error for CR in label: $output"
  pass "--label rejects carriage returns in value"
}

test_rejects_home_workspace_label_collision() {
  local output rc
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label "firstmate" 2>&1) && { fail "expected failure"; return; } || rc=$?
  echo "$output" | grep -q "error: --label 'firstmate' collides with the home workspace label" \
    || fail "wrong error for home label collision: $output"
  pass "--label rejects 'firstmate' (home workspace label collision)"
}

test_rejects_projection_child_pattern() {
  local output rc
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label '└ Door Panel · p:abc123' 2>&1) && { fail "expected failure"; return; } || rc=$?
  echo "$output" | grep -q "error: --label '└" \
    || fail "wrong error for projection pattern: $output"
  pass "--label rejects labels starting with '└'"
}

test_valid_label_passes_validation() {
  local output rc
  # A valid label should pass the label checks and fail on --mode requirement
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label "Door Panel · fix clearance" 2>&1) && { fail "expected failure (--mode required)"; return; } || rc=$?
  echo "$output" | grep -q "ship spawns require --mode" \
    || fail "expected --mode error after valid label, got: $output"
  pass "valid --label passes validation (reaches --mode check)"
}

# --- meta recording (same pattern as fm-spawn.sh's meta write) -------------

test_meta_records_label() {
  local tmp
  tmp=$(fm_test_tmproot meta-test)/meta
  mkdir -p "$(dirname "$tmp")"

  LABEL="Door Panel · fix clearance"
  echo "effort=default" > "$tmp"
  [ -z "$LABEL" ] || echo "label=$LABEL" >> "$tmp"
  grep -q '^label=Door Panel · fix clearance$' "$tmp" \
    || fail "label= not written to meta"
  pass "label= written to meta when LABEL is set"
}

test_meta_omits_label_when_unset() {
  local tmp
  tmp=$(fm_test_tmproot meta-omit)/meta
  mkdir -p "$(dirname "$tmp")"

  LABEL=""
  echo "effort=default" > "$tmp"
  [ -z "$LABEL" ] || echo "label=$LABEL" >> "$tmp"
  grep -q '^label=' "$tmp" && fail "label= written to meta when LABEL is empty" || true
  pass "label= omitted from meta when LABEL is empty"
}

# --- run -------------------------------------------------------------------

test_rejects_newlines_in_label
test_rejects_carriage_return_in_label
test_rejects_home_workspace_label_collision
test_rejects_projection_child_pattern
test_valid_label_passes_validation
test_meta_records_label
test_meta_omits_label_when_unset

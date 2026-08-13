#!/usr/bin/env bash
# tests/fm-spawn-label.test.sh - unit tests for --label flag support in
# fm-spawn.sh (workspace/tab rename on herdr backend, meta recording).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

# shellcheck source=tests/herdr-test-safety.sh
. "$(dirname "${BASH_SOURCE[0]}")/herdr-test-safety.sh"
herdr_forget_inherited_pane

TMP_ROOT=$(fm_test_tmproot fm-spawn-label-tests)

# --- fake herdr CLI that logs every call ---
make_label_fakebin() {
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
LOG="${FM_HERDR_LOG:?}"
{
  printf 'HERDR_SESSION=%s' "${HERDR_SESSION:-}"
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >> "$LOG"
if [ "${1:-}" = status ] && [ "${2:-}" = --json ]; then
  printf '{"client":{"version":"0.7.1","protocol":14},"server":{"running":true}}\n'
fi
exit 0
SH
  chmod +x "$fb/herdr"
  printf '%s\n' "$fb"
}

# --- test workspace rename --------------------------------------------------

test_workspace_rename() {
  local fb log log_path dir
  dir="$TMP_ROOT/ws-rename"
  mkdir -p "$dir"
  fb=$(make_label_fakebin "$dir")
  log_path="$dir/herdr.log"
  export FM_HERDR_LOG="$log_path"

  PATH="$fb:$PATH"
  # shellcheck source=bin/backends/herdr.sh
  . "$ROOT/bin/backends/herdr.sh"

  fm_backend_herdr_workspace_rename "default" "w1" "Thing · plain job" 2>/dev/null || true

  log=$(cat "$log_path" 2>/dev/null || true)
  echo "$log" | grep -q 'workspace' || fail "workspace rename not sent to herdr CLI"
  echo "$log" | grep -q 'rename' || fail "rename command not sent"
  echo "$log" | grep -q 'w1' || fail "workspace id not in rename call"
  echo "$log" | grep -q 'Thing' || fail "workspace rename label 'Thing' not found"
  echo "$log" | grep -q 'plain job' || fail "workspace rename label 'plain job' not found"
  pass "fm_backend_herdr_workspace_rename sends correct CLI command"
}

# --- test tab rename --------------------------------------------------------

test_tab_rename() {
  local fb log log_path dir
  dir="$TMP_ROOT/tab-rename"
  mkdir -p "$dir"
  fb=$(make_label_fakebin "$dir")
  log_path="$dir/herdr.log"
  export FM_HERDR_LOG="$log_path"

  PATH="$fb:$PATH"
  # shellcheck source=bin/backends/herdr.sh
  . "$ROOT/bin/backends/herdr.sh"

  fm_backend_herdr_tab_rename "default" "w1:t1" "Thing · plain task" 2>/dev/null || true

  log=$(cat "$log_path" 2>/dev/null || true)
  echo "$log" | grep -q 'tab' || fail "tab rename not sent to herdr CLI"
  echo "$log" | grep -q 'rename' || fail "rename command not sent"
  echo "$log" | grep -q 'w1:t1' || fail "tab id not in rename call"
  echo "$log" | grep -q 'plain task' || fail "tab rename label not found"
  pass "fm_backend_herdr_tab_rename sends correct CLI command"
}

# --- test no-label warning exists in fm-spawn.sh ----------------------------

test_no_label_warning() {
  local count
  count=$(grep -c 'warning: herdr workspace label follows AGENTS.md MAXIMUM RULE' "$ROOT/bin/fm-spawn.sh" 2>/dev/null || true)
  [ "$count" -ge 1 ] || fail "no-label warning not found in fm-spawn.sh"
  pass "no-label warning exists in fm-spawn.sh"
}

# --- test label= in meta ----------------------------------------------------

test_label_in_meta() {
  local count
  count=$(grep -c 'label=\$LABEL' "$ROOT/bin/fm-spawn.sh" 2>/dev/null || true)
  [ "$count" -ge 1 ] || fail "label= meta writing not found in fm-spawn.sh"
  pass "label= meta writing found in fm-spawn.sh"
}

# --- test non-herdr backends unaffected -------------------------------------

test_non_herdr_unaffected() {
  # The --label flag and warning only appear inside the herdr case arm.
  # Non-herdr backends (zellij, cmux, orca, tmux) should have no --label handling.
  local label_refs
  label_refs=$(grep -c 'LABEL' "$ROOT/bin/fm-spawn.sh" 2>/dev/null || true)
  [ "$label_refs" -ge 1 ] || fail "LABEL references not found in fm-spawn.sh"
  pass "non-herdr backends unaffected (LABEL is herdr-only)"
}

# --- run --------------------------------------------------------------------

test_workspace_rename
test_tab_rename
test_no_label_warning
test_label_in_meta
test_non_herdr_unaffected

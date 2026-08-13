#!/usr/bin/env bash
# tests/fm-spawn-label.test.sh - behavioral tests for --label flag in
# fm-spawn.sh. Exercises the actual validation logic by invoking the script's
# entrypoint, and the meta-recording behavior by driving full spawns against a
# fake tmux backend (the meta write is backend-common) and reading the
# persisted state/<id>.meta contract.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-label)

# Fake tmux: answers the pane-path query so the spawn's worktree-detection poll
# converges immediately; every other tmux call succeeds silently.
make_label_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse
  printf '%s\n' "$fakebin"
}

make_label_spawn_case() {
  local name=$1 case_dir home proj wt fakebin id
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_label_fakebin "$case_dir")
  mkdir -p "$home/data" "$home/projects" "$home/state" "$home/config"
  printf 'claude\n' > "$home/config/crew-harness"
  printf '%s\n' "$$" > "$home/state/.lock"
  printf '%s off\n' "$$" > "$home/state/.trace-context-effective"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  touch "$home/state/.last-watcher-beat"
  id=$name-z1
  mkdir -p "$home/data/$id"
  printf 'brief for %s\n' "$id" > "$home/data/$id/brief.md"
  printf '%s\n' "$home|$proj|$wt|$fakebin|$id"
}

read_label_case() {
  IFS='|' read -r HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR CASE_ID <<EOF
$1
EOF
}

run_label_spawn() {
  local home=$1 wt=$2 fakebin=$3
  shift 3
  env -u FM_TRACE_CONTEXT \
    FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    PATH="$fakebin:$PATH" \
    "$SPAWN" "$@" --mode no-mistakes --yolo off 2>&1
}

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

test_rejects_token_suffix_pattern() {
  local output rc
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label 'Door Panel · p:AbCdEfGhIjKlMnOpQrStUv' 2>&1) && { fail "expected failure"; return; } || rc=$?
  echo "$output" | grep -q "suffix reserved for the projection token grammar" \
    || fail "wrong error for token-suffix label: $output"
  pass "--label rejects a ' · p:<22-char-token>' suffix"
}

test_near_token_suffix_passes_validation() {
  local output rc
  # 21 token characters is not the reserved 22-char grammar, so this label is
  # allowed and the spawn proceeds to the --mode requirement.
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label 'Door Panel · p:AbCdEfGhIjKlMnOpQrStU' 2>&1) && { fail "expected failure (--mode required)"; return; } || rc=$?
  echo "$output" | grep -q "ship spawns require --mode" \
    || fail "expected --mode error after near-token label, got: $output"
  pass "a non-token-shaped ' · p:' label passes validation (reaches --mode check)"
}

test_valid_label_passes_validation() {
  local output rc
  # A valid label should pass the label checks and fail on --mode requirement
  output=$(bash "$ROOT/bin/fm-spawn.sh" --label "Door Panel · fix clearance" 2>&1) && { fail "expected failure (--mode required)"; return; } || rc=$?
  echo "$output" | grep -q "ship spawns require --mode" \
    || fail "expected --mode error after valid label, got: $output"
  pass "valid --label passes validation (reaches --mode check)"
}

# --- meta recording (full spawns; state/<id>.meta is the persisted contract) -

test_meta_records_label() {
  local rec out meta
  rec=$(make_label_spawn_case metalabel)
  read_label_case "$rec"
  out=$(run_label_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" \
    "$CASE_ID" "$PROJ_DIR" --label 'Door Panel · fix clearance') \
    || { fail "spawn with --label failed: $out"; return; }
  meta="$HOME_DIR/state/$CASE_ID.meta"
  [ -f "$meta" ] || { fail "spawn did not write $meta: $out"; return; }
  grep -q '^label=Door Panel · fix clearance$' "$meta" \
    || fail "label= not recorded in state/<id>.meta: $(cat "$meta")"
  pass "spawn records label= in state/<id>.meta when --label is given"
}

test_meta_omits_label_when_unset() {
  local rec out meta
  rec=$(make_label_spawn_case metaomit)
  read_label_case "$rec"
  out=$(run_label_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" \
    "$CASE_ID" "$PROJ_DIR") \
    || { fail "spawn without --label failed: $out"; return; }
  meta="$HOME_DIR/state/$CASE_ID.meta"
  [ -f "$meta" ] || { fail "spawn did not write $meta: $out"; return; }
  if grep -q '^label=' "$meta"; then
    fail "label= recorded in state/<id>.meta without --label: $(cat "$meta")"
  fi
  case "$out" in
    *"herdr spawn without --label"*)
      fail "tmux spawn printed the herdr no-label warning: $out" ;;
  esac
  pass "spawn omits label= from state/<id>.meta and skips the herdr warning on tmux"
}

# --- run -------------------------------------------------------------------

test_rejects_newlines_in_label
test_rejects_carriage_return_in_label
test_rejects_home_workspace_label_collision
test_rejects_projection_child_pattern
test_rejects_token_suffix_pattern
test_near_token_suffix_passes_validation
test_valid_label_passes_validation
test_meta_records_label
test_meta_omits_label_when_unset

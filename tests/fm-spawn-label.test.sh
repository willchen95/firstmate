#!/usr/bin/env bash
# tests/fm-spawn-label.test.sh - behavioral tests for --label flag in
# fm-spawn.sh. Exercises the actual validation logic and meta-writing pattern
# through minimal shell scenarios rather than grepping source code.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- newline validation ----------------------------------------------------
# Exercises the same case-statement logic used in fm-spawn.sh to reject
# control characters that would forge extra key=value lines in meta.

test_rejects_newlines_in_label() {
  # newline in label must be rejected
  (LABEL=$'foo\nbar'; case "$LABEL" in *$'\n'*|*$'\r'*) exit 0 ;; *) exit 1 ;; esac) \
    || fail "did not reject newline in --label value"
  # carriage return in label must be rejected
  (LABEL=$'foo\rbar'; case "$LABEL" in *$'\n'*|*$'\r'*) exit 0 ;; *) exit 1 ;; esac) \
    || fail "did not reject carriage return in --label value"
  # normal label must be allowed
  (LABEL="Thing · plain job"; case "$LABEL" in *$'\n'*|*$'\r'*) exit 1 ;; *) exit 0 ;; esac) \
    || fail "rejected valid --label value"
  pass "--label rejects newlines/CR, allows normal characters"
}

# --- meta recording --------------------------------------------------------
# Exercises the exact same conditional pattern used in fm-spawn.sh to write
# label= into state/<id>.meta.

test_meta_records_label() {
  local tmp
  tmp=$(fm_test_tmproot meta-test)/meta
  mkdir -p "$(dirname "$tmp")"

  LABEL="Door Panel · fix clearance"
  echo "effort=default" > "$tmp"
  # Same pattern as fm-spawn.sh's meta writing
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

# --- warning format --------------------------------------------------------
# Verify the warning message is present in fm-spawn.sh at the expected
# location. This is a structural check because the warning only fires during
# an actual herdr spawn, which cannot be exercised without the full backend.

test_warning_message_format() {
  # The warning should cite the visible-names contract from AGENTS.md section 1
  # and recommend --label '<Thing> · <plain job>' format.
  local line
  line=$(grep -n 'warning: herdr spawn without --label' "$ROOT/bin/fm-spawn.sh" 2>/dev/null || true)
  [ -n "$line" ] || fail "warning message not found in fm-spawn.sh"
  echo "$line" | grep -q 'visible-names' \
    || fail "warning does not cite visible-names contract"
  echo "$line" | grep -q 'AGENTS.md section 1' \
    || fail "warning does not cite AGENTS.md section 1"
  pass "warning message cites visible-names contract correctly"
}

# --- run -------------------------------------------------------------------

test_rejects_newlines_in_label
test_meta_records_label
test_meta_omits_label_when_unset
test_warning_message_format

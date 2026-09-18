#!/usr/bin/env bash
# Contract check for the final worker/secondmate prompts emitted by fm-brief.
# This verifies delivered instructions, not an agent's interpretation of them.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRIEF="$ROOT/bin/fm-brief.sh"
TMP_ROOT=$(fm_test_tmproot fm-ask-user-authority)

test_primary_and_secondmate_instruction_generation() {
  local home ship charter
  home="$TMP_ROOT/home"
  mkdir -p "$home/data"

  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    "$BRIEF" authority-worker sample --mode no-mistakes >/dev/null 2>&1
  ship="$home/data/authority-worker/brief.md"
  assert_grep 'ask-user findings are never yours to answer' "$ship" \
    "generated implementation brief lets the worker own an ask-user decision"
  # shellcheck disable=SC2016 # Backticks are literal generated Markdown.
  assert_grep 'Firstmate applies `ask-user-authority` and obtains any required captain decision' "$ship" \
    "generated implementation brief bypasses the primary authority owner"
  # shellcheck disable=SC2016 # Backticks are literal generated Markdown.
  assert_grep 'Never pass `--yes` or `-y` to `no-mistakes axi run` or `no-mistakes axi respond`' "$ship" \
    "generated implementation brief permits silent ask-user auto-resolution"
  assert_no_grep 'the captain, not you, owns the ask-user decisions' "$ship" \
    "generated implementation brief retained conflicting captain-only wording"

  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_SECONDMATE_CHARTER='Handle sample work.' \
    "$BRIEF" authority-mate --secondmate --no-projects >/dev/null 2>&1
  charter="$home/data/authority-mate/brief.md"
  # shellcheck disable=SC2016 # Backticks are literal generated Markdown.
  assert_grep 'The local `AGENTS.md` is your job description' "$charter" \
    "generated secondmate charter does not load the tracked authority boundary"
  assert_no_grep 'continuous frame-by-frame monitoring' "$charter" \
    "generated secondmate charter duplicated the detailed authority procedure"
  pass "primary workers and secondmates receive the authority rule through generated instructions"
}

test_primary_and_secondmate_instruction_generation

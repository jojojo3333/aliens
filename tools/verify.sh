#!/usr/bin/env bash
# The four checks. A change is not done until all four are green.
#
#   tools/verify.sh rules    the house rules, as checks instead of prose
#   tools/verify.sh static   project parses and imports; data contracts hold
#   tools/verify.sh sim      headless test suite + balance report
#   tools/verify.sh play     the assembled desk, clicked through and asserted
#   tools/verify.sh          all four
#
# Carried over from Deadweight. Do not weaken a check to make it pass — see
# CLAUDE.md.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GODOT_VERSION="4.7-stable"
GODOT="${GODOT:-$REPO_ROOT/.godot-bin/Godot_v${GODOT_VERSION}_linux.x86_64}"

if [[ ! -x "$GODOT" ]]; then
  echo "godot not found at $GODOT" >&2
  echo "run tools/setup_godot.sh first, or set GODOT=/path/to/godot" >&2
  exit 127
fi

# The battles are random, so the count sets the precision of every percentage
# in the balance report. 200 keeps `verify` quick; SIM_RUNS=1000 for a real read.
SIM_RUNS="${SIM_RUNS:-200}"
FAILED=0

hdr() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok()  { printf '\033[32mPASS\033[0m %s\n' "$1"; }
bad() { printf '\033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }
skip(){ printf '\033[33mSKIP\033[0m %s\n' "$1"; }

# A GDScript runtime error prints and carries on: it does not raise, cannot be
# caught, and leaves the exit code at 0. Godot also exits 0 on parse errors. So
# output is inspected everywhere, never trusted.
RUNTIME_ERRORS='SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|Invalid access|Invalid call|Cannot call method'

verify_rules() {
  hdr "rules"
  local out
  out="$(python3 "$REPO_ROOT/tools/check_rules.py" 2>&1)"
  local rc=$?
  echo "$out"
  if [[ $rc -eq 0 ]]; then ok "house rules"; else bad "house rules"; fi
}

verify_static() {
  hdr "static"

  # Import first: it registers every class_name, and a fresh checkout or a new
  # file is otherwise "not declared in the current scope" for the scripts below.
  local out
  out="$("$GODOT" --headless --import --quit-after 2 2>&1)"
  if grep -qiE "$RUNTIME_ERRORS" <<<"$out"; then
    bad "project parses"
    grep -iE "$RUNTIME_ERRORS" <<<"$out" | head -20
  else
    ok "project parses and imports"
  fi

  # Every .gd file, parsed — `--import` only compiles what something references,
  # so a standalone tool can rot unnoticed. `--check-only` exits 0 either way.
  local parse_failed=0
  local gd
  while IFS= read -r gd; do
    local check
    check="$("$GODOT" --headless --check-only --script "res://$gd" 2>&1)"
    if grep -qiE 'Parse Error|Failed to load script|Compile Error' <<<"$check"; then
      parse_failed=1
      echo "  $gd"
      grep -iE 'Parse Error|Compile Error' <<<"$check" | head -3 | sed 's/^/    /'
    fi
  done < <(find sim ui tools tests -name '*.gd' 2>/dev/null | sort)
  if [[ $parse_failed -eq 0 ]]; then ok "every .gd parses"; else bad "every .gd parses"; fi

  out="$("$GODOT" --headless --script res://tools/validate_data.gd 2>&1)"
  local rc=$?
  echo "$out" | grep -E '^(ERROR|data)' || true
  if [[ $rc -eq 0 ]] && ! grep -qE "^ERROR|$RUNTIME_ERRORS" <<<"$out"; then
    ok "data contracts"
  else
    bad "data contracts"
  fi
}

verify_sim() {
  hdr "sim"
  local out rc

  out="$("$GODOT" --headless --script res://tests/run_tests.gd 2>&1)"
  rc=$?
  echo "$out" | grep -E '^(tests:|FAIL)' || true
  if [[ $rc -eq 0 ]] && ! grep -qE "$RUNTIME_ERRORS" <<<"$out"; then
    ok "test suite"
  else
    grep -E "$RUNTIME_ERRORS" <<<"$out" | head -8
    bad "test suite"
  fi

  out="$("$GODOT" --headless --script res://tools/sim_runner.gd -- --runs "$SIM_RUNS" 2>&1)"
  rc=$?
  echo "$out" | grep -vE '^Godot Engine' || true
  if [[ $rc -eq 0 ]] && ! grep -qE "$RUNTIME_ERRORS" <<<"$out"; then
    ok "$SIM_RUNS-run balance report"
  else
    bad "$SIM_RUNS-run balance report"
  fi
}

verify_play() {
  hdr "play"

  # Under a display when one can be had, sized to the project's window, so the
  # clicks are real mouse events landing on real layout.
  local runner=("$GODOT" --headless)
  if command -v xvfb-run >/dev/null 2>&1; then
    runner=(xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT")
  else
    skip "no xvfb-run; running headless"
  fi

  local out
  out="$("${runner[@]}" --path . --script res://tools/play.gd 2>&1)"
  local rc=$?
  echo "$out" | grep -E '^(play:|FAIL|SKIP)' || true
  if grep -qE "$RUNTIME_ERRORS" <<<"$out"; then
    bad "scripted playthrough — runtime errors"
    grep -E "$RUNTIME_ERRORS" <<<"$out" | head -8
    return
  fi
  if [[ $rc -eq 0 ]]; then ok "scripted playthrough"; else bad "scripted playthrough"; fi
}

case "${1:-all}" in
  rules)  verify_rules ;;
  static) verify_static ;;
  sim)    verify_sim ;;
  play)   verify_play ;;
  all)    verify_rules; verify_static; verify_sim; verify_play ;;
  *)      echo "usage: tools/verify.sh [rules|static|sim|play]" >&2; exit 2 ;;
esac

echo
if [[ $FAILED -eq 0 ]]; then
  printf '\033[32mgreen\033[0m\n'
else
  printf '\033[31mred\033[0m\n'
fi
exit $FAILED

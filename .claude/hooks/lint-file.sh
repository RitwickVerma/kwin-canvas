#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): qmllint (syntax only, as make lint-qml), bash -n + shellcheck at error severity (as make lint-shell).
# Only the edited file, only inside this repo. Exit 0 when clean or when the tool is missing;
# exit 2 (output goes to Claude) only on a real error in that file.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$f" ] && [ -f "$f" ] || exit 0
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$f" in "$root"/*) ;; *) exit 0 ;; esac
cd "$root" || exit 0
fail() { { echo "$1"; printf '%s\n' "$2"; } >&2; exit 2; }

is_bash=0
case "$f" in
*.sh) is_bash=1 ;;
*.qml)
    q=/usr/lib/qt6/bin/qmllint   # the Qt5 qmllint in /usr/bin is the wrong one (AGENTS.md)
    [ -x "$q" ] || exit 0
    out=$("$q" "$f" 2>&1)
    # qmllint exits 0 even on a syntax error, so grep for [syntax] exactly like make lint-qml
    printf '%s' "$out" | grep -q '\[syntax\]' && fail "qmllint: syntax error in $f" "$out"
    exit 0
    ;;
*) head -n 1 "$f" 2>/dev/null | grep -qE '^#!.*\b(ba)?sh\b' && is_bash=1 ;;
esac
[ "$is_bash" = 1 ] || exit 0
out=$(bash -n "$f" 2>&1) || fail "bash -n: syntax error in $f" "$out"
if command -v shellcheck >/dev/null 2>&1; then
    out=$(shellcheck --severity=error -x "$f" 2>&1) || fail "shellcheck (error severity) in $f" "$out"
fi
exit 0

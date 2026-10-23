#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Stop hook: run the repo's fast check once per turn, only when the tree differs from HEAD.
# Exit 2 hands the failure back to Claude so it fixes it before finishing.
# stop_hook_active is true when Claude is already continuing because of this hook: exit 0 then,
# or a failing check would loop forever.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = true ] && exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -n "$(git diff --name-only HEAD 2>/dev/null)" ] || exit 0

out=$(make lint unit 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
    {
        echo "Stop check failed: make lint unit (exit $rc). Last output:"
        printf '%s\n' "$out" | tail -n 40
        echo "Fix this before finishing the turn."
    } >&2
    exit 2
fi
exit 0

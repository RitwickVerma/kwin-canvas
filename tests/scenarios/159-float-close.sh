# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window that closes leaves no float behind: the float walk stops, instead of ticking every frame for a window that is gone"
floatheld() { c state >/dev/null; sed -n '1s/.* floatheld=\([0-9]*\).*/\1/p' <<<"$LAST_STATE"; }
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    c "panpx -900 0" >/dev/null
    sleep 1
    assert_eq "a floated window holds a float" "$(floatheld)" 1
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.closeWindow(); });' 1.5
    sleep 1
    assert_eq "its float is gone with it" "$(floatheld)" 0
    c cancel >/dev/null 2>&1
    # Put back the one window this closed. `fixtures` launches all five apps
    # again, which left three extra windows on the desk for every scenario
    # after this one (20, 30, 50 and 61 then drew a different desk). What
    # `fixtures` also did, and this keeps: drop kcalcrc, which the closing
    # window wrote its state to, so the new KCalc starts from its defaults and
    # the goldens do not drift.
    local n; n=$(nwindows)
    rm -f "$CONF"/kcalcrc
    run kcalc >/dev/null 2>&1
    mapped $((n + 1)) || echo "159: kcalc did not map in time" >&2
    sleep 1
    arrange >/dev/null
}

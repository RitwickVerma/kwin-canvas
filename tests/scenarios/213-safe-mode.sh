# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="safe mode: when ui.qml fails to load the canvas closes and stays closed - no black overlay, no frozen slide, no window moved - and logs it once; a hot reload of a good ui.qml brings it back"

safe() { c state >/dev/null; grep -o ' safe=[01]' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }
reals() {
    kwinjs 'var o = []; ["KCalc","sample.txt","Konsole","Dolphin","Gwenview"].forEach(function (k) { workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(k) >= 0) o.push(k + "=" + Math.round(x.frameGeometry.x)); }); }); print("SMREALS " + o.join(" "));' 0.3
    grep -a "SMREALS " "$STATE/kwin.log" | tail -1 | sed 's/.*SMREALS //'
}
hot() { # bump HotRev, so the scene's Loader loads ui.qml afresh
    local r; r=$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key HotRev --default 0)
    setcfg HotRev $((r + 1))
}

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    local ui=build/nest-data/kwin/effects/kwin-canvas/contents/ui/ui.qml
    [ -f "$ui" ] || { skip "no staged ui.qml at $ui"; return; }
    cp "$ui" "$OUT/ui.qml.good"
    local before; before=$(reals)

    # A ui.qml that cannot load: a type that does not exist at its root.
    printf 'import QtQuick\nNoSuchType {}\n' > "$ui"
    hot
    c open; sleep 1.0; c state
    assert_eq "the broken scene puts the canvas in safe mode" "$(safe)" 1
    assert_eq "and the canvas is not left open" "$(sget visible)" false
    assert_eq "it says so in the log, once" "$(grep -ac 'the scene (ui.qml) failed to load' "$LOG")" 1
    c open; sleep 0.6; c state
    assert_eq "a second open is refused" "$(sget visible)" false
    c "slide 400 0"; sleep 1.5; c state
    assert_eq "a slide does nothing" "$(sget visible)" false
    assert_eq "no window moved" "$(reals)" "$before"

    # The good file back, and a hot reload: the canvas works again.
    cp "$OUT/ui.qml.good" "$ui"
    hot
    assert_eq "a hot reload leaves safe mode" "$(safe)" 0
    c open; sleep 1.0; c state
    assert_eq "and the canvas opens again" "$(sget visible)" true
    c cancel >/dev/null; sleep 0.8
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key HotRev --delete
    c state >/dev/null
    arrange >/dev/null
}

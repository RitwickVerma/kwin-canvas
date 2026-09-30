#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Unit tests for the canvas's pure logic (effect/contents/ui/logic.js):
// the cluster gap, the clustering, and the float's physics. Run with
// `make unit`; a failing assertion exits non-zero with the case name.
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "..", "effect", "contents", "ui", "logic.js"), "utf8");
const L = new Function(src + "\nreturn { clusterGapFor, clusterDist, recluster, floatStep, fitRange, smartPan };")();

let pass = 0, fail = 0;
function ok(name, cond) {
    if (cond) { pass++; }
    else { fail++; console.error("FAIL " + name); }
}
function near(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 1e-9 : eps); }
function rect(id, x, y, w, h) { return { id: id, x: x, y: y, width: w, height: h }; }

// ---- the dynamic gap ----
ok("a configured gap is fixed", L.clusterGapFor(rect(1, 0, 0, 100, 100), rect(2, 0, 0, 100, 100), 160) === 160);
ok("the dynamic gap is half the pair's scale",
    L.clusterGapFor(rect(1, 0, 0, 480, 420), rect(2, 0, 0, 500, 400), 0) === 205);
ok("the dynamic gap reads the same scaled up",
    L.clusterGapFor(rect(1, 0, 0, 1500, 900), rect(2, 0, 0, 1700, 900), 0) === 450);

// ---- the distance ----
ok("touching windows are zero apart", L.clusterDist(rect(1, 0, 0, 100, 100), rect(2, 100, 0, 100, 100)) === 0);
ok("a diagonal gap is its true distance", near(L.clusterDist(rect(1, 0, 0, 100, 100), rect(2, 300, 400, 100, 100)), Math.sqrt(130000), 0.01));
ok("an overlap is zero apart", L.clusterDist(rect(1, 0, 0, 200, 200), rect(2, 100, 100, 200, 200)) === 0);

// ---- the user's ultrawide arrangement: one work group, not three ----
{
    const desk = [
        rect("konsole", 8699, -2654, 1455, 687),
        rect("spotify", 7780, -3572, 1492, 918),
        rect("dolphin", 2013, -1171, 1306, 557),
        rect("brave", 322, -728, 1938, 978),
        rect("opencode", 2461, -306, 2637, 861)
    ];
    const r = L.recluster(desk, {}, {}, 0);
    ok("the work group and the far pair are two clusters, not three", r.clusters.length === 2);
    ok("the far pair is its own cluster",
        r.clusters.some(c => c.ids.indexOf("konsole") >= 0 && c.ids.indexOf("spotify") >= 0 && c.n === 2));
    ok("the work group holds the other three",
        r.clusters.some(c => c.n === 3 && c.ids.indexOf("brave") >= 0 && c.ids.indexOf("dolphin") >= 0 && c.ids.indexOf("opencode") >= 0));
    ok("every window is in a cluster", Object.keys(r.clusterOf).length === 5);
}

// ---- the hysteresis: a pair stays past the gap, parts past half again ----
{
    const pair = [rect("a", 0, 0, 100, 100), rect("b", 400, 0, 100, 100)];
    const first = L.recluster(pair, {}, {}, 0);   // the gap 50: 300 apart, separate
    ok("far windows start separate", first.clusters.length === 2);
    // joined in a previous pass, the same distance (300) is inside the leave
    // band (50 * 1.5 = 75? no - 300 > 75, so it must part). A pair that was
    // one cluster stays one until the gap times 1.5: with the dynamic gap 50
    // the leave is 75, so these stay parted.
    const again = L.recluster(pair, first.clusterOf, first.ranks, 0);
    ok("a parted pair stays parted", again.clusters.length === 2);
    // near windows that were one cluster stay one past the join gap
    const nearPair = [rect("a", 0, 0, 100, 100), rect("b", 110, 0, 100, 100)];
    const joined = L.recluster(nearPair, {}, {}, 0);
    ok("near windows join", joined.clusters.length === 1);
    const stretched = [rect("a", 0, 0, 100, 100), rect("b", 130, 0, 100, 100)];
    const kept = L.recluster(stretched, joined.clusterOf, joined.ranks, 0);
    ok("a joined pair survives to half again as far", kept.clusters.length === 1);
}

// ---- the cohesion fades across the band ----
{
    const joined = L.recluster([rect("a", 0, 0, 100, 100), rect("b", 110, 0, 100, 100)], {}, {}, 0);
    ok("a tight cluster is fully cohesive", joined.clusters[0].co === 1);
    // 60 apart: the gap is 50, the leave band runs to 75 - inside the band
    // the cluster holds but its cohesion has begun to fade.
    const stretched = L.recluster([rect("a", 0, 0, 100, 100), rect("b", 160, 0, 100, 100)], joined.clusterOf, joined.ranks, 0);
    ok("a stretched cluster holds in the band", stretched.clusters.length === 1);
    ok("and its cohesion fades", stretched.clusters[0].co > 0 && stretched.clusters[0].co < 1);
}

// ---- the thread order is stable across recomputes ----
{
    const desk = [rect("a", 0, 0, 100, 100), rect("b", 110, 0, 100, 100), rect("c", 220, 0, 100, 100)];
    const first = L.recluster(desk, {}, {}, 0);
    const order1 = first.clusters[0].ids.join(",");
    // move a window without changing the membership; the order must not flip
    const desk2 = [rect("a", 0, 0, 100, 100), rect("b", 115, 40, 100, 100), rect("c", 220, 0, 100, 100)];
    const second = L.recluster(desk2, first.clusterOf, first.ranks, 0);
    ok("the thread order does not re-route", second.clusters[0].ids.join(",") === order1);
}

// ---- the float rests while inside ----
{
    const f = { x: 500, y: 300, vx: 0, vy: 0, wasInX: true, wasInY: true };
    const n = L.floatStep(f, 500, 300, 500, 300, 8, 1900, 8, 1050, 0, 0, false, 1 / 60);
    ok("at rest the picture is the window", n.x === 500 && n.y === 300);
    ok("and it carries only the camera's velocity", n.vx === 0);
    const n2 = L.floatStep(f, 400, 300, 400, 300, 8, 1900, 8, 1050, -6000, 0, false, 1 / 60);
    ok("a moving camera is carried as velocity", n2.vx === -6000 && n2.x === 400);
}

// ---- the float bounces off the edge and settles back against it ----
{
    const f = { x: 100, y: 300, vx: -6000, vy: 0, wasInX: true, wasInY: true };
    const hit = L.floatStep(f, 4, 300, 8, 300, 8, 1900, 8, 1050, -6000, 0, false, 1 / 60);
    ok("the edge reflects the carried velocity inward", hit.vx > 0);
    ok("and the picture stays inside", hit.x >= 8);
    let settled = hit;
    for (let i = 0; i < 240; ++i) settled = L.floatStep(settled, 4, 300, 8, 300, 8, 1900, 8, 1050, 0, 0, false, 1 / 60);
    ok("the picture settles against the edge", near(settled.x, 8, 0.5));
    ok("and the spring comes to rest", Math.abs(settled.vx) < 0.1);
}

// ---- the least pan: the margin, and the margin-free fullscreen ----
{
    const g = { x: 0, y: 0, width: 1920, height: 1080 };
    ok("a half-off window pans to the margin",
        L.smartPan({ x: 1700, y: 0, width: 480, height: 420 }, g, 0, 0, 1, 24).dx === 1700 + 480 - (1920 - 24));
    ok("a fully-in window does not move",
        L.smartPan({ x: 100, y: 100, width: 480, height: 420 }, g, 0, 0, 1, 24).dx === 0);
    const fs = L.smartPan({ x: 416, y: 0, width: 1920, height: 1080 }, g, -416, 0, 1, 24);
    ok("a fullscreen-sized window aligns margin-free", fs.dx === 416 + 416);
    ok("a screen-sized window aligns to the screen's edge, not the margin", L.smartPan({ x: 24, y: 0, width: 1920, height: 1080 }, g, 0, 0, 1, 24).dx === 24);
}

// ---- the hand owns a dragged float ----
{
    const f = { x: 8, y: 300, vx: 100, vy: 0, wasInX: false, wasInY: true };
    const n = L.floatStep(f, 500, 300, 500, 300, 8, 1900, 8, 1050, 0, 0, true, 1 / 60);
    ok("a drag moves the picture with the hand", n.x === 500 && n.vx === 0);
}

console.log("== unit pass " + pass + "  fail " + fail);
process.exit(fail === 0 ? 0 : 1);

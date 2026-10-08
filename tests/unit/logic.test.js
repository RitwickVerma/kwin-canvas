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
const L = new Function(src + "\nreturn { clusterGapFor, clusterDist, recluster, floatStep, fitRange, smartPan, smartPanNeighbourhood, canvasOf, zoomView, fitBox, seamPoint, seamNeighbour, segRectT, threadSpans, qualityFor, tidyRows, simplifyPath };")();

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

// ---- islands never cluster across desktops ----
{
    const cross = [
        Object.assign(rect("a", 0, 0, 100, 100), { desktop: 1 }),
        Object.assign(rect("b", 110, 0, 100, 100), { desktop: 2 })
    ];
    const r = L.recluster(cross, {}, {}, 0);
    ok("windows on different desktops never join a cluster", r.clusters.length === 2);
    const same = [
        Object.assign(rect("a", 0, 0, 100, 100), { desktop: 2 }),
        Object.assign(rect("b", 110, 0, 100, 100), { desktop: 2 })
    ];
    ok("windows on the same island still cluster", L.recluster(same, {}, {}, 0).clusters.length === 1);
    const unmarked = [rect("a", 0, 0, 100, 100), rect("b", 110, 0, 100, 100)];
    ok("rects without a desktop keep the old behaviour", L.recluster(unmarked, {}, {}, 0).clusters.length === 1);
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

// ---- the plane transform ---------------------------------------------------
{
    const c = L.canvasOf(960, 540, 0, 0, 1);
    ok("canvasOf is the identity at 1:1 on the origin", c.x === 960 && c.y === 540);
}
{
    // The invariant that bit the pass-through: a global point on a second
    // output maps with the same formula as its screen-local twin on the
    // first, plus the output's origin over the zoom - the visual transform
    // and its inverse cancel, so input and picture cannot drift apart.
    const x1 = 1920, z = 0.5, vx = -960, vy = -540;
    const a = L.canvasOf(x1 + 700, 400, vx, vy, z);
    const b = L.canvasOf(700, 400, vx, vy, z);
    ok("a second output's origin cancels in canvasOf", near(a.x - b.x, x1 / z) && near(a.y - b.y, 0));
}
{
    // Zooming around an anchor keeps the canvas point under the anchor.
    const ax = 960, ay = 540, vx = 100, vy = -40, z0 = 1, z1 = 0.4;
    const c = L.canvasOf(ax, ay, vx, vy, z0);
    const v = L.zoomView(c, ax, ay, z1);
    const again = L.canvasOf(ax, ay, v.x, v.y, z1);
    ok("the zoom keeps the anchor's canvas point", near(again.x, c.x) && near(again.y, c.y));
}
{
    // A box twice the screen fits at half the screen minus the pads, and
    // the view centres the box on the screen's own centre.
    const g = { x: 0, y: 0, width: 1920, height: 1080 };
    const f = L.fitBox(0, 0, 3840, 2160, g, 80, 0.1);
    ok("a 2x box fits at the binding zoom minus pads",
       near(f.zoom, Math.min((1920 - 160) / 3840, (1080 - 160) / 2160)));
    ok("and the view centres it", near(f.viewX, 1920 - 960 / f.zoom) && near(f.viewY, 1080 - 540 / f.zoom));
}
{
    const g = { x: 0, y: 0, width: 1920, height: 1080 };
    const f = L.fitBox(10, 10, 100, 80, g, 80, 0.1);
    ok("a small box clamps to 1:1", f.zoom === 1.0);
}

// ---- the seam: where a shared mouse parks its pointer ----
{
    const lone = [{ x: 0, y: 0, width: 1920, height: 1080 }];
    ok("a lone screen's edges are all seam", L.seamPoint(lone, 3, 3, 6));
    ok("its far edges too", L.seamPoint(lone, 1917, 1077, 6));
    ok("its interior is not", !L.seamPoint(lone, 100, 100, 6));
    ok("and just past the band is not", !L.seamPoint(lone, 7, 7, 6));
    const pair = [{ x: 0, y: 0, width: 1920, height: 1080 }, { x: 1920, y: 0, width: 1920, height: 1080 }];
    ok("an inner edge between two screens is not a seam", !L.seamPoint(pair, 1919, 500, 6));
    ok("nor is the point just across it", !L.seamPoint(pair, 1921, 500, 6));
    ok("the outer edges of two screens are", L.seamPoint(pair, 3, 500, 6));
    ok("and the far outer edge", L.seamPoint(pair, 3837, 500, 6));
    const stacked = [{ x: 0, y: 0, width: 1920, height: 1080 }, { x: 0, y: 1080, width: 1920, height: 1080 }];
    ok("a stacked pair's shared edge is inner", !L.seamPoint(stacked, 500, 1079, 6));
    ok("a stacked pair's outer top is seam", L.seamPoint(stacked, 500, 3, 6));
    ok("and its outer bottom", L.seamPoint(stacked, 500, 2157, 6));
    // An L-shaped layout: the point is near the left screen's top edge, but
    // near the right screen's left edge - the first screen that contains it
    // is the left one, whose top edge has no neighbour across it.
    const el = [{ x: 0, y: 0, width: 1920, height: 1080 }, { x: 1920, y: 300, width: 1000, height: 780 }];
    ok("an L's protruding outer edge is seam", L.seamPoint(el, 3, 500, 6));
    ok("an L's shared stretch is inner", !L.seamPoint(el, 1919, 900, 6));
    ok("off-layout points are not the desk's business", !L.seamPoint(pair, -10, 500, 6));
}

// ---- the threads travel the depth between their windows ----
{
    // A bare thread: one span, and its z is the mix of the endpoints' z,
    // a hair under the midpoint.
    const spans = L.threadSpans(0, 0, 100, 0, 1000, 1004, []);
    ok("an uncovered thread is one span", spans.length === 1);
    ok("its z is the endpoints' mix", near(spans[0].z, 1002 - 0.001));
}
{
    // A window covering the middle of the thread cuts it into three: the
    // stretch inside the window keeps the thread's own depth there, and the
    // cut points are exactly the window's edges.
    const spans = L.threadSpans(0, 0, 100, 0, 1000, 1004, [{ x: 40, y: -5, w: 20, h: 10 }]);
    ok("a covering window cuts the thread into three spans", spans.length === 3);
    ok("the first span ends at the window's near edge", near(spans[0].x2, 40) && near(spans[0].y2, 0));
    ok("the middle span is the stretch inside the window", near(spans[1].x1, 40) && near(spans[1].x2, 60));
    ok("the last span begins at the far edge", near(spans[2].x1, 60) && near(spans[2].x2, 100));
    // The middle span sits at the thread's depth at t=0.5: 1002 - the hair.
    ok("the covered span keeps the thread's own depth", near(spans[1].z, 1002 - 0.001));
    ok("the z runs along the thread", spans[0].z < spans[1].z && spans[1].z < spans[2].z);
}
{
    // The tuck at the attach: a window one step above the endpoint covers
    // the first stretch, and the thread there sits beneath it - the case a
    // window overlapping another, with the thread meeting the lower one
    // under the higher.
    const spans = L.threadSpans(0, 0, 100, 0, 1000, 1002, [{ x: -5, y: -5, w: 30, h: 10 }]);
    ok("the covered stretch sits beneath the covering window", spans[0].z < 1001);
}
{
    // A window that misses the thread changes nothing.
    const spans = L.threadSpans(0, 0, 100, 0, 1000, 1004, [{ x: 10, y: 20, w: 20, h: 10 }]);
    ok("a window off the thread leaves it whole", spans.length === 1);
}
{
    // A window that swallows the whole thread still leaves spans - all of
    // them beneath the window's z when it sits above the thread's depth.
    const spans = L.threadSpans(0, 0, 100, 0, 1000, 1002, [{ x: -10, y: -10, w: 130, h: 20 }]);
    ok("a window covering the whole thread keeps spans to draw", spans.length === 1);
    ok("and the whole thread sits beneath it", spans[0].z < 1001);
}
{
    // The crossing test itself: inside, crossing, past the end, and a miss.
    const inT = L.segRectT(0, 0, 100, 0, 40, -5, 20, 10);
    ok("a crossing segment clips to the rect", inT !== null && near(inT[0], 0.4) && near(inT[1], 0.6));
    ok("a segment wholly inside spans the rect", (function () { const t = L.segRectT(0, 0, 100, 0, -5, -5, 120, 10); return t !== null && near(t[0], 0) && near(t[1], 1); })());
    ok("a segment that stops inside is clipped at 1", (function () { const t = L.segRectT(0, 0, 50, 0, 0, -5, 100, 10); return t !== null && near(t[0], 0) && near(t[1], 1); })());
    ok("a parallel miss is null", L.segRectT(0, 0, 100, 0, 0, 10, 100, 10) === null);
    ok("a side miss is null", L.segRectT(0, 0, 100, 0, 200, 0, 50, 10) === null);
    ok("a reversed segment clips the same stretch", (function () { const t = L.segRectT(100, 0, 0, 0, 40, -5, 20, 10); return t !== null && near(t[0], 0.4) && near(t[1], 0.6); })());
}

{
    // The fidelity ladder: full below the reduced threshold, then one rung
    // per threshold, bare at the top, and a bad reading reads idle.
    ok("an idle reading wears everything", L.qualityFor(0, 60, 80, 95) === 0);
    ok("a middling reading sheds the web's extras", L.qualityFor(60, 60, 80, 95) === 1);
    ok("a busy reading goes minimal", L.qualityFor(80, 60, 80, 95) === 2);
    ok("a pegged machine gets rectangles", L.qualityFor(95, 60, 80, 95) === 3);
    ok("the thresholds are exact at the edge", L.qualityFor(79.9, 60, 80, 95) === 1);
    ok("a missing reading counts as idle", L.qualityFor(undefined, 60, 80, 95) === 0);
    ok("a non-finite reading counts as idle", L.qualityFor(NaN, 60, 80, 95) === 0);
    ok("a zero threshold degrades at once", L.qualityFor(0, 0, 0, 0) === 3);
    ok("and every rung is reachable by thresholds alone", (function () {
        return L.qualityFor(0, 0, 100, 100) === 1 && L.qualityFor(0, 100, 0, 100) === 2 && L.qualityFor(0, 100, 100, 0) === 3;
    })());

    // The tidy pack: reading order (top to bottom, then left to right),
    // left-to-right rows, the gap between items and between rows, and the
    // wrap at the row's width.
    ok("tidy fits one row", (function () {
        const out = L.tidyRows([{ x: 300, y: 200, width: 100, height: 50 }, { x: 100, y: 300, width: 80, height: 40 }], { gap: 16, origin: { x: 0, y: 0 }, maxWidth: 1000 });
        return near(out[0].x, 0) && near(out[0].y, 0) && near(out[1].x, 116) && near(out[1].y, 0);
    })());
    ok("tidy sorts by y then x", (function () {
        const out = L.tidyRows([{ x: 900, y: 10, width: 50, height: 50 }, { x: 0, y: 500, width: 50, height: 50 }, { x: 500, y: 10, width: 50, height: 50 }], { gap: 0, origin: { x: 0, y: 0 }, maxWidth: 1000 });
        return near(out[0].x, 0) && near(out[1].x, 50) && near(out[2].x, 100) && near(out[0].y, 0) && near(out[2].y, 0);
    })());
    ok("tidy wraps at the row width", (function () {
        const out = L.tidyRows([{ x: 0, y: 0, width: 100, height: 20 }, { x: 0, y: 0, width: 60, height: 30 }], { gap: 10, origin: { x: 0, y: 0 }, maxWidth: 120 });
        return near(out[0].x, 0) && near(out[0].y, 0) && near(out[1].x, 0) && near(out[1].y, 30);
    })());
    ok("tidy never wraps the first item of a row", (function () {
        const out = L.tidyRows([{ x: 0, y: 0, width: 200, height: 20 }, { x: 0, y: 0, width: 50, height: 20 }], { gap: 10, origin: { x: 5, y: 5 }, maxWidth: 150 });
        return near(out[0].x, 5) && near(out[0].y, 5) && near(out[1].x, 5) && near(out[1].y, 35);
    })());
    ok("tidy respects the origin and the row gap", (function () {
        const out = L.tidyRows([{ x: 0, y: 0, width: 40, height: 10 }, { x: 0, y: 0, width: 40, height: 10 }, { x: 0, y: 0, width: 40, height: 10 }], { gap: 8, origin: { x: 2, y: 3 }, maxWidth: 90 });
        return near(out[0].x, 2) && near(out[0].y, 3) && near(out[1].x, 50) && near(out[1].y, 3) && near(out[2].x, 2) && near(out[2].y, 21);
    })());
    const g1920 = { x: 0, y: 0, width: 1920, height: 1080 };
    ok("the neighbourhood pan is the smart pan with no neighbours", (function () {
        const d = L.smartPanNeighbourhood({ x: 4000, y: 300, width: 460, height: 420 }, [], g1920, 0, 0, 1, 24);
        return near(d.dx, 2564) && near(d.dy, 0);
    })());
    ok("a neighbour just off the screen pulls the pan over to include it", (function () {
        const d = L.smartPanNeighbourhood({ x: 4000, y: 300, width: 460, height: 420 },
            [{ x: 4500, y: 300, width: 700, height: 360 }], g1920, 0, 0, 1, 24);
        return near(d.dx, 3278) && near(d.dy, 0);
    })());
    ok("an already-visible neighbour keeps the least pan", (function () {
        const d = L.smartPanNeighbourhood({ x: 4000, y: 300, width: 460, height: 420 },
            [{ x: 4000, y: 800, width: 700, height: 360 }], g1920, 0, 0, 1, 24);
        return near(d.dx, 2564) && near(d.dy, 0);
    })());
    ok("two neighbours on the same side: the pan takes the nearest edge that shows both", (function () {
        const d = L.smartPanNeighbourhood({ x: 4000, y: 300, width: 460, height: 420 },
            [{ x: 4500, y: 300, width: 700, height: 360 }, { x: 5300, y: 300, width: 400, height: 300 }], g1920, 0, 0, 1, 24);
        return d.dx > 2580 && d.dx < 4000 && near(d.dy, 0);
    })());
    ok("an oversized focused window keeps the edge alignment", (function () {
        const d = L.smartPanNeighbourhood({ x: 24, y: 0, width: 1920, height: 1080 },
            [{ x: 3000, y: 0, width: 400, height: 300 }], g1920, 0, 0, 1, 24);
        return near(d.dx, 24) && near(d.dy, 0);
    })());
    ok("a window beyond the radius never competes", (function () {
        const d = L.smartPanNeighbourhood({ x: 4000, y: 300, width: 460, height: 420 },
            [{ x: 100, y: 120, width: 480, height: 420 }], g1920, 0, 0, 1, 24);
        return near(d.dx, 2564) && near(d.dy, 0);
    })());
}

// ---- the trail's simplification ----
ok("a straight line collapses to its ends", L.simplifyPath([{ x: 0, y: 0, t: 1 }, { x: 10, y: 0, t: 2 }, { x: 20, y: 0, t: 3 }], 40).length === 2);
const corner = L.simplifyPath([{ x: 0, y: 0, t: 1 }, { x: 100, y: 0, t: 2 }, { x: 100, y: 100, t: 3 }], 40);
ok("a real corner survives", corner.length === 3);
const jitter = L.simplifyPath([{ x: 0, y: 0, t: 1 }, { x: 50, y: 5, t: 2 }, { x: 100, y: 0, t: 3 }], 40);
ok("the jitter on a straight run collapses", jitter.length === 2 && jitter[1].t === 3);
const keepT = L.simplifyPath([{ x: 0, y: 0, t: 1 }, { x: 50, y: 0, t: 2 }, { x: 0, y: 90, t: 3 }], 40);
ok("the timestamps ride the kept points", keepT.length === 3 && keepT[2].t === 3);

console.log("== unit pass " + pass + "  fail " + fail);
process.exit(fail === 0 ? 0 : 1);

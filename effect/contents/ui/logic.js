// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// The canvas's pure logic, shared between the effect's QML and the unit
// tests: no QML types, no state, every function a function of its
// arguments. `node tests/unit/logic.test.js` exercises this file directly,
// which is the fast iteration loop; the nest scenarios then verify the
// wiring.

// The gap that joins two windows into one cluster. A configured ClusterGap
// is the fixed pixel gap; left at 0 the gap is half the pair's own scale -
// the average of the two windows' smaller sides - so a cluster reads the
// same on a laptop and an ultrawide.
function clusterGapFor(a, b, gapCfg) {
    const g0 = Number(gapCfg) || 0;
    if (g0 > 0) return g0;
    const sa = Math.min(a.width, a.height), sb = Math.min(b.width, b.height);
    return Math.max(24, (sa + sb) / 2 * 0.5);
}

// The closest distance between two window rectangles: the true gap a thread
// would have to bridge, whatever the diagonal.
function clusterDist(a, b) {
    const dx = Math.max(0, Math.max(a.x - (b.x + b.width), b.x - (a.x + a.width)));
    const dy = Math.max(0, Math.max(a.y - (b.y + b.height), b.y - (a.y + a.height)));
    return Math.sqrt(dx * dx + dy * dy);
}

// The whole clustering: rects are { x, y, width, height, id } in canvas
// pixels. prevOf maps id -> the previous cluster index (the hysteresis),
// ranks maps id -> the thread rank (the stable order). Returns
// { clusters: [{ cx, cy, n, ids, co }], clusterOf, ranks }.
function recluster(rects, prevOf, ranks, gapCfg) {
    const list = rects;
    const parent = [];
    for (let i = 0; i < list.length; ++i) parent.push(i);
    const edges = [];
    for (let i = 0; i < list.length; ++i) {
        for (let j = i + 1; j < list.length; ++j) {
            const d = clusterDist(list[i], list[j]);
            const gap = clusterGapFor(list[i], list[j], gapCfg);
            const samePrev = prevOf[list[i].id] !== undefined && prevOf[list[i].id] === prevOf[list[j].id];
            if (d <= gap || (samePrev && d <= gap * 1.5)) {
                let a = i, b = j;
                while (parent[a] !== a) { parent[a] = parent[parent[a]]; a = parent[a]; }
                while (parent[b] !== b) { parent[b] = parent[parent[b]]; b = parent[b]; }
                if (a !== b) { parent[a] = b; edges.push({ a: i, b: j, d: d, gap: gap }); }
            }
        }
    }
    const byRoot = {};
    for (let i = 0; i < list.length; ++i) {
        let r = i;
        while (parent[r] !== r) { parent[r] = parent[parent[r]]; r = parent[r]; }
        if (!byRoot[r]) byRoot[r] = [];
        byRoot[r].push(i);
    }
    let maxRank = -1;
    for (const id in ranks) if (ranks[id] > maxRank) maxRank = ranks[id];
    const out = [];
    const of = {};
    for (const r in byRoot) {
        const idxs = byRoot[r];
        let cx = 0, cy = 0;
        const ordered = [];
        for (let k = 0; k < idxs.length; ++k) {
            const e = list[idxs[k]];
            cx += e.x + e.width / 2;
            cy += e.y + e.height / 2;
            if (ranks[e.id] === undefined) ranks[e.id] = ++maxRank;
            ordered.push(e.id);
        }
        ordered.sort(function (p, q) { return ranks[p] - ranks[q]; });
        let co = 1;
        for (let k = 0; k < edges.length; ++k) {
            let rr = edges[k].a;
            while (parent[rr] !== rr) { parent[rr] = parent[parent[rr]]; rr = parent[rr]; }
            if (rr !== +r) continue;
            const ratio = edges[k].d / edges[k].gap;
            co = Math.min(co, Math.max(0, 1 - (ratio - 1) / 0.5));
        }
        const c = { cx: cx / idxs.length, cy: cy / idxs.length, n: idxs.length, ids: ordered, co: co };
        for (let k = 0; k < idxs.length; ++k) of[list[idxs[k]].id] = out.length;
        out.push(c);
    }
    return { clusters: out, clusterOf: of, ranks: ranks };
}

// One step of the float's physics. f is { x, y, vx, vy, wasInX, wasInY }
// (screen px), (tx, ty) the window's screen spot, (cx, cy) the clamped
// spot, (bl, br, bt, bb) the screen bounds the picture is kept inside,
// cameraVX/VY the camera's own screen velocity, dragging whether the hand
// owns the window, dt the step in seconds. Mutates and returns f.
function floatStep(f, tx, ty, cx, cy, bl, br, bt, bb, cameraVX, cameraVY, dragging, dt) {
    if (dragging) {
        f.x = tx; f.y = ty; f.vx = 0; f.vy = 0;
        f.wasInX = cx === tx; f.wasInY = cy === ty;
        return f;
    }
    if (cx === tx && cy === ty) {
        f.vx = cameraVX; f.vy = cameraVY;
        f.x = tx; f.y = ty;
        f.wasInX = true; f.wasInY = true;
        return f;
    }
    if (f.wasInX && tx !== cx) {
        if (tx < cx) { f.x = bl; f.vx = Math.abs(f.vx) * 0.45; }
        else { f.x = br; f.vx = -Math.abs(f.vx) * 0.45; }
        f.wasInX = false;
    }
    if (f.wasInY && ty !== cy) {
        if (ty < cy) { f.y = bt; f.vy = Math.abs(f.vy) * 0.45; }
        else { f.y = bb; f.vy = -Math.abs(f.vy) * 0.45; }
        f.wasInY = false;
    }
    const w0 = 7, c0 = 14;
    f.vx += (-w0 * w0 * (f.x - cx) - c0 * f.vx) * dt;
    f.vy += (-w0 * w0 * (f.y - cy) - c0 * f.vy) * dt;
    f.x += f.vx * dt;
    f.y += f.vy * dt;
    return f;
}

// The screen offsets a window's top-left can take, for a window w x h on a
// screen g with a margin: the range that keeps it wholly inside, and the
// centred offset. fits is false when the window is too large either way.
function fitRange(w, h, g, margin) {
    const x0 = margin, x1 = g.width - w - margin;
    const y0 = margin, y1 = g.height - h - margin;
    return { x0: x0, x1: x1, y0: y0, y1: y1,
             cx: Math.round((g.width - w) / 2), cy: Math.round((g.height - h) / 2),
             fits: x1 >= x0 && y1 >= y0 };
}

// The least camera pan (canvas px) that keeps `rect` wholly inside the
// screen `g` at the view (viewX, viewY) and zoom, with a margin. A rect
// larger than the screen is left- and top-aligned, margin-free - the
// window fills the screen, so a margin would push it visibly off-centre.
function smartPan(rect, g, viewX, viewY, zoom, pad) {
    const padC = (pad === undefined ? 24 : pad) / zoom;
    const sl = viewX + g.x / zoom, st = viewY + g.y / zoom;
    const sw = g.width / zoom, sh = g.height / zoom;
    let dx = 0, dy = 0;
    if (rect.width <= sw - 2 * padC) {
        if (rect.x < sl + padC) dx = rect.x - (sl + padC);
        else if (rect.x + rect.width > sl + sw - padC) dx = rect.x + rect.width - (sl + sw - padC);
    } else if (rect.x !== sl) dx = rect.x - sl;
    if (rect.height <= sh - 2 * padC) {
        if (rect.y < st + padC) dy = rect.y - (st + padC);
        else if (rect.y + rect.height > st + sh - padC) dy = rect.y + rect.height - (st + sh - padC);
    } else if (rect.y !== st) dy = rect.y - st;
    return { dx: dx, dy: dy };
}

// The canvas point under a global screen position: the inverse of the
// plane transform. The screen's own origin lives inside the global
// position, so one formula serves every output - a pointer on a second
// monitor maps the same way, no per-screen term.
function canvasOf(gx, gy, viewX, viewY, zoom) {
    return { x: viewX + gx / zoom, y: viewY + gy / zoom };
}

// The view that zooms to z with the canvas point `c` under the anchor
// (a global screen position) staying put: setZoom's pure half. The view
// is the canvas coordinate of the layout origin at that zoom.
function zoomView(c, anchorX, anchorY, z) {
    return { x: c.x - anchorX / z, y: c.y - anchorY / z };
}

// The zoom that fits the box (l, t, r, b) into the screen g with a pad
// margin, and the view that centres the box: zoomExtents' pure half.
function fitBox(l, t, r, b, g, pad, zoomMin) {
    const z = Math.max(zoomMin, Math.min(1.0, Math.min((g.width - 2 * pad) / (r - l), (g.height - 2 * pad) / (b - t))));
    const cx = (l + r) / 2 - (g.x + g.width / 2) / z;
    const cy = (t + b) / 2 - (g.y + g.height / 2) / z;
    return { zoom: z, viewX: cx, viewY: cy };
}

// The seam: the outer few pixels of the desk. A tool that shares the mouse
// with another machine (deskflow, synergy) parks the pointer on the screen
// border it hands the mouse over across, and there it sits - a pointer the
// desk itself put there, not the hand. A hover that reads the parked pointer
// would glow and pan to whatever window the seam touches. seamPoint says
// whether a point lies in that band: within `margin` of a screen's edge, but
// only an edge with no other screen across it - the border between two local
// screens is a place a living hand rests, the desk's outer border is where a
// shared mouse parks.
function seamPoint(screens, x, y, margin) {
    for (let i = 0; i < screens.length; ++i) {
        const s = screens[i];
        if (x < s.x || x >= s.x + s.width || y < s.y || y >= s.y + s.height) continue;
        if (x - s.x < margin && !seamNeighbour(screens, s, "x", s.x)) return true;
        if (s.x + s.width - x < margin && !seamNeighbour(screens, s, "x", s.x + s.width)) return true;
        if (y - s.y < margin && !seamNeighbour(screens, s, "y", s.y)) return true;
        if (s.y + s.height - y < margin && !seamNeighbour(screens, s, "y", s.y + s.height)) return true;
        return false;
    }
    return false;
}

// Does another screen's edge run flush along this screen's edge at `at`?
// Flush along the whole span the two share: an edge is inner only where a
// neighbour actually abuts it, so an L-shaped layout keeps its outer corners.
function seamNeighbour(screens, s, axis, at) {
    for (let i = 0; i < screens.length; ++i) {
        const r = screens[i];
        if (r === s) continue;
        if (axis === "x") {
            if ((at === r.x || at === r.x + r.width) && r.y < s.y + s.height && s.y < r.y + r.height) return true;
        } else if ((at === r.y || at === r.y + r.height) && r.x < s.x + s.width && s.x < r.x + r.width) {
            return true;
        }
    }
    return false;
}

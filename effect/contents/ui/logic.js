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

// The neighbourhood-aware smart pan: the focused rect wholly inside the
// padded screen (smartPan's own rule), then, among the pans that keep it
// there, the one that brings the most neighbours at least partially on
// screen, then the least displacement among the ties. The candidates are
// the midpoints between the neighbours' edge breakpoints: a neighbour's
// visibility only changes at its edges, so a midpoint sits safely inside
// its interval and the sweep cannot miss a jump.
function smartPanNeighbourhood(rect, others, g, viewX, viewY, zoom, pad) {
    const padC = (pad === undefined ? 24 : pad) / zoom;
    const sl = viewX + g.x / zoom, st = viewY + g.y / zoom;
    const sw = g.width / zoom, sh = g.height / zoom;
    let xMin = -Infinity, xMax = Infinity;
    let yMin = -Infinity, yMax = Infinity;
    if (rect.width <= sw - 2 * padC) {
        xMax = rect.x - (sl + padC);
        xMin = rect.x + rect.width - (sl + sw - padC);
    } else { xMin = rect.x - sl; xMax = xMin; }
    if (rect.height <= sh - 2 * padC) {
        yMax = rect.y - (st + padC);
        yMin = rect.y + rect.height - (st + sh - padC);
    } else { yMin = rect.y - st; yMax = yMin; }
    // The base: the least displacement (smartPan's own pick).
    let dx = Math.max(xMin, Math.min(0, xMax));
    let dy = Math.max(yMin, Math.min(0, yMax));
    if (dx === 0 && dy === 0) return { dx: dx, dy: dy }; // already in view: the neighbourhood stays put, a rest under the pointer is sacred
    if (!others || others.length === 0) return { dx: dx, dy: dy };
    // The neighbourhood is local: only the windows within a screen's own
    // scale of the focused one may pull the camera. A window across the
    // plane never competes - the pan stays around the window it lands on.
    const radius = Math.max(sw, sh);
    const cx = rect.x + rect.width / 2, cy = rect.y + rect.height / 2;
    const near = [];
    for (let i = 0; i < others.length; ++i) {
        const w = others[i];
        const dxc = w.x + w.width / 2 - cx, dyc = w.y + w.height / 2 - cy;
        if (Math.hypot(dxc, dyc) <= radius) near.push(w);
    }
    others = near;
    if (others.length === 0) return { dx: dx, dy: dy };
    // Fully inside the screen counts; an edge just touching does not.
    // (The old rule counted a window whose corner grazed the screen,
    // which is how the camera kept parking the cluster just outside.)
    function xIn(w, d) { return d > w.x - sl && d < w.x + w.width - sl - sw; }
    function yIn(w, d) { return d > w.y - st && d < w.y + w.height - st - sh; }
    function count(dxx, dyy) {
        let n = 0;
        for (let i = 0; i < others.length; ++i) {
            if (xIn(others[i], dxx) && yIn(others[i], dyy)) n++;
        }
        return n;
    }
    function sweep(cur, fixed, lo, hi, xAxis) {
        const pts = [lo, hi];
        for (let i = 0; i < others.length; ++i) {
            const w = others[i];
            const a = xAxis ? w.x - sl - sw : w.y - st - sh;
            const b = xAxis ? w.x + w.width - sl : w.y + w.height - st;
            if (a > lo && a < hi) pts.push(a);
            if (b > lo && b < hi) pts.push(b);
        }
        pts.sort(function (p, q) { return p - q; });
        // The smart placement: a pan that keeps strictly more of the
        // neighbourhood on screen wins, and among those the LEAST
        // displacement - the camera moves as little as it can, so the
        // most of the other windows stay in view. Nothing strictly
        // better: the base stands (the least move, the rest under the
        // pointer sacred).
        const baseN = xAxis ? count(cur, fixed) : count(fixed, cur);
        let best = cur;
        let bestN = baseN;
        let bestD = Math.abs(cur);
        for (let i = 0; i + 1 < pts.length; ++i) {
            const mid = (pts[i] + pts[i + 1]) / 2;
            const n = xAxis ? count(mid, fixed) : count(fixed, mid);
            const d = Math.abs(mid);
            if (n > bestN || (n === bestN && d < bestD)) { bestN = n; bestD = d; best = mid; }
        }
        return bestN > baseN ? best : cur;
    }
    for (let pass = 0; pass < 2; ++pass) {
        dx = sweep(dx, dy, xMin, xMax, true);
        dy = sweep(dy, dx, yMin, yMax, false);
    }
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

// The stretch of a segment that lies inside a rectangle, as the fraction
// pair [t0, t1] of the segment, or null when they never meet. Liang-Barsky:
// four half-planes, each clips a parameter range, and the intersection of
// the ranges is the visible stretch.
function segRectT(x1, y1, x2, y2, rx, ry, rw, rh) {
    const dx = x2 - x1, dy = y2 - y1;
    let t0 = 0, t1 = 1;
    const halfPlanes = [
        [-dx, x1 - rx],          // left of the rect
        [dx, rx + rw - x1],      // right
        [-dy, y1 - ry],          // top
        [dy, ry + rh - y1]       // bottom
    ];
    for (let i = 0; i < 4; ++i) {
        const p = halfPlanes[i][0], q = halfPlanes[i][1];
        if (p === 0) {
            if (q < 0) return null;   // parallel and outside
        } else {
            const t = q / p;
            if (p < 0) {
                if (t > t1) return null;
                if (t > t0) t0 = t;
            } else {
                if (t < t0) return null;
                if (t < t1) t1 = t;
            }
        }
    }
    if (t0 >= t1) return null;
    return [t0, t1];
}

// A cluster thread is a line THROUGH the stack, not a flat sticker: at any
// point along it its z is the linear mix of its two windows' z, so a window
// occludes exactly the stretch where the window's z is above the thread's
// there. The thread is cut at every window crossing and each stretch is
// returned with its own z, so the view's sibling ordering does the weaving
// - over the lower, under the higher, and ducking under any window that
// covers a middle stretch. rects are { x, y, w, h } in the endpoints'
// coordinates; zA and zB are the endpoints' z.
function threadSpans(x1, y1, x2, y2, zA, zB, rects) {
    const ts = [0, 1];
    for (let i = 0; i < rects.length; ++i) {
        const r = rects[i];
        const t = segRectT(x1, y1, x2, y2, r.x, r.y, r.w, r.h);
        if (t) ts.push(t[0], t[1]);
    }
    ts.sort(function (a, b) { return a - b; });
    const out = [];
    for (let i = 0; i < ts.length - 1; ++i) {
        const t0 = ts[i], t1 = ts[i + 1];
        if (t1 - t0 < 1e-6) continue;
        const tm = (t0 + t1) / 2;
        // The hair below the mix: an exact tie with a window's z would
        // leave the order to the delegates' creation order, so the thread
        // always sits a hair under the window whose depth it shares.
        out.push({
            x1: x1 + (x2 - x1) * t0, y1: y1 + (y2 - y1) * t0,
            x2: x1 + (x2 - x1) * t1, y2: y1 + (y2 - y1) * t1,
            z: zA + (zB - zA) * tm - 0.001
        });
    }
    return out;
}

// The fidelity ladder: how much eye candy the canvas may run at a given
// system load. 0 is everything; 3 is the bare minimum (plain rectangles,
// no web, no shadows). A non-finite or missing reading counts as idle, so a
// broken probe can never strip a quiet desktop of its looks.
function qualityFor(busy, reduced, minimal, bare) {
    const b = Number.isFinite(Number(busy)) ? Number(busy) : 0;
    if (b >= bare) return 3;
    if (b >= minimal) return 2;
    if (b >= reduced) return 1;
    return 0;
}

// The tidy pack: windows (sorted top to bottom, then left to right) laid
// into left-to-right rows from the origin, wrapping when the next item
// would run past the row's width. The gap applies between items and
// between rows. Returns an array of { x, y } aligned with the sorted
// order; the caller owns the mapping back to its entries.
function tidyRows(list, opts) {
    const gap = Number.isFinite(Number(opts.gap)) ? Number(opts.gap) : 0;
    const ox = Number.isFinite(Number(opts.origin.x)) ? Number(opts.origin.x) : 0;
    const oy = Number.isFinite(Number(opts.origin.y)) ? Number(opts.origin.y) : 0;
    const maxW = Number.isFinite(Number(opts.maxWidth)) ? Number(opts.maxWidth) : Infinity;
    const items = list.slice().sort(function (a, b) {
        return (a.y - b.y) || (a.x - b.x);
    });
    const out = [];
    let x = ox, y = oy, rowBottom = 0, first = true;
    for (let i = 0; i < items.length; ++i) {
        const it = items[i];
        if (!first && x + it.width > ox + maxW) {
            x = ox;
            y = rowBottom + gap;
            rowBottom = 0;
        }
        out.push({ x: x, y: y });
        x += it.width + gap;
        rowBottom = Math.max(rowBottom, y + it.height);
        first = false;
    }
    return out;
}

// The trail's anti-scribble: the Ramer-Douglas-Peucker simplification keeps
// only the points that change the path's direction (beyond tol canvas
// pixels), so the camera's jitter collapses into a clean ribbon through the
// real turns. The {x,y,t} points keep their timestamps for the age fade.
function simplifyPath(pts, tol) {
    if (!pts || pts.length <= 2) return pts || [];
    const keep = new Array(pts.length).fill(false);
    keep[0] = keep[pts.length - 1] = true;
    const stack = [[0, pts.length - 1]];
    while (stack.length) {
        const pair = stack.pop();
        const a = pair[0], b = pair[1];
        const dx = pts[b].x - pts[a].x, dy = pts[b].y - pts[a].y;
        const len = Math.hypot(dx, dy) || 1;
        let maxD = -1, maxI = -1;
        for (let i = a + 1; i < b; i++) {
            const d = Math.abs(dy * (pts[i].x - pts[a].x) - dx * (pts[i].y - pts[a].y)) / len;
            if (d > maxD) { maxD = d; maxI = i; }
        }
        if (maxD > tol) {
            keep[maxI] = true;
            stack.push([a, maxI]);
            stack.push([maxI, b]);
        }
    }
    return pts.filter(function (_, i) { return keep[i]; });
}

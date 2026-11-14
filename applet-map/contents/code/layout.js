// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// The map widget's pure layout: no QML types, no state, every function a
// function of its arguments, so `node tests/unit/maplayout.test.js` checks it
// directly. main.qml and MapView.qml are the wiring.
//
// The plane is vast and mostly empty: clusters sit thousands of pixels apart,
// and a map drawn to scale shrinks every one of them to a speck. The map keeps
// what matters to scale (the windows and the screens) and squeezes the empty
// ground between them. Along each axis the spans the windows and the screens
// cover keep their length; an empty gap no longer than the cap keeps its length
// too, and a longer one is drawn cap * (1 + 0.6 ln(gap / cap)) long. A far
// cluster so comes close, still farther than a near one, and the order of things
// along each axis never changes. The mapping is piecewise linear and strictly
// increasing, so it has an exact inverse: a click or a drop on the map is a
// point on the plane.

// The covered runs: the spans ([a, b] pairs) merged where they overlap or touch, in order.
function mergeSpans(spans) {
    const s = [];
    for (let i = 0; i < spans.length; ++i) {
        const a = Number(spans[i][0]), b = Number(spans[i][1]);
        if (Number.isFinite(a) && Number.isFinite(b)) s.push([Math.min(a, b), Math.max(a, b)]);
    }
    s.sort(function (p, q) { return p[0] - q[0]; });
    const out = [];
    for (let i = 0; i < s.length; ++i) {
        const last = out[out.length - 1];
        if (last && s[i][0] <= last[1]) last[1] = Math.max(last[1], s[i][1]);
        else out.push([s[i][0], s[i][1]]);
    }
    return out;
}

// How long an empty gap is drawn: itself up to the cap, then the logarithm's slow growth (ten
// times the gap is about 1.4 caps more).
function gapLength(gap, cap) {
    if (!(gap > cap) || !(cap > 0)) return gap;
    return cap * (1 + 0.6 * Math.log(gap / cap));
}

// One axis's mapping. spans: what keeps its length; cap: the longest gap drawn to scale
// (Infinity draws everything to scale). Returns { to(v), from(u), length, folds }: to maps
// a plane coordinate onto the map axis (0 at the first span's start), from is its inverse,
// length the drawn extent, folds the drawn middles of the squeezed gaps.
function axisMap(spans, cap) {
    const runs = mergeSpans(spans);
    const P = [], U = [], folds = [];
    let u = 0;
    for (let i = 0; i < runs.length; ++i) {
        P.push(runs[i][0]); U.push(u);
        u += runs[i][1] - runs[i][0];
        P.push(runs[i][1]); U.push(u);
        if (i + 1 < runs.length) {
            const gap = runs[i + 1][0] - runs[i][1];
            const drawn = gapLength(gap, cap);
            if (drawn < gap) folds.push(u + drawn / 2);
            u += drawn;
        }
    }
    if (!P.length) { P.push(0, 1); U.push(0, 1); u = 1; }
    const along = function (from, onto, v) {
        const n = from.length;
        if (v <= from[0]) return onto[0] + (v - from[0]);
        if (v >= from[n - 1]) return onto[n - 1] + (v - from[n - 1]);
        let lo = 0, hi = n - 1;
        while (hi - lo > 1) {
            const mid = (lo + hi) >> 1;
            if (from[mid] <= v) lo = mid; else hi = mid;
        }
        const span = from[hi] - from[lo];
        return span > 0 ? onto[lo] + (v - from[lo]) * (onto[hi] - onto[lo]) / span : onto[lo];
    };
    return {
        to: function (v) { return along(P, U, v); },
        from: function (m) { return along(U, P, m); },
        length: Math.max(1, u),
        folds: folds
    };
}

// The longest gap drawn to scale: a third of a typical window, about the room the canvas leaves
// between two windows of one cluster, so a cluster keeps its shape and the empty plane between
// clusters is squeezed.
function capFor(sizes) {
    const s = sizes.filter(function (v) { return v > 0; }).sort(function (a, b) { return a - b; });
    if (!s.length) return 400;
    const median = s[s.length >> 1];
    return Math.max(120, Math.min(700, median / 3));
}

// The map's two axes for a plane reading: what keeps its length is every window on the plane and
// every screen's camera. A minimized window is not on the plane (the map shows it in a tray), so
// it takes no room. toScale draws all of it to scale. Returns { x, y } axis maps.
function planeLayout(plane, toScale) {
    const xs = [], ys = [], ws = [], hs = [];
    const wins = plane && plane.windows ? plane.windows : [];
    for (let i = 0; i < wins.length; ++i) {
        const w = wins[i];
        if (w.min) continue;
        xs.push([w.x, w.x + w.w]);
        ys.push([w.y, w.y + w.h]);
        ws.push(w.w);
        hs.push(w.h);
    }
    const cams = plane && plane.camera ? plane.camera : [];
    for (let i = 0; i < cams.length; ++i) {
        xs.push([cams[i][0], cams[i][0] + cams[i][2]]);
        ys.push([cams[i][1], cams[i][1] + cams[i][3]]);
    }
    return {
        x: axisMap(xs, toScale ? Infinity : capFor(ws)),
        y: axisMap(ys, toScale ? Infinity : capFor(hs))
    };
}

// The window the keyboard steps to from rect `from` towards dir ("left", "right", "up",
// "down"): the nearest one whose centre lies that way, the straight line favoured over the
// slant. rects: [{ id, x, y, w, h }]. Returns the id, or "" when nothing lies that way.
function stepTowards(from, rects, dir) {
    const fx = from.x + from.w / 2, fy = from.y + from.h / 2;
    let best = "", bestScore = Infinity;
    for (let i = 0; i < rects.length; ++i) {
        const r = rects[i];
        if (r.id === from.id) continue;
        const dx = r.x + r.w / 2 - fx, dy = r.y + r.h / 2 - fy;
        const along = dir === "left" ? -dx : dir === "right" ? dx : dir === "up" ? -dy : dy;
        const across = dir === "left" || dir === "right" ? Math.abs(dy) : Math.abs(dx);
        if (along <= 0) continue;
        const score = along + across * 2;
        if (score < bestScore) { bestScore = score; best = r.id; }
    }
    return best;
}

// The search: every word of the query is in the window's caption or its app's name, in any case.
function matches(query, caption, app) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) { return w.length; });
    const hay = (String(caption || "") + " " + String(app || "")).toLowerCase();
    for (let i = 0; i < words.length; ++i) if (hay.indexOf(words[i]) < 0) return false;
    return true;
}

// The window ids as KWin and Plasma's task manager each write them ({…} or bare, any case) made
// one, so the two can be matched.
function normId(id) {
    return String(id || "").replace(/[{}]/g, "").toLowerCase();
}

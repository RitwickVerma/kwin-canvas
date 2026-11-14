#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Unit tests for the map widget's pure layout (applet-map/contents/code/layout.js):
// the squeezed gaps, their inverse, the keyboard step and the search. Run with
// `make unit`; a failing assertion exits non-zero with the case name.
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "..", "applet-map", "contents", "code", "layout.js"), "utf8");
const names = Array.from(src.matchAll(/^function ([A-Za-z0-9_]+)\(/gm), (m) => m[1]);
const M = new Function(src + "\nreturn { " + names.join(", ") + " };")();

let pass = 0, fail = 0;
function ok(name, cond) {
    if (cond) { pass++; }
    else { fail++; console.error("FAIL " + name); }
}
function near(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps); }

// ---- the covered runs ----
{
    const r = M.mergeSpans([[500, 900], [0, 100], [80, 200], [200, 300], [NaN, 4]]);
    ok("mergeSpans: overlapping and touching spans merge, in order", JSON.stringify(r) === "[[0,300],[500,900]]");
    ok("mergeSpans: a reversed span is turned round", JSON.stringify(M.mergeSpans([[10, 0]])) === "[[0,10]]");
}

// ---- the squeezed gap ----
{
    ok("gapLength: a gap up to the cap keeps its length", M.gapLength(300, 600) === 300);
    ok("gapLength: a longer gap is drawn shorter", M.gapLength(60000, 600) < 60000 && M.gapLength(60000, 600) > 600);
    ok("gapLength: a farther gap is still drawn longer", M.gapLength(60000, 600) > M.gapLength(6000, 600));
    ok("gapLength: an infinite cap draws everything to scale", M.gapLength(60000, Infinity) === 60000);
}

// ---- one axis ----
{
    // Two clusters 50 000 px apart, each 2000 wide.
    const a = M.axisMap([[0, 2000], [52000, 54000]], 600);
    ok("axisMap: the first span starts the axis", a.to(0) === 0);
    ok("axisMap: a span keeps its length", near(a.to(2000) - a.to(0), 2000) && near(a.to(54000) - a.to(52000), 2000));
    ok("axisMap: the empty gap is squeezed", a.to(52000) - a.to(2000) < 5000);
    ok("axisMap: the drawn length adds up", near(a.length, 4000 + M.gapLength(50000, 600)));
    ok("axisMap: one fold, in the gap's middle", a.folds.length === 1 && near(a.folds[0], 2000 + M.gapLength(50000, 600) / 2));
    let up = true;
    for (let v = -500; v < 56000; v += 250) if (!(a.to(v + 250) > a.to(v))) up = false;
    ok("axisMap: the mapping always increases", up);
    let back = true;
    for (let v = -500; v < 56000; v += 777) if (!near(a.from(a.to(v)), v, 1e-6)) back = false;
    ok("axisMap: from undoes to, inside, between and outside the spans", back);
    const flat = M.axisMap([[0, 2000], [52000, 54000]], Infinity);
    ok("axisMap: to scale nothing is squeezed and nothing folds", near(flat.length, 54000) && flat.folds.length === 0);
    const empty = M.axisMap([], 600);
    ok("axisMap: nothing to draw is a unit axis", empty.length === 1 && empty.to(0) === 0 && empty.from(1) === 1);
    const point = M.axisMap([[100, 100], [100, 100]], 600);
    ok("axisMap: a zero-length span maps without dividing by zero", Number.isFinite(point.to(100)) && Number.isFinite(point.from(0)));
}

// ---- the cap ----
{
    ok("capFor: a third of the median window", near(M.capFor([900, 1200, 1800]), 400));
    ok("capFor: never below a small window's room", M.capFor([100, 120]) === 120);
    ok("capFor: never above a big screen's", M.capFor([4000, 5000]) === 700);
    ok("capFor: no windows, a sane default", M.capFor([]) === 400);
}

// ---- the plane's two axes ----
{
    const plane = {
        camera: [[0, 0, 1920, 1080]],
        windows: [
            { x: 100, y: 100, w: 800, h: 600 },
            { x: 80000, y: 100, w: 800, h: 600 },
            { x: 100, y: 40000, w: 800, h: 600, min: 1 }
        ]
    };
    const l = M.planeLayout(plane, false);
    ok("planeLayout: the far cluster comes close", l.x.to(80000) < 6000);
    ok("planeLayout: a minimized window takes no room", l.y.length < 2000);
    const scale = M.planeLayout(plane, true);
    ok("planeLayout: to scale, the plane's own distances", near(scale.x.to(80000) - scale.x.to(100), 79900));
    ok("planeLayout: no reading, a unit map", M.planeLayout(null, false).x.length === 1);
}

// ---- the keyboard's step ----
{
    const from = { id: "a", x: 0, y: 0, w: 100, h: 100 };
    const rects = [from,
        { id: "right", x: 300, y: 0, w: 100, h: 100 },
        { id: "slant", x: 200, y: 300, w: 100, h: 100 },
        { id: "below", x: 0, y: 400, w: 100, h: 100 }];
    ok("stepTowards: straight right", M.stepTowards(from, rects, "right") === "right");
    ok("stepTowards: down favours the straight line over the slant", M.stepTowards(from, rects, "down") === "below");
    ok("stepTowards: nothing lies left", M.stepTowards(from, rects, "left") === "");
    ok("stepTowards: nothing lies up", M.stepTowards(from, rects, "up") === "");
}

// ---- the search and the ids ----
{
    ok("matches: every word, in any case, caption or app", M.matches("konsole FISH", "~ : fish — Konsole", "org.kde.konsole"));
    ok("matches: a word in neither is no match", !M.matches("brave", "~ : fish — Konsole", "konsole"));
    ok("matches: an empty query matches all", M.matches("  ", "x", ""));
    ok("normId: braces and case go", M.normId("{AB-cd}") === "ab-cd" && M.normId("ab-cd") === "ab-cd");
}

// ---- the census: every function of layout.js is called by a test above ----
{
    const self = fs.readFileSync(__filename, "utf8");
    for (const n of names) ok("layout.js: " + n + " has a unit test that calls it", self.indexOf("M." + n + "(") >= 0);
}

console.log("== map layout pass " + pass + "  fail " + fail);
process.exit(fail === 0 ? 0 : 1);

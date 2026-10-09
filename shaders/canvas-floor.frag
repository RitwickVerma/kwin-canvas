// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The canvas floor: the plane at rest, alive. The ground is the
// canvas's own - the background and the multi-octave grid, scrolling
// with the saved view - and the canvas's remembered state lives on it:
// the rooms breathe where the clusters sit, the day-trail runs through
// it as a ribbon of flowing light, the pointer's own light follows the
// hand and lingers, and the real windows cast their faint glow where
// they stand. Layered slow motion everywhere - the drift, the pulse,
// the march - so the floor is never a picture, always a place.
//
// The uniforms below are fed from the kwin-canvas passthrough plugin's
// state file (kwin-canvas-state.txt) by the engine's fork; the engine's
// own iMouse, iWindowCount and iWindowRects cover the hand and the
// windows. See docs/shader-integration.md for the channel and the fork
// contract. Absent the fork the canvas uniforms read zero and the floor
// is simply the calm grid on the background.
//
// @channels none

uniform int iCanvasClusterCount;   // up to 16, the plane's clusters
uniform vec4 iCanvasClusters[16];  // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;     // up to 64, the day-trail's samples
uniform vec2 iCanvasTrail[64];     // the screen path points, oldest first
uniform float iCanvasGridBase;     // the minor grid spacing, plane pixels
uniform float iCanvasGridFactor;   // each octave is this many times coarser
uniform float iCanvasGridOctaves;  // the octaves drawn
uniform vec3 iCanvasGridColor;     // the line colour, 0..1
uniform vec3 iCanvasBackground;    // the plane's ground, 0..1
uniform vec2 iCanvasView;          // the plane coordinate of the screen's top-left

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i), f),
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(7.1, 3.7);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    // The plane coordinate under this pixel: the screen is the plane
    // minus the view, so the plane is the screen plus the view.
    vec2 plane = fragCoord + iCanvasView;
    float t = iTime;

    // The ground: the canvas's own background, slowly living. A gentle
    // fbm drift warps the floor's light, so the dark never sits still.
    float drift = fbm(plane * 0.0015 + vec2(t * 0.02, -t * 0.015)) * 0.14;
    float breathe = 0.97 + 0.03 * sin(t * 0.4);
    vec3 col = mix(iCanvasBackground * 0.5, iCanvasBackground * 1.2, uv.y);
    col += vec3(0.05, 0.07, 0.11) * drift;
    col *= breathe;

    // The grid: the plane's own lines, scrolling with the view. Each
    // octave breathes a little, so the grid feels alive, not printed.
    float spacing = max(iCanvasGridBase, 1.0);
    if (iCanvasGridBase > 4.0) {
        for (int o = 0; o < 4; o++) {
            if (float(o) >= iCanvasGridOctaves) break;
            vec2 m = mod(plane, spacing);
            vec2 d = min(m, spacing - m);
            float pulse = 0.9 + 0.1 * sin(t * 0.5 + float(o) * 1.7);
            float g = 1.0 - smoothstep(0.0, 1.3 + 0.5 * float(o), min(d.x, d.y));
            float w = 0.10 + 0.22 * float(o);
            col = mix(col, iCanvasGridColor, g * w * pulse);
            spacing *= max(iCanvasGridFactor, 2.0);
        }
    }

    // The rooms: each cluster breathes where it sits - the cool halo and
    // the warm heart trade places on the room's own beat.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec2 c = iCanvasClusters[i].xy;
        float n = max(iCanvasClusters[i].z, 1.0);
        float beat = sin(t * 0.7 + float(i) * 1.618) * 0.5 + 0.5;
        float r = (60.0 + 22.0 * n) * (0.85 + 0.3 * beat);
        float dist = length(fragCoord - c);
        float bloom = exp(-(dist * dist) / (2.0 * r * r));
        float core = exp(-(dist * dist) / (2.0 * r * r * 0.10));
        col += vec3(0.30, 0.50, 0.95) * bloom * (0.30 + 0.25 * beat);
        col += vec3(1.0, 0.93, 0.82) * core * (0.22 + 0.18 * beat);
    }

    // The trail: the day's path, with light flowing along it - a pulse
    // marches the whole ribbon, segment by segment.
    for (int i = 0; i < iCanvasTrailCount - 1 && i < 63; i++) {
        vec2 a = iCanvasTrail[i];
        vec2 b = iCanvasTrail[i + 1];
        vec2 pa = fragCoord - a;
        vec2 ba = b - a;
        float seg = length(ba);
        float h = clamp(dot(pa, ba) / max(seg * seg, 1.0), 0.0, 1.0);
        float d = length(pa - ba * h);
        float flow = 0.55 + 0.45 * sin(t * 1.3 - float(i) * 0.35 + h * 3.0);
        float ribbon = exp(-d * d / (2.0 * 8.0 * 8.0));
        col += iCanvasGridColor * 1.6 * ribbon * flow * 0.22;
    }

    // The pointer: the hand's light follows the mouse and lingers.
    vec2 m = iMouse.xy;
    if (m.x > 0.5 || m.y > 0.5) {
        float md = length(fragCoord - m);
        col += vec3(0.9, 0.85, 0.7) * exp(-md * md / (2.0 * 110.0 * 110.0)) * 0.10;
        col += vec3(1.0, 0.98, 0.9) * exp(-md * md / (2.0 * 26.0 * 26.0)) * 0.05;
    }

    // The windows: the real windows cast their faint light on the plane.
    for (int i = 0; i < iWindowCount && i < 16; i++) {
        vec4 w = iWindowRects[i];
        vec2 c = w.xy + w.zw * 0.5;
        float md = length(fragCoord - c);
        float rr = max(w.z, w.w) * 0.75;
        col += vec3(0.45, 0.6, 0.95) * exp(-md * md / (2.0 * rr * rr)) * 0.045;
    }

    fragColor = vec4(col, 1.0);
}

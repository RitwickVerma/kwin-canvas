// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// A night sea. Everything in it glows with one light: the bioluminescence.
//
// The whole image answers one question - what glows in the dark water.
// The water itself is a near-black blue-green, calm, with the faintest
// teal of the night air at the horizon. Every light in it is the same
// cold living glow:
//
//   - the rooms are the shoals: where a cluster of the plane sits, the
//     plankton have gathered, a wide soft bloom under the surface that
//     breathes on the room's own slow beat;
//   - the windows are the lanterns: the small bright sparks of the boats
//     afloat on the dark, each spilling its light down the water in a
//     fading streak;
//   - the day-trail is the wake: a single luminous ribbon where the
//     passage stirred the plankton, bright at the head and fading along
//     the path it took;
//   - the pointer is the one thing that falls in: its ripple spreads and
//     the plankton it disturbs light up around it;
//   - and everywhere, a few scattered sparks drift and twinkle - the
//     plankton doing what plankton do.
//
// The state arrives in the canvas's logical top-down coordinates; the
// shader lives in the engine's physical bottom-up pixels. The cs factor
// scales the one into the other, and every y flips on entry - the two
// fixes that keep each glow where its window really is.
//
// For the kde-shader-wallpaper engine (docs/shader-integration.md).
// The iCanvas* uniforms are declared here - the engine's fork uploads
// them; without the fork they read zero and the sea is simply dark.

// @channels none

uniform int iCanvasClusterCount;
uniform vec4 iCanvasClusters[16]; // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;
uniform vec2 iCanvasTrail[64];   // the day-trail, projected
uniform vec3 iCanvasBackground;  // the canvas's own ground colour
uniform vec2 iCanvasSize;        // the logical virtual desktop

// The one colour the sea glows with.
const vec3 glow = vec3(0.32, 0.90, 0.78);
const vec3 glowBright = vec3(0.62, 0.98, 0.90);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The water's slow, nearly silent breathing - two octaves of a calm swell.
float swell(vec2 p, float t) {
    return 0.68 * noise(p * 0.9 + vec2(t * 0.020, -t * 0.014))
         + 0.32 * noise(p * 2.6 + vec2(-t * 0.033, t * 0.026));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);
    float t = iTime;
    vec2 uv = fragCoord;

    // The water: the near-black blue-green, a breath of the night air at
    // the horizon, darkening into the deep below. The swell shifts the
    // darkness a little - the only sign the sea is alive.
    vec3 air = vec3(0.020, 0.062, 0.085);
    vec3 deep = vec3(0.0035, 0.014, 0.022);
    vec3 bg = mix(deep, air, smoothstep(0.55, 0.0, uv.y / res.y));
    if (iCanvasBackground != vec3(0.0)) bg = mix(bg, iCanvasBackground, 0.35);

    float sw = swell(uv * 0.0035, t);
    float waveShade = 0.90 + 0.22 * sw;
    vec3 col = bg * waveShade;

    // The scattered sparks: the plankton drifting everywhere, twinkling
    // at their own pace. Sparse - the dark is the point.
    float spark = noise(uv * 0.09 + vec2(t * 0.012, -t * 0.008));
    float tw = 0.5 + 0.5 * sin(t * (0.6 + hash(floor(uv * 0.09)) * 1.4) + hash(floor(uv * 0.09)) * 6.28);
    col += glow * smoothstep(0.965, 1.0, spark) * tw * 0.05;

    // The shoals: the rooms of the plane. Where a cluster sits, the
    // plankton have gathered - a wide soft bloom under the surface,
    // breathing on the room's own beat.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec4 cl = iCanvasClusters[i];
        vec2 c = vec2(cl.x * cs.x, (iCanvasSize.y - cl.y) * cs.y);
        float members = cl.z;
        float beat = 0.5 + 0.5 * sin(t * 0.32 + float(i) * 2.399);
        float R = 110.0 + members * 26.0;             // the shoal's reach
        float d = length(uv - c);
        float edge = 0.60 + 0.40 * noise(uv * 0.016 + vec2(t * 0.010, beat) + float(i) * 7.3);

        float bloom = exp(-d * d / (R * R));
        float heart = exp(-d * d / (R * R * 0.14));
        col += glow * bloom * (0.10 + 0.16 * beat) * edge;
        col += glowBright * heart * (0.05 + 0.07 * beat);
    }

    // The lanterns: the real windows, the boats' lights on the dark.
    // A bright spark at each, and its light spilled down the water.
    for (int j = 0; j < iWindowCount && j < 16; j++) {
        vec4 w = iWindowRects[j];
        vec2 c = vec2((w.x + w.z * 0.5) * cs.x, (iCanvasSize.y - (w.y + w.w * 0.5)) * cs.y);
        float side = max(w.z * cs.x, w.w * cs.y) * 0.30;
        float d = length(uv - c);
        col += glowBright * exp(-d * d / (6.0 * 6.0)) * 1.1;
        col += glow * exp(-d * d / (side * side)) * 0.22;
        float streak = exp(-pow((uv.x - c.x) / (side * 0.5), 2.0))
                     * smoothstep(c.y + side * 6.0, c.y, uv.y);
        col += glow * streak * 0.14;
    }

    // The wake: the passage the camera left. One ribbon, bright at the
    // head (the newest point) and fading back along the path it took.
    for (int k = 0; k < iCanvasTrailCount - 1 && k < 63; k++) {
        vec2 a = vec2(iCanvasTrail[k].x * cs.x, (iCanvasSize.y - iCanvasTrail[k].y) * cs.y);
        vec2 b = vec2(iCanvasTrail[k + 1].x * cs.x, (iCanvasSize.y - iCanvasTrail[k + 1].y) * cs.y);
        vec2 pa = uv - a;
        vec2 ba = b - a;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1.0), 0.0, 1.0);
        float d = length(pa - ba * h);
        float age = float(k + 1) / float(max(iCanvasTrailCount - 1, 1));
        float headPulse = (k >= iCanvasTrailCount - 2) ? (0.75 + 0.25 * sin(t * 2.2)) : 1.0;
        float width = 4.0 + 6.0 * age;
        col += glow * exp(-d * d / (width * width)) * (0.05 + 0.30 * age) * headPulse;
    }

    // The one thing that falls in: the pointer. Its hover is a faint
    // bloom; its press sends the ripple, and the plankton light up.
    if (iMouse.z > 0.0) {
        vec2 m = iMouse.xy;
        float md = length(uv - m);
        col += glow * exp(-md * md / (60.0 * 60.0)) * 0.05;
        if (iMouse.z > 0.5) {
            float ripple = sin(md * 0.10 - t * 2.4) * exp(-md * 0.006) * 0.30;
            col += glow * ripple * smoothstep(320.0, 0.0, md);
            col += glowBright * exp(-md * md / (46.0 * 46.0)) * 0.16;
        }
    }

    // The breathing of the whole, and the soft edge into the dark.
    col *= 0.96 + 0.04 * sin(t * 0.26);
    vec2 vig = uv / res;
    col *= 1.0 - 0.30 * pow(16.0 * (vig.x - 0.5) * (vig.x - 0.5) * (vig.y - 0.5) * (vig.y - 0.5), 1.4);

    fragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(0.94)), 1.0);
}

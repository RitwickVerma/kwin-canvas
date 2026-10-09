// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// The plane at night.
//
// Seen from above, the plane is a night sea of windows, and every
// window is a light afloat in the dark. The sea exists on its own: a
// field of soft distant lights drifting and twinkling in the deep
// blue, with nothing to prove. The canvas's state is its weather:
//
//   - the rooms are the harbours: where a cluster of windows gathers,
//     the lights crowd into a warm pool that breathes on the room's
//     own beat;
//   - the windows are the lanterns: the sharp cool sparks of the
//     boats afloat on the dark;
//   - the day-trail is the wake: a faint smear of light where the
//     camera travelled, bright at the head and fading behind it;
//   - the pointer is the eye: the lights beneath it sharpen into
//     focus and glow brighter while the rest of the sea falls away
//     into the soft out-of-focus haze, as if the finger chooses what
//     to see;
//   - and the camera's position is the tide: the whole light field
//     drifts slowly with the plane's view, so the desktop at rest
//     carries the memory of where the canvas has been.
//
// The state arrives in the canvas's logical top-down coordinates; the
// shader lives in the engine's physical bottom-up pixels. The cs
// factor scales the one into the other, and every y flips on entry -
// the two fixes that keep each glow where its window really is.
//
// For the kde-shader-wallpaper engine (docs/shader-integration.md).
// The iCanvas* uniforms are declared here - the engine's fork uploads
// them; without the fork they read zero and the sea is simply the
// procedural night.

// @channels none

uniform int iCanvasClusterCount;
uniform vec4 iCanvasClusters[16]; // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;
uniform vec2 iCanvasTrail[64];   // the day-trail, projected
uniform vec3 iCanvasBackground;  // the canvas's own ground colour
uniform vec2 iCanvasSize;        // the logical virtual desktop
uniform vec2 iCanvasView;        // the camera's position on the plane

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The slow breathing of the deep: a domain-warped field of the blue
// night, the haze the lights float in.
float nightHaze(vec2 p, float t) {
    vec2 q = vec2(0.0);
    q.x = noise(p + vec2(0.0, t * 0.016));
    q.y = noise(p + vec2(5.2, 1.3) - vec2(0.0, t * 0.012));
    return noise(p + q * 0.55);
}

// One cell of the light field. p and c are in the cell grid's space
// (the scaled pixels); sc converts back to pixels. The pointer's
// focus shrinks and brightens the lights beneath it.
vec3 cellLight(vec2 p, vec2 c, float sc, vec2 focus, float focusR) {
    vec2 h1 = vec2(hash(c + vec2(13.1, 7.7)), hash(c + vec2(4.3, 11.9)));
    vec2 h2 = vec2(hash(c + vec2(1.7, 9.9)), hash(c + vec2(5.3, 2.9)));
    float orb = hash(c + vec2(8.7, 1.3)) * 6.2831;
    float sp = 0.04 + 0.10 * hash(c + vec2(4.1, 6.7));
    vec2 lp = c + h1 + vec2(cos(iTime * sp + orb), sin(iTime * sp * 0.83 + orb * 1.71)) * 0.30;
    vec2 d = (p - lp) * sc;
    float dd = dot(d, d);
    float sz = (2.2 + 3.4 * h2.x) * sc / 44.0;
    float focusAmt = exp(-dot(focus - lp * sc, focus - lp * sc) / (focusR * focusR));
    sz *= mix(1.0, 0.32, focusAmt);
    float tw = 0.72 + 0.28 * sin(iTime * (0.3 + 0.6 * h2.y) + h1.x * 6.2831);
    float disc = exp(-dd / (sz * sz));
    float rim = exp(-pow(sqrt(dd) - sz * 0.72, 2.0) * (3.2 / (sz * sz)));
    float b = (disc * 0.45 + rim * 0.55) * tw;
    b *= mix(1.0, 1.7, focusAmt);
    vec3 warm = vec3(1.0, 0.62, 0.28);
    vec3 cool = vec3(0.55, 0.78, 1.0);
    vec3 tint = mix(cool, warm, h1.y);
    return tint * b;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);
    vec2 uv = fragCoord;

    // The night itself: the canvas's ground colour under a slow blue
    // haze, deeper toward the corners of the plane.
    vec3 bg = (iCanvasBackground == vec3(0.0)) ? vec3(0.012, 0.020, 0.045) : iCanvasBackground;
    vec3 col = bg;
    float hz = nightHaze(uv * 0.0016, iTime);
    col += vec3(0.010, 0.024, 0.052) * hz;

    // The pointer is the eye: the focus point, in the field's own
    // space per layer.
    vec2 m = iMouse.xy;
    float focusR = 240.0;

    // The light sea: three parallax layers, each drifting with the
    // camera's view so the desktop remembers where the plane has been.
    for (int layer = 0; layer < 3; layer++) {
        float sc = 44.0 + 44.0 * float(layer);
        vec2 drift = iCanvasView * (0.004 + 0.003 * float(layer));
        vec2 p = uv / sc + drift;
        p += vec2(iTime * (0.004 + 0.003 * float(layer)), -iTime * 0.002);
        vec2 cell = floor(p);
        vec2 focus = m / sc;
        for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
                vec2 c = mod(cell + vec2(float(dx), float(dy)), 512.0);
                col += cellLight(p, c, sc, focus, focusR / sc);
            }
        }
    }

    // The rooms are the harbours: the warm pools where the lights
    // crowd together, breathing on each room's beat.
    for (int i = 0; i < iCanvasClusterCount; i++) {
        vec4 cl = iCanvasClusters[i];
        vec2 c = vec2(cl.x * cs.x, (iCanvasSize.y - cl.y) * cs.y);
        c = clamp(c, vec2(80.0), res - vec2(80.0));
        float n = cl.z;
        float beat = 0.5 + 0.5 * sin(iTime * 0.32 + float(i) * 2.399);
        float R = 130.0 + n * 30.0;
        float d = length(uv - c);
        float edge = 0.62 + 0.38 * noise(uv * 0.016 + vec2(float(i) * 7.3, beat));
        vec3 amber = vec3(1.0, 0.62, 0.28);
        col += amber * exp(-d * d / (R * R)) * (0.10 + 0.14 * beat) * edge;
        col += vec3(1.0, 0.82, 0.55) * exp(-d * d / (R * R * 0.12)) * (0.05 + 0.07 * beat);
    }

    // The windows are the lanterns: the sharp cool sparks.
    for (int i = 0; i < iWindowCount && i < 16; i++) {
        vec4 w = iWindowRects[i];
        vec2 c = vec2((w.x + w.z * 0.5) * cs.x, (iCanvasSize.y - (w.y + w.w * 0.5)) * cs.y);
        c = clamp(c, vec2(80.0), res - vec2(80.0));
        float side = max(w.z * cs.x, w.w * cs.y) * 0.30;
        vec2 d = uv - c;
        float dd = dot(d, d);
        vec3 cool = vec3(0.55, 0.78, 1.0);
        col += cool * exp(-dd / (side * side * 4.0)) * 0.10;
        col += vec3(0.85, 0.94, 1.0) * exp(-dd / (side * side * 0.35)) * 0.14;
    }

    // The day-trail is the wake: the faint smear of light where the
    // camera travelled, bright at the head and fading behind it.
    if (iCanvasTrailCount > 1) {
        float total = float(max(iCanvasTrailCount - 1, 1));
        for (int k = 0; k < iCanvasTrailCount - 1 && k < 63; k++) {
            vec2 a = vec2(iCanvasTrail[k].x * cs.x, (iCanvasSize.y - iCanvasTrail[k].y) * cs.y);
            vec2 b = vec2(iCanvasTrail[k + 1].x * cs.x, (iCanvasSize.y - iCanvasTrail[k + 1].y) * cs.y);
            vec2 ab = b - a;
            float abLen = length(ab);
            if (abLen < 0.5) {
                continue;
            }
            float t = clamp(dot(uv - a, ab) / (abLen * abLen), 0.0, 1.0);
            vec2 q = a + ab * t;
            float d = length(uv - q);
            float age = float(k + 1) / total;
            float wdt = 3.0 + 5.0 * age;
            float pulse = (k >= iCanvasTrailCount - 2) ? (0.75 + 0.25 * sin(iTime * 2.2)) : 1.0;
            vec3 amber = vec3(1.0, 0.62, 0.28);
            col += amber * exp(-d * d / (wdt * wdt)) * (0.04 + 0.16 * age) * pulse;
        }
    }

    // The pointer is the eye: a soft bloom under the finger.
    if (iMouse.z > 0.0) {
        vec2 d = uv - m;
        float md = dot(d, d);
        col += vec3(0.9, 0.75, 0.5) * exp(-md / (240.0 * 240.0)) * 0.05;
    }

    // The night breathes, and the corners fall away.
    col *= 0.96 + 0.04 * sin(iTime * 0.26);
    vec2 vig = uv / res;
    float v = smoothstep(0.75, 0.35, length(vig - 0.5) * 1.5);
    col *= mix(0.55, 1.0, v);

    fragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(0.92)), 1.0);
}

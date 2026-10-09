// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The plane breathes. The closed desktop is the canvas's plane seen at
// rest, but the floor is not paper: three curtains of aurora flow
// across it on their own slow beats - the canvas's blue, a violet
// crest, a teal undercurrent - warped by the same layered noise the
// engine's best skies use. The canvas's remembered state is the light
// IN the field: the rooms glow as warm pools where the clusters sit
// (each breathing on its own rhythm, the aurora brightening where it
// passes them), the day-trail runs through as a river of moving light,
// the real windows cast their faint reflections where they stand, and
// the pointer is a torch that parts the curtains. A fine star-dust
// settles everywhere, and the whole field breathes.
//
// The iCanvas* uniforms are fed from the kwin-canvas passthrough
// plugin's state file (kwin-canvas-state.txt) by the engine's fork;
// the engine's own iMouse, iWindowCount and iWindowRects cover the
// hand and the windows. The state arrives in the screen's top-down
// coordinates and this shader flips it to the GL's bottom-up. See
// docs/shader-integration.md for the channel and the fork contract.
// Absent the fork the canvas uniforms read zero and the field is the
// aurora alone.
//
// @channels none

uniform int iCanvasClusterCount;   // up to 16, the plane's clusters
uniform vec4 iCanvasClusters[16];  // x,y = the room centre (top-down), z = the member count
uniform int iCanvasTrailCount;     // up to 64, the day-trail's samples
uniform vec2 iCanvasTrail[64];     // the path points (top-down), oldest first
uniform vec3 iCanvasBackground;    // the plane's ground, 0..1
uniform vec2 iCanvasSize;         // the LOGICAL virtual desktop (the state's space)

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

// One aurora curtain: the layered noise warped by itself, flowing.
float auroraField(vec2 p, float t, float speed) {
    vec2 q = p + vec2(0.0, t * speed);
    float w = fbm(q * 1.5 + vec2(t * 0.12, 0.0));
    q += w * 0.45;
    return fbm(q * 2.1 - vec2(t * 0.08, 0.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float t = iTime;

    // The state arrives in LOGICAL pixels (the KWin geometry); this shader
    // renders in PHYSICAL pixels (the output's size, the dpr included). One
    // factor maps the state onto the screen - at 100% scale it is one.
    // Absent the fork's size upload the uniform reads zero: fall back to
    // the identity, so the features land where the logical state puts them
    // rather than nowhere.
    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);

    // The sky: the plane's own background, deep, a little lighter below
    // so the windows and the pools read on top of it.
    vec3 col = mix(iCanvasBackground * 0.30, iCanvasBackground * 1.35, uv.y);

    // The aurora: three curtains at the different scales, speeds and
    // hues. The crests carry the colour; the curtains fade toward the
    // bottom so the floor stays the floor.
    vec2 asp = uv * vec2(res.x / res.y, 1.0);
    float f1 = auroraField(asp * 1.3, t, 0.22);
    float f2 = auroraField(asp * 2.6 + vec2(3.1, 0.0), t, 0.38);
    float f3 = auroraField(asp * 0.7 + vec2(7.7, 0.0), t, 0.13);

    float crest1 = pow(clamp(f1, 0.0, 1.0), 3.0) * smoothstep(1.05, 0.25, uv.y);
    float crest2 = pow(clamp(f2, 0.0, 1.0), 3.0) * smoothstep(1.05, 0.25, uv.y);
    float crest3 = pow(clamp(f3, 0.0, 1.0), 3.0) * smoothstep(1.05, 0.25, uv.y);

    col += vec3(0.06, 0.38, 0.95) * crest1 * 0.5;
    col += vec3(0.55, 0.16, 0.95) * crest2 * 0.38;
    col += vec3(0.04, 0.82, 0.85) * crest3 * 0.30;

    // The star-dust: a fine grain over the whole field, so even the
    // empty floor shimmers instead of sitting.
    float dust = noise(uv * res * 0.02 + vec2(t * 0.05, -t * 0.04)) * 0.5 + 0.5;
    col += vec3(0.5, 0.6, 0.8) * (dust - 0.5) * 0.04;

    // The rooms: the warm pools where the clusters sit, each on its own
    // beat; the aurora brightens as it passes them.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec2 c = iCanvasClusters[i].xy * cs;
        c.y = res.y - c.y;  // the logical top-down -> the physical bottom-up
        float n = max(iCanvasClusters[i].z, 1.0);
        float beat = sin(t * 0.6 + float(i) * 2.399) * 0.5 + 0.5;
        float r = (70.0 + 26.0 * n) * (0.9 + 0.25 * beat);
        float d = length(fragCoord - c);
        float pool = exp(-(d * d) / (2.0 * r * r));
        float core = exp(-(d * d) / (2.0 * r * r * 0.08));
        col += vec3(1.0, 0.72, 0.40) * pool * (0.20 + 0.20 * beat);
        col += vec3(1.0, 0.95, 0.85) * core * (0.24 + 0.18 * beat);
        float resp = exp(-(d * d) / (2.0 * r * r * 2.2));
        col += vec3(0.10, 0.50, 1.0) * resp * 0.10;
    }

    // The trail: the day's path as a river of moving light.
    for (int i = 0; i < iCanvasTrailCount - 1 && i < 63; i++) {
        vec2 a = iCanvasTrail[i] * cs;
        vec2 b = iCanvasTrail[i + 1] * cs;
        a.y = res.y - a.y;
        b.y = res.y - b.y;
        vec2 pa = fragCoord - a;
        vec2 ba = b - a;
        float seg = length(ba);
        float h = clamp(dot(pa, ba) / max(seg * seg, 1.0), 0.0, 1.0);
        float d = length(pa - ba * h);
        float flow = 0.5 + 0.5 * sin(t * 1.1 - float(i) * 0.30 + h * 4.0);
        col += vec3(0.35, 0.75, 1.0) * exp(-d * d / (2.0 * 10.0 * 10.0)) * (0.10 + 0.12 * flow);
    }

    // The windows: the real windows cast their faint reflections.
    for (int i = 0; i < iWindowCount && i < 16; i++) {
        vec4 w = iWindowRects[i];
        vec2 c = vec2((w.x + w.z * 0.5) * cs.x, res.y - (w.y + w.w * 0.5) * cs.y);
        float md = length(fragCoord - c);
        float rr = max(w.z, w.w) * cs.x * 0.7;
        col += vec3(0.35, 0.55, 1.0) * exp(-md * md / (2.0 * rr * rr)) * 0.05;
    }

    // The torch: the pointer parts the aurora, warm.
    vec2 m = iMouse.xy;
    if (m.x > 0.5 || m.y > 0.5) {
        float md = length(fragCoord - m);
        col += vec3(1.0, 0.85, 0.60) * exp(-md * md / (2.0 * 90.0 * 90.0)) * 0.08;
        col += vec3(1.0, 0.97, 0.90) * exp(-md * md / (2.0 * 20.0 * 20.0)) * 0.04;
    }

    // The whole field breathes, slowly.
    col *= 0.97 + 0.03 * sin(t * 0.33);

    fragColor = vec4(col, 1.0);
}

// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The plane at dusk: a mountain valley.
//
// The scenery stands on its own: the ridges fold into the haze, the sun
// goes down behind them, and the valley floor breathes its mist. Far
// back in the sky hangs the plane itself, compressed to a band: the
// windows are its sheets, outlined and faint, and the rooms are the
// glow-gatherings among them. Everything sits at its true place - the
// geography is the canvas's own, and it drifts with the camera, so the
// desktop carries the memory of where the plane has been; the pointer
// is a torch in the dusk.
//
// The fork's engine uploads the iCanvas* uniforms from
// kwin-canvas-state.txt (see docs/shader-integration.md); without it
// every reading is zero and the valley is simply empty of people. The
// shader declares them itself - the engine's header must NOT declare
// them too, or the duplicate declarations fail the compile.
// @channels none

uniform int iCanvasClusterCount;
uniform vec4 iCanvasClusters[16]; // x,y = the room's centre, z = the member count
uniform int iCanvasTrailCount;
uniform vec2 iCanvasTrail[64];
uniform vec3 iCanvasBackground;
uniform vec2 iCanvasSize;
uniform vec2 iCanvasView;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(11.7, 5.3);
        a *= 0.5;
    }
    return v;
}

float ridge(vec2 p) {
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 4; i++) {
        v += a * (1.0 - abs(noise(p) * 2.0 - 1.0));
        p = p * 2.13 + vec2(7.1, 3.7);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float t = iTime;

    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);

    // The dusk sky: the deep blue above, the warm band where the sun
    // is going down.
    vec3 skyTop = vec3(0.05, 0.09, 0.21);
    vec3 skyHorizon = vec3(0.88, 0.44, 0.30);
    vec3 col = mix(skyHorizon, skyTop, smoothstep(0.46, 0.80, uv.y));

    // The sun, half-set behind the far ridge.
    vec2 sunPos = vec2(0.62, 0.50);
    float sunD = length(uv - sunPos);
    col += vec3(1.0, 0.70, 0.40) * exp(-sunD * 22.0) * 0.8;
    col += vec3(1.0, 0.55, 0.30) * exp(-sunD * 130.0) * 0.45;
    col += vec3(1.0, 0.92, 0.75) * smoothstep(0.016, 0.0, sunD);

    // The ridges drift with the camera's view: the desktop carries the
    // memory of where the plane has been.
    vec2 drift = iCanvasView * 0.00014;

    float horizon = 0.55;

    // The far ridge, pale in the haze.
    float mf = ridge(vec2(uv.x * 3.1, 1.0) + drift * 0.6 + vec2(0.0, 3.3));
    float farH = horizon + (mf - 0.55) * 0.34;
    float inFar = step(uv.y, farH);
    vec3 farCol = mix(skyHorizon * 1.05, vec3(0.17, 0.19, 0.30), mf);
    col = mix(col, farCol, inFar * 0.94);

    // The near ridge, dark and taller.
    float mn = ridge(vec2(uv.x * 2.2, 1.0) + drift * 1.1 + vec2(0.0, 9.1));
    float nearH = horizon + 0.05 + (mn - 0.55) * 0.44;
    float inNear = step(uv.y, nearH);
    vec3 nearCol = mix(vec3(0.09, 0.11, 0.19), vec3(0.030, 0.045, 0.10), mn);
    col = mix(col, nearCol, inNear);

    // The valley floor below, breathing its mist.
    float inFloor = step(uv.y, horizon - 0.02);
    vec3 floorCol = mix(vec3(0.030, 0.045, 0.085), vec3(0.014, 0.022, 0.045), smoothstep(horizon - 0.02, 0.0, uv.y));
    float mist = fbm(vec2(uv.x * 5.0, 1.0) + t * 0.045 + drift * 2.2);
    floorCol += vec3(0.05, 0.07, 0.10) * mist * smoothstep(horizon - 0.02, horizon - 0.18, uv.y);
    col = mix(col, floorCol, inFloor);

    // The distant plane: the whole canvas far back in the sky, compressed
    // to a band. The windows are its sheets - outlined, faint - and the
    // rooms are the glow-gatherings among them. The positions are the
    // true ones, scaled down: the geography is the canvas's own, and it
    // drifts with the camera.
    float k = 0.055;
    vec2 vc = vec2(res.x * 0.5, res.y * 0.24);
    vc += iCanvasView * 0.0003 * cs;

    // The sheets: the windows, outlined.
    for (int w = 0; w < 16; w++) {
        if (w >= iWindowCount) break;
        vec4 wr = iWindowRects[w];
        vec2 sc = vc + vec2(wr.x + wr.z * 0.5 - iCanvasSize.x * 0.5,
                            iCanvasSize.y * 0.5 - (wr.y + wr.w * 0.5)) * k * cs;
        vec2 sz = vec2(wr.z, wr.w) * k * cs;
        vec2 p = uv * res - sc;
        vec2 q = abs(p) - sz * 0.5;
        float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
        float line = 1.0 - smoothstep(0.8, 2.0, abs(edge));
        col += vec3(1.0, 0.78, 0.50) * line * 0.30;
        col += vec3(1.0, 0.85, 0.60) * (1.0 - smoothstep(0.0, max(sz.x, sz.y) * 0.5, length(p))) * 0.05;
    }

    // The rooms: the clusters, glowing far back, breathing on their own
    // beats.
    for (int i = 0; i < 16; i++) {
        if (i >= iCanvasClusterCount) break;
        vec4 cl = iCanvasClusters[i];
        vec2 cp = vc + vec2(cl.x - iCanvasSize.x * 0.5,
                            iCanvasSize.y * 0.5 - cl.y) * k * cs;
        float n = clamp(cl.z, 1.0, 9.0);
        float R = 3.0 + n * 1.6;
        float d = length(uv * res - cp);
        float beat = 0.5 + 0.5 * sin(t * 0.32 + float(i) * 2.399);
        col += vec3(1.0, 0.72, 0.42) * exp(-(d * d) / (R * R)) * (0.20 + 0.28 * beat);
        col += vec3(1.0, 0.92, 0.75) * exp(-(d * d) / (R * R * 0.10)) * (0.08 + 0.12 * beat);
    }

    // The torch: the pointer.
    if (iMouse.z > 0.0) {
        vec2 m = iMouse.xy - iScreenOffset;
        float md = length(uv * res - m);
        col += vec3(1.0, 0.62, 0.35) * exp(-(md * md) / 1600.0) * 0.30;
    }

    // The breathing, the vignette, the gamma.
    col *= 0.96 + 0.04 * sin(t * 0.26);
    vec2 vig = uv * (1.0 - uv);
    col *= 1.0 - 0.35 * pow(16.0 * vig.x * vig.y, 1.4);
    fragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(0.92)), 1.0);
}

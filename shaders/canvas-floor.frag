// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// The plane is an open ocean.
//
// The canvas's own state is the ocean's life. The clusters are the
// islands: each room is a landmass ringed in sand and breaking foam,
// with a lighthouse at its heart whose beam sweeps on the room's own
// beat. The windows are the boats - little hulls with lanterns whose
// light spills down the water. The day-trail is the passage the camera
// left: a phosphorescent wake across the deep. And the pointer is the
// one thing that falls in - its ripple spreads, and the glitter around
// it brightens. The waves flow toward the sun; the sun's path of light
// rides the crests; the islands break the swell and shadow the water
// away from it.
//
// The state arrives in the canvas's logical top-down coordinates; the
// shader lives in the engine's physical bottom-up pixels. The cs factor
// scales the one into the other, and every y flips on entry - the two
// fixes that keep each island, boat and wake where its window really is.
//
// For the kde-shader-wallpaper engine (docs/shader-integration.md).
// The iCanvas* uniforms are declared here - the engine's fork uploads
// them; without the fork they read zero and the ocean is simply empty.

// @channels none

uniform int iCanvasClusterCount;
uniform vec4 iCanvasClusters[16]; // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;
uniform vec2 iCanvasTrail[64];   // the day-trail, projected
uniform vec3 iCanvasBackground;  // the canvas's own ground colour
uniform vec2 iCanvasSize;        // the logical virtual desktop

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

// Two octaves of the flowing swell - the deep roll and the chop on top.
float swell(vec2 p, float t) {
    float h = 0.0;
    h += 0.62 * noise(p * 1.0 + vec2(t * 0.045, t * 0.028));
    h += 0.26 * noise(p * 2.3 - vec2(t * 0.031, t * 0.052));
    h += 0.12 * noise(p * 5.1 + vec2(t * 0.060, t * 0.017));
    return h;
}

// The surface normal from the swell's slope - the light to the sun.
vec2 swellNormal(vec2 p, float t) {
    float e = 1.8;
    return vec2(swell(p, t) - swell(p + vec2(e, 0.0), t),
                swell(p, t) - swell(p + vec2(0.0, e), t));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);
    float t = iTime;
    vec2 uv = fragCoord;

    // The sun, high on the right; the light flows from it.
    vec2 sun = res * vec2(0.74, 0.16);
    vec2 lightDir = normalize(vec2(-0.45, -0.89));
    float sunGlow = exp(-pow(length(uv - sun) / (res.y * 0.30), 2.0));

    // The deep - the canvas's own ground water-coloured, darkening away
    // from the sun and with the distance from the top.
    vec3 water = vec3(0.016, 0.10, 0.19);
    vec3 shore = vec3(0.05, 0.30, 0.40);
    vec3 bg = mix(shore, water, clamp((uv.y / res.y) * 0.85 + sunGlow * 0.5, 0.0, 1.0));
    if (iCanvasBackground != vec3(0.0)) bg = mix(bg, iCanvasBackground, 0.30);

    // The swell's own shading - the wave faces toward the sun catch it.
    vec2 sw = swellNormal(uv * 0.0045, t);
    float waveShade = 0.52 + 0.48 * clamp(dot(normalize(sw + vec2(1e-4)), lightDir), -1.0, 1.0);
    vec3 col = bg * (0.45 + 0.75 * waveShade);

    // The sun's path of light down the water - the glitter band.
    float band = exp(-pow((uv.x - sun.x) * 0.0038, 2.0)) * smoothstep(sun.y + res.y * 0.75, sun.y, uv.y);
    col += vec3(1.0, 0.82, 0.48) * band * 0.22;
    // The sparkles that ride the crests inside the band.
    float crest = pow(max(0.0, sw.x + sw.y), 2.0);
    float glint = smoothstep(0.55, 1.0, noise(uv * 0.23 + vec2(t * 0.11, -t * 0.07)));
    col += vec3(1.0, 0.90, 0.70) * crest * glint * band * 0.55;
    // The sun's own disc, softened.
    col += vec3(1.0, 0.88, 0.60) * exp(-pow(length(uv - sun) / (res.y * 0.06), 2.0)) * 0.9;

    // The islands: the rooms of the plane.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec4 cl = iCanvasClusters[i];
        vec2 c = vec2(cl.x * cs.x, (iCanvasSize.y - cl.y) * cs.y);
        float members = cl.z;
        float beat = 0.5 + 0.5 * sin(t * 0.45 + float(i) * 2.399);
        float R = 30.0 + members * 17.0;              // the room's size = its land
        float d = length(uv - c);

        // The shadow the island casts away from the sun.
        vec2 sh = c + vec2(R * 1.15, R * 0.55);
        float sdist = length(uv - sh);
        float shadow = smoothstep(R * 1.25, R * 0.55, sdist);
        col *= 1.0 - shadow * 0.32;

        // The breaking foam ring - alive, ragged, breathing with the room.
        float foam = smoothstep(R + 12.0, R + 5.0, d) * (1.0 - smoothstep(R + 4.0, R - 4.0, d));
        foam *= 0.55 + 0.45 * noise(uv * 0.16 + vec2(t * 0.07, beat * 2.0) + float(i) * 13.7);

        // The sand rim, then the grass, then the hill - the land itself.
        float sand = smoothstep(R + 2.0, R - 5.0, d) * (1.0 - smoothstep(R - 6.0, R - 13.0, d));
        float grass = smoothstep(R - 12.0, R - 18.0, d) * (1.0 - smoothstep(R - 18.0, R * 0.30, d));
        float hill = smoothstep(R * 0.32, R * 0.10, d);
        float hillShade = 0.55 + 0.45 * noise(c * 0.05 + float(i) * 3.1);

        col = mix(col, vec3(0.88, 0.82, 0.62), sand);
        col = mix(col, vec3(0.05, 0.26, 0.13) * (0.75 + 0.35 * hillShade), grass);
        col = mix(col, vec3(0.14, 0.34, 0.16) * hillShade, hill);
        col = mix(col, vec3(0.96, 0.98, 1.0), foam * 0.75);

        // The lighthouse at the heart - a white point, and its beam
        // sweeping the water on the room's own beat.
        vec2 lt = c + vec2(R * 0.10, -R * 0.10);
        float ld = length(uv - lt);
        col += vec3(1.0, 0.97, 0.88) * exp(-ld * ld / (2.5 * 2.5)) * 1.4;
        float beamAng = t * 0.22 + float(i) * 1.7;
        vec2 beamDir = vec2(cos(beamAng), sin(beamAng));
        float beam = pow(max(0.0, dot(normalize(uv - lt), beamDir)), 40.0) * smoothstep(R * 5.0, R * 0.8, ld);
        col += vec3(1.0, 0.92, 0.65) * beam * (0.55 + 0.45 * beat);
    }

    // The boats: the real windows, afloat on the water.
    for (int j = 0; j < iWindowCount && j < 16; j++) {
        vec4 w = iWindowRects[j];
        vec2 c = vec2((w.x + w.z * 0.5) * cs.x, (iCanvasSize.y - (w.y + w.w * 0.5)) * cs.y);
        float side = max(w.z * cs.x, w.w * cs.y) * 0.28;
        float d = length(uv - c);
        // The hull.
        col += vec3(0.03, 0.05, 0.07) * smoothstep(side, side * 0.35, d);
        // The lantern's glow on the boat.
        col += vec3(1.0, 0.72, 0.38) * exp(-d * d / (side * side * 2.5)) * 0.9;
        // The lantern's light spilled down the water - the column.
        float streak = exp(-pow((uv.x - c.x) / (side * 0.6), 2.0)) * smoothstep(c.y + side * 4.0, c.y, uv.y);
        col += vec3(1.0, 0.80, 0.45) * streak * 0.30;
    }

    // The passage: the day-trail as the phosphorescent wake.
    for (int k = 0; k < iCanvasTrailCount - 1 && k < 63; k++) {
        vec2 a = vec2(iCanvasTrail[k].x * cs.x, (iCanvasSize.y - iCanvasTrail[k].y) * cs.y);
        vec2 b = vec2(iCanvasTrail[k + 1].x * cs.x, (iCanvasSize.y - iCanvasTrail[k + 1].y) * cs.y);
        vec2 pa = uv - a;
        vec2 ba = b - a;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1.0), 0.0, 1.0);
        float d = length(pa - ba * h);
        float flow = 0.5 + 0.5 * sin(t * 0.85 - float(k) * 0.40 + h * 5.5);
        float width = 2.0 + 2.5 * flow;
        col += vec3(0.45, 0.80, 1.0) * exp(-d * d / (width * width)) * 0.20;
    }

    // The one thing that fell in: the pointer's ripple.
    if (iMouse.z > 0.5) {
        vec2 m = iMouse.xy;
        float md = length(uv - m);
        float ripple = sin(md * 0.11 - t * 2.6) * exp(-md * 0.007) * 0.30;
        col += vec3(0.80, 0.95, 1.0) * ripple * smoothstep(260.0, 0.0, md);
        col += vec3(0.90, 1.0, 1.0) * exp(-md * md / (70.0 * 70.0)) * 0.14;
    }

    // The breathing of the whole, and the soft edge.
    col *= 0.96 + 0.04 * sin(t * 0.30);
    vec2 vig = uv / res;
    col *= 1.0 - 0.28 * pow(16.0 * (vig.x - 0.5) * (vig.x - 0.5) * (vig.y - 0.5) * (vig.y - 0.5), 1.4);

    fragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(0.92)), 1.0);
}

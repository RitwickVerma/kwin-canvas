// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// @channels none

// The astronaut floats again. An original reading of the Wallpaper Engine
// scene that inspired it: the deep dusk, the great planet overhead, the
// calm dark ocean, and the figure afloat at the water line. The canvas's
// state is the weather: the camera's view drifts the stars and the water,
// and the rooms are the faint warm lights low in the sky.

uniform int iCanvasClusterCount;
uniform vec4 iCanvasClusters[16];
uniform int iCanvasTrailCount;
uniform vec2 iCanvasTrail[64];
uniform vec3 iCanvasBackground;
uniform vec2 iCanvasSize;
uniform vec2 iCanvasView;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
    return noise(p) * 0.62 + noise(p * 2.6 + vec2(3.1, 7.4)) * 0.38;
}

// distance to a segment (the astronaut's arms, the glints)
float glow(vec2 p, vec2 c, float r) {
    return exp(-dot(p - c, p - c) / (r * r));
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// the planet: the shaded sphere with the banded surface + the lit limb.
vec3 planetCol(vec2 p, vec2 pc, float pr, float t) {
    vec2 d = (p - pc) / pr;
    float r = dot(d, d);
    if (r > 1.0) return vec3(-1.0);
    float z = sqrt(max(0.0, 1.0 - r));
    // the light comes from the upper-left, behind the viewer's shoulder
    vec3 n = normalize(vec3(d, z));
    vec3 l = normalize(vec3(-0.55, -0.45, 0.70));
    float lam = clamp(dot(n, l), 0.0, 1.0);
    // the slow surface bands
    float b1 = fbm2(vec2(d.x * 3.0, d.y * 3.0) + t * 0.01);
    float b2 = noise(vec2(d.x * 9.0 + 1.7, d.y * 9.0) + t * 0.02);
    vec3 surface = mix(vec3(0.10, 0.28, 0.42), vec3(0.28, 0.55, 0.72), b1);
    surface = mix(surface, vec3(0.55, 0.78, 0.90), b2 * 0.55);
    vec3 col = surface * (0.18 + 0.95 * lam);
    // the terminator deepens to the dusk purple
    col = mix(col, vec3(0.12, 0.07, 0.22), smoothstep(0.18, 0.0, lam) * 0.8);
    // the atmosphere rim on the dark side
    float rim = pow(1.0 - z, 2.2);
    col += vec3(0.45, 0.72, 0.95) * rim * 0.55;
    // the specular glint where the light hits
    float spec = pow(max(dot(reflect(-l, n), vec3(0.0, 0.0, 1.0)), 0.0), 40.0);
    col += vec3(1.0, 0.95, 0.85) * spec * 0.7;
    return col;
}

// the astronaut: 1 where the figure floats, 0 elsewhere. p = the point,
// wl = the water line, hc = the helmet centre, hr = the helmet radius.
float astronautMask(vec2 p, vec2 hc, float hr, float wl) {
    // the helmet
    float hd = length(p - hc) - hr;
    // the suit (the chest + the shoulders, sinking into the water)
    vec2 sc = vec2(hc.x, wl + hr * 0.55);
    vec2 q = (p - sc) / vec2(hr * 1.55, hr * 1.05);
    float sd = length(q) - 1.0;
    // the two arms spreading at the water level
    float a1 = segDist(p, vec2(hc.x - hr * 0.9, wl), vec2(hc.x - hr * 2.9, wl + hr * 0.28)) - hr * 0.34;
    float a2 = segDist(p, vec2(hc.x + hr * 0.9, wl), vec2(hc.x + hr * 2.9, wl + hr * 0.28)) - hr * 0.34;
    float d = min(min(hd, sd), min(a1, a2));
    return 1.0 - smoothstep(-1.5, 1.5, d);
}

// the astronaut's colour where the mask is 1
vec3 astronautCol(vec2 p, vec2 hc, float hr, float wl, vec2 pc, float t) {
    // the helmet shell: the white suit lit by the planet's light
    vec2 toPlanet = normalize(pc - hc);
    float lit = clamp(dot(normalize(p - hc), toPlanet) * 0.6 + 0.5, 0.0, 1.0);
    vec3 col = mix(vec3(0.16, 0.19, 0.26), vec3(0.92, 0.94, 0.97), lit);
    // the visor: the dark glass in front, catching the planet's glow
    vec2 vc = hc + vec2(0.0, hr * 0.28);
    float vd = length((p - vc) / vec2(hr * 0.55, hr * 0.38)) - 1.0;
    if (vd < 0.0) {
        vec3 glass = vec3(0.03, 0.05, 0.09);
        // the planet reflected in the glass
        float pr = glow(p, vc + vec2(0.0, -hr * 0.10), hr * 0.16);
        glass += vec3(0.30, 0.62, 0.85) * pr * 0.9;
        // the glass shine
        glass += vec3(1.0) * glow(p, vc + vec2(-hr * 0.16, -hr * 0.12), hr * 0.05) * 0.8;
        col = glass;
    }
    // the rim light along the helmet's planet-side edge
    float rim = pow(clamp(dot(normalize(p - hc), toPlanet), 0.0, 1.0), 3.0);
    col += vec3(0.5, 0.75, 0.95) * rim * 0.55;
    // everything below the water line sinks into the water's colour
    col = mix(col, vec3(0.02, 0.05, 0.10), smoothstep(wl - 2.0, wl + 26.0, p.y));
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord;
    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);
    float t = iTime;

    // the camera's drift (the weather)
    vec2 drift = vec2(0.0);
    if (iCanvasSize.x > 1.0) drift = iCanvasView * 0.004;

    // the dusk sky
    float horizon = res.y * 0.62;
    vec3 sky = mix(vec3(0.19, 0.10, 0.30), vec3(0.095, 0.055, 0.165), smoothstep(horizon, horizon + res.y * 0.16, uv.y));
    sky = mix(sky, vec3(0.038, 0.028, 0.085), smoothstep(horizon + res.y * 0.08, horizon + res.y * 0.42, uv.y));
    vec3 col = sky;

    // the stars - a wrapped cell field drifting with the view + the time
    if (uv.y > horizon + 4.0) {
        for (int layer = 0; layer < 2; layer++) {
            float sp = (layer == 0) ? 340.0 : 520.0;
            vec2 cell = floor(uv / sp) + floor(drift * (layer == 0 ? 0.12 : 0.20));
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    vec2 c = mod(cell + vec2(float(dx), float(dy)), 64.0);
                    vec2 stp = c * sp + vec2(hash(c) * sp, hash(c + 7.0) * sp);
                    vec2 lp = stp + sin(t * 0.03 + hash(c + 3.0) * 6.283) * stp * 0.12;
                    float d = length(uv - lp);
                    float tw = 0.5 + 0.5 * sin(t * (0.7 + hash(c) * 1.6) + hash(c) * 6.283);
                    float sz = (layer == 0) ? 1.4 : 0.9;
                    float star = exp(-d * d / (sz * sz));
                    vec3 st = (layer == 0) ? vec3(0.85, 0.88, 1.0) : vec3(0.62, 0.68, 0.85);
                    col += st * star * (0.10 + 0.55 * tw) * (layer == 0 ? 1.0 : 0.55);
                }
            }
        }
    }

    // the rooms - the faint warm lights low in the sky, at their true bearing
    for (int i = 0; i < 16; i++) {
        if (i >= iCanvasClusterCount) break;
        vec2 cl = iCanvasClusters[i].xy;
        vec2 c = vec2(cl.x * cs.x, (iCanvasSize.y - cl.y) * cs.y);
        // the bearing from the desktop's centre, low over the horizon
        vec2 b = c - res * 0.5;
        vec2 lp = vec2(res.x * 0.5 + b.x * 0.10, horizon - res.y * 0.05 - abs(b.x) * 0.02);
        float d = length(uv - lp);
        float beat = 0.5 + 0.5 * sin(t * 0.5 + float(i) * 2.399);
        col += vec3(1.0, 0.62, 0.35) * exp(-d * d / 300.0) * (0.05 + 0.10 * beat);
    }

    // the planet
    vec2 pc = vec2(res.x * 0.68, res.y * 0.66);
    float pr = res.y * 0.30;
    vec3 pl = planetCol(uv, pc, pr, t);
    if (pl.r >= 0.0) {
        col = mix(col, pl, 1.0 - smoothstep(0.0, 0.02, abs(length((uv - pc) / pr) - 1.0) * pr));
    }
    // the planet's soft halo in the sky
    col += vec3(0.32, 0.55, 0.85) * glow(uv, pc, pr * 1.25) * 0.10;

    // the ocean
    float inWater = 1.0 - step(horizon, uv.y);
    vec2 wp = vec2(uv.x * 0.006, (res.y - uv.y) * 0.006);
    float sw = fbm2(wp + drift * 0.35 + vec2(t * 0.05, 0.0));
    vec3 water = mix(vec3(0.02, 0.055, 0.11), vec3(0.035, 0.085, 0.16), smoothstep(res.y, horizon, uv.y) * 0.0 + sw);
    water = mix(vec3(0.008, 0.025, 0.06), vec3(0.035, 0.085, 0.16), smoothstep(res.y, horizon, uv.y));
    water *= 0.85 + 0.30 * sw;
    col = mix(col, water, inWater);

    // the planet's reflection - the vertical smear below it
    if (inWater > 0.5) {
        float rx = pc.x + (uv.x - pc.x) * 0.35;
        float ry = horizon + (pc.y - horizon) * 0.6;
        float d = abs(uv.x - rx) + abs((uv.y - ry) * 2.2);
        float refl = exp(-d * d / (pr * pr * 0.5));
        vec3 rcol = vec3(0.14, 0.30, 0.46) * refl * (0.35 + 0.45 * sw);
        // the ripple breaks it up
        rcol *= 0.6 + 0.4 * noise(vec2(uv.x * 0.02, uv.y * 0.02) + t * 0.3);
        col += rcol;
    }

    // the water glitter - the shimmering path toward the planet
    if (inWater > 0.5) {
        float path = exp(-pow((uv.x - pc.x) / (res.x * 0.22), 2.0));
        float glint = pow(noise(vec2(uv.x * 0.014, uv.y * 0.10) + t * 0.25), 12.0);
        col += vec3(0.35, 0.55, 0.80) * path * glint * smoothstep(res.y, horizon, uv.y) * 0.9;
    }

    // the astronaut
    vec2 hc = vec2(res.x * 0.46, horizon - res.y * 0.012);
    float hr = res.y * 0.052;
    hc.y += sin(t * 0.55) * res.y * 0.005;
    hc.x += cos(t * 0.38) * res.y * 0.003;
    float mask = astronautMask(uv, hc, hr, horizon);
    if (mask > 0.01) {
        col = mix(col, astronautCol(uv, hc, hr, horizon, pc, t), mask);
    }
    // the astronaut's reflection - the mirrored, dimmed, rippled copy
    if (inWater > 0.5) {
        float my = 2.0 * horizon - uv.y;
        float mx = uv.x + sin(uv.y * 0.02 + t * 0.6) * 3.0;
        float rmask = astronautMask(vec2(mx, my), hc, hr, horizon);
        if (rmask > 0.01) {
            vec3 rcol = astronautCol(vec2(mx, my), hc, hr, horizon, pc, t) * 0.28;
            rcol = mix(rcol, vec3(0.02, 0.05, 0.10), 0.45);
            // the ripple smear
            rcol *= 0.7 + 0.3 * noise(vec2(uv.x * 0.01, uv.y * 0.05) + t * 0.35);
            col = mix(col, rcol, rmask * 0.8);
        }
    }
    // the water line's fresnel - the bright edge where the ocean meets the air
    col += vec3(0.40, 0.62, 0.85) * exp(-abs(uv.y - horizon) / 2.2) * (0.22 + 0.15 * sw) * 0.6;

    // the canvas background breathes through the very top
    if (iCanvasBackground != vec3(0.0)) {
        col = mix(col, iCanvasBackground * 0.4, smoothstep(horizon + res.y * 0.36, res.y, uv.y) * 0.35);
    }

    // the breathing + the vignette + the gamma
    col *= 0.96 + 0.04 * sin(t * 0.26);
    vec2 vg = uv / res;
    float vig = 1.0 - 0.34 * pow(16.0 * (vg.x - 0.5) * (vg.x - 0.5) * (vg.y - 0.5) * (vg.y - 0.5), 0.9);
    col *= vig;
    fragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(0.94)), 1.0);
}

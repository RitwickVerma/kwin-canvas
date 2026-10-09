// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// The plane is a star system.
//
// The canvas's clusters are the suns, each with its windows as the
// worlds orbiting it on the room's own beat; the day-trail is the
// comet's path across the dark; the real windows are the pale lights
// at the glass's edge; the pointer is a lens that bends the starlight.
//
// The engine (kde-shader-wallpaper) supplies the standard i* uniforms;
// the iCanvas* set comes from the kwin-canvas state file through the
// engine fork documented in docs/shader-integration.md. The state's
// coordinates arrive in KWin's LOGICAL top-down pixels: the cs factor
// maps them onto the physical screen and the y is flipped to the
// shader's bottom-up, so every light lands where its window is.

// @channels none

uniform int iCanvasClusterCount;   // the rooms
uniform vec4 iCanvasClusters[16];  // x,y = the centre (logical), z = the member count
uniform int iCanvasTrailCount;     // the day-trail's points (logical)
uniform vec2 iCanvasTrail[64];
uniform vec3 iCanvasBackground;    // the canvas's own ground colour
uniform vec2 iCanvasSize;          // the logical virtual desktop

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p)
{
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(7.1, 3.7);
        a *= 0.5;
    }
    return v;
}

// The nebulae: three drifting fields of the domain-warped fbm.
vec3 nebula(vec2 uv, float t)
{
    vec2 q = uv * 1.4;
    float w1 = fbm(q + vec2(t * 0.014, t * 0.007));
    q += vec2(w1) * 0.55;
    float n1 = fbm(q * 1.7 - vec2(t * 0.009, 0.0));
    float n2 = fbm(uv * 0.9 + vec2(-t * 0.005, t * 0.011));
    float n3 = fbm(uv * 2.4 + vec2(t * 0.018, -t * 0.016));
    vec3 c = vec3(0.0);
    c += vec3(0.32, 0.14, 0.55) * pow(max(n1, 0.0), 2.0) * 0.9;
    c += vec3(0.06, 0.26, 0.60) * pow(max(n2, 0.0), 2.0) * 0.5;
    c += vec3(0.03, 0.52, 0.52) * pow(max(n3, 0.0), 2.4) * 0.4;
    return c;
}

// One parallax layer of the star field.
vec3 starLayer(vec2 uv, float density, float speed, float t)
{
    vec2 g = floor(uv);
    vec2 f = fract(uv) - 0.5;
    float h = hash(g);
    float star = step(1.0 - density, h);
    if (star < 0.5)
        return vec3(0.0);
    float tw = 0.55 + 0.45 * sin(t * speed + h * 6.2831);
    float d = length(f);
    float body = smoothstep(0.055, 0.0, d) * tw;
    float bright = step(0.993, h);
    float flare = smoothstep(0.012, 0.0, abs(f.x)) * smoothstep(0.06, 0.0, abs(f.y))
                + smoothstep(0.012, 0.0, abs(f.y)) * smoothstep(0.06, 0.0, abs(f.x));
    return vec3(body) + vec3(bright * flare * 0.9);
}

// A cluster: the sun with its windows as the orbiting worlds.
vec3 solarSystem(vec2 uv, vec2 c, float members, float beat, float t)
{
    vec3 col = vec3(0.0);
    float d = length(uv - c);
    col += vec3(1.0, 0.62, 0.25) * 0.5 * exp(-d / 95.0) * (0.75 + 0.25 * beat);
    col += vec3(1.0, 0.88, 0.62) * smoothstep(9.0, 8.0, d);
    col += vec3(1.0, 0.80, 0.55) * exp(-d * d / (20.0 * 20.0));
    int n = int(clamp(members, 1.0, 9.0));
    for (int i = 0; i < 9; i++) {
        if (i >= n)
            break;
        float radius = 36.0 + float(i) * 26.0;
        float ang = t * (0.30 + 0.08 * float(i)) + float(i) * 2.094 + beat * 0.6;
        vec2 pos = c + vec2(cos(ang), sin(ang) * 0.55) * radius;
        float rr = length((uv - c) / vec2(radius, radius * 0.55));
        col += vec3(0.5, 0.7, 1.0) * smoothstep(0.035, 0.0, abs(rr - 1.0)) * 0.5 / (radius * 0.09 + 1.0);
        float pd = length(uv - pos);
        col += vec3(0.45, 0.65, 1.0) * exp(-pd * pd / (7.0 * 7.0)) * 0.6;
        col += vec3(0.9, 0.95, 1.0) * smoothstep(2.2, 1.8, pd);
    }
    return col;
}

// The comet riding the day-trail.
vec3 comet(vec2 uv, float t)
{
    if (iCanvasTrailCount < 2)
        return vec3(0.0);
    float total = float(iCanvasTrailCount - 1);
    float ft = fract(t * 0.09) * total;
    int i0 = int(floor(ft));
    int i1 = min(i0 + 1, iCanvasTrailCount - 1);
    vec2 head = mix(iCanvasTrail[i0], iCanvasTrail[i1], fract(ft));
    float d = length(uv - head);
    vec3 col = vec3(1.0, 0.72, 0.38) * exp(-d * d / (14.0 * 14.0)) * 0.9;
    for (int k = 1; k <= 7; k++) {
        int idx = i0 - k;
        if (idx < 0)
            break;
        float fade = 1.0 - float(k) / 8.0;
        float td = length(uv - iCanvasTrail[idx]);
        col += vec3(0.4, 0.7, 1.0) * exp(-td * td / (15.0 * 15.0)) * 0.3 * fade;
    }
    return col;
}

// The real windows: the pale lights at the glass's edge.
vec3 windowLights(vec2 uv, vec2 cs)
{
    vec3 col = vec3(0.0);
    for (int i = 0; i < iWindowCount && i < 16; i++) {
        vec4 w = iWindowRects[i];
        vec2 c = vec2((w.x + w.z * 0.5) * cs.x, (iCanvasSize.y - (w.y + w.w * 0.5)) * cs.y);
        float side = max(w.z, w.w);
        float d = length(uv - c);
        col += vec3(0.30, 0.45, 0.75) * exp(-d * d / (side * side * 0.16)) * 0.28;
    }
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord;
    vec2 m = iMouse.xy;
    vec2 cs = (iCanvasSize.x > 1.0) ? res / iCanvasSize : vec2(1.0);
    float t = iTime;

    vec3 bg = (iCanvasBackground == vec3(0.0)) ? vec3(0.028, 0.033, 0.06) : iCanvasBackground;
    vec3 col = bg * 0.5;

    col += nebula(uv * 0.8, t) * 1.1;

    vec2 pm = (m - res * 0.5) * 0.03;
    col += starLayer(uv + pm * 0.4, 0.4, 0.8, t);
    col += starLayer(uv * 0.6 + pm, 0.6, 0.5, t);
    col += starLayer(uv * 1.7 - pm * 0.5, 0.13, 1.9, t);

    for (int i = 0; i < 16; i++) {
        if (i >= iCanvasClusterCount)
            break;
        vec4 cl = iCanvasClusters[i];
        vec2 c = vec2(cl.x * cs.x, (iCanvasSize.y - cl.y) * cs.y);
        float beat = 0.55 + 0.45 * sin(t * 0.5 + float(i) * 2.399);
        col += solarSystem(uv, c, cl.z, beat, t);
    }

    col += comet(uv, t);

    col += windowLights(uv, cs);

    col += vec3(0.35, 0.55, 1.0) * exp(-dot(uv - m, uv - m) / (32.0 * 32.0)) * 0.30;

    col *= 0.96 + 0.04 * sin(t * 0.35);

    fragColor = vec4(col, 1.0);
}

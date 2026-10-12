// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026 Ritwick Verma
// The plane's true-sphere bend: the world layer's picture read as the
// surface of a sphere the screen is a slice of. Each pixel samples the
// surface at its own arc distance from the sphere's centre - the radius
// times asin(rp / radius) - so the content curves away toward the rim in
// every direction and no axis stays straight. The pixel offsets carry the
// screen's own aspect, so the sphere is round whatever the screen's shape;
// radius is the silhouette radius in pixels, driven by the zoom. The caller
// gates the pass, so at 1:1 nothing of this runs and the plane is flat.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float viewW;
    float viewH;
    float radius;
};

layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 p = (qt_TexCoord0 - vec2(0.5)) * vec2(viewW, viewH);
    float rp = length(p);
    // rp at the centre, the arc toward the rim: never less than rp, so the
    // picture recedes under itself exactly as a sphere's surface does.
    float s = radius * asin(clamp(rp / radius, 0.0, 1.0));
    vec2 uv = vec2(0.5) + (p / max(rp, 1e-4)) * (s / vec2(viewW, viewH));
    fragColor = texture(src, clamp(uv, vec2(0.0), vec2(1.0))) * qt_Opacity;
}

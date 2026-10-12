// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026 Ritwick Verma
// The plane's barrel bend: the sphere pass the world layer drives at zoom-out.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float bend;
};
layout(binding = 1) uniform sampler2D src;
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 c = uv - vec2(0.5, 0.5);
    uv.y += bend * (c.x * c.x - 0.0833);
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    fragColor = texture(src, uv) * qt_Opacity;
}

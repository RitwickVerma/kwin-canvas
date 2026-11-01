// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The blur behind a window's thumbnail, where the blur effect blurs behind the window on the
// desktop (a thumbnail is drawn past KWin's effects, so a translucent window showed the plane
// sharp behind it). wall is the screen's wallpaper, blurred once for the whole screen; this
// samples the part of it behind the patch, cuts the window's corners as corners.frag does, and
// adds the blur effect's grain. Compiled with `make shaders` into blur.frag.qsb.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 patchRect;  // this patch in its window, as fractions of the window: x, y, w, h
    vec4 area;       // the window on the screen, as fractions of the screen: x, y, w, h
    vec2 itemSize;   // the window's size, in its own pixels
    float radius;    // the window's corner radius, in the same pixels
    float squircle;  // 0 circle .. 1 superellipse
    float grain;     // the noise's amplitude, 0 .. 1
};
layout(binding = 1) uniform sampler2D wall;

void main()
{
    vec2 w = patchRect.xy + qt_TexCoord0 * patchRect.zw;
    vec4 c = texture(wall, area.xy + w * area.zw);
    float a = 1.0;
    if (radius > 0.0) {
        vec2 q = abs(w * itemSize - 0.5 * itemSize) - (0.5 * itemSize - vec2(radius));
        if (q.x > 0.0 && q.y > 0.0) {
            vec2 d = q / radius;
            float circle = length(d);
            vec2 d2 = d * d;
            float superellipse = sqrt(sqrt(d2.x * d2.x + d2.y * d2.y));
            a = clamp(0.5 - (mix(circle, superellipse, squircle) - 1.0) * radius, 0.0, 1.0);
        }
    }
    // Grain fixed to the screen's pixels, as the blur effect's noise texture is.
    float n = fract(sin(dot(floor(gl_FragCoord.xy), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    c.rgb = clamp(c.rgb + vec3(n * grain) * c.a, 0.0, 1.0);
    fragColor = c * (a * qt_Opacity);
}

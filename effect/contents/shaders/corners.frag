// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// A window's thumbnail with rounded corners, so a window the Rounded Corners effect shapes on the
// desktop keeps its shape on the canvas (a thumbnail is drawn from the window's surface, past
// KWin's effects). The corner is a blend of a circle and a superellipse of power 4: squircle 0 is
// a circle, 1 the superellipse. Compiled with `make shaders` into corners.frag.qsb.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;   // the item's size, in its own pixels
    float radius;    // the corner radius, in the same pixels; 0 draws the thumbnail as it is
    float squircle;  // 0 circle .. 1 superellipse
};
layout(binding = 1) uniform sampler2D source;

void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    float a = 1.0;
    if (radius > 0.0) {
        // Distance past the start of the corner, per axis; inside the corner square both are > 0.
        vec2 q = abs(qt_TexCoord0 * itemSize - 0.5 * itemSize) - (0.5 * itemSize - vec2(radius));
        if (q.x > 0.0 && q.y > 0.0) {
            vec2 d = q / radius;
            float circle = length(d);
            vec2 d2 = d * d;
            float superellipse = sqrt(sqrt(d2.x * d2.x + d2.y * d2.y));
            float r = mix(circle, superellipse, squircle);
            // About a pixel of antialiasing across the edge.
            a = clamp(0.5 - (r - 1.0) * radius, 0.0, 1.0);
        }
    }
    fragColor = c * (a * qt_Opacity);
}

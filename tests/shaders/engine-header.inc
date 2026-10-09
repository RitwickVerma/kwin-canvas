// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// The shader wallpaper engine's shared header, reconstructed for the
// compile check (tools/lint-shader.sh). The engine concatenates this,
// the shader and the mainImage wrapper; the iCanvas* uniforms are
// deliberately absent - the canvas shaders declare their own.
#version 330 core
in vec2 fragCoord;
in vec2 qt_TexCoord0;
out vec4 fragColor;

uniform vec3 iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform float iFrameRate;
uniform int iFrame;
uniform vec4 iMouse;
uniform vec2 iMousePrev;
uniform vec4 iDate;
uniform float iSampleRate;
uniform vec3 iChannelResolution[4];
uniform float iChannelTime[4];

uniform sampler2D iChannel0;
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;

// Window tracking (for window-reactive effects)
uniform int iWindowCount;
uniform vec4 iWindowRects[16];
uniform vec4 iWindowRectsPrev[16];
uniform vec2 iWindowVelocities[16];

// kwin-canvas integration: the canvas shaders declare their own
// iCanvas* uniforms in their own source; the engine only uploads them.

// Multi-monitor (experimental). All zero when the feature is off.
uniform vec2 iScreenOffset;
uniform int  iScreenIndex;
uniform int  iScreenCount;

// Per-virtual-desktop (experimental). Zero / 1 / 0 by default.
uniform int   iVirtualDesktop;
uniform int   iVirtualDesktopCount;
uniform float iVirtualDesktopAnim;

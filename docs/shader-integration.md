# The shader channel

The canvas publishes its remembered state so a shader wallpaper can draw the
floor the plane actually lives on: the cluster lights where the rooms sit,
and the day-trail as a ribbon of light. The rendering half is not ours - it
is the [shader wallpaper plugin](https://github.com/y4my4my4m/kde-shader-wallpaper)
(Shadertoy conventions, `.frag` files) - and the seam needs nothing special:
the overworld already shows the desktop's own wallpaper as its floor, so
whatever wallpaper you run is the same picture at 1:1.

## The channel

At every commit the effect pushes four lines to the pass-through plugin:

```
view=X,Y
grid=BASE,FACTOR,OCTAVES,R,G,B,BR,BG,BB   (the ground's own knobs)
cluster=CX,CY,N        (one per cluster, up to 16)
trail=X1,Y1,X2,Y2,...  (the day-trail's last 64 samples, oldest first)
```

The view, the grid and the clusters are in plane coordinates; the plugin
writes `$XDG_CONFIG_HOME/kwin-canvas-state.txt`, projecting the clusters
and the trail to screen pixels (`x - viewX`) because a fragment shader
works in pixels and should not need camera math, and passing the grid
through raw (the shader scrolls it with the view itself). The file looks
like:

```
view=-600,0
grid=64,8,4,127,143,176,28,31,38
cluster=1560,542,5
trail=1560,540,960,540
```

The view line stays in plane coordinates (it is state, not a position).

## The shader side

The starter is `shaders/canvas-floor.frag`: a deep calm floor, a soft bloom
and a warm core at every cluster (the glow grows with the member count), and
the trail as a faint ribbon. Drop it into the plugin's `Shaders/` directory
and pick it in the gallery - with the fork absent it still compiles and the
uniforms read zero, so the floor is simply the grid on the background.

The engine's fork adds one uniform block, filled from the state file each
second:

```glsl
uniform int iCanvasClusterCount;   // up to 16
uniform vec4 iCanvasClusters[16];  // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;     // up to 64
uniform vec2 iCanvasTrail[64];     // the screen path points, oldest first
uniform float iCanvasGridBase;     // the minor grid spacing, plane pixels
uniform float iCanvasGridFactor;   // each octave is this many times coarser
uniform float iCanvasGridOctaves;  // the octaves drawn
uniform vec3 iCanvasGridColor;     // the line colour, 0..1
uniform vec3 iCanvasBackground;    // the plane's ground, 0..1
uniform vec2 iCanvasView;          // the plane coordinate of the screen's top-left
```

(The plugin is GPL-3.0 and lives outside this tree, so the fork is its own
project or an upstream pull request - the contract above is all the canvas
promises.)

### The fork's rules (what the compile check enforces)

- **The engine's header must NOT declare the iCanvas uniforms.** The engine
  concatenates its shared header + the shader + the `mainImage` wrapper; if
  a fork adds the uniform block to the header, every canvas shader that also
  declares its own fails to compile with the duplicate-declaration error.
  The shaders declare their own uniforms; the engine only uploads them.
- **The engine uploads the uniforms** (the `setUniformValue` family) at the
  render; a fork that adds the uploads must mirror them from the engine to
  the renderer thread (the `synchronize` step), the window-tracking pattern.
- **After reinstalling the engine, relaunch System Settings** (and the
  plasmashell): the running processes hold the old plugin in memory.
- The engine's wallpaper has a boot quirk (the `devicePixelRatio` of an
  undefined screen in its first frames); it is the engine's, not the
  channel's.

The tree carries the contract as a compile check: `make lint-shader`
concatenates `tests/shaders/engine-header.inc` (the engine's header, without
the iCanvas block) with each `shaders/*.frag` and the wrapper, and compiles
the result with `glslangValidator` - a uniform declared twice, or any GLSL
break, fails the lint instead of a user's desktop.

## The state itself

The channel carries what the plane remembers at rest: the saved view (where
the eye left the location), the clusters (the rooms, with their sizes), and
the day-trail (where the screen has been this session). It updates at every
commit, so the floor settles when you step out and moves when you rearrange.

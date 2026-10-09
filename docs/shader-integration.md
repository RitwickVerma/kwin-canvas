# The shader channel

The canvas publishes its remembered state so a shader wallpaper can draw the
floor the plane actually lives on: the cluster lights where the rooms sit,
and the day-trail as a ribbon of light. The rendering half is not ours - it
is the [shader wallpaper plugin](https://github.com/y4my4my4m/kde-shader-wallpaper)
(Shadertoy conventions, `.frag` files) - and the seam needs nothing special:
the overworld already shows the desktop's own wallpaper as its floor, so
whatever wallpaper you run is the same picture at 1:1.

## The channel

At every commit the effect pushes three lines to the pass-through plugin:

```
view=X,Y
cluster=CX,CY,N        (one per cluster, up to 16)
trail=X1,Y1,X2,Y2,...  (the day-trail's last 64 samples, oldest first)
```

Everything is in plane coordinates. The plugin writes
`$XDG_CONFIG_HOME/kwin-canvas-state.txt`, projecting the clusters and the
trail to screen pixels (`x - viewX`), because a fragment shader works in
pixels and should not need camera math. The file looks like:

```
view=-600,0
cluster=1560,542,5
trail=1560,540,960,540
```

The view line stays in plane coordinates (it is state, not a position).

## The shader side

The starter is `shaders/canvas-floor.frag`: a deep calm floor, a soft bloom
and a warm core at every cluster (the glow grows with the member count), and
the trail as a faint ribbon. Drop it into the plugin's `Shaders/` directory
and pick it in the gallery - with the fork absent it still compiles and the
uniforms read zero, so the floor is simply the calm.

The engine's fork adds one uniform block, filled from the state file each
frame:

```glsl
uniform int iCanvasClusterCount;   // up to 16
uniform vec4 iCanvasClusters[16];  // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;     // up to 64
uniform vec2 iCanvasTrail[64];     // the screen path points, oldest first
```

(The plugin is GPL-3.0 and lives outside this tree, so the fork is its own
project or an upstream pull request - the contract above is all the canvas
promises.)

## The state itself

The channel carries what the plane remembers at rest: the saved view (where
the eye left the location), the clusters (the rooms, with their sizes), and
the day-trail (where the screen has been this session). It updates at every
commit, so the floor settles when you step out and moves when you rearrange.

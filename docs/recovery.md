# Recovering a deleted activity

Every frame tag on the open canvas carries a remove button — the red
`edit-delete` `IconButton` in `FrameTag` (`effect/contents/ui/main.qml`), shown
while more than one activity exists. It removes *any* activity, not only the
ones `addActivity()` made, and it asks nothing. Deleting the wrong one costs a
uuid and one config line; the data behind it is still on disk. This is how to
put it back.

## What a delete does

- `kactivitymanagerd` drops the `uuid=Name` line from `[activities]` in
  `~/.config/kactivitymanagerdrc` and writes the file out again.
- KWin clears the uuid from every window's `activities`: those windows become
  "on all activities". They do not move, close, or lose geometry.
- plasmashell deletes that activity's desktop containment (its wallpaper and
  folder view). Panels are global — containments with an empty `activityId` —
  so the panel layout stays.
- Nothing touches the score database. Resources, scores and events are keyed
  by the uuid and are left in
  `~/.local/share/kactivitymanagerd/resources/database`.

## What survives

| Data | Where | Survives |
|---|---|---|
| activity uuid and name | `~/.config/kactivitymanagerdrc`, `[activities]`, `uuid=Name` | no — the daemon rewrites the file |
| resource scores and events (used files, favourites) | `~/.local/share/kactivitymanagerd/resources/database` | yes |
| favourites per activity | `~/.config/kactivitymanagerd-statsrc` | yes |
| window positions remembered per activity | `rememberwindowpositions_windows` in `~/.config/kde.org/kwin.conf` | yes, with the uuid inside |
| window-to-activity assignment | the window, not a file | no — put it back by hand |
| per-activity desktop containment | `plasma-org.kde.plasma.desktop-appletsrc`, `activityId=` | no — plasmashell makes a fresh one |
| panels, wallpaper plugin, applets | the same file, empty `activityId` | yes |
| a hidden frame (`HiddenFrames`) | `kwinrc`, `[Effect-kwin-canvas]` | yes |

## Check first

The uuid is the key to everything. Without it there is nothing to restore to.

```bash
DB=~/.local/share/kactivitymanagerd/resources/database
sqlite3 -readonly "$DB" "select usedActivity, count(*) from ResourceScoreCache
                         group by usedActivity order by 2 desc limit 5;"
```

A row with a healthy count whose uuid is *not* in `kactivitymanagerdrc` is
exactly the case this page is for. The same query on `ResourceEvent` and
`ResourceLink` shows the rest of that activity's history. Take the counts
while you are here: they are the numbers to match after the restore.

## The recipe

Back up first, because step 2 edits a file the daemon owns:

```bash
mkdir -p ~/activity-recovery.bak
cp ~/.config/kactivitymanagerdrc ~/.config/kactivitymanagerd-statsrc \
   ~/.config/kde.org/kwin.conf ~/.config/kwinrc \
   ~/.config/plasma-org.kde.plasma.desktop-appletsrc ~/activity-recovery.bak/
```

1. **Stop the daemon**, so it cannot write over the file on its way out:

   ```bash
   systemctl --user stop plasma-kactivitymanagerd.service
   ```

2. **Write the activity back**, with its original uuid and name:

   ```bash
   kwriteconfig6 --file kactivitymanagerdrc --group activities \
                 --key a997dc53-dfd3-4f66-9260-911e5d00443d Default
   cat ~/.config/kactivitymanagerdrc
   ```

   The key is the uuid, the value is the name, and nothing else goes in this
   group. Any name will do — the uuid is what the scores and the saved window
   positions are keyed to.

3. **Start the daemon and check it read the file**:

   ```bash
   systemctl --user start plasma-kactivitymanagerd.service
   qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
          org.kde.ActivityManager.Activities.ListActivities
   qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
          org.kde.ActivityManager.Activities.ActivityName a997dc53-dfd3-4f66-9260-911e5d00443d
   ```

   `ListActivities` must list the uuid and `ActivityName` must return the name
   written. KWin follows the daemon, so its activity list and `currentActivity`
   update when the daemon comes back — no KWin restart, and the canvas picks it
   up on its next open.

4. **Make it the current activity**:

   ```bash
   qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
          org.kde.ActivityManager.Activities.SetCurrentActivity a997dc53-dfd3-4f66-9260-911e5d00443d
   ```

5. **Put the windows back.** They are on all activities now. One KWin script
   does the whole set:

   ```js
   var target = "a997dc53-dfd3-4f66-9260-911e5d00443d";
   var ws = workspace.windowList();
   for (var i = 0; i < ws.length; i++) {
       var w = ws[i];
       if (!w.normalWindow) continue;
       print("restore " + w.caption + " " + JSON.stringify(w.activities));
       w.activities = [target];
   }
   ```

   ```bash
   id=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/restore-activities.js restore)
   qdbus6 org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run
   qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript restore
   ```

   By hand instead: the title bar menu of each window → *Activities*. New
   windows need nothing: `rememberwindowpositions` carries the uuid in its
   saved table and returns a window to the activity it was last on.

6. **Look at the place.** The restored activity's desktop containment is new,
   so its wallpaper and desktop icons are the defaults again. Its windows are
   where they were, because their positions never changed.

## The activity that replaced it

The canvas names a new activity `"Activity " + (activities + 1)`, so a
mis-click can leave an empty "Activity 2" behind. It is harmless and it gets a
frame of its own. Remove it from System Settings → Activities — not with the
tag button that started this.

## Prevention

Left as it is, on purpose: the tag button removes any activity, and the only
guard is that the last one cannot be removed. If it bites again, the cheap
fixes, in the order they change the most:

- Refuse the remove button while the activity has windows on it
  (`Window.activities`).
- Remember the ids `addActivity()` created and offer removal only for those.
- Ask before removing, and name canvas-made activities `Canvas N` so they read
  as the canvas's own.

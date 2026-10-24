/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    The canvas's scene tree, loaded by main.qml through a version-stamped
    URL: bumping the HotRev knob (make hot) makes the QML engine compile
    this file afresh, so a UI edit lands in the running session without a
    re-login. The logic lives on the effect itself, in main.qml.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kwin as KWin
import org.kde.plasma.components as PC3


Item {
    component Grip : Item {
        id: grip
        required property Item viewItem
        property int cursor: Qt.ArrowCursor
        property bool tappable: false
        // A click with a few pixels of hand noise must stay a click: the drag
        // does not move anything until the hand has travelled this far.
        property real dragDead: 0
        // Whether the hand has genuinely dragged: past the dead zone. The
        // weight follows this, so a sloppy click never lifts a window.
        readonly property bool moving: Math.hypot(total.x, total.y) >= grip.dragDead
        // Off during a grasp: a control the eye cannot see (a frame edge band)
        // must not take a drag the hand meant for the plane. Window bodies and
        // resize grips stay live - moving and resizing windows is what a grasp
        // is for.
        property bool holdOff: false
        property alias buttons: gripDrag.acceptedButtons
        readonly property bool hovered: gripHover.hovered
        readonly property bool active: gripDrag.active
        readonly property point total: gripDrag.activeTranslation
        signal dragStarted()
        signal dragged(real dx, real dy)
        signal dragEnded()
        signal tapped(int count, int modifiers, int button)

        HoverHandler {
            id: gripHover
            enabled: !grip.viewItem.spaceHeld && !(grip.holdOff && effect.grasp) && !effect.seamPark && !effect.chromeHover
            cursorShape: gripDrag.active && grip.cursor === Qt.ArrowCursor ? Qt.ClosedHandCursor : grip.cursor
            onHoveredChanged: grip.viewItem.hoverCount += hovered ? 1 : -1
            Component.onDestruction: if (hovered) grip.viewItem.hoverCount -= 1
        }
        DragHandler {
            id: gripDrag
            target: null
            enabled: !grip.viewItem.spaceHeld && !(grip.holdOff && effect.grasp) && !effect.chromeHover
            acceptedButtons: effect.gripButtons
            // The portal buttons drag a control exactly as the left button
            // does; where they land on the ground instead they pan (panDrag).
            // A drag of one of them is also the canvas being navigated for as
            // long as it lasts - the view counts it into navHeld, which runs
            // the edge pan and holds the screen edges off - because a
            // TapHandler cannot: a drag past the tap threshold cancels its
            // press, and with it the record of the button being down.
            readonly property bool portal: active && (centroid.pressedButtons & effect.portalButtons) !== 0
            onPortalChanged: grip.viewItem.portalDrags += portal ? 1 : -1
            Component.onDestruction: if (portal) grip.viewItem.portalDrags -= 1
            property point last: Qt.point(0, 0)
            onActiveChanged: {
                effect.sceneGestures += active ? 1 : -1;
                effect.noteGesture(true);
                last = Qt.point(0, 0);
                if (active) grip.dragStarted(); else grip.dragEnded();
            }
            onActiveTranslationChanged: {
                const t = activeTranslation;
                if (grip.dragDead > 0 && Math.hypot(t.x, t.y) < grip.dragDead) return;
                grip.dragged(t.x - last.x, t.y - last.y);
                last = t;
            }
        }
        TapHandler {
            enabled: grip.tappable && !grip.viewItem.spaceHeld && !effect.chromeHover
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onTapped: (eventPoint, button) => grip.tapped(tapCount, point.modifiers, button)
        }
    }

    // The menus' background: opaque, because the Plasma style's translucent
    // menu assumes the desktop blur behind it and the canvas provides none.
    component MenuBackground : Rectangle {
        implicitWidth: 220
        implicitHeight: 24
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
    }

    component IconButton : Rectangle {
        id: button
        required property Item viewItem
        property string icon: ""
        // A short text drawn in place of the icon (the monitor chips' numbers).
        property string label: ""
        property color hoverColor: "#60ffffff"
        signal clicked()
        width: 18
        height: 18
        radius: 3
        color: buttonHover.hovered ? hoverColor : "#30ffffff"
        Kirigami.Icon {
            visible: button.label === ""
            anchors.fill: parent
            anchors.margins: 2
            source: button.icon
            color: "#ffffff"
        }
        Text {
            visible: button.label !== ""
            anchors.centerIn: parent
            text: button.label
            color: "#ffffff"
            font.pixelSize: 11
            font.bold: true
        }
        HoverHandler {
            id: buttonHover
            enabled: !effect.chromeHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: button.viewItem.hoverCount += hovered ? 1 : -1
            Component.onDestruction: if (hovered) button.viewItem.hoverCount -= 1
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            enabled: !effect.chromeHover
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: button.clicked()
        }
    }

    // The activity's name tag: a Grip for its frame group, plus the activity
    // controls: hide or show this frame, add an activity, remove this one.
    component FrameTag : Grip {
        id: tag
        required property string activity
        required property int activityIndex
        required property var screen
        readonly property bool current: activity === effect.currentActivity
        readonly property bool hidden: effect.isHidden(activity, screen)
        // With several monitors the activity wears one tag, on the monitor the chrome is on,
        // and no output names: the monitors are the cameras, not things on the plane. A small
        // numbered chip per monitor shows or hides that monitor's frame.
        readonly property bool multi: { effect.screensRev; return KWin.Workspace.screens.length > 1; }
        readonly property bool mine: !multi || screen === (effect.chromeScr || effect.primaryScreen)
        readonly property color accent: effect.palette[activityIndex % effect.palette.length]
        cursor: Qt.SizeAllCursor
        width: tagRow.implicitWidth + 12
        height: tagRow.implicitHeight + 6
        opacity: effect.chromeFade * effect.skinReveal
        onDragStarted: effect.targetRaw = null
        onDragged: (dx, dy) => effect.dragTarget(activity, dx, dy)

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: tag.accent
            opacity: tag.hidden ? 0.45 : (tag.current ? 1 : 0.8)
        }
        Row {
            id: tagRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tag.multi ? effect.labelOf(tag.activity) : effect.labelOf(tag.activity) + " \u00b7 " + tag.screen.name + "  " + tag.screen.geometry.width + "x" + tag.screen.geometry.height
                color: effect.textOn(tag.accent)
                font.pixelSize: 12
                font.bold: true
            }
            IconButton {
                visible: !tag.multi
                anchors.verticalCenter: parent.verticalCenter
                viewItem: tag.viewItem
                icon: tag.hidden ? "view-hidden" : "view-visible"
                onClicked: effect.setHidden(tag.activity, tag.screen, !tag.hidden)
            }
            Repeater {
                model: tag.multi ? KWin.Workspace.screens : []
                delegate: IconButton {
                    required property int index
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    viewItem: tag.viewItem
                    label: String(index + 1)
                    opacity: effect.isHidden(tag.activity, modelData) ? 0.4 : 1
                    onClicked: effect.setHidden(tag.activity, modelData, !effect.isHidden(tag.activity, modelData))
                }
            }
            IconButton {
                visible: tag.activity !== ""
                anchors.verticalCenter: parent.verticalCenter
                viewItem: tag.viewItem
                icon: "list-add"
                onClicked: effect.addActivity()
            }
            IconButton {
                visible: effect.activityIds.length > 1
                anchors.verticalCenter: parent.verticalCenter
                viewItem: tag.viewItem
                icon: "edit-delete"
                hoverColor: "#80ff4040"
                onClicked: effect.removeActivity(tag.activity)
            }
        }
    }

        // ---- per-screen view ---------------------------------------------------
    // The scene tree lives in ui.qml, loaded through a version-stamped
    // URL. Bumping the HotRev knob (make hot) gives the URL a new
    // revision, which makes the QML engine compile the file afresh
    // instead of reusing its in-memory component - the only KWin-side
    // way to pick up a QML edit without restarting the compositor.
    // The logic above this delegate lives on the effect itself and is
    // unaffected by the bump.
    // The loaded scene must own the keyboard focus: KWin delivers the
    // scene's keys to the QuickView's active focus item, and a static
    // focus binding inside a loaded item never takes it - the split's
    // own regression. The force is the only form that registers.
    Component.onCompleted: { console.log("kwin-canvas ui: loaded"); if (view.chromeWanted) chromeLoader.active = true; view.forceActiveFocus(); view.checkWallpaper(); }
        id: view
        readonly property var screen: KWin.SceneView.screen
        readonly property rect sg: KWin.SceneView.screen.geometry
        // The whole scene fades against the real desktop at every seam, but
        // only as a fade through black: KWin composites the canvas's
        // framebuffer over black, not over the desktop, so this fade masks
        // the zoom jump of a close from a zoomed-out overworld and nothing
        // else. The 1:1 seams never fade - the canvas and the desktop are
        // the same picture there, and an instant swap is invisible.
        opacity: effect.sceneFade
        property bool spaceHeld: false
        // Separate cameras: a monitor that is not the one the overview is open on shows its
        // desk as it really is, the windows at their real places over the wallpaper, and
        // takes no input of its own. (The effect's flags are read guarded: a hot reload swaps
        // this file and not the effect's own.)
        readonly property bool replica: effect.separate === true && effect.camScreen !== null && effect.camScreen !== undefined && screen !== effect.camScreen && effect.visible
        // Whether KWin.DesktopBackground can draw the desktop's wallpaper.
        // It can for Plasma's own picture wallpapers; for a video or a scene
        // (Wallpaper Engine, waywallen) it paints solid black, and the
        // frames carried that black over the real desktop: every fly showed
        // it, since the frames move and the black moves with them. Where it
        // cannot draw, the layers step aside and the compositor's own
        // desktop shows through, as it does at 1:1 between the frames.
        // False until plasmashell has answered, and the scene is rebuilt on
        // every open: starting optimistic let the frames paint KWin's black
        // over a video wallpaper for the frame or two before the reply
        // (a recording showed one fully black frame per open). Unknown shows
        // the desktop window, which for a picture wallpaper is the same
        // picture, and only a known picture wallpaper hands over to the
        // frames' own item.
        // The effect's own answer when it has one (it outlives the scene, so
        // it is known before the first frame); this scene's own query only
        // for an effect compiled before it had one (a hot reload swaps this
        // file and not main.qml).
        property bool queried: false
        property bool wallpaperDrawable: effect.wallpaperPicture !== undefined ? effect.wallpaperPicture : queried
        function checkWallpaper() {
            wallpaperQuery.arguments = ["let r = ''; const ds = desktops(); for (let i = 0; i < ds.length; ++i) { r += (ds[i].wallpaperPlugin || '') + '|'; } print(r);"];
            wallpaperQuery.call();
        }
        KWin.DBusCall {
            id: wallpaperQuery
            service: "org.kde.plasmashell"
            path: "/PlasmaShell"
            dbusInterface: "org.kde.PlasmaShell"
            method: "evaluateScript"
            onFinished: (result) => {
                const known = ["org.kde.image", "org.kde.slideshow", "org.kde.color", "org.kde.potd", "kwin-canvas-ground"];
                const plugins = String(result || "").split("|").filter(function (p) { return p.trim().length > 0; });
                // An empty answer says nothing: keep what was last known.
                if (plugins.length === 0) return;
                view.queried = plugins.every(function (p) { return known.indexOf(p.trim()) !== -1; });
                console.log("kwin-canvas ui: wallpaper " + plugins.join(",") + " drawable=" + view.wallpaperDrawable + " effect=" + effect.wallpaperPicture);
            }
        }
        Connections {
            target: effect
            function onVisibleChanged() { if (effect.visible) view.checkWallpaper(); }
        }
        // Number of grips and buttons under the pointer. The pan handler
        // refuses a left press while this is non-zero, so a drag that starts
        // on one of them acts on it instead of racing the pan.
        property int hoverCount: 0
        readonly property bool overControl: hoverCount > 0
        // Drags a portal button is holding, on any control of this screen
        // (a window body, a resize grip, a frame tag or edge). A press of one
        // is a navigation the moment it lands, but the tracker that knows that
        // is a TapHandler and a drag cancels it, so the drags count here too.
        property int portalDrags: 0
        // A pan button held down (PanHold), the canvas modifier (CanvasHold),
        // or the middle button: this screen is being navigated.
        // Four sources, one per stretch of the gesture: the
        // tap tracker knows the press the moment it lands and the release the
        // moment it lifts, whether or not the pointer ever moves — a pointer
        // parked at a screen edge is the whole gesture — the pan drag is
        // active for the stretch where the tracker has handed the gesture to
        // the drag, a drag on a control counts itself (portalDrags) for the
        // stretch where the drag has cancelled the tracker, and the canvas
        // modifier is down for its whole hold, during a grasp and in the open
        // overworld alike. None outlives the button.
        readonly property bool navHeld: navHold.pressed || panDrag.active || portalDrags > 0 || effect.canvasHold
        onNavHeldChanged: effect.navHolds += navHeld ? 1 : -1
        Component.onDestruction: if (navHeld) effect.navHolds -= 1
        // Input is live while the overworld is open, and while a grasp holds
        // the canvas quietly at 1:1 - a slide without a grasp stays inert,
        // which is what keeps a slide a brief animation and nothing more.
        enabled: !replica && (!effect.quiet || effect.grasp || effect.switcherActive)
        focus: true
        Connections {
            target: effect
            function onVisibleChanged() { if (effect.visible) { view.hoverCount = 0; view.spaceHeld = false; } }
            // The switcher asks for the keyboard focus through a property
            // bump: the effect's own scope cannot name a view delegate.
            function onSwitcherFocusReqChanged() { view.focus = true; }
        }

        // The plane's base: opaque, so nothing shows through to the real
        // desktop under the effect wherever no wallpaper reaches (grid mode,
        // or a blur radius of 0 with the layer hidden). Below everything.
        Rectangle {
            anchors.fill: parent
            z: -100
            color: effect.configuration.Background
            // The wallpaper mode is a true passthrough: the effect draws no
            // base there, so the real desktop (wallpaper included) shows
            // through the plane untouched - zero copies, nothing to grey it.
            visible: effect.backdropMode() !== "wallpaper"
        }

        // The wallpaper where DesktopBackground cannot draw it: the desktop's
        // own window, as the compositor has it, filling the view. Shown in
        // every state the canvas is up, quiet slides included (the frames
        // move in a fly; this does not), and only for a wallpaper that is
        // not a picture, so a picture wallpaper is exactly as before. The
        // window is looked up here, not through a binding: the stacking
        // order does not notify, and a hot reload swaps this file but not
        // the effect's own.
        KWin.WindowThumbnail {
            id: deskThumb
            anchors.fill: parent
            z: -91
            property var desk: null
            client: desk
            visible: effect.visible && !view.wallpaperDrawable && client !== null
            function refresh() {
                const w = effect.desktopWindowFor(view.screen);
                if (w !== desk) desk = w;
            }
            Component.onCompleted: refresh()
            Connections {
                target: effect
                function onVisibleChanged() { if (effect.visible) deskThumb.refresh(); }
            }
            Connections {
                target: view
                function onWallpaperDrawableChanged() { deskThumb.refresh(); }
            }
            Timer {
                interval: 1000
                repeat: true
                running: effect.visible && !view.wallpaperDrawable
                onTriggered: deskThumb.refresh()
            }
        }

        // The wallpaper under the plane: KWin's own desktop background, drawn
        // raw - no blur, no dim, no treatment - whenever the canvas is up.
        // The scene is composited over black, not over the desktop, so
        // wherever no frame covers the view (a zoomed-out view, and a slide
        // at 1:1 that has carried its frame away: measured, up to 37% of the
        // screen black until the landing snapped to the desktop) the plane's
        // gaps would show that black. At 1:1 with the frame in place it is
        // the same picture under the frame.
        KWin.DesktopBackground {
            anchors.fill: parent
            z: -90
            visible: effect.visible && view.wallpaperDrawable
            output: view.screen
            desktop: KWin.Workspace.currentDesktop
            activity: effect.currentActivity || "default"
        }
        // The plane's items - the ground, the frame bands, the windows, the
        // tags, the web and the chips - gathered under one item. (They keep
        // their indentation across the wrapper: it is a scope, not a
        // lexical one.)
        // The desk of a monitor the overview is not open on: every window at its real place.
        Repeater {
            model: view.replica ? effect.entries : []
            delegate: KWin.WindowThumbnail {
                required property var modelData
                readonly property var e: modelData
                client: e.window
                visible: !e.window.deleted
                x: { effect.revision; return e.frameX - view.sg.x; }
                y: { effect.revision; return e.frameY - view.sg.y; }
                width: { effect.revision; return e.width; }
                height: { effect.revision; return e.height; }
            }
        }
        Item {
            anchors.fill: parent
            visible: !view.replica

        Ground {
            anchors.fill: parent
            originX: -effect.viewX * effect.zoom - view.sg.x
            originY: -effect.viewY * effect.zoom - view.sg.y
            zoom: effect.zoom
            baseSpacing: effect.configuration.GridBase
            octaveFactor: effect.configuration.GridOctaveFactor
            octaves: effect.configuration.GridOctaves
            background: effect.configuration.Background
            lineColor: effect.configuration.LineColor
            tileImage: effect.configuration.TileImage
            showLabels: effect.configuration.ShowLabels !== false
            // With the wallpaper behind it the base rect above is the ground's
            // background, and the grid draws over the wallpaper.
            drawBackground: effect.backdropMode() !== "wallpaper"
            // The 1:1 view is the desktop itself: the grid draws only when
            // the camera is zoomed out - never over the wallpaper during a
            // grasp, a hover fetch or any other flat pan.
            visible: zoom < 0.999
        }


        // Pan: left-drag on the ground, middle-drag anywhere, hold Space and
        // left-drag anywhere (Space disables every Grip and IconButton), or
        // hold a PanHold button and drag anywhere. Ground click: drop the
        // selection.
        TapHandler {
            enabled: !view.spaceHeld && !view.overControl && !effect.chromeHover
            acceptedButtons: Qt.LeftButton
            onTapped: (eventPoint, button) => { if ((point.modifiers & effect.marqueeModifiers()) === 0 && !effect.entryAtScreen(eventPoint.position.x + view.sg.x, eventPoint.position.y + view.sg.y)) effect.clearSelection(); }
        }

        // A left drag on the ground pans, or, with the add gesture's modifier
        // held, selects by rectangle. The two are told apart by the modifiers
        // the press itself carries: the keys may never reach this item
        // (pass-through hands them to the windows), and the hover events the
        // scene synthesizes between frames carry none, but every real pointer
        // event has the modifier state.
        // The hold itself, on the button alone: no motion is needed for the
        // canvas to be navigated, so a pointer parked in an edge band pans
        // while the button is down. The middle button navigates with nothing
        // configured, the way it does in the drag below, so a held middle
        // button pans at an edge and holds the Screen Edges handlers off the
        // canvas as a hold of any PanHold button does. A tap handler with no
        // policy of its own takes a passive grab for those buttons only, so
        // the left button, the window gestures and the toolbar are untouched,
        // and a release always lifts it.
        TapHandler {
            id: navHold
            acceptedButtons: effect.panHoldButtons | Qt.MiddleButton
            enabled: !effect.chromeHover
        }

        // MB5 tours the clusters wherever it fires - the grasp's hold and
        // the open overworld alike. The press is otherwise someone else's
        // (over a window in the overworld the pass-through hands it on; at
        // 1:1 it is the window's own back/forward gesture).
        TapHandler {
            acceptedButtons: effect.swapButtons
            enabled: !effect.chromeHover
            onTapped: effect.swapWindow()
        }

        DragHandler {
            id: panDrag
            target: null
            // The middle button pans from anywhere, even over a window or a
            // tag: this handler is on the screen's root item, so every press
            // lands on it. The left button and the PanHold buttons pan only on
            // the ground (or anywhere with Space held, or while this drag is
            // already going), so a press on a control is the control's - a
            // drag that starts on one acts on it instead of racing the pan, and
            // a held portal button moves the window it was pressed on rather
            // than panning under it.
            acceptedButtons: Qt.MiddleButton
                             | ((active || (!effect.chromeHover && (view.spaceHeld || !view.overControl))) ? effect.gripButtons : 0)
            cursorShape: (active || view.navHeld) ? Qt.ClosedHandCursor : (view.spaceHeld ? Qt.OpenHandCursor : Qt.ArrowCursor)
            property bool marquee: false
            property point last: Qt.point(0, 0)
            // The hand's own record of the drag: how far it travelled, when it
            // started, and when it last moved. A fling is that average velocity
            // and only if the hand was still moving at the release: a drag that
            // pauses before letting go - the way a careful placement ends - is
            // a placement, not a throw.
            property real travelX: 0
            property real travelY: 0
            property real startedAt: 0
            property real movedAt: 0
            onActiveChanged: {
                // The reset belongs to the press, not to both transitions: the
                // release needs the travel and the times the drag ended with,
                // so zeroing them first would make every fling a no-op.
                effect.sceneGestures += active ? 1 : -1;
                effect.noteGesture(true);
                if (active) {
                    last = Qt.point(0, 0);
                    travelX = 0; travelY = 0;
                    effect.camStop();
                    startedAt = Date.now();
                    movedAt = startedAt;
                    const mods = effect.marqueeModifiers();
                    marquee = !view.spaceHeld && mods !== 0 && (centroid.modifiers & mods) !== 0 && (centroid.pressedButtons & Qt.LeftButton) !== 0;
                    if (marquee) {
                        marqueeBox.x0 = centroid.pressPosition.x; marqueeBox.y0 = centroid.pressPosition.y;
                        marqueeBox.x1 = marqueeBox.x0; marqueeBox.y1 = marqueeBox.y0;
                    }
                } else if (marquee) {
                    // The centroid resets on release; the box kept the last corner.
                    marquee = false;
                    const r = marqueeBox.rect;
                    const c0 = effect.globalToCanvas(r.x + view.sg.x, r.y + view.sg.y);
                    effect.selectInRect(c0.x, c0.y, r.width / effect.zoom, r.height / effect.zoom);
                } else {
                    // Let go: carry the plane if the hand was still moving.
                    const now = Date.now();
                    if (now - movedAt <= 120) effect.camFling(travelX, travelY, now - startedAt);
                }
            }
            onActiveTranslationChanged: {
                const t = activeTranslation;
                if (marquee) {
                    marqueeBox.x1 = marqueeBox.x0 + t.x;
                    marqueeBox.y1 = marqueeBox.y0 + t.y;
                    return;
                }
                const dx = t.x - last.x, dy = t.y - last.y;
                effect.panBy(dx, dy);
                last = t;
                travelX += dx;
                travelY += dy;
                if (dx !== 0 || dy !== 0) movedAt = Date.now();
            }
        }

        // Edge panning: while a button navigates the canvas - a PanHold button
        // or the middle button, held anywhere, a window or the ground - and the
        // pointer sits within EdgePanMargin of this screen's edge, the camera
        // keeps moving the way a drag would have — faster the deeper the pointer
        // is in the band — and stops when it leaves the band or the button comes
        // up. A window in hand rides the pan (edgePanStep): holding the button
        // on a window and pushing the pointer to the edge carries the window
        // with it. The screen the pointer is on does the panning, so a hold that
        // walks onto another screen hands over to that screen's view. A Timer,
        // as the camera's is, for the same reason: it steps from the event loop
        // rather than waiting for a frame, and its own step is what gets drawn.
        Timer {
                        interval: 16
            repeat: true
            running: view.navHeld && effect.edgePan && (effect.canvasOpen || effect.grasp) && !effect.chromeHover
            onTriggered: effect.edgePanStep(view.sg, interval / 1000)
        }

        // Zoom at the cursor, whether or not a pan button is held: a notch up
        // zooms in, a notch down zooms out. (With the pass-through plugin
        // loaded, a pointer over a client area belongs to the window, the wheel
        // included, and this handler never sees it.)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                effect.noteGesture();
                const steps = event.angleDelta.y / 120;
                if (steps === 0) return;
                const anchor = Qt.point(event.x + view.sg.x, event.y + view.sg.y);
                // On the spring, so a notch reads as a zoom rather than a jump
                // and a burst of notches rides as one motion; several notches
                // from where the last one was heading, never from mid-step.
                const from = effect.camHasGoal ? effect.camGoalZoom : effect.zoom;
                // The door closes at the seam: a zoom-in that would cross
                // 1:1 flies the camera home and re-enters the location on
                // the arrival instead of clamping at the boundary.
                if (effect.configuration.WheelDoor !== false && steps > 0 && from * Math.pow(effect.zoomStep, steps) >= 1.0) {
                    if (!effect.smoothZoom) {
                        effect.commit(null);
                        return;
                    }
                    effect.camGo(1.0, effect.viewX, effect.viewY, anchor.x, anchor.y, 2.0);
                    effect.camOnArrive = function () { effect.commit(null); };
                    return;
                }
                effect.camZoomTo(from * Math.pow(effect.zoomStep, steps), anchor.x, anchor.y);
            }
        }

        // Z order, back to front: ground, monitor frames with their real
        // desktop background, windows in KWin's stacking order, frame tags, HUD.

        // Monitor frames: one per activity per output. An activity's frames
        // are a rigid group; dragging any edge band moves them all. The
        // interior is the Plasma desktop background for that output, so each
        // frame reads as a desk top. A hidden frame is not drawn; its tag stays.
        Repeater {
            model: effect.activityIds
            delegate: Repeater {
                id: activityFrames
                required property string modelData
                required property int index
                readonly property string activity: modelData
                readonly property bool current: modelData === effect.currentActivity
                readonly property color accent: effect.palette[index % effect.palette.length]
                // Re-read on a hotplug or a rearrange (screensRev), so the
                // frames follow Display Configuration.
                model: { effect.screensRev; return KWin.Workspace.screens; }
                delegate: Item {
                    id: frame
                    required property var modelData
                    readonly property rect og: modelData.geometry
                    // Quiet, the frame is just its wallpaper, no tint or
                    // outline, until the skin comes out with the zoom and
                    // the pan - so the desktop looks like itself at the seam.
                    visible: !effect.isHidden(activityFrames.activity, modelData)
                    x: { effect.revision; return (effect.peekTarget(activityFrames.activity).x + og.x - effect.viewX) * effect.zoom - view.sg.x; }
                    y: { effect.revision; return (effect.peekTarget(activityFrames.activity).y + og.y - effect.viewY) * effect.zoom - view.sg.y; }
                    width: og.width * effect.zoom
                    height: og.height * effect.zoom
                    z: 1

                    // An empty activity makes KWin 6.7 dereference a null
                    // activities object when activities are disabled, so
                    // always pass a non-empty one.
                    KWin.DesktopBackground {
                        visible: view.wallpaperDrawable
                        anchors.fill: parent
                        output: frame.modelData
                        desktop: KWin.Workspace.currentDesktop
                        activity: activityFrames.activity || "default"
                    }

                    // Sheet tint: keeps the frame legible when no background
                    // window exists. It fades out toward 1:1, so stepping out
                    // looks like the desktop until the camera moves, and rides
                    // the chrome fade on the way in.
                    Rectangle {
                        anchors.fill: parent
                        visible: effect.skinReveal > 0.02
                        color: activityFrames.accent
                        opacity: (activityFrames.current ? 0.10 : 0.06) * effect.skinReveal * effect.chromeFade
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: effect.skinReveal > 0.02
                        color: "transparent"
                        border.width: activityFrames.current ? 2 : 1
                        border.color: activityFrames.accent
                        opacity: (activityFrames.current ? 0.95 : 0.6) * effect.chromeFade * effect.skinReveal
                    }

                    // A gesture on the frame's own area (windows sit above and
                    // take their own taps). Off during a grasp: the frames are
                    // bare wallpaper then, and a click there should be a click
                    // on the plane.
                    TapHandler {
                        enabled: !view.spaceHeld && !effect.grasp
                        acceptedButtons: Qt.LeftButton
                        onTapped: effect.frameGesture(activityFrames.activity, tapCount, point.modifiers)
                    }

                    // Edge bands: grips for the whole group.
                    Repeater {
                        model: 4
                        delegate: Grip {
                            required property int index
                            readonly property int band: 8
                            viewItem: view
                            cursor: Qt.SizeAllCursor
                            holdOff: true
                            x: index === 1 ? frame.width - band : 0
                            y: index === 2 ? frame.height - band : 0
                            width: (index === 0 || index === 2) ? frame.width : band
                            height: (index === 1 || index === 3) ? frame.height : band
                            onDragStarted: effect.targetRaw = null
                            onDragged: (dx, dy) => effect.dragTarget(activityFrames.activity, dx, dy)
                        }
                    }
                }
            }
        }

        // Windows.
        Repeater {
            model: effect.entries.length
            delegate: Item {
                id: thumb
                required property int index
                // The entry object keeps its identity across drags, so the
                // geometry bindings read the table directly and depend on
                // revision to re-evaluate after dragEntry().
                readonly property var entry: effect.entries[index]
                // A window that spawns into the open overworld enters
                // gently: it fades and grows in over a fifth of a second
                // instead of popping. The open's own populate never fades
                // (its entries carry no born), and neither does the quiet
                // seam - the location is the real windows. Only a freshly
                // born entry fades: a re-sort hands a delegate an old entry
                // it has not held before, and that must not replay the
                // entrance.
                property var seen: null
                property real enterFade: 1
                onEntryChanged: {
                    if (thumb.entry !== thumb.seen) {
                        thumb.seen = thumb.entry;
                        if (thumb.entry && thumb.entry.born && !effect.quiet && Date.now() - thumb.entry.born < 500) {
                            thumb.enterFade = 0;
                            enterFadeAnim.restart();
                        }
                    }
                }
                Component.onCompleted: {
                    effect.noteBuilt("thumb");
                    thumb.seen = thumb.entry;
                    if (thumb.entry.born && !effect.quiet && Date.now() - thumb.entry.born < 500) {
                        thumb.enterFade = 0;
                        enterFadeAnim.restart();
                    }
                }
                NumberAnimation {
                    id: enterFadeAnim
                    target: thumb
                    property: "enterFade"
                    to: 1
                    duration: 200
                    easing.type: Easing.OutCubic
                }
                // The entry a drag started on. A raise restacks the entries
                // under the delegates, so a drag follows its entry, not its index.
                property var held: null
                readonly property int heldIndex: { effect.revision; return effect.entries.indexOf(held); }
                x: { effect.revision; effect.floatRev; effect.viewX; effect.viewY; effect.zoom; effect.moveRev; const f = (effect.floatAnchor && effect.floatAnchor[thumb.entry.window.internalId]) || effect.floatOf[thumb.entry.window.internalId]; const base = (effect.entries[index].x - effect.viewX) * effect.zoom - view.sg.x; return f ? f.x - view.sg.x : base; }
                y: { effect.revision; effect.floatRev; effect.viewX; effect.viewY; effect.zoom; effect.moveRev; const f = (effect.floatAnchor && effect.floatAnchor[thumb.entry.window.internalId]) || effect.floatOf[thumb.entry.window.internalId]; const base = (effect.entries[index].y - effect.viewY) * effect.zoom - view.sg.y; return f ? f.y - view.sg.y : base; }
                width: { effect.revision; return effect.entries[index].width * effect.zoom; }
                height: { effect.revision; return effect.entries[index].height * effect.zoom; }
                visible: !effect.quiet || entry.activity === effect.currentActivity
                // The entries are the real stacking order, so the index IS the
                // z; the hovered window lifts above the web, and nothing else
                // re-orders.
                z: thumb.entry === effect.focusEntry ? 2000 : 1000 + index
                // Weight: the window lifts while the hand holds it, trails and
                // leans with the hand, and springs back when the hand stops.
                // The entry is exact throughout; this is the picture only.
                // The lift follows the drag's dead zone, so a click with hand
                // noise never grabs.
                readonly property bool heavy: effect.windowPhysics && !effect.quiet
                // Hovered: the scene's own hover, or the effect's poll. The
                // poll is the one that works over a window's client area while
                // the pass-through plugin owns the pointer there, so the glow,
                // the shadow and the lift follow it; the scene's hover stays
                // for the instant title-bar feel.
                readonly property bool hovered: body.hovered || effect.hoverEntry === thumb.entry
                property bool lifted: body.active && body.moving && heavy
                // Depth: how far up the stack this window sits. The stack IS
                // the z - the focused window paints on top, the entries' order
                // below it - so the visual depth rises and falls with every
                // restack: a hover raising a window for real slides the whole
                // stack up with it. Rank 1 is the top, and the shadow and the
                // size below follow the rank, so the stacking is legible at a
                // glance instead of being a property only the pointer sees.
                readonly property real depth: { effect.revision; effect.focusEntry; effect.selectionRev; effect.switcherActive; return ((thumb.entry === effect.focusEntry || (effect.switcherActive && effect.isSelected(thumb.entry)) ? effect.entries.length + 1 : index + 1) / (effect.entries.length + (effect.focusEntry ? 1 : 0))); }
                readonly property real depthScale: (effect.quiet || effect.ql >= 1) ? 1 : (1 + (0.025 * thumb.depth - 0.01) * Math.max(effect.skinReveal, effect.switcherRise))
                scale: depthScale * (lifted ? 1.03 : (thumb.hovered && heavy ? 1.008 : 1)) * (0.94 + 0.06 * thumb.enterFade)
                // A search dims what it does not match.
                readonly property bool searchDim: effect.searchActive === true && effect.searchText !== "" && !effect.searchHitSet[thumb.entry.window.internalId]
                opacity: effect.thumbOpacity * thumb.enterFade * (searchDim ? 0.18 : 1)
                Behavior on opacity { enabled: effect.searchActive === true; NumberAnimation { duration: 140 } }
                Behavior on scale { enabled: !effect.quiet; SpringAnimation { spring: 3.6; damping: 0.5; epsilon: 0.001 } }
                transform: [
                    Rotation {
                        origin.x: thumb.width / 2
                        origin.y: thumb.height / 2
                        angle: thumb.lifted ? effect.dragLean : 0
                        Behavior on angle {
                            enabled: thumb.heavy
                            SpringAnimation { spring: 3.4; damping: 0.42; epsilon: 0.02 }
                        }
                    },
                    Translate {
                        // The trail, plus the magnet's pull onto a snapped edge
                        // (zero on an effect that predates it: a hot reload).
                        x: thumb.lifted ? effect.dragLagX + (effect.snapKickX || 0) : 0
                        y: thumb.lifted ? effect.dragLagY + (effect.snapKickY || 0) : 0
                        Behavior on x {
                            enabled: thumb.heavy
                            SpringAnimation { spring: 3.4; damping: 0.42; epsilon: 0.2 }
                        }
                        Behavior on y {
                            enabled: thumb.heavy
                            SpringAnimation { spring: 3.4; damping: 0.42; epsilon: 0.2 }
                        }
                    }
                ]

                // Bare fidelity: the live picture is the canvas's dearest
                // cost, so a pegged machine gets the window as a named
                // rectangle - a light wash over the plane, the caption
                // always up - and keeps the real thumbnails for calmer
                // times. Everything else (drag, focus, passthrough) works
                // exactly as before.
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.07)
                    visible: effect.ql >= 3
                }

                KWin.WindowThumbnail {
                    anchors.fill: parent
                    client: thumb.entry.window
                    visible: effect.ql < 3
                }

                // The soft shadow under the window: the lifted and the
                // hovered one float a little, glass over the plane - and the
                // stack's own height shows as a standing shadow, deeper the
                // higher the window sits, so a restack is visible in the
                // shadows before the pointer even moves.
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    anchors.margins: -2 - (effect.quiet ? 0 : 6 * thumb.depth)
                    z: -2
                    radius: 8
                    color: "#000000"
                    visible: effect.ql < 1 && Math.max(effect.skinReveal, effect.switcherRise) > 0.02
                    opacity: Math.max(effect.skinReveal, effect.switcherRise) * (liftedNow ? 0.30 : (thumb.hovered ? 0.16 : 0.05 + 0.13 * thumb.depth))
                    readonly property bool liftedNow: body.active && body.moving && thumb.heavy
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                // The focus glow: the window the pointer has settled on wears
                // the activity's colour softly, so the eye knows which window
                // the canvas considers yours.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    z: -1
                    radius: 6
                    readonly property color accent: effect.activityColor(thumb.entry.activity)
                    visible: { effect.selectionRev; effect.skinReveal; return effect.skinReveal > 0.02 && !effect.isSelected(thumb.entry); }
                    opacity: thumb.hovered ? effect.skinReveal : 0
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    color: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.5)
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    visible: effect.skinReveal > 0.02
                    opacity: effect.skinReveal
                    readonly property bool sel: { effect.selectionRev; return effect.isSelected(thumb.entry); }
                    border.width: sel ? 3 : (thumb.hovered || body.active ? 2 : 1)
                    border.color: sel ? Kirigami.Theme.highlightColor
                                : (thumb.hovered || body.active ? effect.activityColor(thumb.entry.activity) : "#40ffffff")
                }

                // The grasp's landing ring: during the hold, the window
                // under the pointer is the one a click would fly to. The
                // ring says so before the click lands, and disappears the
                // moment the hold ends or the skin comes in.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 6
                    color: "transparent"
                    border.width: 2
                    border.color: "#b8ffffff"
                    visible: { effect.graspTarget; effect.skinReveal; return effect.grasp && effect.skinReveal > 0.02 && thumb.entry === effect.graspTarget; }
                }

                // The pass-through's rest cue: while the pointer rests out
                // the hover delay over this window, a thin line fills along
                // its top edge, so the handoff is anticipated instead of a
                // surprise. The pass-through publishes the window and the
                // delay; this fills over exactly that delay. The handoff
                // completes it - the line hands the pointer over and fades
                // into the window's own glow instead of cutting - and while
                // the window holds the pointer, the line stays full: the
                // window wears the hand.
                readonly property bool resting: { effect.restStart; return String(thumb.entry.window.internalId) === effect.restStart.split("|")[0]; }
                readonly property bool engaged: { effect.hoverId; return String(thumb.entry.window.internalId) === effect.hoverId; }
                property real restFill: 0
                onRestingChanged: {
                    if (resting) {
                        restFill = 0;
                        restAnim.to = 1;
                        restAnim.duration = Math.max(1, Number(effect.restStart.split("|")[1]) || 900);
                        restAnim.restart();
                    } else if (restFill > 0.01) {
                        restAnim.to = 0;
                        restAnim.duration = 260;
                        restAnim.restart();
                    } else {
                        restFill = 0;
                        restAnim.stop();
                    }
                }
                onEngagedChanged: {
                    if (engaged) {
                        restFill = 1;
                        restAnim.stop();
                    }
                }
                NumberAnimation {
                    id: restAnim
                    target: thumb
                    property: "restFill"
                    to: 1
                    easing.type: Easing.Linear
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: parent.width * thumb.restFill
                    height: 2
                    color: "#2a6ddf"
                    visible: thumb.restFill > 0
                    opacity: thumb.engaged ? 1 : 0.85
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 2
                    text: thumb.entry.window.caption
                    color: "#ffffff"
                    font.pixelSize: 12
                    visible: effect.ql >= 3 || effect.zoom < 0.6 || thumb.hovered
                    style: Text.Outline
                    styleColor: "#000000"
                }

                // The pin: a pinned window wears its marker and never leaves
                // the screen.
                Kirigami.Icon {
                    visible: effect.isPinnedEntry(thumb.entry) && effect.skinReveal > 0.02
                    source: "window-pin"
                    width: 14
                    height: 14
                    anchors.right: parent.right
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 1
                    anchors.rightMargin: 2
                    color: effect.activityColor(thumb.entry.activity)
                }

                // The client decides the size it ends up with. Follow it.
                Connections {
                    target: thumb.entry.window
                    function onFrameGeometryChanged() { effect.syncIndex(thumb.index); }
                    function onStackingOrderChanged() { Qt.callLater(effect.resync); }
                }

                // Body: move on drag, pick on click. The grip takes the PanHold
                // buttons like every other control (Grip), so with pass-through
                // or plane input live a held right button on a window is a
                // portal into the canvas: the app under it never sees the
                // press, and the drag moves the window on the plane instead.
                Grip {
                    id: body
                    anchors.fill: parent
                    viewItem: view
                    tappable: true
                    dragDead: 14
                    // The open hand: the window's own area - the title bar
                    // and the edges - reads as grabbable, while the client
                    // area keeps the app's cursor under the pass-through.
                    cursor: Qt.OpenHandCursor
                    onDragStarted: { thumb.held = thumb.entry; effect.beginDrag(thumb.index); }
                    onDragged: (dx, dy) => {
                        // The held entry, not the held index: a raise or a
                        // re-sort mid-drag renumbers the entries, and the
                        // drag must keep following the window the hand holds.
                        effect.dragEntry(effect.entries.indexOf(thumb.held), dx, dy);
                        effect.noteDrag(dx, dy);
                    }
                    onDragEnded: effect.endDrag()
                    onTapped: (count, modifiers, button) => {
                        // The world is the map: during the grasp a tap on a
                        // window is the release's destination - the hold
                        // jumps it to 1:1 and the release commits there.
                        effect.dbg("tap", "body tap index=" + index + " count=" + count + " mods=" + modifiers + " grasp=" + effect.grasp + " spaceHeld=" + view.spaceHeld + " button=" + button);
                        if (effect.grasp) {
                            effect.graspJumpTo(index);
                            return;
                        }
                        effect.windowGesture(thumb.entry, count, modifiers, button);
                    }
                }

                // The window's client area, where planeTakes() lets the
                // pointer through to the window. No handlers, so without the
                // shim the body below takes everything as before.
                Item {
                    objectName: "kwin-canvas-client"
                    readonly property var entry: thumb.entry
                    readonly property rect fg: thumb.entry.window.frameGeometry
                    readonly property rect cg: thumb.entry.window.clientGeometry
                    x: (cg.x - fg.x) * effect.zoom
                    y: (cg.y - fg.y) * effect.zoom
                    width: cg.width * effect.zoom
                    height: cg.height * effect.zoom
                    z: 5
                }

                // Resize grips: four edges, four corners, above the body. Each
                // drag step commands the real window to the new size.
                Repeater {
                    model: 8
                    delegate: Grip {
                        id: grip
                        required property int index
                        readonly property int b: 6
                        readonly property int c: 14
                        readonly property bool north: index === 0 || index === 4 || index === 5
                        readonly property bool south: index === 1 || index === 6 || index === 7
                        readonly property bool west: index === 2 || index === 4 || index === 6
                        readonly property bool east: index === 3 || index === 5 || index === 7
                        readonly property bool corner: index >= 4
                        property real startW: 0
                        property real startH: 0
                        viewItem: view
                        z: 10
                        x: corner ? (west ? 0 : thumb.width - c) : (west ? 0 : (east ? thumb.width - b : c))
                        y: corner ? (north ? 0 : thumb.height - c) : (north ? 0 : (south ? thumb.height - b : c))
                        width: corner ? c : ((west || east) ? b : Math.max(0, thumb.width - 2 * c))
                        height: corner ? c : ((north || south) ? b : Math.max(0, thumb.height - 2 * c))
                        cursor: corner
                            ? ((north && west) || (south && east) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                            : ((north || south) ? Qt.SizeVerCursor : Qt.SizeHorCursor)
                        onDragStarted: {
                            thumb.held = thumb.entry;
                            startW = thumb.entry.width;
                            startH = thumb.entry.height;
                        }
                        onDragged: {
                            const t = grip.total;
                            let rw = startW, rh = startH;
                            if (east) rw = startW + t.x / effect.zoom;
                            if (west) rw = startW - t.x / effect.zoom;
                            if (south) rh = startH + t.y / effect.zoom;
                            if (north) rh = startH - t.y / effect.zoom;
                            effect.requestSize(effect.entries.indexOf(thumb.held), rw, rh, west, north);
                        }
                    }
                }
            }
        }


        // App popups, above the windows and the frame tags, below the
        // toolbar and the canvas's menus, in KWin's stacking order. Each is
        // drawn at its real geometry with the plane transform, and its area
        // is where planeTakes() lets the pointer through to it.
        Repeater {
            model: effect.appPopups
            delegate: Item {
                required property var modelData
                required property int index
                readonly property rect fg: modelData ? modelData.frameGeometry : Qt.rect(0, 0, 0, 0)
                objectName: "kwin-canvas-popup"
                x: fg.x * effect.planeScale + effect.planeOffsetX - view.sg.x
                y: fg.y * effect.planeScale + effect.planeOffsetY - view.sg.y
                width: fg.width * effect.planeScale
                height: fg.height * effect.planeScale
                z: 70000 + index

                KWin.WindowThumbnail {
                    anchors.fill: parent
                    client: parent.modelData
                }
            }
        }

        // Clusters: the badge that names the cluster the eye is on, and -
        // just outside this repeater, hoisted to the view level - the
        // threads that bind the members: a polyline weaving through them,
        // riding the same motion as the windows, lit where the pointer's
        // cluster is and a faint sketch for the rest when zoomed out far
        // enough to see the plane. The badge floats over the active
        // cluster's centre: a glass chip with its number, so the travel
        // keys have a stop to point at.
        Repeater {
            model: effect.clusters.length
            delegate: Item {
                required property int index
                Component.onCompleted: effect.noteBuilt("badge")
                // The cluster list is replaced wholesale by every recluster,
                // and a delegate can outlive the list it was built for by a
                // frame: the read must never throw on the stale index.
                readonly property var cluster: effect.clusters[index] || null
                readonly property bool active: { effect.clusterRev; effect.focusEntry; effect.selectionRev; return cluster !== null && effect.clusterIndex() === index; }
                readonly property real cx: { effect.revision; effect.viewX; effect.viewY; effect.zoom; return cluster ? (cluster.cx - effect.viewX) * effect.zoom - view.sg.x : 0; }
                readonly property real cy: { effect.revision; effect.viewX; effect.viewY; effect.zoom; return cluster ? (cluster.cy - effect.viewY) * effect.zoom - view.sg.y : 0; }
                visible: !effect.quiet && cluster !== null && cluster.n > 1
                // The delegate fills the whole view - the wrapper has no size
                // of its own, and the badge positions from the cluster's
                // centre. The badge floats above the windows, so the wrapper
                // carries its z; the threads live outside it, at the view
                // level, where their own z can weave them through the
                // windows (a child's z cannot lift it out of its parent).
                width: view.width
                height: view.height
                z: 59000
                // The badge: the cluster's number in reading order, glass. A
                // hand on it drags the whole cluster across the plane.
                Rectangle {
                    id: badge
                    x: cx - width / 2
                    y: cy - height - 14
                    Behavior on x { SpringAnimation { spring: 2.6; damping: 0.62; epsilon: 0.5 } }
                    Behavior on y { SpringAnimation { spring: 2.6; damping: 0.62; epsilon: 0.5 } }
                    z: 59000
                    // Overworld chrome like the web: hidden at 1:1, where a
                    // cluster chip would float over the desktop and its grip
                    // would catch drags the hand means for the windows.
                    visible: parent.active && cluster.n > 1 && effect.skinReveal > 0.02
                    opacity: effect.skinReveal
                    width: row.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: "#cc1e2126"
                    border.width: 1
                    border.color: "#66ffffff"
                    Grip {
                                                anchors.fill: parent
                        viewItem: view
                        cursor: Qt.OpenHandCursor
                        onDragStarted: effect.beginClusterDrag(index)
                        onDragged: (dx, dy) => effect.dragCluster(index, dx, dy)
                        onDragEnded: effect.endDrag()
                    }
                    Row {
                        id: row
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: { effect.clusterRev; const n = effect.clusterNames[effect.clusterFingerprint(cluster)]; return n ? n : "#" + (index + 1); }
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cluster.n + " windows"
                            color: "#b8ffffff"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // The cluster webs, hoisted to the view level: every stretch of
        // every thread carries its own z, a sibling of the windows' z, so
        // the web weaves over the lower window, under the higher, and ducks
        // under every window a thread passes beneath in the stack - as the
        // float bobs and the hover re-stacks. One neon thread per pair of
        // windows, lit where the eye's cluster is, a faint sketch for the
        // rest when zoomed out far enough to see the plane.

        // The tour's trace: while a flight runs, a thin line remembers
        // where the camera came from. The plane keeps its spatial history
        // until the arrival erases it; the line fades as the flight eats
        // the distance, so a settled canvas never carries it.
        Item {
            visible: effect.camTraceFade > 0.01 && !effect.quiet
            x: -(effect.viewX * effect.zoom) - view.sg.x
            y: -(effect.viewY * effect.zoom) - view.sg.y
            scale: effect.zoom
            transformOrigin: Item.TopLeft
            z: 500
            opacity: effect.camTraceFade * 0.35
            Shape {
                ShapePath {
                    strokeColor: "#ffffff"
                    strokeWidth: 2 / effect.zoom
                    fillColor: "transparent"
                    startX: effect.camFromX
                    startY: effect.camFromY
                    PathLine { x: effect.viewX; y: effect.viewY }
                }
            }
        }

        // The web, woven by the effect when the layout changes (the stack, the
        // clusters, the hover, the selection, the focus, the active window) and never
        // by the camera, as a few layers: every span between the same two windows of
        // the stack shares one path (Logic.webLayers). The Repeater counts the layers,
        // so a re-weave that keeps their number (a drag, a hover) updates the paths of
        // the existing items instead of destroying and building every one, and a
        // dozen windows' web is a dozen or so items, not hundreds.
        Repeater {
            model: effect.threadData.length
            delegate: Item {
                id: layer
                required property int index
                readonly property var t: effect.threadData[index] || ({ z: 0, lit: false, co: 0, d: "" })
                // The paths are in the plane's own coordinates; the camera is a
                // uniform translate-plus-scale, applied here once per layer per frame.
                x: -(effect.viewX * effect.zoom) - view.sg.x
                y: -(effect.viewY * effect.zoom) - view.sg.y
                scale: effect.zoom
                transformOrigin: Item.TopLeft
                z: t.z
                // The unlit constellation fades out with the zoom, dissolving
                // between 0.45 and 0.5 instead of cutting out at half zoom, while a
                // lit thread (the cluster the focus is in) draws at every zoom; a
                // quiet hold carries no web at all.
                readonly property real want: (t.lit ? Math.max(0.3, 0.55 * t.co) * Math.min(1, Math.max(0, (1 - effect.zoom) * 4)) : (effect.ql >= 2 ? 0 : 0.22 * Math.min(1, Math.max(0, (0.5 - effect.zoom) * 20)) * t.co)) * effect.skinReveal
                property real show: 0
                opacity: show
                Behavior on show { NumberAnimation { duration: 350; easing.type: Easing.InOutCubic } }
                onWantChanged: show = want
                Component.onCompleted: { show = want; effect.noteBuilt("web"); }
                Shape {
                    // The strokes divide by the zoom so the wrapper's scale keeps
                    // them at a constant screen width.
                    ShapePath {
                        strokeWidth: 5 / effect.zoom
                        strokeColor: Qt.rgba(1, 1, 1, 0.10)
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: layer.t.d }
                    }
                    ShapePath {
                        strokeWidth: 1.6 / effect.zoom
                        strokeColor: Qt.rgba(1, 1, 1, 0.8)
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: layer.t.d }
                    }
                }
            }
        }

        // The cluster chips, on the plane itself: the world is the map, so
        // the map's business lives where the clusters live. While the grasp
        // holds and the skin is out, a chip per cluster floats over its
        // centre - the same number the world's badge wears - and a tap
        // flies the camera to fit the cluster. The camera transform matches
        // the threads' wrapper: canvas coordinates, one uniform transform
        // per frame.
        Repeater {
            model: effect.chipCount
            delegate: Item {
                required property int index
                Component.onCompleted: effect.noteBuilt("chip")
                readonly property var c: effect.clusters[index] || null
                x: { effect.revision; effect.clusterRev; effect.viewX; effect.viewY; effect.zoom; return c ? -(effect.viewX * effect.zoom) - view.sg.x + (c.cx - 12) * effect.zoom : 0; }
                y: { effect.revision; effect.clusterRev; effect.viewX; effect.viewY; effect.zoom; return c ? -(effect.viewY * effect.zoom) - view.sg.y + (c.cy - 12) * effect.zoom : 0; }
                width: 24 * effect.zoom
                height: 24 * effect.zoom
                z: 40000
                // The wrapper stays visible: Qt skips bindings on invisible
                // items, so a visible gate here would freeze the chip out of
                // the grasp that should show it. The chip's pixels and its
                // tap gate on the grasp below.
                visible: true
                opacity: { effect.clusterRev; effect.skinReveal; effect.grasp; return (effect.grasp && effect.skinReveal > 0.02 && index < effect.clusters.length && effect.clusters[index].n > 1) ? effect.skinReveal : 0; }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#cc1e2126"
                    border.width: 1
                    border.color: "#66ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: { effect.clusterRev; const c2 = effect.clusters[index]; const n = c2 ? effect.clusterNames[effect.clusterFingerprint(c2)] : ""; return n ? n : "#" + (index + 1); }
                        color: "#ffffff"
                        font.pixelSize: 11 * effect.zoom
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    enabled: { effect.clusterRev; effect.skinReveal; effect.grasp; effect.chromeHover; return !effect.chromeHover && effect.grasp && effect.skinReveal > 0.02 && index < effect.clusters.length && effect.clusters[index].n > 1; }
                    onTapped: effect.graspClusterTo(index)
                }
                HoverHandler {
                    enabled: { effect.clusterRev; effect.skinReveal; effect.grasp; effect.chromeHover; return !effect.chromeHover && effect.grasp && effect.skinReveal > 0.02 && index < effect.clusters.length && effect.clusters[index].n > 1; }
                    onHoveredChanged: view.hoverCount += hovered ? 1 : -1
                    Component.onDestruction: if (hovered) view.hoverCount -= 1
                }
            }
        }
        } // the plane

        // The marquee stays flat: a screen-space selection rectangle.
        Rectangle {
            id: marqueeBox
            property real x0: 0
            property real y0: 0
            property real x1: 0
            property real y1: 0
            readonly property rect rect: Qt.rect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0))
            visible: panDrag.active && panDrag.marquee
            z: 90000
            x: rect.x; y: rect.y; width: rect.width; height: rect.height
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
            border.width: 1
            border.color: Kirigami.Theme.highlightColor
        }

        Keys.onPressed: (event) => {
            const k = event.key;
            // The search takes every key while it runs (the functions live on the effect;
            // a hot reload swaps this file and not the effect, which may predate them).
            if (effect.searchActive && effect.searchKey && effect.searchKey(k, event.text, event.modifiers)) { event.accepted = true; return; }
            // A slash starts it, when the canvas has the keys.
            if (k === Qt.Key_Slash && !effect.quiet && effect.searchStart && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { effect.searchStart(); event.accepted = true; return; }
            // Ctrl+Z steps the layout back one commit, wherever the canvas
            // is open - the undo belongs to the plane, not to a window.
            if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_Z) {
                if (!event.isAutoRepeat) effect.undo();
                event.accepted = true;
                return;
            }
            if (effect.bound("pan", k)) {
                if (!event.isAutoRepeat) view.spaceHeld = true;
            } else if (effect.bound("next", k) && !(event.modifiers & Qt.ShiftModifier)) {
                effect.dbg("key", "next pressed k=" + k);
                if (!event.isAutoRepeat) {
                    // In the switcher the cycle rides the gate, so a held
                    // key's repeats can never machine-gun it whatever the
                    // delivery; the plain overview keeps its own Tab cycle.
                    if (effect.switcherActive) effect.switcherCycle(1);
                    else effect.cycleSelection(1);
                }
            } else if (effect.bound("prev", k) || (effect.bound("next", k) && (event.modifiers & Qt.ShiftModifier))) {
                // Shift+Tab arrives as Tab with the shift modifier, whatever
                // the platform does about Backtab, so both count as previous.
                if (!event.isAutoRepeat) {
                    if (effect.switcherActive) effect.switcherCycle(-1);
                    else effect.cycleSelection(-1);
                }
            } else if (effect.bound("cancel", k)) {
                effect.cancel();
            } else if (effect.bound("apply", k)) {
                effect.applyKey();
            } else if (effect.bound("home", k)) {
                effect.home();
            } else if (effect.bound("origin", k)) {
                effect.origin();
            } else if (effect.bound("fit", k)) {
                effect.zoomExtents(true);
            } else if (effect.bound("zoomIn", k)) {
                const p = effect.cursorScreen();
                effect.camZoomTo(effect.zoom * effect.zoomStep, p.x, p.y);
            } else if (effect.bound("zoomOut", k)) {
                const p = effect.cursorScreen();
                effect.camZoomTo(effect.zoom / effect.zoomStep, p.x, p.y);
            } else if (effect.bound("panLeft", k)) {
                effect.panKey(-1, 0);
            } else if (effect.bound("panRight", k)) {
                effect.panKey(1, 0);
            } else if (effect.bound("panUp", k)) {
                effect.panKey(0, -1);
            } else if (effect.bound("panDown", k)) {
                effect.panKey(0, 1);
            } else if (effect.bound("clusterNext", k) && !(event.modifiers & Qt.ShiftModifier)) {
                if (!event.isAutoRepeat) effect.clusterTravel(1);
            } else if (effect.bound("clusterPrev", k) || (effect.bound("clusterNext", k) && (event.modifiers & Qt.ShiftModifier))) {
                if (!event.isAutoRepeat) effect.clusterTravel(-1);
            } else if (k >= Qt.Key_1 && k <= Qt.Key_9) {
                // The digits hop straight to cluster N - the badge's number.
                // The cluster is the room, so a bare digit is the jump.
                const n = k - Qt.Key_1 + 1;
                const mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier);
                if (!mods) effect.clusterJumpTo(n);
                // The functions live on the effect; a hot reload swaps this
                // file and not the effect's own, which may predate them.
                else if (mods === Qt.ControlModifier) { if (!event.isAutoRepeat && effect.bookmarkSet) effect.bookmarkSet(n); }
                else if (mods === Qt.AltModifier) { if (!event.isAutoRepeat && effect.bookmarkGo) effect.bookmarkGo(n); }
                else return;
            } else {
                return;
            }
            event.accepted = true;
        }

        Keys.onReleased: (event) => {
            if (effect.bound("pan", event.key) && !event.isAutoRepeat) {
                view.spaceHeld = false;
                event.accepted = true;
            }
            // Releasing the switcher's chord enters the selected window, the
            // way releasing Alt+Tab lands on the tabbox's pick - but it
            // waits a human beat first, so the pick settles under the eye
            // instead of jumping in at the tab keyup (a re-tap mid-hold
            // carries the modifiers, so its keyup is neither a modifier
            // nor a bare Tab, and can never arm it). The scene cannot
            // always see the release of a key the global shortcut consumed,
            // so this is only the fast path: the modifier key-up arms the
            // settle through the shared handler, and the plugin's live
            // modifier poll is the slow, always-works path.
            if (effect.switcherActive && effect.switcherFromChord && !event.isAutoRepeat) {
                const mod = event.key === Qt.Key_Alt || event.key === Qt.Key_Control
                        || event.key === Qt.Key_Meta || event.key === Qt.Key_Shift;
                if (mod) {
                    effect.chordRelease();
                    event.accepted = true;
                }
            }
        }

        // The search's field: what was typed and how many windows match, in glass at the top
        // of the screen the canvas opened on.
        Rectangle {
            visible: effect.searchActive === true && view.screen === (effect.chromeScr || effect.primaryScreen)
            z: 100003
            anchors.horizontalCenter: parent.horizontalCenter
            y: Kirigami.Units.gridUnit * 4
            width: Math.max(Kirigami.Units.gridUnit * 22, searchRow.implicitWidth + Kirigami.Units.largeSpacing * 3)
            height: searchRow.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: height / 2
            color: Qt.rgba(0.08, 0.08, 0.10, 0.82)
            border.width: 1
            border.color: effect.searchText !== "" && effect.searchHits.length === 0 ? "#c0ff6b6b" : "#40ffffff"
            Row {
                id: searchRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon { source: "search"; width: Kirigami.Units.iconSizes.small; height: width; anchors.verticalCenter: parent.verticalCenter }
                PC3.Label {
                    text: effect.searchText !== "" ? effect.searchText + "\u258f" : "Type to find a window\u258f"
                    opacity: effect.searchText !== "" ? 1 : 0.6
                    color: "#ffffff"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                }
                PC3.Label {
                    visible: effect.searchText !== ""
                    text: effect.searchHits.length === 0 ? "no match" : (effect.searchIndex + 1) + " of " + effect.searchHits.length
                    color: "#ffffff"
                    opacity: 0.6
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // The chrome (the lens, the grasp's hint, the frame tags, the arrange menu, the toast, the
        // switcher, the toolbar and the help) is built only when it can be seen: the scene is
        // created afresh on every open, and building all of it cost about half of each open's
        // first frame, a quick slide or fly included, which shows none of it. It is built
        // synchronously once wanted (an asynchronous build cannot resolve this file's inline
        // components, Grip and the rest, and gained nothing in KWin's scene), and it stays
        // until the scene goes away with the close.
        readonly property bool chromeWanted: !effect.quiet || effect.grasp || effect.switcherActive || !!effect.toastText
        onChromeWantedChanged: if (chromeWanted) chromeLoader.active = true
        Loader {
            id: chromeLoader
            anchors.fill: parent
            // Set, never bound: once built the chrome stays for the scene's life.
            active: false
            sourceComponent: Component {
                Item {
                    // The corner lens: the world shrunk into a chip for a glance at
                    // the plane while working. The overlay is gone - the world is the
                    // map - so the lens is the only map surface left.
                    Item {
                        id: planeMap
                        z: 80000
                        readonly property int mw: Math.round(view.sg.width * 0.16)
                        readonly property int mh: Math.round(view.sg.height * 0.2)
                        // The corner lens: the world shrunk into a chip for a glance at
                        // the plane while working. The overlay is gone - the world is
                        // the map - so the lens is the only map surface left.
                        readonly property bool asMinimap: ((effect.canvasOpen && !effect.quiet && (effect.zoom < 0.9 || effect.navHeld) && !effect.grasp) || (effect.visible && effect.quiet && effect.grasp)) && view.screen === (effect.chromeScr || effect.primaryScreen)
                        // Mirrored into the effect's own flags: logState and the other
                        // effect functions cannot see this item's id, so the map
                        // publishes its home for them.
                        onAsMinimapChanged: effect.mapMinimap = asMinimap
                        // The lens hugs the bottom-right corner, but never the toolbar:
                        // when the HUD holds the bottom or the right edge, the chip
                        // steps clear of it (the map's z would otherwise draw over the
                        // toolbar, and a glance-map must never cover the controls).
                        readonly property rect home: Qt.rect(
                            hud.visible && hud.atRight ? hud.x - mw - Kirigami.Units.largeSpacing : view.sg.width - mw - Kirigami.Units.largeSpacing * 2,
                            hud.visible && hud.atBottom ? hud.y - mh - Kirigami.Units.largeSpacing : view.sg.height - mh - Kirigami.Units.largeSpacing * 2,
                            mw, mh)
                        visible: asMinimap
                        property bool morphReady: false
                        Component.onCompleted: {
                            x = home.x; y = home.y; width = home.width; height = home.height;
                            morphReady = true;
                        }
                        onHomeChanged: {
                            if (!morphReady) return;
                            x = home.x; y = home.y; width = home.width; height = home.height;
                        }
                        Behavior on x { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
                        Behavior on y { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
                        Behavior on width { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
                        Behavior on height { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        // The map lives: every binding depends on the revision and the
                        // camera explicitly - a function's reads do not register as
                        // dependencies, so without these the map would be a still.
                        readonly property rect wb: { effect.revision; effect.screensRev; return effect.worldBounds(); }
                        readonly property real sc: { effect.revision; return Math.min((width - 12) / wb.width, (height - 12) / wb.height); }
                        readonly property real ox: { effect.revision; return (width - wb.width * sc) / 2; }
                        readonly property real oy: { effect.revision; return (height - wb.height * sc) / 2; }
                        function mx(cx) { return ox + (cx - wb.x) * sc; }
                        function my(cy) { return oy + (cy - wb.y) * sc; }
                        scale: 1.0
                        // The map's content: the sheets, the outlines and the dim,
                        // behind the lens's glass.
                        Item {
                            anchors.fill: parent
                            // The quiet grasp never runs the chrome's fade-in, and a normal
                            // exit leaves it at 0: the hold's map must not inherit that.
                            opacity: effect.grasp ? 1 : effect.chromeFade
                        // The dim behind the lens, and the tint over it: the tint is
                        // what makes the white sheets read as cards instead of a
                        // negative reflection over the desktop.
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0.07, 0.07, 0.09, 0.42)
                            // The minimap's dark region bleeds into the plane instead of
                            // ending at a line: the edge is a soft falloff. The ladder
                            // sheds the edge's blur at the same rung as the backdrop's.
                            layer.enabled: effect.ql < 2
                            layer.effect: GaussianBlur {
                                radius: 5
                                samples: 17
                                transparentBorder: false
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: "transparent"
                            border.width: 1
                            border.color: "#3affffff"
                        }

                        Repeater {
                            model: { effect.revision; effect.screensRev; return effect.frames().length; }
                            delegate: Rectangle {
                                required property int index
                                readonly property var f: { effect.revision; effect.screensRev; return effect.frames()[index]; }
                                visible: planeMap.asMinimap
                                x: { effect.revision; effect.screensRev; planeMap.width; planeMap.height; return planeMap.mx(f.x); }
                                y: { effect.revision; effect.screensRev; planeMap.width; planeMap.height; return planeMap.my(f.y); }
                                width: { effect.revision; planeMap.width; planeMap.height; return f.width * planeMap.sc; }
                                height: { effect.revision; planeMap.width; planeMap.height; return f.height * planeMap.sc; }
                                readonly property color accent: effect.palette[index % effect.palette.length]
                                color: Qt.rgba(accent.r, accent.g, accent.b, 0.30)
                                border.width: 1
                                border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.75)
                                opacity: 0.9
                            }
                        }
                        Repeater {
                            model: effect.entries.length
                            delegate: Rectangle {
                                required property int index
                                readonly property var e: effect.entries[index]
                                // The map is of the plane, so a floated window's sheet
                                // sits at its coordinates, where it is parked, and not
                                // where its picture rides the screen's edge: the glance
                                // shows where the window is, and the camera rectangle
                                // shows how far the eye has gone from it.
                                x: { effect.revision; return planeMap.mx(e.x); }
                                y: { effect.revision; return planeMap.my(e.y); }
                                width: { effect.revision; return Math.max(1.6, e.width * planeMap.sc); }
                                height: { effect.revision; return Math.max(1.6, e.height * planeMap.sc); }
                                radius: 1
                                color: Qt.rgba(1, 1, 1, 0.5)
                                border.width: 0.6
                                border.color: effect.isSelected(e) ? "#b8ffffff" : "#4affffff"
                                // The lens is a glance, not a surface: its taps belong
                                // to the world beneath it, never to the sheets.
                            }
                        }
                        // The map is the navigation surface: a left drag anywhere on it
                        // pans the camera, and it must never fall through to the window
                        // drawn under the pointer - a drag that started on a sheet or
                        // on the map's empty ground would otherwise grab that window
                        // and drag the canvas with it. The sheets and the camera
                        // rectangle sit above this and keep their own gestures.
                        Item {
                            anchors.fill: parent
                            DragHandler {
                                target: null
                                acceptedButtons: Qt.LeftButton
                                enabled: planeMap.asMinimap && !effect.chromeHover
                                property point last: Qt.point(0, 0)
                                onActiveChanged: {
                                    effect.sceneGestures += active ? 1 : -1;
                                    if (active) {
                                        effect.noteGesture(true);
                                        last = Qt.point(0, 0);
                                    }
                                }
                                onActiveTranslationChanged: {
                                    const t = activeTranslation;
                                    effect.panBy(t.x - last.x, t.y - last.y);
                                    last = t;
                                }
                            }
                        }
                        // The camera's viewport on the map: the rectangle that IS the
                        // screen. It floats - a soft halo under a rounded glass chip -
                        // melts away when the view dominates the map, and expands to
                        // take the map the moment a step in begins, while the map's
                        // content fades with the chrome.
                        Item {
                            id: cameraRect
                            // The camera can wander past the world's edge, and the
                            // rect must never wander past the map's: it hugs the
                            // chip's border there, and a view bigger than the world
                            // fills the chip exactly instead of sticking out.
                            readonly property real rectW: { effect.zoom; effect.revision; planeMap.width; return Math.min(Math.max(3, view.sg.width / effect.zoom * planeMap.sc), planeMap.width); }
                            readonly property real rectH: { effect.zoom; effect.revision; planeMap.height; return Math.min(Math.max(3, view.sg.height / effect.zoom * planeMap.sc), planeMap.height); }
                            width: rectW
                            height: rectH
                            x: { effect.revision; effect.viewX; effect.zoom; planeMap.width; planeMap.height; const raw = planeMap.mx(effect.viewX + view.sg.x / effect.zoom); return Math.max(0, Math.min(raw, planeMap.width - rectW)); }
                            y: { effect.revision; effect.viewY; effect.zoom; planeMap.width; planeMap.height; const raw = planeMap.my(effect.viewY + view.sg.y / effect.zoom); return Math.max(0, Math.min(raw, planeMap.height - rectH)); }
                            // The graceful extreme: a view that covers most of the map
                            // melts instead of becoming a huge slab.
                            readonly property real cover: Math.min(1, (width * height) / Math.max(1, planeMap.width * planeMap.height))
                            readonly property real fade: 0.35 + 0.65 * (1 - Math.min(1, Math.max(0, (cover - 0.55) / 0.45)))
                            // The step in: the world's window expands to take the map.
                            readonly property real expansion: effect.entering ? Math.max(1, planeMap.width / Math.max(1, width)) : 1
                            scale: expansion
                            transformOrigin: Item.Center
                            Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.55; epsilon: 0.01 } }
                            // The halo, under the chip: the float.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -7
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.08)
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.12)
                                border.width: 1
                                border.color: "#e8ffffff"
                                opacity: cameraRect.fade
                                // The rectangle itself pans the camera: drag the
                                // viewport across the map and the view follows. The
                                // drag counts as a scene gesture so a release asked
                                // for mid-drag waits for the hand to come up.
                                DragHandler {
                                    enabled: !effect.chromeHover
                                    property point last: Qt.point(0, 0)
                                    onActiveChanged: {
                                        effect.sceneGestures += active ? 1 : -1;
                                        if (active) {
                                            effect.noteGesture(true);
                                            last = Qt.point(0, 0);
                                        }
                                    }
                                    onActiveTranslationChanged: {
                                        const t = activeTranslation;
                                        effect.panBy(t.x - last.x, t.y - last.y);
                                        last = t;
                                    }
                                }
                            }
                        }
                        }
                        // The minimap's own click flies the camera to the point; the
                        // lens never steals the pointer from the windows beneath it.
                        TapHandler {
                            enabled: planeMap.asMinimap && !effect.chromeHover
                            onTapped: (eventPoint) => {
                                const wb = effect.worldBounds();
                                const cx = wb.x + (eventPoint.position.x - planeMap.ox) / planeMap.sc;
                                const cy = wb.y + (eventPoint.position.y - planeMap.oy) / planeMap.sc;
                                const g = effect.actionScreen().geometry;
                                effect.camGo(effect.zoom, cx - (g.x + g.width / 2) / effect.zoom, cy - (g.y + g.height / 2) / effect.zoom);
                            }
                        }
                    }
                    // The grasp teaches itself: one line, while the hold is zoomed out
                    // enough for the world to be the map, naming what the hand can do.
                    Item {
                        z: 80000
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        width: hintRow.implicitWidth + 20
                        height: 26
                        visible: effect.grasp && effect.skinReveal > 0.5 && !effect.switcherActive
                        opacity: effect.skinReveal
                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            color: "#cc1e2126"
                            border.width: 1
                            border.color: "#33ffffff"
                        }
                        Row {
                            id: hintRow
                            anchors.centerIn: parent
                            spacing: 9
                            Text { text: "click to fly"; color: "#ffffff"; font.pixelSize: 11 }
                            Text { text: "·"; color: "#77ffffff"; font.pixelSize: 11 }
                            Text { text: "drag to pan"; color: "#ffffff"; font.pixelSize: 11 }
                            Text { text: "·"; color: "#77ffffff"; font.pixelSize: 11 }
                            Text { text: "wheel to zoom"; color: "#ffffff"; font.pixelSize: 11 }
                            Text { text: "·"; color: "#77ffffff"; font.pixelSize: 11 }
                            // The last word flips exactly where the release's outcome
                            // flips: above 0.72 the release lands, below it the release
                            // widens into the overworld. The grasp's two outcomes read
                            // before the hold ends.
                            Text { text: { effect.zoom; return effect.zoom < 0.72 ? "release to open the world" : "release to land" } color: "#ffffff"; font.pixelSize: 11 }
                        }
                    }

                    // Frame tags, above the windows so they can always be grabbed.
                    Repeater {
                        model: effect.activityIds
                        delegate: Repeater {
                            id: activityTags
                            required property string modelData
                            required property int index
                            model: { effect.screensRev; return KWin.Workspace.screens; }
                            delegate: FrameTag {
                                required property var modelData
                                visible: effect.skinReveal > 0.02 && mine && !view.replica
                                viewItem: view
                                activity: activityTags.modelData
                                activityIndex: activityTags.index
                                screen: modelData
                                x: { effect.revision; return (effect.peekTarget(activity).x + screen.geometry.x - effect.viewX) * effect.zoom - view.sg.x; }
                                y: { effect.revision; return (effect.peekTarget(activity).y + screen.geometry.y - effect.viewY) * effect.zoom - view.sg.y - height - 2; }
                                z: 60000
                            }
                        }
                    }

                    // Arrange menu for the selection, opened by the context gesture on a window.
                    Connections {
                        target: effect
                        function onContextRequested(entry) {
                            // Attached properties resolve against this Connections object, so go through the view.
                            // One menu, on the screen the pointer is on: every screen's view
                            // is connected to this signal, and the pointer's screen is where
                            // the gesture was made, not the focused window's.
                            if (view.screen !== effect.actionScreen()) return;
                            const p = effect.cursorScreen();
                            arrangeMenu.x = p.x - view.sg.x;
                            arrangeMenu.y = p.y - view.sg.y;
                            arrangeMenu.open();
                        }
                    }
                    PC3.Menu {
                        id: arrangeMenu
                        z: 100001
                        title: "Arrange"
                        onOpened: effect.canvasMenus++
                        onClosed: effect.canvasMenus = Math.max(0, effect.canvasMenus - 1)
                        // The Plasma menu background assumes the desktop blur behind it;
                        // over the canvas there is none, so the menu is drawn opaque.
                        background: MenuBackground { }
                        PC3.MenuItem { text: "Arrange horizontally"; icon.name: "view-split-left-right"; onTriggered: effect.arrange("horizontal") }
                        PC3.MenuItem { text: "Arrange vertically";   icon.name: "view-split-top-bottom"; onTriggered: effect.arrange("vertical") }
                        PC3.MenuItem { text: "Tile";                 icon.name: "view-grid";             onTriggered: effect.arrange("tile") }
                        PC3.Menu {
                            title: "Grid"
                            icon.name: "view-grid"
                            background: MenuBackground { }
                            Repeater {
                                model: ["1x2", "2x1", "2x2", "3x1", "1x3", "3x2", "2x3", "3x3", "4x2", "2x4"]
                                delegate: PC3.MenuItem {
                                    required property string modelData
                                    text: modelData.replace("x", " × ") + "  (rows × columns)"
                                    onTriggered: { const p = modelData.split("x"); effect.arrange("grid", Number(p[0]), Number(p[1])); }
                                }
                            }
                        }
                        PC3.MenuItem { text: "Cascade";              icon.name: "window-duplicate";      onTriggered: effect.arrange("cascade") }
                        PC3.MenuItem { text: "Tidy this activity";    icon.name: "view-sort-ascending";   onTriggered: effect.tidy() }
                        PC3.MenuSeparator {}
                        PC3.Menu {
                            title: "Send to"
                            icon.name: "activities"
                            background: MenuBackground { }
                            Repeater {
                                model: effect.activityIds
                                delegate: PC3.MenuItem {
                                    required property string modelData
                                    required property int index
                                    text: effect.labelOf(modelData)
                                    onTriggered: effect.sendTo(modelData)
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: Kirigami.Units.smallSpacing; width: 12; height: 12; radius: 3; color: effect.palette[index % effect.palette.length] }
                                }
                            }
                            PC3.MenuSeparator {}
                            PC3.MenuItem { text: "Plane, outside every activity"; icon.name: "edit-none"; onTriggered: effect.sendTo(null) }
                        }
                        PC3.MenuSeparator {}
                        PC3.MenuItem { text: "Clear selection";      icon.name: "edit-select-none";      onTriggered: effect.clearSelection() }
                        PC3.MenuSeparator {}
                        PC3.MenuItem { text: effect.pinTargetsPinned() ? "Unfloat" : "Float"; icon.name: "window-pin"; onTriggered: effect.togglePin() }
                    }

                    // The toast: a brief glass chip naming what just happened (a saved
                    // or jumped-to view).
                    Rectangle {
                        z: 100001
                        visible: view.screen === (effect.chromeScr || effect.primaryScreen) && effect.toastText !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Kirigami.Units.largeSpacing * 3
                        width: toastLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: toastLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.cornerRadius
                        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.78)
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                        opacity: { effect.toastRev; return effect.toastText !== "" ? 1 : 0; }
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        PC3.Label {
                            id: toastLabel
                            anchors.centerIn: parent
                            text: effect.toastText
                        }
                    }

                    // The switcher's pick: the chosen window's name, its live picture
                    // and the cluster it belongs to. It rides the switcher's z-rise, so
                    // the card and the pile settle together, and each step swaps the
                    // content in place.
                    Rectangle {
                        z: 100002
                        visible: { effect.switcherActive; return view.screen === (effect.chromeScr || effect.primaryScreen) && effect.switcherActive; }
                        opacity: effect.switcherRise
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: hud.bottom
                        anchors.topMargin: Kirigami.Units.largeSpacing
                        width: switchRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: switchRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                        radius: 16
                        color: Qt.rgba(0.05, 0.05, 0.08, 0.72)
                        border.width: 1
                        border.color: "#33ffffff"
                        Row {
                            id: switchRow
                            anchors.centerIn: parent
                            spacing: Kirigami.Units.largeSpacing
                            Item {
                                width: 220
                                height: 124
                                visible: effect.ql < 2
                                KWin.WindowThumbnail {
                                    anchors.fill: parent
                                    client: effect.switcherPick() ? effect.switcherPick().window : null
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Kirigami.Units.smallSpacing
                                PC3.Label {
                                    text: {
                                        effect.selectionRev; effect.revision;
                                        const p = effect.switcherPick();
                                        return p ? p.window.caption : "";
                                    }
                                    font.pointSize: 15
                                    font.weight: Font.DemiBold
                                    color: "#ffffff"
                                }
                                PC3.Label {
                                    text: {
                                        effect.selectionRev; effect.revision; effect.clusterRev;
                                        const p = effect.switcherPick();
                                        const ci = p ? effect.clusterIndexOfEntry(p) : -1;
                                        return ci >= 0 ? ("cluster #" + (ci + 1) + " · " + effect.clusters[ci].n + " windows") : "";
                                    }
                                    font.pointSize: 10
                                    color: "#99ffffff"
                                }
                            }
                        }
                    }

                    // HUD: a Plasma toolbar, top centre. Camera state, the actions, help
                    // with the bindings, and the settings pages that own them.
                    Rectangle {
                        id: hud
                        z: 100000
                        visible: view.screen === (effect.chromeScr || effect.primaryScreen) && (!effect.quiet || effect.skinReveal > 0.5)
                        opacity: effect.chromeFade * (effect.quiet ? Math.max(0, Math.min(1, (effect.skinReveal - 0.5) * 2)) : 1)
                        readonly property string pos: String(effect.configuration.HudPosition || "Top").toLowerCase()
                        readonly property bool atBottom: pos.indexOf("bottom") === 0
                        readonly property bool atLeft: pos === "left" || pos === "topleft" || pos === "bottomleft"
                        readonly property bool atRight: pos === "right" || pos === "topright" || pos === "bottomright"
                        readonly property bool centredV: pos === "left" || pos === "right"
                        readonly property bool inCorner: pos === "topleft" || pos === "topright" || pos === "bottomleft" || pos === "bottomright"
                        // Shape: auto follows the position (square in a corner, vertical on
                        // a side, horizontal on the top or bottom), or forced by config.
                        readonly property string shape: {
                            const want = String(effect.configuration.HudShape || "auto").toLowerCase();
                            if (want === "horizontal" || want === "vertical" || want === "square") return want;
                            return inCorner ? "square" : (centredV ? "vertical" : "horizontal");
                        }
                        readonly property bool vertical: shape === "vertical"
                        readonly property bool square: shape === "square"
                        readonly property int squareColumns: 4
                        anchors.top: atBottom || centredV ? undefined : parent.top
                        anchors.bottom: atBottom ? parent.bottom : undefined
                        anchors.verticalCenter: centredV ? parent.verticalCenter : undefined
                        anchors.left: atLeft ? parent.left : undefined
                        anchors.right: atRight ? parent.right : undefined
                        anchors.horizontalCenter: !atLeft && !atRight ? parent.horizontalCenter : undefined
                        anchors.margins: Kirigami.Units.largeSpacing
                        width: hudRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: hudRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.cornerRadius
                        color: Qt.rgba(0.05, 0.05, 0.08, 0.72)
                        border.width: 1
                        border.color: "#33ffffff"
                        Kirigami.Theme.inherit: false
                        Kirigami.Theme.colorSet: Kirigami.Theme.Window

                        HoverHandler {
                            enabled: !effect.chromeHover
                            onHoveredChanged: view.hoverCount += hovered ? 1 : -1
                            Component.onDestruction: if (hovered) view.hoverCount -= 1
                        }

                        GridLayout {
                            id: hudRow
                            anchors.centerIn: parent
                            flow: hud.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            rows: hud.vertical ? -1 : (hud.square ? -1 : 1)
                            columns: hud.vertical ? 1 : (hud.square ? hud.squareColumns : -1)
                            rowSpacing: Kirigami.Units.smallSpacing
                            columnSpacing: Kirigami.Units.smallSpacing

                            // Separators only in the linear shapes; a square reads as rows.
                            component Sep : Kirigami.Separator {
                                visible: !hud.square
                                Layout.fillHeight: !hud.vertical
                                Layout.fillWidth: hud.vertical
                                Layout.margins: Kirigami.Units.smallSpacing
                            }

                            Kirigami.Icon {
                                visible: !hud.square
                                source: "activities"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                Layout.alignment: Qt.AlignCenter
                            }
                            PC3.Label {
                                text: hud.vertical ? effect.labelOf(effect.currentActivity) + "\n" + Math.round(effect.zoom * 100) + "%"
                                                   : effect.labelOf(effect.currentActivity) + "   " + Math.round(effect.zoom * 100) + "%"
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignCenter
                                Layout.columnSpan: hud.square ? hud.squareColumns : 1
                                Layout.rightMargin: hud.vertical || hud.square ? 0 : Kirigami.Units.smallSpacing
                            }
                            // One swatch per activity in its frame colour; click to zoom to it.
                            Repeater {
                                model: effect.activityIds
                                delegate: Rectangle {
                                    required property string modelData
                                    required property int index
                                    readonly property bool current: modelData === effect.currentActivity
                                    width: Kirigami.Units.iconSizes.small
                                    height: Kirigami.Units.iconSizes.small
                                    radius: 3
                                    color: effect.palette[index % effect.palette.length]
                                    border.width: current ? 2 : 0
                                    border.color: "#ffffff"
                                    Layout.alignment: Qt.AlignCenter
                                    PC3.ToolTip.text: effect.labelOf(modelData)
                                    PC3.ToolTip.visible: swatchHover.hovered
                                    HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: effect.zoomToActivity(modelData) }
                                }
                            }
                            Sep {}
                            // The hand dot: whose is the pointer? Filled = the window's,
                            // hollow = the canvas's. Polled from the plugin's own state.
                            Rectangle {
                                visible: effect.passthroughLive
                                width: 10
                                height: 10
                                radius: 5
                                color: effect.handOnWindow ? "#2a6ddf" : "transparent"
                                border.width: 1
                                border.color: "#80ffffff"
                                Layout.alignment: Qt.AlignCenter
                                PC3.ToolTip.text: effect.handOnWindow ? "The pointer is the window's" : "The pointer is the canvas's"
                                PC3.ToolTip.visible: handDotHover.hovered
                                HoverHandler { id: handDotHover; cursorShape: Qt.PointingHandCursor }
                            }
                            // The fidelity rung: a quiet dot appears only when the canvas
                            // has stepped down for the machine's load, coloured by how far.
                            Rectangle {
                                visible: effect.ql > 0
                                width: 10
                                height: 10
                                radius: 5
                                color: effect.ql === 1 ? "#d9a441" : (effect.ql === 2 ? "#d97a41" : "#d95050")
                                border.width: 1
                                border.color: "#80ffffff"
                                Layout.alignment: Qt.AlignCenter
                                PC3.ToolTip.text: effect.ql === 1 ? "The canvas is reduced: the machine is busy" : (effect.ql === 2 ? "The canvas is minimal: the machine is loaded" : "The canvas is bare: only the rectangles work")
                                    + (effect.configuration.QualityMode === "Auto" ? " (cpu " + Math.round(effect.cpuBusy) + "%, gpu " + Math.round(effect.gpuBusy) + "%, memory " + Math.round(effect.memBusy) + "%)" : " (fixed by the Quality setting)")
                                PC3.ToolTip.visible: rungHover.hovered
                                HoverHandler { id: rungHover; cursorShape: Qt.PointingHandCursor }
                            }
                            Sep {}
                            PC3.ToolButton { icon.name: "zoom-fit-best";   text: "Fit";    display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Zoom to fit (" + effect.keyLabel(effect.configuration.KeyFit) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.zoomExtents(true) }
                            PC3.ToolButton { icon.name: "go-home";         text: "Home";   display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Look through this activity's frames (" + effect.keyLabel(effect.configuration.KeyHome) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.home() }
                            PC3.ToolButton { icon.name: "zoom-in";         text: "In";     display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Zoom in (" + effect.keyLabel(effect.configuration.KeyZoomIn) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.camZoomTo(effect.zoom * effect.zoomStep, view.sg.x + view.sg.width / 2, view.sg.y + view.sg.height / 2) }
                            PC3.ToolButton { icon.name: "zoom-out";        text: "Out";    display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Zoom out (" + effect.keyLabel(effect.configuration.KeyZoomOut) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.camZoomTo(effect.zoom / effect.zoomStep, view.sg.x + view.sg.width / 2, view.sg.y + view.sg.height / 2) }
                            Sep {}
                            PC3.ToolButton { icon.name: "snap-bounding-box-edges";   text: "Edges";   display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.snapEdges;   onToggled: effect.snapEdges = checked;   PC3.ToolTip.text: "Snap to edges";   PC3.ToolTip.visible: hovered }
                            PC3.ToolButton { icon.name: "snap-bounding-box-corners"; text: "Corners"; display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.snapCorners; onToggled: effect.snapCorners = checked; PC3.ToolTip.text: "Snap to corners"; PC3.ToolTip.visible: hovered }
                            PC3.ToolButton { icon.name: "snap-grid";                 text: "Grid";    display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.snapGrid;    onToggled: effect.snapGrid = checked;    PC3.ToolTip.text: "Snap to grid (" + effect.configuration.SnapGridSize + " px)"; PC3.ToolTip.visible: hovered }
                            Sep {}
                            PC3.ToolButton { icon.name: "dialog-ok-apply"; text: "Enter";  display: hud.vertical || hud.square ? PC3.AbstractButton.IconOnly : PC3.AbstractButton.TextBesideIcon; PC3.ToolTip.text: "Enter the location under the screen centre (" + effect.keyLabel(effect.configuration.KeyApply) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.enterHere() }
                            PC3.ToolButton { icon.name: "dialog-cancel";   text: "Cancel"; display: hud.vertical || hud.square ? PC3.AbstractButton.IconOnly : PC3.AbstractButton.TextBesideIcon; PC3.ToolTip.text: "Back to where you were, nothing moved (" + effect.keyLabel(effect.configuration.KeyCancel) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.cancel() }
                            Sep {}
                            PC3.ToolButton { icon.name: "help-contextual"; text: "Help"; display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.helpOpen; onToggled: effect.helpOpen = checked; PC3.ToolTip.text: "Controls"; PC3.ToolTip.visible: hovered }
                            PC3.ToolButton {
                                icon.name: "configure"; text: "Settings"; display: PC3.AbstractButton.IconOnly
                                PC3.ToolTip.text: "Settings"; PC3.ToolTip.visible: hovered
                                onClicked: settingsMenu.open()
                                PC3.Menu {
                                    id: settingsMenu
                                    onOpened: effect.canvasMenus++
                                    onClosed: effect.canvasMenus = Math.max(0, effect.canvasMenus - 1)
                                    background: MenuBackground { }
                                    x: hud.vertical ? (hud.atRight ? -width : parent.width) : 0
                                    y: hud.vertical ? 0 : parent.height
                                    PC3.MenuItem { text: "Effect settings…";  icon.name: "preferences-desktop-effects"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kwin_effects") }
                                    PC3.MenuItem { text: "Shortcuts…";        icon.name: "preferences-desktop-keyboard"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_keys") }
                                    PC3.MenuItem { text: "Screen edges…";     icon.name: "preferences-desktop-screen-edges"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kwinscreenedges") }
                                    PC3.MenuItem { text: "Activities…";       icon.name: "activities"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_activities") }
                                }
                            }
                        }
                    }

                    // Help: the bindings, read from the same config the actions use.
                    Rectangle {
                        z: 100000
                        visible: effect.helpOpen && hud.visible
                        opacity: effect.chromeFade
                        anchors.top: hud.vertical ? hud.top : (hud.atBottom ? undefined : hud.bottom)
                        anchors.bottom: !hud.vertical && hud.atBottom ? hud.top : undefined
                        anchors.left: hud.vertical ? (hud.atLeft ? hud.right : undefined) : (hud.atLeft ? hud.left : undefined)
                        anchors.right: hud.vertical ? (hud.atRight ? hud.left : undefined) : (hud.atRight ? hud.right : undefined)
                        anchors.horizontalCenter: !hud.vertical && !hud.atLeft && !hud.atRight ? hud.horizontalCenter : undefined
                        anchors.margins: Kirigami.Units.smallSpacing
                        width: helpGrid.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: helpGrid.implicitHeight + Kirigami.Units.largeSpacing * 2
                        radius: Kirigami.Units.cornerRadius
                        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        Kirigami.Theme.inherit: false
                        Kirigami.Theme.colorSet: Kirigami.Theme.Window
                        HoverHandler {
                            onHoveredChanged: view.hoverCount += hovered ? 1 : -1
                            Component.onDestruction: if (hovered) view.hoverCount -= 1
                        }
                        GridLayout {
                            id: helpGrid
                            anchors.centerIn: parent
                            columns: 2
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: Kirigami.Units.smallSpacing
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "drag ground / " + effect.keyLabel(effect.configuration.KeyPan) + "+drag / middle-drag" } PC3.Label { text: "pan" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "hold " + effect.holdLabel(effect.configuration.PanHold) + " or middle" } PC3.Label { text: "the canvas takes the pointer: drag the ground to pan, drag a window to move it" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "hold it / to a screen edge" }                        PC3.Label { text: "the canvas keeps panning; a window in hand comes along" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "hold " + effect.holdLabel(effect.configuration.CanvasHold) } PC3.Label { text: "on the desktop: the location itself becomes the canvas; drags and the wheel work, release applies" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "hold it, tap " + effect.holdLabel(effect.configuration.SwapButton) } PC3.Label { text: "tour the clusters - the plane's desktops - the camera hops to the next one" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "click a window / rest on it" }                        PC3.Label { text: "the camera pans the least that fits it wholly into view" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "wheel / " + effect.keyLabel(effect.configuration.KeyZoomIn) + " / " + effect.keyLabel(effect.configuration.KeyZoomOut) } PC3.Label { text: "zoom at the cursor" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "drag window" }                                       PC3.Label { text: "move it on the plane" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "drag window edge or corner" }                        PC3.Label { text: "resize it" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "drag frame tag or edge" }                            PC3.Label { text: "move that activity's screens" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "eye on a frame tag" }                                PC3.Label { text: "hide or show that frame; a hidden frame takes no windows" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseSelect) + " window" }        PC3.Label { text: "select it" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseSelectAdd) + " window, or +drag ground" } PC3.Label { text: "add to the selection, or select by rectangle" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseSelectToggle) + " window" }  PC3.Label { text: "toggle its selection; a selected window drags the whole selection" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseContextMenu) + " window" }   PC3.Label { text: "arrange the selection: horizontal, vertical, tile, grid, cascade" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseFocusWindow) + " window" }   PC3.Label { text: effect.focusHelp() }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseZoomToActivity) + " frame" }  PC3.Label { text: "zoom to that activity" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseGotoActivity) + " frame" }    PC3.Label { text: "apply with that activity current" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.gestureLabel(effect.configuration.MouseNewActivityAt) + " window outside frames" } PC3.Label { text: "new activity centred on it" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyNext) + " / " + effect.keyLabel(effect.configuration.KeyPrev) } PC3.Label { text: "step the selection through the windows; the camera follows" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyPanLeft) + " / " + effect.keyLabel(effect.configuration.KeyPanRight) + " / " + effect.keyLabel(effect.configuration.KeyPanUp) + " / " + effect.keyLabel(effect.configuration.KeyPanDown) } PC3.Label { text: "pan the camera one step" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "1..9" }                                          PC3.Label { text: "jump straight to that cluster - its number on the badge; the camera returns to the spot you left it at" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "Ctrl+1..9 / Alt+1..9" }                    PC3.Label { text: "keep this view in that slot / fly back to it - the camera's place and how far out" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: "the dot in the toolbar" }                          PC3.Label { text: "whose hand is on the pointer: filled - the window's, hollow - the canvas's" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyApply) }      PC3.Label { text: "enter the location under the screen centre; with a window selected, enter it focused" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyCancel) }     PC3.Label { text: "back to where you were, nothing moved" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyHome) }       PC3.Label { text: "look through this activity's frames" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyOrigin) }     PC3.Label { text: "camera to the canvas origin" }
                            PC3.Label { font.family: "monospace"; opacity: 0.85; text: effect.keyLabel(effect.configuration.KeyFit) }        PC3.Label { text: "zoom to fit" }
                        }
                    }
                }
            }
        }



    }

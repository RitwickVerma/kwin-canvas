/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "map.h"

#include <input.h>
#include <input_event.h>
#include <plugin.h>

#include <KConfigWatcher>
#include <QHash>
#include <QMatrix4x4>
#include <QPointF>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QTimer>

namespace KWin
{
class Item;
class Window;
class LogicalOutput;
class SurfaceInterface;
}

/**
 * One window's watch for where its frame sits in its thumbnail texture: revision changes when
 * the window item's bounding rect (the texture's extent) or the shadow changes. Per window, so a
 * window's resize re-reads only its own picture's frame. The item comes when a Wayland window
 * first maps, and KWin may build it again; the watch looks for it on every map and frame change.
 */
class CanvasFrameWatch : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    CanvasFrameWatch(KWin::Window *window, QObject *parent);

    int revision() const
    {
        return m_revision;
    }

Q_SIGNALS:
    void revisionChanged();

private:
    void bump();
    void hookItem();
    QPointer<KWin::Window> m_window;
    QPointer<KWin::Item> m_item;
    QMetaObject::Connection m_itemConnection;
    int m_revision = 0;
};

/**
 * The canvas scene's in-process helper, set on KWin's QML engine as the context property
 * canvasPlugin. A thumbnail's texture is KWin's own render of the window with its shadow
 * (Window::visibleGeometry), and where the window sits inside it is readable only from C++:
 * frameInTexture answers that synchronously, so the scene draws a window's picture straight from
 * KWin's texture with the Rounded Corners shape instead of rendering it into a layer of its own
 * (a second full-size texture and a second pass per window). frameWatch(window) says when to
 * ask again for that window; revision, for an older effect, changes whenever any window's
 * shadow does.
 */
class CanvasSceneHelper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    explicit CanvasSceneHelper(QObject *parent = nullptr);

    int revision() const
    {
        return m_revision;
    }
    /**
     * The window's frame inside its thumbnail texture: [left, top, frame width, frame height,
     * visible width, visible height] in logical pixels, left and top measured from the
     * texture's edge; empty when @p window is not a KWin window.
     */
    Q_INVOKABLE QVariantList frameInTexture(QObject *window) const;
    /**
     * The window's CanvasFrameWatch, made on first ask and kept until the window goes; null when
     * @p window is not a KWin window.
     */
    Q_INVOKABLE QObject *frameWatch(QObject *window);
    /**
     * How many application windows KWin is drawing offscreen for a thumbnail
     * (Window::isOffscreenRendering): each is copied on every frame it changes and, hidden or
     * minimized, kept drawing at the screen's rate. A closed canvas should hold none; the state
     * line reports it. Desktop windows are left out: the scene keeps a picture wallpaper's, which
     * never changes.
     */
    Q_INVOKABLE int offscreenWindows() const;
    /**
     * How full the GPU's memory is, as a used percentage via NVML, or -1 without it. Synchronous
     * and cheap (one driver call): a closed canvas asks it every few seconds while it keeps a
     * scene, and lets the scene go when a game fills the card.
     */
    Q_INVOKABLE int gpuMemory() const;
    /**
     * Moves @p window's frame so its top-left is (@p x, @p y), as a move (Window::move), keeping
     * its size. A script's frameGeometry write is a move-and-resize: at an unchanged size KWin
     * moves the frame at once, but every configure already sent to the client keeps the place
     * the window had when it was sent, and when the client commits one (a focus change's,
     * committed late by a busy client or one the canvas covered) KWin puts the window back
     * there. A move re-aims those configures at the new place. False when @p window is not a
     * KWin window or is gone.
     */
    Q_INVOKABLE bool moveWindow(QObject *window, qreal x, qreal y);

Q_SIGNALS:
    void revisionChanged();

private:
    void watch(KWin::Window *window);
    int m_revision = 0;
    QHash<const KWin::Window *, CanvasFrameWatch *> m_frameWatches;
};

/**
 * Input pass-through for the kwin-canvas effect.
 *
 * While the canvas is open it holds every input event, and the windows on
 * screen are thumbnails. This filter sits between KWin's global-shortcut
 * filter and its effects filter. When the canvas tells it the camera (view,
 * zoom, the per-activity targets) and switches it on, it maps each pointer
 * event from the screen onto the plane, finds the topmost drawn window
 * there, and hands the event to that window's surface as if the pointer were
 * over it at 1:1. Events over the ground, and over a window's decoration,
 * fall through to the canvas.
 *
 * A press inside a window's client area raises the window and starts an
 * implicit grab that lasts until every button is up. A press of a canvas
 * button (setNavButtons) is the canvas's instead, wherever it lands, so a held
 * button is a portal into the canvas rather than something the window sees. A
 * press on the ground leaves the whole gesture to the canvas. The hold button
 * (setHoldButtons) is the same story wherever it lands: a quick release is
 * replayed as the window's own click, a hold outlasting the threshold opens
 * the canvas. Hover and wheel go to the window under the pointer. Every key
 * goes to the seat's focused
 * surface, which KWin keeps on the active window; global chords have already
 * had their turn, so the canvas's own chord still fires.
 *
 * The canvas talks to it over D-Bus on KWin's bus name, object /KWinCanvas,
 * interface org.kde.kwin.canvas.Passthrough.
 */
class CanvasPassthrough : public KWin::Plugin, public KWin::InputEventFilter
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwin.canvas.Passthrough")

public:
    CanvasPassthrough();
    ~CanvasPassthrough() override;

public Q_SLOTS:
    /** Identity and the KWin this was built for: "kwin-canvas-passthrough VERSION kwin KWIN". */
    Q_SCRIPTABLE QString probe() const;
    /** Switch the filter on or off. Off drops any grab and leaves the hovered surface. */
    Q_SCRIPTABLE void setActive(bool active);
    /**
     * The canvas camera. targetsJson maps activity id to {"x":..,"y":..},
     * the canvas point each activity's frames put at global (0,0).
     */
    Q_SCRIPTABLE void setCamera(double viewX, double viewY, double zoom, const QString &currentActivity, const QString &targetsJson);
    /**
     * Separate cameras: the output the canvas is open on ("" with the cameras merged).
     * A pointer on any other output is the real desktop - the windows at their real
     * places, the hover immediate - because the effect draws that output as a replica of
     * its desk. targetsJson of setCamera then also holds "activity|output" targets.
     */
    Q_SCRIPTABLE void setSeparate(const QString &activeOutput);
    /**
     * The mouse buttons the canvas owns while they are down (its PanHold
     * buttons, the middle button). A press of one of them is never handed to a
     * window and never starts a grab, wherever the pointer is: it goes to the
     * canvas, whose QML then owns the whole gesture - drag the ground to pan,
     * drag a window to move it on the plane, hold still at a screen edge to
     * keep panning. Motion and wheel while one is down stay the canvas's too.
     * Zero restores the plain pass-through of every button. (An int: the effect
     * sends it as one, since QDBus does not demote a double to an int slot.)
     */
    Q_SCRIPTABLE void setNavButtons(int buttons);
    /**
     * How long the canvas-modifier buttons must stay down (ms) before the
     * press is the canvas rather than a click (the effect's HoldDelay).
     */
    Q_SCRIPTABLE void setHoldDelay(int ms);
    /**
     * How long the pointer must rest on a window (ms) before input passes
     * through to it (the effect's HoverDelay).
     */
    Q_SCRIPTABLE void setHoverDelay(int ms);
    /**
     * The zoom door (WheelDoor): with the canvas closed, a wheel over the
     * bare ground opens the canvas at the seam and zooms the world out.
     */
    Q_SCRIPTABLE void setDoorEnabled(bool enabled);
    /**
     * The canvas-modifier buttons (CanvasHold). A press of one of them is
     * consumed wherever the pointer is and flips the effect's canvasHold
     * property, so the effect can open quietly at 1:1 and commit on the
     * release - the hold that makes the location itself the canvas. This
     * works while the canvas is closed, which is the whole point: the filter
     * sees the press before any window does. Zero turns the modifier off.
     */
    Q_SCRIPTABLE void setHoldButtons(int buttons);
    /**
     * The trace flag: with it on, every decision this filter takes (hold
     * press and release, click replay, enter and leave, the overlay's
     * ownership of the pointer) is logged, so the effect's and the
     * plugin's halves of a gesture can be read side by side in KWin's log.
     */
    Q_SCRIPTABLE void setVerbose(bool verbose);
    /**
     * Keep the canvas's scene views alive between openings instead of KWin
     * destroying and building them on every open (QuickSceneEffect's view
     * caching, which is not a QML property). Returns whether the canvas effect
     * was found and now has it as asked.
     */
    Q_SCRIPTABLE bool setViewCaching(bool enabled);
    /**
     * How the Rounded Corners effect (kwin4_effect_shapecorners) shapes windows, as JSON, so the
     * canvas can shape its thumbnails the same way: a thumbnail is drawn past KWin's effects.
     * {"on": loaded, "active": px, "inactive": px, "squircle": 0..1, "tile", "max", "full": skip
     * those windows, "exclusions": [...], "inclusions": [...]}; its own defaults where kwinrc
     * has no value.
     */
    Q_SCRIPTABLE QString cornerStyle() const;
    /**
     * How the blur effect blurs windows, as JSON, so the canvas can put the same blur behind its
     * thumbnails: a thumbnail is drawn past KWin's effects. {"effect": the loaded blur effect
     * ("better_blur_dx", "blur") or "", "strength", "noise", and for Better Blur DX its force
     * blur: "radius", "force": "only" (the classes listed) or "all-but" (every class but them),
     * "classes": [...], "menus", "docks"; "regions": {internalId: [[x, y, w, h], ...]}, the blur
     * a Wayland window asks for itself, in its frame's coordinates}. The effect's own defaults
     * where kwinrc has no value.
     */
    Q_SCRIPTABLE QString blurStyle() const;
    Q_SCRIPTABLE QString state() const;
    /**
     * The machine's load, for the fidelity ladder: "cpu=N load=NN.NN
     * mem=MMMM gpu=GGG vram=VVV". cpu is the busy percentage since the
     * previous call (0 on the first), load is the one-minute average, mem
     * is the memory's used share as a percentage, gpu is the GPU's busy
     * share and vram the used share of its memory, both via NVML or -1
     * where the driver is absent. Cheap: three /proc reads, polled every
     * couple of seconds while the overworld is open.
     */
    Q_SCRIPTABLE QString load() const;
    // The live keyboard modifier mask, for the switcher's release
    // detection: the effect polls this while a chord-held switcher is up,
    // and reads the chord's end when its modifier clears.
    Q_SCRIPTABLE int modifiers() const;
    // The panel applet's window decor: one of close, minimize, maximize,
    // float, applied to the focused window through the real KWin::Window
    // API - in-process, so it works with the canvas closed too, including
    // on maximized windows, which wear no decoration bar.
    Q_SCRIPTABLE void windowAction(const QString &action);
    // The shader channel: the effect pushes the plane's remembered state
    // (the view, the clusters, the day-trail) at each commit; the plugin
    // writes it as a plain text file the shader wallpaper's engine can
    // hand to a fragment shader as uniforms, screen-projected here.
    Q_SCRIPTABLE void setCanvasState(const QString &state);

Q_SIGNALS:
    // The focused window changed, or one of its flags did (maximized, floating, keep above or
    // below, excluded from capture, the caption), or the title-bar button order was written:
    // the decor applet reads state() on this instead of polling for it.
    Q_SCRIPTABLE void windowChanged();

public:
    bool pointerMotion(KWin::PointerMotionEvent *event) override;
    bool pointerButton(KWin::PointerButtonEvent *event) override;
    bool pointerAxis(KWin::PointerAxisEvent *event) override;
    bool keyboardKey(KWin::KeyboardKeyEvent *event) override;

private:
    QPointF toCanvas(const QPointF &screen) const;
    QPointF targetOf(KWin::Window *window) const;
    /** The output holding a global point, or null. */
    KWin::LogicalOutput *outputAt(const QPointF &point) const;
    /** The output a window's frame sits on (its centre's, else the nearest). */
    KWin::LogicalOutput *outputOfWindow(KWin::Window *window) const;
    /** The target of the current activity on one output, for a pointer on a replica output. */
    QPointF replicaTarget(const KWin::LogicalOutput *output) const;
    bool drawn(KWin::Window *window) const;
    KWin::Window *windowAt(const QPointF &canvas) const;
    /** The topmost client window under a real screen point: the click candidate at 1:1. */
    KWin::Window *windowUnder(const QPointF &screen) const;
    /**
     * The system's own chrome - a dock, a panel, a popup, an applet's
     * dropdown - under a real screen point, or nullptr when the point is
     * the canvas's domain (a plain client or nothing). The chrome owns its
     * pixels outright; the first client containing the point decides.
     */
    KWin::Window *chromeAt(const QPointF &screen) const;
    /** Publish the chrome flag to the effect on every change. */
    void publishChrome(const QPointF &screen);
    /** Out of idle, if it was: the input is live again, and the effect hears it (passthroughIdle). */
    void wakeFromIdle();
    /** The startup registrations (the D-Bus objects, the scene helper), tried again until they take. */
    void registerLater(int attempt);
    /** The tally, the grab and the hold follow the buttons an event says are down (a release can pass this filter by). */
    void reconcileButtons(Qt::MouseButtons down);
    /** The native title-bar button order, from kwinrc, for the decor applet. */
    void readButtonOrder();
    /** Follow the focused window's flags, and tell the decor applet when any of them change. */
    void watchActive(KWin::Window *w);
    /**
     * The kwin-canvas effect, or nullptr: looked up once and kept, since the filter publishes on
     * most events and findEffect walks every loaded effect. A reloaded effect is a new object;
     * the pointer goes null with the old one and the next call looks again.
     */
    QObject *canvasEffect() const;
    void publishRest(KWin::Window *w);
    void publishHover(KWin::Window *w);
    bool atSeam(const QPointF &screen) const;
    /** Enter (or stay on) the input surface of @p window under @p canvas. False if no surface takes input there. */
    bool enter(KWin::Window *window, const QPointF &canvas);
    void leave();
    void clearGrab();
    /** A hold-button press that was a click, not a hold: replay press and release to the window under the pointer. */
    void replayClick();

    bool m_active = false;
    /** The pointer's last global position, for the hover clock's re-check. */
    QPointF m_lastPosition;
    /** The pointer has moved since the activation: the passthrough is live. */
    bool m_settled = false;
    double m_viewX = 0;
    double m_viewY = 0;
    double m_zoom = 1;
    QString m_current;
    QHash<QString, QPointF> m_targets;
    /** Separate cameras: the output the canvas is open on, or empty when merged. */
    bool m_separate = false;
    QString m_camOutput;
    /**
     * The output a pointer event is on when that output is not the camera's (a replica
     * of its desk): set by toCanvas for the event being handled, null otherwise. It makes
     * targetOf and drawn read that output's desk at 1:1 for the whole handler.
     */
    mutable const KWin::LogicalOutput *m_replica = nullptr;
    /** The trace flag (setVerbose): log every decision this filter takes. */
    bool m_verbose = false;
    /** The zoom door (WheelDoor): the wheel over the ground opens the canvas. */
    bool m_door = true;

    QPointer<KWin::Window> m_grab;
    bool m_grabGround = false;
    Qt::MouseButtons m_buttons;
    /** Buttons the canvas owns while they are down (setNavButtons), a mask of Qt::MouseButton values. */
    uint m_nav = 0;
    /** The canvas-modifier buttons (setHoldButtons), a mask of Qt::MouseButton values. */
    uint m_hold = 0;
    /** The passthrough let go of the input: no input for a while, so the
     * canvas has it back - the keys, the wheel and the clicks are the
     * canvas's until the next touch. */
    bool m_idle = false;
    mutable QPointer<QObject> m_canvasEffect;
    // What publishRest and publishHover last told the effect: an unchanged value is not written
    // again (the filter asks on every motion). Cleared when the effect is looked up afresh.
    mutable QString m_restPublished;
    mutable QString m_hoverPublished;
    // The state the shader file last got: an unchanged one is not written (a save is an fsync on
    // the compositor's thread, and the effect sends it every second while open).
    QString m_canvasStateWritten;
    // Keys whose press went to a window: their release goes there too, wherever the pointer is by
    // then, or the client's own repeat runs on. Cleared when the canvas lets the input go.
    QSet<quint32> m_keysToWindow;
    /** The D-Bus object is registered: the startup retries stop once it is. */
    bool m_registered = false;
    /** The map widget's object (/KWinCanvas/Map), registered by the same retries. */
    CanvasMap m_map;
    bool m_mapRegistered = false;
    /** The idle clock: restarted on every input event. */
    QTimer m_idleTimer;
    /** A hold button is currently down (one of m_hold). */
    bool m_holdDown = false;
    /** The hold button that is down, for the mask-change check in setHoldButtons. */
    Qt::MouseButton m_heldButton = Qt::NoButton;
    /** A hold button is down but the threshold has not passed: it may still be a click. */
    bool m_holdCandidate = false;
    /** The candidate's button, for the replay and the mask check. */
    Qt::MouseButton m_candidateButton = Qt::NoButton;
    /** The candidate's button as the device sent it (evdev code), which the replay hands on
     *  unchanged: see sendButton in passthrough.cpp. */
    quint32 m_candidateNativeButton = 0;
    /** Every button currently down, whatever owns it: published to the effect, which defers a focus fly until the hand lets go. */
    Qt::MouseButtons m_allButtons;
    /** The hold threshold: a hold button must stay down this long to open the canvas. */
    QTimer m_holdTimer;
    QPointer<KWin::Window> m_hover;
    QPointer<KWin::SurfaceInterface> m_hoverSurface;
    /** The window the pointer rests on, before the hover delay has passed:
     * a pass-over never hands the input over; a rest does. */
    QPointer<KWin::Window> m_hoverCandidate;
    /** The hover delay: how long the pointer must rest on a window before
     * the passthrough takes it over. */
    QTimer m_hoverTimer;
    /** A left press on a window while the canvas is closed: a candidate click
     * the effect flies to on the release - a click on an already-active window
     * raises no activation, so the press is the only trace of it. */
    QPointer<KWin::Window> m_clickWindow;
    /** The native title-bar button order (kwinrc, org.kde.kdecoration2), kept current by a config watcher. */
    QString m_buttonsLeft;
    QString m_buttonsRight;
    KConfigWatcher::Ptr m_configWatcher;
    /** The focused window whose flag changes are told to the decor applet (windowChanged). */
    QPointer<KWin::Window> m_watchedActive;
    /** Where the candidate press landed: motion beyond a few pixels makes it a drag. */
    QPointF m_clickPos;
    /** The pointer sits over the system's own chrome (a dock, a panel, a
     * popup): published to the effect so its scene stands back and the
     * chrome gets the click natively. */
    bool m_chromeHover = false;
    /** The QML scene's helper (CanvasSceneHelper), once KWin's QML engine has it. */
    QPointer<CanvasSceneHelper> m_sceneHelper;
    mutable qulonglong m_prevTotal = 0;
    mutable qulonglong m_prevIdle = 0;
};

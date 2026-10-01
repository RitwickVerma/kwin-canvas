/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <input.h>
#include <input_event.h>
#include <plugin.h>

#include <QHash>
#include <QMatrix4x4>
#include <QPointF>
#include <QPointer>
#include <QString>
#include <QTimer>

namespace KWin
{
class Window;
class SurfaceInterface;
}

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
 * press on the ground leaves the whole gesture to the canvas. Hover and wheel
 * go to the window under the pointer. Every key goes to the seat's focused
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
     * The mouse buttons the canvas owns while they are down (its PanHold
     * buttons, the middle button). A press of one of them is never handed to a
     * window and never starts a grab, wherever the pointer is: it goes to the
     * canvas, whose QML then owns the whole gesture - drag the ground to pan,
     * drag a window to move it on the plane, hold still at a screen edge to
     * keep panning. Motion and wheel while one is down stay the canvas's too.
     * Zero restores the plain pass-through of every button. (A double because
     * the effect's DBusCall marshals its numbers that way.)
     */
    Q_SCRIPTABLE void setNavButtons(int buttons);
    /**
     * How long the canvas-modifier buttons must stay down (ms) before the
     * press is the canvas rather than a click (the effect's HoldDelay).
     */
    Q_SCRIPTABLE void setHoldDelay(int ms);
    /**
     * The canvas-modifier buttons (CanvasHold). A press of one of them is
     * consumed wherever the pointer is and flips the effect's canvasHold
     * property, so the effect can open quietly at 1:1 and commit on the
     * release - the hold that makes the location itself the canvas. This
     * works while the canvas is closed, which is the whole point: the filter
     * sees the press before any window does. Zero turns the modifier off.
     */
    Q_SCRIPTABLE void setHoldButtons(int buttons);
    /** One line of state for the nest harness: active, camera, grab, hover. */
    Q_SCRIPTABLE QString state() const;

public:
    bool pointerMotion(KWin::PointerMotionEvent *event) override;
    bool pointerButton(KWin::PointerButtonEvent *event) override;
    bool pointerAxis(KWin::PointerAxisEvent *event) override;
    bool keyboardKey(KWin::KeyboardKeyEvent *event) override;

private:
    QPointF toCanvas(const QPointF &screen) const;
    QPointF targetOf(KWin::Window *window) const;
    bool drawn(KWin::Window *window) const;
    KWin::Window *windowAt(const QPointF &canvas) const;
    /** The topmost client window under a real screen point: the click candidate at 1:1. */
    KWin::Window *windowUnder(const QPointF &screen) const;
    /** The seam: within the margin of the desk's outer border, where a shared mouse parks its pointer. */
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
    /** Where the candidate press landed: motion beyond a few pixels makes it a drag. */
    QPointF m_clickPos;
};

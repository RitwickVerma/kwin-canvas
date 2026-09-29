/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "passthrough.h"

#include <config-kwin.h>
#include <effect/effecthandler.h>
#include <wayland/seat.h>
#include <wayland/surface.h>
#include <wayland_server.h>
#include <window.h>
#include <workspace.h>

#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusConnection>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QTimer>

Q_LOGGING_CATEGORY(KWIN_CANVAS, "kwin_canvas_passthrough", QtWarningMsg)

using namespace KWin;

static const QString s_path = QStringLiteral("/KWinCanvas");

// The canvas-modifier buttons as a mask, from the effect's config. The
// plugin reads this itself at startup: the effect publishes the mask over
// D-Bus, but its publish can race the plugin's own startup, and a missed
// publish would leave the modifier dead until the next reconfigure. The
// names carry both Qt values for the side buttons, as the effect does -
// KWin delivers MB5 as ExtraButton3, not ForwardButton.
static uint parseHoldButtons(const QString &spec)
{
    uint mask = 0;
    const QStringList names = spec.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &raw : names) {
        const QString n = raw.trimmed().toLower();
        if (n == QLatin1String("leftbutton")) {
            mask |= Qt::LeftButton;
        } else if (n == QLatin1String("middlebutton")) {
            mask |= Qt::MiddleButton;
        } else if (n == QLatin1String("rightbutton")) {
            mask |= Qt::RightButton;
        } else if (n == QLatin1String("forwardbutton")) {
            mask |= Qt::ForwardButton | Qt::ExtraButton3;
        } else if (n == QLatin1String("backbutton")) {
            mask |= Qt::BackButton | Qt::ExtraButton4;
        }
    }
    return mask;
}

CanvasPassthrough::CanvasPassthrough()
    : Plugin()
    // KWin inserts a filter before the first one of equal or greater weight,
    // so this lands after the global-shortcut filter and before the effects.
    , InputEventFilter(InputFilterOrder::Effects)
{
    input()->installInputEventFilter(this);
    // The session bus can still be starting when the plugin loads; a failed
    // registration is retried a few times rather than lost, since the effect
    // only ever finds the plugin through this object.
    for (int i = 1; i <= 5; ++i) {
        QTimer::singleShot(200 * i, this, [this]() {
            QDBusConnection::sessionBus().registerObject(s_path, this, QDBusConnection::ExportScriptableSlots);
        });
    }
    // The hold mask from the config, so a missed publish cannot leave the
    // modifier dead; the effect's setHoldButtons keeps it current.
    m_hold = parseHoldButtons(KSharedConfig::openConfig(QStringLiteral("kwinrc"))->group(QStringLiteral("Effect-kwin-canvas")).readEntry("CanvasHold", QStringLiteral("BackButton")));
    m_holdTimer.setSingleShot(true);
    m_holdTimer.setInterval(300);
    connect(&m_holdTimer, &QTimer::timeout, this, [this]() {
        // The hold outlasted the threshold: it is the canvas modifier, not a
        // click. The press was consumed from the start, so the window under
        // the pointer never saw it and has nothing to release.
        m_holdCandidate = false;
        m_holdDown = true;
        m_heldButton = m_candidateButton;
        if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
            canvas->setProperty("canvasHold", true);
        }
    });
}

CanvasPassthrough::~CanvasPassthrough()
{
    QDBusConnection::sessionBus().unregisterObject(s_path);
    input()->uninstallInputEventFilter(this);
}

QString CanvasPassthrough::probe() const
{
    return QStringLiteral("kwin-canvas-passthrough %1 kwin %2").arg(QStringLiteral(CANVAS_VERSION), KWIN_VERSION_STRING);
}

void CanvasPassthrough::setActive(bool active)
{
    if (m_active == active) {
        return;
    }
    m_active = active;
    if (!active) {
        clearGrab();
        leave();
    }
}

void CanvasPassthrough::setCamera(double viewX, double viewY, double zoom, const QString &currentActivity, const QString &targetsJson)
{
    m_viewX = viewX;
    m_viewY = viewY;
    m_zoom = zoom > 0 ? zoom : 1;
    m_current = currentActivity;
    m_targets.clear();
    const QJsonObject all = QJsonDocument::fromJson(targetsJson.toUtf8()).object();
    for (auto it = all.begin(); it != all.end(); ++it) {
        const QJsonObject t = it->toObject();
        m_targets.insert(it.key(), QPointF(t.value(QStringLiteral("x")).toDouble(), t.value(QStringLiteral("y")).toDouble()));
    }
}

void CanvasPassthrough::setNavButtons(int buttons)
{
    m_nav = uint(buttons);
}

void CanvasPassthrough::setHoldButtons(int buttons)
{
    const uint mask = uint(buttons);
    if (m_hold == mask) {
        return;
    }
    m_hold = mask;
    // The mask changed under a held button: treat the hold as over, so the
    // canvas closes rather than waiting for a release that no longer counts.
    if (m_holdDown && !(mask & uint(m_heldButton))) {
        m_holdDown = false;
        if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
            canvas->setProperty("canvasHold", false);
        }
    }
    // A press still waiting out the threshold, for a button that no longer
    // counts, is replayed as the click it was.
    if (m_holdCandidate && !(mask & uint(m_candidateButton))) {
        m_holdCandidate = false;
        m_holdTimer.stop();
        replayClick();
    }
}

// The press of a hold button that turned out to be a click, not a hold:
// deliver it to the window under the pointer, press and release, at the
// pointer's own place. The seat's pointer state is whatever the normal
// chain keeps - the real window at 1:1, the plugin's hover in the overworld
// - so only the buttons need replaying.
void CanvasPassthrough::replayClick()
{
    SeatInterface *seat = waylandServer()->seat();
    seat->notifyPointerButton(m_candidateButton, PointerButtonState::Pressed);
    seat->notifyPointerFrame();
    seat->notifyPointerButton(m_candidateButton, PointerButtonState::Released);
    seat->notifyPointerFrame();
}

QString CanvasPassthrough::state() const
{
    return QStringLiteral("active=%1 view=(%2,%3) zoom=%4 grab=%5 ground=%6 hover=%7 nav=%8 hold=%9")
        .arg(m_active ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(m_viewX)
        .arg(m_viewY)
        .arg(m_zoom)
        .arg(m_grab ? m_grab->caption() : QStringLiteral("-"))
        .arg(m_grabGround ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(m_hover ? m_hover->caption() : QStringLiteral("-"))
        .arg(m_nav)
        .arg(m_hold);
}

// ---- the plane ---------------------------------------------------------------

QPointF CanvasPassthrough::toCanvas(const QPointF &screen) const
{
    return QPointF(m_viewX + screen.x() / m_zoom, m_viewY + screen.y() / m_zoom);
}

// The activity a window belongs to for placement: the current one when it is
// there or on every activity, else its first. Same rule as the effect.
QPointF CanvasPassthrough::targetOf(Window *window) const
{
    QString id = m_current;
    if (!window->isOnAllActivities() && !window->isOnActivity(m_current)) {
        const QStringList a = window->activities();
        if (!a.isEmpty()) {
            id = a.first();
        }
    }
    return m_targets.value(id, QPointF(m_viewX, m_viewY));
}

// What the quiet canvas draws: at 1:1 this activity's windows, zoomed out
// every activity's. Same filter as the effect's entries.
bool CanvasPassthrough::drawn(Window *window) const
{
    if (!window->isClient() || window->isDeleted() || window->isUnmanaged()) {
        return false;
    }
    if (window->isDesktop() || window->isDock() || window->isPopupWindow() || window->isSpecialWindow()) {
        return false;
    }
    if (window->isMinimized() || window->isHidden() || !window->isOnCurrentDesktop()) {
        return false;
    }
    if (m_zoom < 0.999) {
        return true;
    }
    return window->isOnAllActivities() || window->isOnActivity(m_current);
}

Window *CanvasPassthrough::windowAt(const QPointF &canvas) const
{
    const QList<Window *> &stack = workspace()->stackingOrder();
    for (auto it = stack.crbegin(); it != stack.crend(); ++it) {
        Window *w = *it;
        if (!drawn(w)) {
            continue;
        }
        const QRectF frame = QRectF(w->frameGeometry()).translated(targetOf(w));
        if (frame.contains(canvas)) {
            return w;
        }
    }
    return nullptr;
}

// ---- delivery ----------------------------------------------------------------

bool CanvasPassthrough::enter(Window *window, const QPointF &canvas)
{
    SurfaceInterface *root = window->surface();
    if (!root) {
        return false;
    }
    // The window's real global position is the canvas point minus its target;
    // its own input transformation takes that to surface coordinates.
    const QPointF global = canvas - targetOf(window);
    const QMatrix4x4 toSurface = window->inputTransformation();
    const QPointF local = toSurface.map(global);
    // A point outside every input region, a server-side title bar for one,
    // stays the canvas's. mapToInputSurface falls back to the root surface,
    // so ask inputSurfaceAt first, as Window::hitTest does.
    if (!root->inputSurfaceAt(local)) {
        return false;
    }
    const auto [surface, childLocal] = root->mapToInputSurface(local);
    SeatInterface *seat = waylandServer()->seat();
    if (m_hoverSurface != surface) {
        QMatrix4x4 toChild;
        toChild.translate(childLocal.x() - local.x(), childLocal.y() - local.y());
        seat->notifyPointerEnter(surface, global, toChild * toSurface);
        m_hoverSurface = surface;
        m_hover = window;
    } else {
        seat->notifyPointerMotion(global);
    }
    seat->notifyPointerFrame();
    return true;
}

void CanvasPassthrough::leave()
{
    if (m_hoverSurface) {
        SeatInterface *seat = waylandServer()->seat();
        seat->notifyPointerLeave();
        seat->notifyPointerFrame();
    }
    m_hoverSurface = nullptr;
    m_hover = nullptr;
}

void CanvasPassthrough::clearGrab()
{
    m_grab = nullptr;
    m_grabGround = false;
    m_buttons = Qt::NoButton;
}

// ---- the filter --------------------------------------------------------------

bool CanvasPassthrough::pointerMotion(PointerMotionEvent *event)
{
    if (!m_active) {
        return false;
    }
    // A canvas button is down: the whole gesture is the canvas's, wherever the
    // pointer is (a window being dragged on the plane, a pan, an edge). The
    // window under the pointer is not entered and no motion is notified to it.
    if (event->buttons.toInt() & m_nav) {
        return false;
    }
    if (m_grabGround) {
        return false;
    }
    const QPointF canvas = toCanvas(event->position);
    if (m_grab) {
        // Implicit grab: the window keeps the pointer until the buttons are up.
        if (!enter(m_grab, canvas)) {
            waylandServer()->seat()->notifyPointerMotion(canvas - targetOf(m_grab));
            waylandServer()->seat()->notifyPointerFrame();
        }
        return true;
    }
    Window *w = windowAt(canvas);
    if (w && enter(w, canvas)) {
        return true;
    }
    leave();
    return false;
}

bool CanvasPassthrough::pointerButton(PointerButtonEvent *event)
{
    // Every button change is published to the effect: a focus fly must wait
    // until the hand lets go, or the opening canvas would grab the drag.
    const bool wasAny = m_allButtons != Qt::NoButton;
    if (event->state == PointerButtonState::Pressed) {
        m_allButtons |= event->button;
    } else {
        m_allButtons &= ~event->button;
    }
    if (wasAny != (m_allButtons != Qt::NoButton)) {
        if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
            canvas->setProperty("pointerButtons", int(m_allButtons));
        }
    }
    // A canvas-modifier button (CanvasHold) is a modifier, never a click: no
    // window ever sees it, wherever the pointer is and whether or not the
    // canvas is open. Each press and release flips the effect's canvasHold
    // property, which opens the canvas quietly at 1:1 for the hold and
    // commits on the release - the hold that makes the location itself the
    // canvas. It works while the canvas is closed because this filter sees
    // the press before anything else does.
    if (uint(event->button) & m_hold) {
        const bool pressed = event->state == PointerButtonState::Pressed;
        if (pressed) {
            if (!m_holdDown && !m_holdCandidate) {
                // The press is consumed from the start and the threshold
                // decides what it was: outlasted, it is the canvas modifier;
                // released first, it is replayed as the click it was.
                m_holdCandidate = true;
                m_candidateButton = Qt::MouseButton(uint(event->button));
                m_holdTimer.start();
            }
        } else {
            if (m_holdDown) {
                m_holdDown = false;
                if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
                    canvas->setProperty("canvasHold", false);
                }
            } else if (m_holdCandidate) {
                // A quick press, not a hold: give the window the click the
                // modifier would have swallowed, at the pointer's own place.
                m_holdCandidate = false;
                m_holdTimer.stop();
                replayClick();
            }
        }
        return true;
    }
    if (!m_active) {
        return false;
    }
    const bool pressed = event->state == PointerButtonState::Pressed;
    // A canvas button belongs to the canvas: it never starts a grab, never
    // reaches a window, and never leaves one, wherever the pointer is. The
    // release is the canvas's too - the window never saw the press, so it must
    // not see the release - and the button is left out of the bookkeeping that
    // decides when a grab is over.
    if (uint(event->button) & m_nav) {
        return false;
    }
    const bool first = pressed && m_buttons == Qt::NoButton;
    if (pressed) {
        m_buttons |= event->button;
    } else {
        m_buttons &= ~event->button;
    }
    if (first) {
        // A new gesture: the window under the pointer takes it, or the ground does.
        const QPointF canvas = toCanvas(event->position);
        Window *w = windowAt(canvas);
        if (w && enter(w, canvas)) {
            m_grab = w;
            m_grabGround = false;
            workspace()->activateWindow(w);
        } else {
            leave();
            m_grab = nullptr;
            m_grabGround = true;
        }
    }
    bool consumed = false;
    if (m_grab) {
        SeatInterface *seat = waylandServer()->seat();
        seat->notifyPointerButton(event->button, event->state);
        seat->notifyPointerFrame();
        consumed = true;
    }
    if (m_buttons == Qt::NoButton) {
        m_grab = nullptr;
        m_grabGround = false;
    }
    return consumed;
}

bool CanvasPassthrough::keyboardKey(KeyboardKeyEvent *event)
{
    if (!m_active || event->state == KeyboardKeyState::Repeated) {
        return false;
    }
    SeatInterface *seat = waylandServer()->seat();
    if (!seat->focusedKeyboardSurface()) {
        return false;
    }
    seat->notifyKeyboardKey(event->nativeScanCode, event->state, event->serial);
    return true;
}

bool CanvasPassthrough::pointerAxis(PointerAxisEvent *event)
{
    if (!m_active || m_grabGround) {
        return false;
    }
    // With a canvas button down the wheel is the canvas's too: a notch zooms
    // the canvas at the pointer instead of scrolling the window under it.
    if (event->buttons.toInt() & m_nav) {
        return false;
    }
    const QPointF canvas = toCanvas(event->position);
    Window *w = m_grab ? m_grab.data() : windowAt(canvas);
    if (!w || !enter(w, canvas)) {
        return false;
    }
    SeatInterface *seat = waylandServer()->seat();
    seat->notifyPointerAxis(event->orientation, event->delta, event->deltaV120, event->source, event->inverted);
    seat->notifyPointerFrame();
    return true;
}

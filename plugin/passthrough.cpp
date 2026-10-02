/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "passthrough.h"

#include <config-kwin.h>
#include <core/output.h>
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

Q_LOGGING_CATEGORY(KWIN_CANVAS, "kwin_canvas_passthrough", QtDebugMsg)

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
    // The passthrough lets go on its own: after a while with no input -
    // the pointer still, no keys - the canvas takes the input back, so
    // the Esc the user reaches for is the canvas's, not the window's,
    // until the next touch.
    m_idleTimer.setInterval(4000);
    m_idleTimer.setSingleShot(false);
    connect(&m_idleTimer, &QTimer::timeout, this, [this]() {
        if (m_active && !m_idle) {
            m_idle = true;
            if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
                canvas->setProperty("passthroughIdle", true);
            }
        }
    });
    // The passthrough engages on a rest, not a pass-over: the pointer must
    // hold still on a window for this long before the window takes the
    // input - sweeping across the overworld stays the canvas's. The delay is
    // the effect's HoverDelay knob, a deliberate pause by default so looking
    // around never activates a window.
    m_hoverTimer.setSingleShot(true);
    m_hoverTimer.setInterval(std::max(50, KSharedConfig::openConfig(QStringLiteral("kwinrc"))->group(QStringLiteral("Effect-kwin-canvas")).readEntry("HoverDelay", 900)));
    connect(&m_hoverTimer, &QTimer::timeout, this, [this]() {
        if (m_hoverCandidate && m_active && !m_grabGround) {
            const QPointF canvas = toCanvas(m_lastPosition);
            if (windowAt(canvas) == m_hoverCandidate.data()) {
                enter(m_hoverCandidate.data(), canvas);
            }
        }
    });
    m_holdTimer.setSingleShot(true);
    m_holdTimer.setInterval(std::max(50, KSharedConfig::openConfig(QStringLiteral("kwinrc"))->group(QStringLiteral("Effect-kwin-canvas")).readEntry("HoldDelay", 300)));
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
    // Fresh activation: the pointer has not aimed yet. The first motion
    // settles the filter, and until it does, buttons and the wheel belong
    // to the canvas - the wheel right after the overworld opens zooms it,
    // not the window that happens to sit under the pointer.
    m_settled = false;
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

void CanvasPassthrough::setHoldDelay(int ms)
{
    if (ms > 0) {
        m_holdTimer.setInterval(ms);
    }
}

void CanvasPassthrough::setHoverDelay(int ms)
{
    if (ms > 0) {
        m_hoverTimer.setInterval(ms);
        qCDebug(KWIN_CANVAS) << "hover delay set to" << ms << "ms";
    }
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

void CanvasPassthrough::setVerbose(bool verbose)
{
    m_verbose = verbose;
    qCDebug(KWIN_CANVAS) << "canvas-passthrough: verbose" << (verbose ? "on" : "off");
}

// The press of a hold button that turned out to be a click, not a hold:
// deliver it to the window under the pointer, press and release, at the
// pointer's own place. The seat's pointer state is whatever the normal
// chain keeps - the real window at 1:1, the plugin's hover in the overworld
// - so only the buttons need replaying.
void CanvasPassthrough::replayClick()
{
    if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: replaying the click the hold threshold did not outlast";
    SeatInterface *seat = waylandServer()->seat();
    seat->notifyPointerButton(m_candidateButton, PointerButtonState::Pressed);
    seat->notifyPointerFrame();
    seat->notifyPointerButton(m_candidateButton, PointerButtonState::Released);
    seat->notifyPointerFrame();
}

QString CanvasPassthrough::state() const
{
    return QStringLiteral("active=%1 view=(%2,%3) zoom=%4 grab=%5 ground=%6 hover=%7 nav=%8 hold=%9 seam=%10")
        .arg(m_active ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(m_viewX)
        .arg(m_viewY)
        .arg(m_zoom)
        .arg(m_grab ? m_grab->caption() : QStringLiteral("-"))
        .arg(m_grabGround ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(m_hover ? m_hover->caption() : QStringLiteral("-"))
        .arg(m_nav)
        .arg(m_hold)
        .arg(atSeam(waylandServer()->seat()->pointerPos()) ? QStringLiteral("1") : QStringLiteral("0"));
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

Window *CanvasPassthrough::windowUnder(const QPointF &screen) const
{
    const QList<Window *> &stack = workspace()->stackingOrder();
    for (auto it = stack.crbegin(); it != stack.crend(); ++it) {
        Window *w = *it;
        if (!w->isClient() || w->isDeleted() || w->isUnmanaged()) {
            continue;
        }
        if (w->isDesktop() || w->isDock() || w->isSpecialWindow()) {
            continue;
        }
        if (w->isMinimized() || w->isHidden() || !w->isOnCurrentDesktop()) {
            continue;
        }
        if (QRectF(w->frameGeometry()).contains(screen)) {
            return w;
        }
    }
    return nullptr;
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

// Does another output's edge run flush along this output's edge at `at`?
// The border between two local screens is a place a living hand rests; the
// desk's outer border is where a shared mouse parks.
static bool seamNeighbour(const QList<LogicalOutput *> &outputs, const LogicalOutput *s, char axis, qreal at)
{
    const Rect g = s->geometry();
    for (const LogicalOutput *r : outputs) {
        if (r == s) {
            continue;
        }
        const Rect h = r->geometry();
        if (axis == 'x') {
            if ((at == h.x() || at == h.x() + h.width()) && h.y() < g.y() + g.height() && g.y() < h.y() + h.height()) {
                return true;
            }
        } else if ((at == h.y() || at == h.y() + h.height()) && h.x() < g.x() + g.width() && g.x() < h.x() + h.width()) {
            return true;
        }
    }
    return false;
}

// The seam, mirroring the effect's seamPoint: within a few pixels of the
// desk's outer border, where deskflow and its kin park the pointer while
// another machine has the mouse. There a rest is not a hover - it is a
// pointer nobody is holding - so no window under it may take the input.
bool CanvasPassthrough::atSeam(const QPointF &screen) const
{
    constexpr qreal margin = 6;
    const QList<LogicalOutput *> outputs = workspace()->outputs();
    for (const LogicalOutput *s : outputs) {
        const Rect g = s->geometry();
        if (screen.x() < g.x() || screen.x() >= g.x() + g.width() || screen.y() < g.y() || screen.y() >= g.y() + g.height()) {
            continue;
        }
        if (screen.x() - g.x() < margin && !seamNeighbour(outputs, s, 'x', g.x())) {
            return true;
        }
        if (g.x() + g.width() - screen.x() < margin && !seamNeighbour(outputs, s, 'x', g.x() + g.width())) {
            return true;
        }
        if (screen.y() - g.y() < margin && !seamNeighbour(outputs, s, 'y', g.y())) {
            return true;
        }
        if (g.y() + g.height() - screen.y() < margin && !seamNeighbour(outputs, s, 'y', g.y() + g.height())) {
            return true;
        }
        return false;
    }
    return false;
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
        if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: entered" << window->caption();
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
        if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: left the hover";
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
    // A candidate click turned drag: the effect must not fly to it.
    if (m_clickWindow && (event->position - m_clickPos).manhattanLength() > 6) {
        m_clickWindow = nullptr;
    }
    if (m_idle) {
        m_idle = false;
        if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
            canvas->setProperty("passthroughIdle", false);
        }
    }
    m_idleTimer.start();
    if (!m_active) {
        return false;
    }
    // The first motion is the user aiming at the canvas: from here the
    // passthrough is live and the window under the pointer takes input.
    m_settled = true;
    // The grasp's overlay owns the pointer outright: once the hold zooms
    // out past the overlay's threshold, the map under the pointer takes
    // every motion - no window under it may hover, or the pointer's rest
    // would hand the input to the real window drawn under a sheet and the
    // sheet's click or drag would never reach the canvas.
    if (m_holdDown && m_zoom < 0.85) {
        if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: overlay owns the pointer, motion stays in the canvas";
        leave();
        m_grab = nullptr;
        m_grabGround = true;
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
    m_lastPosition = event->position;
    if (m_grab) {
        // Implicit grab: the window keeps the pointer until the buttons are up.
        if (!enter(m_grab, canvas)) {
            waylandServer()->seat()->notifyPointerMotion(canvas - targetOf(m_grab));
            waylandServer()->seat()->notifyPointerFrame();
        }
        return true;
    }
    // The seam: a pointer parked on the desk's outer border is not a rest,
    // it is a pointer nobody is holding (a shared mouse handed to another
    // machine). No window under it may take the input; the canvas keeps it.
    if (atSeam(event->position)) {
        m_hoverCandidate = nullptr;
        m_hoverTimer.stop();
        leave();
        return false;
    }
    Window *w = windowAt(canvas);
    if (w) {
        // The rest, not the pass-over: a new window under the pointer
        // restarts the hover clock, and only the timeout hands the input
        // over. The window already hovered keeps it through the motion.
        // Until the clock fires the motion is the scene's, so the canvas
        // still sees the pointer wherever the window will not take it.
        if (w != m_hoverCandidate.data()) {
            m_hoverCandidate = w;
            m_hoverTimer.start();
        }
        if (m_hover == w) {
            return enter(w, canvas);
        }
        return false;
    }
    m_hoverCandidate = nullptr;
    m_hoverTimer.stop();
    leave();
    return false;
}

bool CanvasPassthrough::pointerButton(PointerButtonEvent *event)
{
    m_idle = false;
    m_idleTimer.start();
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
                if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: hold candidate pressed, waiting the delay";
            }
        } else {
            if (m_holdDown) {
                m_holdDown = false;
                if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: hold released, canvas closes";
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
    // A left press on a window while the canvas is closed is a candidate
    // click: the effect flies to that window on the release, which covers a
    // click on a window that is already active, where no activation fires
    // and the press is the only trace of the click. A press of a nav button
    // is never one, and motion past a few pixels clears it (a drag).
    if (event->state == PointerButtonState::Pressed && event->button == Qt::LeftButton
        && !m_active && !(uint(event->button) & m_nav)) {
        m_clickWindow = windowUnder(event->position);
        m_clickPos = event->position;
    } else if (event->state == PointerButtonState::Released && m_clickWindow && event->button == Qt::LeftButton) {
        if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
            canvas->setProperty("clickedWindow", QVariant::fromValue<QObject *>(m_clickWindow.data()));
        }
        m_clickWindow = nullptr;
    }
    if (!m_active) {
        return false;
    }
    // The grasp's overlay owns the pointer outright (see pointerMotion):
    // a press over a sheet is the sheet's, never the real window drawn
    // under the map.
    if (m_holdDown && m_zoom < 0.85) {
        leave();
        m_grab = nullptr;
        m_grabGround = true;
        return false;
    }
    // The passthrough waits for the aim: until the pointer's first motion
    // after the activation, buttons belong to the canvas - the first click
    // after the overworld opens is the canvas's, not the window's.
    if (!m_settled || m_idle) {
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
        // A new gesture. The press belongs to the window only after the
        // rest: a click, a grab and the double-click to enter all start
        // with a press, and the hover's delay is what tells them apart - a
        // rested pointer hands the press over, a fresh touch is the
        // canvas's, so the enter and the selection never lose to the window.
        const QPointF canvas = toCanvas(event->position);
        m_hoverTimer.stop();
        Window *w = windowAt(canvas);
        if (w && m_hover == w && enter(w, canvas)) {
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
    // The idle's keys are the canvas's - the Esc the user reaches for is
    // the canvas's cancel, not the window's - and typing does not wake the
    // passthrough; the pointer's touch does.
    if (m_idle) {
        return false;
    }
    m_idle = false;
    m_idleTimer.start();
    if (!m_active || event->state == KeyboardKeyState::Repeated) {
        return false;
    }
    // Heavily scoped: the keys belong to the window only while the pointer
    // hovers one of its kind. The moment the cursor is over the ground,
    // the frames or the gaps, the canvas has the keys back.
    if (!m_hover) {
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
    // The idle's wheel is the canvas's, and it does not wake the
    // passthrough - only the pointer's touch does.
    if (m_idle) {
        return false;
    }
    m_idle = false;
    m_idleTimer.start();
    if (!m_active || !m_settled || m_grabGround) {
        return false;
    }
    // With a canvas button down the wheel is the canvas's too: a notch zooms
    // the canvas at the pointer instead of scrolling the window under it.
    // The hold counts: a wheel during the grasp zooms the keyhole into the
    // map, wherever the pointer sits.
    if ((event->buttons.toInt() & m_nav) || m_holdDown) {
        return false;
    }
    const QPointF canvas = toCanvas(event->position);
    Window *w = m_grab ? m_grab.data() : nullptr;
    if (!w) {
        Window *cand = windowAt(canvas);
        if (cand && m_hover == cand) {
            w = cand;
        } else if (cand) {
            // Over a window the wheel is that window's business, and the
            // window is not active until the rest completes: a wheel during
            // the rest must not zoom the canvas out from under the eye.
            return true;
        }
    }
    if (!w || !enter(w, canvas)) {
        return false;
    }
    SeatInterface *seat = waylandServer()->seat();
    seat->notifyPointerAxis(event->orientation, event->delta, event->deltaV120, event->source, event->inverted);
    seat->notifyPointerFrame();
    return true;
}

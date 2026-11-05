/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "passthrough.h"

#include <config-kwin.h>
#include <core/output.h>
#include <effect/effecthandler.h>
#include <effect/quickeffect.h>
#include <scene/windowitem.h>
#include <wayland/seat.h>
#include <wayland/surface.h>
#include <wayland_server.h>
#include <window.h>
#include <workspace.h>

#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusConnection>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibrary>
#include <QLoggingCategory>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <cmath>

Q_LOGGING_CATEGORY(KWIN_CANVAS, "kwin_canvas_passthrough", QtDebugMsg)

using namespace KWin;

static const QString s_path = QStringLiteral("/KWinCanvas");
static const QString s_mapPath = QStringLiteral("/KWinCanvas/Map");

// A window caption as one field of the state reply. The reply is split on
// "|" by the decor applet and read as one line, and real captions carry both
// ("Inbox | Mail", a title with a newline), so they would shift every flag
// after the caption or end the line early.
static QString replyField(const QString &caption)
{
    QString s = caption;
    s.replace(QLatin1Char('|'), QLatin1Char('/'));
    s.replace(QLatin1Char('\n'), QLatin1Char(' '));
    s.replace(QLatin1Char('\r'), QLatin1Char(' '));
    return s;
}

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

CanvasSceneHelper::CanvasSceneHelper(QObject *parent)
    : QObject(parent)
{
    for (Window *w : workspace()->windows()) {
        watch(w);
    }
    connect(workspace(), &Workspace::windowAdded, this, &CanvasSceneHelper::watch);
}

void CanvasSceneHelper::watch(Window *window)
{
    connect(window, &Window::shadowChanged, this, [this]() {
        ++m_revision;
        Q_EMIT revisionChanged();
    });
}

QObject *CanvasSceneHelper::frameWatch(QObject *window)
{
    Window *w = qobject_cast<Window *>(window);
    if (!w) {
        return nullptr;
    }
    if (CanvasFrameWatch *watch = m_frameWatches.value(w)) {
        return watch;
    }
    auto *watch = new CanvasFrameWatch(w, this);
    // The scene's binding holds it, but the window owns its life: QML must not collect it.
    QQmlEngine::setObjectOwnership(watch, QQmlEngine::CppOwnership);
    m_frameWatches.insert(w, watch);
    connect(w, &QObject::destroyed, this, [this, w]() {
        delete m_frameWatches.take(w);
    });
    return watch;
}

CanvasFrameWatch::CanvasFrameWatch(Window *window, QObject *parent)
    : QObject(parent)
    , m_window(window)
{
    connect(window, &Window::shadowChanged, this, &CanvasFrameWatch::bump);
    connect(window, &Window::readyForPaintingChanged, this, &CanvasFrameWatch::hookItem);
    connect(window, &Window::frameGeometryChanged, this, &CanvasFrameWatch::hookItem);
    hookItem();
}

// The item's bounding rect is the texture's extent. It settles in the item's own slots after a
// resize (the surface and the decoration resize there), so a frameInTexture read when the frame
// changed can be a step behind; its change asks again once the item has caught up. A plain move
// leaves it alone: it is in the item's own coordinates.
void CanvasFrameWatch::hookItem()
{
    Item *item = m_window ? m_window->windowItem() : nullptr;
    if (item == m_item) {
        return;
    }
    disconnect(m_itemConnection);
    m_item = item;
    if (item) {
        m_itemConnection = connect(item, &Item::boundingRectChanged, this, &CanvasFrameWatch::bump);
        bump();
    }
}

void CanvasFrameWatch::bump()
{
    ++m_revision;
    Q_EMIT revisionChanged();
}

QVariantList CanvasSceneHelper::frameInTexture(QObject *window) const
{
    const Window *w = qobject_cast<Window *>(window);
    if (!w) {
        return {};
    }
    // The texture is KWin's render of visibleGeometry (the frame, its shadow and whatever the
    // client draws past the frame), stretched over the whole texture
    // (WindowThumbnailSource::update). visibleGeometry is the window item's bounding rect mapped
    // to the scene, and the item takes a move in its own frameGeometryChanged slot: read from a
    // binding that ran first, it was the old place while the frame was the new one, and the
    // picture sampled the texture shifted by the whole move - every slide's landing, which moves
    // every window in the frame before the close. In the item's own coordinates the frame sits at
    // the origin (WindowItem::updateGeometry places the item at the window's pos()), so where the
    // frame lies in the texture does not depend on where the window is.
    const WindowItem *item = w->windowItem();
    if (!item) {
        return {};
    }
    const RectF bounds = item->boundingRect();
    const RectF frame = w->frameGeometry();
    return {-bounds.x(), -bounds.y(), frame.width(), frame.height(), bounds.width(), bounds.height()};
}

int CanvasSceneHelper::offscreenWindows() const
{
    int count = 0;
    for (const Window *w : workspace()->windows()) {
        if (w->isOffscreenRendering() && !w->isDesktop()) {
            ++count;
        }
    }
    return count;
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
            if (!m_registered) {
                m_registered = QDBusConnection::sessionBus().registerObject(s_path, this, QDBusConnection::ExportScriptableSlots);
            }
            // The map widget's object beside it, with its change signal exported.
            if (!m_mapRegistered) {
                m_mapRegistered = QDBusConnection::sessionBus().registerObject(s_mapPath, &m_map, QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals);
            }
            // The scene's helper goes on KWin's QML engine the same way: the effects handler and
            // the workspace may still be coming up when the plugin loads. The scene reads it when
            // its views are made, at the first open, well after this.
            if (!m_sceneHelper && effects && effects->qmlEngine() && workspace()) {
                m_sceneHelper = new CanvasSceneHelper(this);
                effects->qmlEngine()->rootContext()->setContextProperty(QStringLiteral("canvasPlugin"), m_sceneHelper);
            }
        });
    }
    // The hold mask from the config, so a missed publish cannot leave the
    // modifier dead; the effect's setHoldButtons keeps it current.
    m_hold = parseHoldButtons(KSharedConfig::openConfig(QStringLiteral("kwinrc"))->group(QStringLiteral("Effect-kwin-canvas")).readEntry("CanvasHold", QStringLiteral("BackButton")));
    // The passthrough lets go on its own: after a while with no input -
    // the pointer still, no keys - the canvas takes the input back, so
    // the Esc the user reaches for is the canvas's, not the window's,
    // until the next touch. The clock runs only while the canvas has the
    // input (setActive): every touch restarts it, and it fires once.
    m_idleTimer.setInterval(4000);
    m_idleTimer.setSingleShot(true);
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
    // The zoom door: the wheel over the bare ground opens the canvas from
    // the closed location. The knob is read once at load - the effect and
    // the plugin both live until the session ends.
    m_door = KSharedConfig::openConfig(QStringLiteral("kwinrc"))->group(QStringLiteral("Effect-kwin-canvas")).readEntry("WheelDoor", true);
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
    QDBusConnection::sessionBus().unregisterObject(s_mapPath);
    QDBusConnection::sessionBus().unregisterObject(s_path);
    input()->uninstallInputEventFilter(this);
    // The scene must not keep a pointer to the helper this deletes with it.
    if (m_sceneHelper && effects && effects->qmlEngine()) {
        effects->qmlEngine()->rootContext()->setContextProperty(QStringLiteral("canvasPlugin"), nullptr);
    }
}

QString CanvasPassthrough::probe() const
{
    return QStringLiteral("kwin-canvas-passthrough %1 kwin %2").arg(QStringLiteral(CANVAS_VERSION), KWIN_VERSION_STRING);
}

void CanvasPassthrough::wakeFromIdle()
{
    if (!m_idle) {
        return;
    }
    m_idle = false;
    if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
        canvas->setProperty("passthroughIdle", false);
    }
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
    // Nor has it rested anywhere: a candidate left from the last opening would
    // match the window under a pointer that rests there again, so the hover
    // clock would never start and the window never take the input until the
    // pointer left it and came back.
    m_hoverCandidate = nullptr;
    m_hoverTimer.stop();
    // The idle clock starts with the activation, as if the hand had just
    // touched, and a closed canvas has no idle: there is no input to take back.
    wakeFromIdle();
    if (active) {
        m_idleTimer.start();
    } else {
        m_idleTimer.stop();
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

void CanvasPassthrough::setSeparate(const QString &activeOutput)
{
    m_separate = !activeOutput.isEmpty();
    m_camOutput = activeOutput;
    m_replica = nullptr;
}

void CanvasPassthrough::setCanvasState(const QString &state)
{
    // The shader channel: the effect pushes the plane's remembered state at
    // each commit (view=, grid=, cluster= lines in plane coordinates);
    // the clusters land here screen-projected (scaled by the
    // zoom the effect publishes), so a fragment shader works in pixels with
    // no camera math of its own; the grid passes through raw and scrolls
    // with the view on the shader side.
    // Written through QSaveFile: the shader polls this file, and an in-place
    // truncate-and-write lets it read a half-written plane. The save is a
    // rename, so a reader sees the old file or the new one, never a mix.
    QSaveFile f(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/kwin-canvas-state.txt"));
    if (!f.open(QIODevice::WriteOnly)) {
        return;
    }
    QTextStream out(&f);
    // The shader renders in PHYSICAL pixels (the output's pixel size, dpr
    // included) while the plane's state is LOGICAL (the KWin geometry). The
    // logical size rides along so the shader can scale the state to its own
    // space - at 100% scale the factor is one and nothing moves.
    out << "size=" << workspace()->geometry().width() << ',' << workspace()->geometry().height() << QLatin1Char('\n');
    double viewX = 0.0, viewY = 0.0, zoomV = 1.0;
    const QStringList lines = state.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        if (line.startsWith(QLatin1String("view="))) {
            const QStringList p = line.mid(5).split(QLatin1Char(','));
            if (p.size() == 2) {
                viewX = p[0].toDouble();
                viewY = p[1].toDouble();
            }
            out << line << QLatin1Char('\n');
        } else if (line.startsWith(QLatin1String("zoom="))) {
            const double z = line.mid(5).toDouble();
            if (z > 0.0 && std::isfinite(z)) {
                zoomV = z;
            }
            out << line << QLatin1Char('\n');
        } else if (line.startsWith(QLatin1String("grid="))) {
            // The ground's own knobs pass through raw: the shader draws the
            // same grid, scrolling with the view it reads from the view line.
            out << line << QLatin1Char('\n');
        } else if (line.startsWith(QLatin1String("cluster="))) {
            const QStringList p = line.mid(8).split(QLatin1Char(','));
            if (p.size() == 3) {
                out << "cluster=" << int((p[0].toDouble() - viewX) * zoomV) << ',' << int((p[1].toDouble() - viewY) * zoomV) << ',' << p[2] << QLatin1Char('\n');
            }
        }
    }
    out.flush();
    f.commit();
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
    // QTimer::setInterval restarts a running timer, and the effect publishes
    // the delay on every reconfigure (every settings write, every debug
    // command): an unchanged value must leave a running rest clock alone, or
    // a pointer resting in the 900 ms window never gets its hover.
    if (ms > 0 && m_hoverTimer.interval() != ms) {
        m_hoverTimer.setInterval(ms);
        qCDebug(KWIN_CANVAS) << "hover delay set to" << ms << "ms";
    }
}

void CanvasPassthrough::setDoorEnabled(bool enabled)
{
    m_door = enabled;
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

QString CanvasPassthrough::cornerStyle() const
{
    // The effect's own defaults (its options.kcfg) where the user has set nothing.
    const KConfigGroup g = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals)->group(QStringLiteral("Round-Corners"));
    const bool on = KWin::effects && KWin::effects->isEffectLoaded(QStringLiteral("kwin4_effect_shapecorners"));
    const bool squircleShape = g.readEntry("UseSquircleShape", true);
    QJsonObject o;
    o[QStringLiteral("on")] = on;
    o[QStringLiteral("active")] = g.readEntry("Size", 20);
    o[QStringLiteral("inactive")] = g.readEntry("InactiveCornerRadius", 20);
    o[QStringLiteral("squircle")] = squircleShape ? g.readEntry("Squircleness", 0.55) : 0.0;
    o[QStringLiteral("tile")] = g.readEntry("DisableRoundTile", true);
    o[QStringLiteral("max")] = g.readEntry("DisableRoundMaximize", true);
    o[QStringLiteral("full")] = g.readEntry("DisableRoundFullScreen", true);
    o[QStringLiteral("exclusions")] = QJsonArray::fromStringList(g.readEntry("Exclusions", QStringList()));
    o[QStringLiteral("inclusions")] = QJsonArray::fromStringList(g.readEntry("Inclusions", QStringList()));
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

QString CanvasPassthrough::blurStyle() const
{
    QJsonObject o;
    QString id;
    for (const QString &e : {QStringLiteral("better_blur_dx"), QStringLiteral("blur")}) {
        if (KWin::effects && KWin::effects->isEffectLoaded(e)) {
            id = e;
            break;
        }
    }
    o[QStringLiteral("effect")] = id;
    if (id.isEmpty()) {
        return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
    }
    // Better Blur DX is KWin's blur forked: the same strength and noise, with the same defaults
    // (both blur.kcfg), and its force blur on top.
    const bool better = id == QStringLiteral("better_blur_dx");
    const KConfigGroup g = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals)
                               ->group(better ? QStringLiteral("Effect-better-blur-dx") : QStringLiteral("Effect-blur"));
    o[QStringLiteral("strength")] = g.readEntry("BlurStrength", 15);
    o[QStringLiteral("noise")] = g.readEntry("NoiseStrength", 5);
    if (better) {
        o[QStringLiteral("radius")] = g.readEntry("CornerRadius", 0.0);
        o[QStringLiteral("force")] = g.readEntry("BlurMatching", true) ? QStringLiteral("only") : QStringLiteral("all-but");
        o[QStringLiteral("classes")] = QJsonArray::fromStringList(
            g.readEntry("WindowClasses", QStringLiteral("class1\nclass2")).split(QLatin1Char('\n'), Qt::SkipEmptyParts));
        o[QStringLiteral("menus")] = g.readEntry("BlurMenus", false);
        o[QStringLiteral("docks")] = g.readEntry("BlurDocks", false);
    }
    // What each window asks for itself. The surface's region is in the surface's own
    // coordinates, which start at the buffer's corner; a region for the whole surface is
    // infinite, so it is cut to the surface first. X11 windows' blur property is not read.
    QJsonObject regions;
    if (KWin::workspace()) {
        const auto windows = KWin::workspace()->windows();
        for (KWin::Window *w : windows) {
            KWin::SurfaceInterface *surface = w->surface();
            if (!surface) {
                continue;
            }
            const KWin::RegionF region = surface->blurRegion().intersected(KWin::RectF(QPointF(0, 0), surface->size()));
            if (region.isEmpty()) {
                continue;
            }
            const QPointF offset = w->bufferGeometry().topLeft() - w->frameGeometry().topLeft();
            QJsonArray rects;
            for (const KWin::RectF &r : region.rects()) {
                rects.append(QJsonArray{r.x() + offset.x(), r.y() + offset.y(), r.width(), r.height()});
            }
            regions[w->internalId().toString()] = rects;
        }
    }
    o[QStringLiteral("regions")] = regions;
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

bool CanvasPassthrough::setViewCaching(bool enabled)
{
    if (!KWin::effects) {
        return false;
    }
    auto *effect = qobject_cast<KWin::QuickSceneEffect *>(KWin::effects->findEffect(QStringLiteral("kwin-canvas")));
    if (!effect) {
        return false;
    }
    if (effect->isViewCachingEnabled() != enabled) {
        effect->setViewCachingEnabled(enabled);
        qCDebug(KWIN_CANVAS) << "canvas-passthrough: view caching" << (enabled ? "on" : "off");
    }
    return true;
}

void CanvasPassthrough::publishRest(KWin::Window *w)
{
    // No passthrough, no cue: the handoff the cue anticipates exists only
    // while the plugin owns the canvas's input. A deactivation clears the
    // property through leave().
    if (!m_active) w = nullptr;
    if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
        if (w) {
            // The window and the delay the hover clock is waiting out, so
            // the canvas can fill a cue along the window's edge while the
            // rest runs: the handoff is anticipated instead of a surprise.
            canvas->setProperty("restStart", QStringLiteral("%1|%2").arg(w->internalId().toString()).arg(m_hoverTimer.interval()));
        } else {
            canvas->setProperty("restStart", QString());
        }
    }
}

void CanvasPassthrough::publishHover(KWin::Window *w)
{
    if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
        // The window that holds the pointer wears the hand: the canvas
        // keeps its cue's line full along that window's edge while the
        // pass-through owns the input.
        canvas->setProperty("hoverId", w ? w->internalId().toString() : QString());
    }
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
    // The panel applet's window decor rides the same reply: the trailing
    // " win=" token names the focused window - internalId, caption,
    // maximized, floating (on all desktops),
    // keep-above, keep-below and exclude-from-capture flags - so the panel
    // can draw the decor for the window the user is actually on.
    QString win;
    if (KWin::Window *w = workspace()->activeWindow(); w) {
        win = QStringLiteral(" win=%1|%2|%3|%4|%5|%6|%7")
                  .arg(w->internalId().toString())
                  .arg(replyField(w->caption()))
                  .arg(w->maximizeMode() == KWin::MaximizeMode::MaximizeFull ? QStringLiteral("1") : QStringLiteral("0"))
                  .arg(w->isOnAllDesktops() ? QStringLiteral("1") : QStringLiteral("0"))
                  .arg(w->keepAbove() ? QStringLiteral("1") : QStringLiteral("0"))
                  .arg(w->keepBelow() ? QStringLiteral("1") : QStringLiteral("0"))
                  .arg(w->excludeFromCapture() ? QStringLiteral("1") : QStringLiteral("0"));
    }
    return QStringLiteral("active=%1 view=(%2,%3) zoom=%4 grab=%5 ground=%6 hover=%7 nav=%8 hold=%9 seam=%10")
               .arg(m_active ? QStringLiteral("true") : QStringLiteral("false"))
               .arg(m_viewX)
               .arg(m_viewY)
               .arg(m_zoom)
               .arg(m_grab ? replyField(m_grab->caption()) : QStringLiteral("-"))
               .arg(m_grabGround ? QStringLiteral("true") : QStringLiteral("false"))
               .arg(m_hover ? replyField(m_hover->caption()) : QStringLiteral("-"))
               .arg(m_nav)
               .arg(m_hold)
               .arg(atSeam(waylandServer()->seat()->pointerPos()) ? QStringLiteral("1") : QStringLiteral("0"))
        + win;
}

// The panel applet's window decor: the four glyph actions, applied to the
// focused window through the real KWin::Window API - in-process, so they
// work in the nest too (unlike the D-Bus killWindow path).
void CanvasPassthrough::windowAction(const QString &action)
{
    KWin::Window *w = workspace()->activeWindow();
    if (!w) {
        return;
    }
    if (action == QLatin1String("close")) {
        w->closeWindow();
    } else if (action == QLatin1String("minimize")) {
        w->setMinimized(!w->isMinimized());
    } else if (action == QLatin1String("maximize")) {
        const bool full = w->maximizeMode() == KWin::MaximizeMode::MaximizeFull;
        w->setMaximize(!full, !full);
    } else if (action == QLatin1String("float")) {
        // The float is the system's own "on all desktops" pin: one flag, so
        // the canvas, the pill, a window rule and KDE's menu always agree.
        w->setOnAllDesktops(!w->isOnAllDesktops());
    } else if (action == QLatin1String("keepabove")) {
        w->setKeepAbove(!w->keepAbove());
    } else if (action == QLatin1String("keepbelow")) {
        w->setKeepBelow(!w->keepBelow());
    } else if (action == QLatin1String("capture")) {
        w->setExcludeFromCapture(!w->excludeFromCapture());
    }
}

// The GPU's busy share and the used share of its memory via NVML, loaded on
// demand with QLibrary so the plugin carries no link-time dependency on the
// NVIDIA driver. Without the driver (or on another vendor's GPU) both stay
// -1 and the CPU and memory channels alone govern the ladder. The memory
// matters on its own: a game holding most of it leaves the compositor's
// textures (every thumbnail is one) a few allocations from failing, and a
// full card is what wedged the driver on 2026-10-30.
static void nvmlRead(int *busy, int *vram)
{
    if (busy) {
        *busy = -1;
    }
    *vram = -1;
    // Initialised once: nvmlInit is reference-counted and not free, and this
    // runs every couple of seconds for the whole session. The device handle
    // is kept with it; a failed start leaves both channels at -1 for good.
    static bool tried = false;
    static void *dev = nullptr;
    static int (*utilFn)(void *, void *) = nullptr;
    static int (*memFn)(void *, void *) = nullptr;
    if (!tried) {
        tried = true;
        static QLibrary lib(QStringLiteral("libnvidia-ml.so.1"));
        if (lib.load()) {
            auto initFn = (int (*)())lib.resolve("nvmlInit_v2");
            auto handleFn = (int (*)(unsigned, void **))lib.resolve("nvmlDeviceGetHandleByIndex_v2");
            if (initFn && handleFn && initFn() == 0 && handleFn(0, &dev) == 0 && dev) {
                utilFn = (int (*)(void *, void *))lib.resolve("nvmlDeviceGetUtilizationRates");
                memFn = (int (*)(void *, void *))lib.resolve("nvmlDeviceGetMemoryInfo");
            }
        }
    }
    // nvmlUtilization_t is two unsigned ints: gpu, then memory (the memory
    // controller's busy share, not how full the memory is).
    // A null busy asks for the memory alone (the kept scene's watch): one driver call.
    unsigned int rates[2] = {0, 0};
    if (busy && utilFn && utilFn(dev, rates) == 0) {
        *busy = int(rates[0]);
    }
    // nvmlMemory_t is three unsigned long longs: total, free, used.
    unsigned long long memory[3] = {0, 0, 0};
    if (memFn && memFn(dev, memory) == 0 && memory[0] > 0) {
        *vram = int(100.0 * double(memory[2]) / double(memory[0]));
    }
}

int CanvasSceneHelper::gpuMemory() const
{
    int vram = -1;
    nvmlRead(nullptr, &vram);
    return vram;
}

QString CanvasPassthrough::load() const
{
    // The machine's load for the fidelity ladder. cpu is the busy share
    // between this call and the previous one, from the first /proc/stat
    // line (all cores together, so a four-core game pegs it at ~100 the
    // same as an eight-core one). load is the one-minute average and mem
    // the available memory, both for the trace. gpu is the GPU's busy
    // share and vram the used share of its memory, via NVML, each -1
    // where the driver is absent. A few small
    // reads, a few microseconds; the effect polls it every couple of
    // seconds only.
    qulonglong total = 0;
    qulonglong idle = 0;
    QFile stat(QStringLiteral("/proc/stat"));
    if (stat.open(QIODevice::ReadOnly)) {
        const QByteArray line = stat.readLine();
        const QList<QByteArray> parts = line.simplified().split(' ');
        // parts: cpu, user, nice, system, idle, iowait, irq, softirq, steal...
        if (parts.size() >= 5 && parts[0] == "cpu") {
            for (int i = 1; i < parts.size() && i < 9; ++i) {
                total += parts[i].toULongLong();
            }
            idle = parts[4].toULongLong();
        }
    }
    int cpu = 0;
    if (m_prevTotal && total > m_prevTotal) {
        const qulonglong dt = total - m_prevTotal;
        const qulonglong di = idle >= m_prevIdle ? idle - m_prevIdle : 0;
        cpu = int(100 - 100 * double(di) / double(dt));
    }
    m_prevTotal = total;
    m_prevIdle = idle;

    double load1 = 0;
    QFile loadavg(QStringLiteral("/proc/loadavg"));
    if (loadavg.open(QIODevice::ReadOnly)) {
        load1 = QString::fromLatin1(loadavg.readLine()).section(QLatin1Char(' '), 0, 0).toDouble();
    }
    int mem = 0;
    QFile meminfo(QStringLiteral("/proc/meminfo"));
    if (meminfo.open(QIODevice::ReadOnly)) {
        qulonglong memTotal = 0, memAvail = 0;
        // procfs seq_files report a zero size, so QFile::atEnd() is true
        // before the first read - the loop runs on readLine() alone.
        while (true) {
            const QByteArray line = meminfo.readLine();
            if (line.isEmpty()) break;
            if (line.startsWith("MemTotal:")) {
                memTotal = line.mid(9).simplified().split(' ')[0].toULongLong();
            } else if (line.startsWith("MemAvailable:")) {
                memAvail = line.mid(13).simplified().split(' ')[0].toULongLong();
                break;
            }
        }
        // The used share, not the available kB: the third channel the ladder
        // reads, alongside the CPU and the GPU.
        mem = memTotal ? int(100 - 100.0 * double(memAvail) / double(memTotal)) : 0;
    }
    int gpu = -1;
    int vram = -1;
    nvmlRead(&gpu, &vram);
    return QStringLiteral("cpu=%1 load=%2 mem=%3 gpu=%4 vram=%5").arg(cpu).arg(load1, 0, 'f', 2).arg(mem).arg(gpu).arg(vram);
}

int CanvasPassthrough::modifiers() const
{
    // The live keyboard modifier mask. The effect polls this while a
    // chord-held switcher is up and reads the chord's end when its
    // modifier clears - the scene cannot always see the release of a key
    // the global shortcut consumed.
    return int(input()->keyboardModifiers());
}

// ---- the plane ---------------------------------------------------------------

LogicalOutput *CanvasPassthrough::outputAt(const QPointF &point) const
{
    const QList<LogicalOutput *> outputs = workspace()->outputs();
    for (LogicalOutput *o : outputs) {
        const Rect g = o->geometry();
        if (point.x() >= g.x() && point.x() < g.x() + g.width() && point.y() >= g.y() && point.y() < g.y() + g.height()) {
            return o;
        }
    }
    return nullptr;
}

LogicalOutput *CanvasPassthrough::outputOfWindow(Window *window) const
{
    const QRectF f = window->frameGeometry();
    const QPointF c = f.center();
    if (LogicalOutput *o = outputAt(c)) {
        return o;
    }
    LogicalOutput *best = nullptr;
    qreal bestD = 0;
    const QList<LogicalOutput *> outputs = workspace()->outputs();
    for (LogicalOutput *o : outputs) {
        const Rect g = o->geometry();
        const qreal dx = std::max({qreal(g.x()) - c.x(), qreal(0), c.x() - (g.x() + g.width())});
        const qreal dy = std::max({qreal(g.y()) - c.y(), qreal(0), c.y() - (g.y() + g.height())});
        const qreal d = std::hypot(dx, dy);
        if (!best || d < bestD) {
            best = o;
            bestD = d;
        }
    }
    return best;
}

QPointF CanvasPassthrough::replicaTarget(const LogicalOutput *output) const
{
    return m_targets.value(m_current + QLatin1Char('|') + output->name(), m_targets.value(m_current, QPointF(m_viewX, m_viewY)));
}

QPointF CanvasPassthrough::toCanvas(const QPointF &screen) const
{
    m_replica = nullptr;
    if (m_separate) {
        const LogicalOutput *o = outputAt(screen);
        if (o && o->name() != m_camOutput) {
            // Not the camera's monitor: the real desktop, the plane at 1:1 on this
            // monitor's own desk.
            m_replica = o;
            return screen + replicaTarget(o);
        }
    }
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
    if (m_replica) {
        return replicaTarget(m_replica);
    }
    if (m_separate) {
        // Each monitor has its own desk: a window maps to the plane through the desk of
        // the monitor it sits on, the way the effect's entries do.
        if (const LogicalOutput *o = outputOfWindow(window)) {
            const auto it = m_targets.constFind(id + QLatin1Char('|') + o->name());
            if (it != m_targets.constEnd()) {
                return *it;
            }
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
    // A replica monitor is the real desktop at 1:1: only this activity's windows.
    if (!m_replica && m_zoom < 0.999) {
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
        if (w->isDesktop()) {
            continue;
        }
        if (w->isMinimized() || w->isHidden() || !w->isOnCurrentDesktop()) {
            continue;
        }
        if (QRectF(w->frameGeometry()).contains(screen)) {
            // The system's own chrome owns the click: a dock, a panel or an
            // applet's dropdown is never a window the canvas may fly to, and
            // the window drawn under it must not become the click candidate.
            if (w->isDock() || w->isPopupWindow() || w->isSpecialWindow()) {
                return nullptr;
            }
            return w;
        }
    }
    return nullptr;
}

Window *CanvasPassthrough::chromeAt(const QPointF &screen) const
{
    const QList<Window *> &stack = workspace()->stackingOrder();
    for (auto it = stack.crbegin(); it != stack.crend(); ++it) {
        Window *w = *it;
        if (!w->isClient() || w->isDeleted()) {
            continue;
        }
        if (w->isDesktop()) {
            continue;
        }
        if (w->isMinimized() || w->isHidden() || !w->isOnCurrentDesktop()) {
            continue;
        }
        if (!QRectF(w->frameGeometry()).contains(screen)) {
            continue;
        }
        if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: chromeAt " << screen.x() << "," << screen.y() << " top=" << w->caption() << " dock=" << w->isDock() << " popup=" << w->isPopupWindow() << " special=" << w->isSpecialWindow() << " unmanaged=" << w->isUnmanaged() << " type=" << int(w->windowType());
        if (w->isDock() || w->isPopupWindow() || w->isSpecialWindow() || w->isUnmanaged()) {
            return w;
        }
        return nullptr;
    }
    return nullptr;
}

void CanvasPassthrough::publishChrome(const QPointF &screen)
{
    const bool chrome = chromeAt(screen) != nullptr;
    if (chrome == m_chromeHover) {
        return;
    }
    m_chromeHover = chrome;
    if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
        canvas->setProperty("chromeHover", chrome);
    }
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
    // The rest the hover clock waited out is over: the handoff happened,
    // so the canvas's filling cue is done too.
    publishRest(nullptr);
    publishHover(window);
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
    // Whatever rest was running over the window is over with it, and the
    // window no longer wears the hand.
    publishRest(nullptr);
    publishHover(nullptr);
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
    // The chrome flag is published on every event, active or not: the quiet
    // grasp's scene needs it too, and the scene's handlers read it fresh for
    // each press.
    publishChrome(event->position);
    // A candidate click turned drag: the effect must not fly to it.
    if (m_clickWindow && (event->position - m_clickPos).manhattanLength() > 6) {
        m_clickWindow = nullptr;
    }
    // A closed canvas has nothing to hover, rest or wake: past the chrome and
    // the click candidate the motion is the desktop's. This filter sees every
    // motion of the session, a game's included (a gaming mouse sends a
    // thousand a second), so it stops here. The hold opens the canvas from
    // the closed desktop and keeps the whole path.
    if (!m_active && !m_holdDown) {
        return false;
    }
    wakeFromIdle();
    m_idleTimer.start();
    // passthrough is live and the window under the pointer takes input.
    m_settled = true;
    // The grasp's zoomed-out world owns the pointer outright: once the hold
    // zooms out past the threshold, the map under the pointer takes every
    // motion - no window under it may hover, or the pointer's rest would
    // hand the input to the real window drawn under a sheet and the sheet's
    // click or drag would never reach the canvas.
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
    // The system's own chrome - a dock, a panel, an applet's dropdown -
    // owns its pixels outright. Nothing under it may hover or be entered;
    // the chrome gets the pointer natively, exactly as when the canvas is
    // closed.
    if (m_chromeHover) {
        m_hoverCandidate = nullptr;
        m_hoverTimer.stop();
        leave();
        return false;
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
    if (w && m_replica) {
        // A monitor the overview is not open on is the real desktop: the hover is
        // immediate, as it is when the canvas is closed.
        m_hoverCandidate = w;
        m_hoverTimer.stop();
        return enter(w, canvas);
    }
    if (w) {
        // The rest, not the pass-over: a new window under the pointer
        // restarts the hover clock, and only the timeout hands the input
        // over. The window already hovered keeps it through the motion.
        // Until the clock fires the motion is the scene's, so the canvas
        // still sees the pointer wherever the window will not take it.
        if (w != m_hoverCandidate.data()) {
            m_hoverCandidate = w;
            m_hoverTimer.start();
            publishRest(w);
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
    publishChrome(event->position);
    // A press is never a rest: whatever cue the hover clock was filling
    // stops the moment a button lands.
    publishRest(nullptr);
    // A press wakes the passthrough as a motion does, and the effect hears it.
    wakeFromIdle();
    if (m_active) {
        m_idleTimer.start();
    }
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
            // The hold works everywhere now: over the desktop or a window,
            // in the closed location or the open overworld. A press that
            // outlasts the threshold is the canvas modifier; released
            // sooner it is replayed as the click it was (replayClick), so
            // a window's own back button still works. Held in the open
            // overworld it is navigation only, as ever.
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
        if (m_verbose) qCDebug(KWIN_CANVAS) << "canvas-passthrough: click candidate at" << event->position.x() << "," << event->position.y() << "->" << (m_clickWindow ? m_clickWindow->caption() : QStringLiteral("-"));
        m_clickPos = event->position;
    } else if (event->state == PointerButtonState::Released && m_clickWindow && event->button == Qt::LeftButton) {
        if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
            canvas->setProperty("clickedWindow", QVariant::fromValue<QObject *>(m_clickWindow.data()));
        }
        m_clickWindow = nullptr;
    }
    // The system's own chrome - a dock, a panel, an applet's dropdown -
    // owns its pixels. A press over it never enters or activates the
    // window drawn underneath; the scene's handlers stand back too (the
    // chromeHover gate), so the chrome gets the click natively.
    if (m_chromeHover) {
        leave();
        m_grab = nullptr;
        m_grabGround = false;
        return false;
    }
    // The grasp's zoomed-out world owns the pointer outright (see
    // pointerMotion): a press over a sheet is the sheet's, never the real
    // window drawn under the map.
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
    if (m_verbose) qCDebug(KWIN_CANVAS) << "keyboardKey" << event->key;
    // The idle's keys are the canvas's - the Esc the user reaches for is
    // the canvas's cancel, not the window's. Typing restarts the idle
    // clock but hands no key over; the key itself stays the canvas's
    // while the passthrough is idle. A closed canvas's keys are the desktop's.
    if (!m_active || m_idle) {
        return false;
    }
    m_idleTimer.start();
    if (event->state == KeyboardKeyState::Repeated) {
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
    // The door: with the canvas closed, the wheel over the bare ground
    // zooms the world out of the location - the plugin publishes the step
    // and the effect opens at the seam. Over a window, the chrome, or
    // during a hold the wheel stays theirs.
    if (!m_active && m_door && !m_holdDown) {
        if (!windowUnder(event->position) && !chromeAt(event->position)) {
            if (QObject *canvas = effects->findEffect(QStringLiteral("kwin-canvas"))) {
                // An open canvas owns its own wheel: its QML handler zooms
                // at the pointer. Consuming the step here would eat it -
                // the door only opens the closed world.
                if (canvas->property("visible").toBool()) {
                    return false;
                }
                // The raw delta is positive scrolling down (KWin maps the
                // fake axis so), which is the zoom out - the door's step.
                canvas->setProperty("doorStep", event->delta > 0 ? -1 : 1);
                return true;
            }
        }
        return false;
    }
    // The idle's wheel is the canvas's, and it does not wake the
    // passthrough - only the pointer's touch does.
    if (!m_active || m_idle) {
        return false;
    }
    m_idleTimer.start();
    if (!m_settled || m_grabGround) {
        return false;
    }
    // The system's own chrome takes its wheel natively: a scroll over the
    // dock or a dropdown must never reach the canvas or the window under it.
    if (m_chromeHover) {
        return false;
    }
    // With a canvas button down the wheel is the canvas's too: a notch zooms
    // the canvas at the pointer instead of scrolling the window under it.
    // The hold counts: a wheel during the grasp zooms the keyhole into the
    // map, wherever the pointer sits. A fake axis event carries no held
    // buttons, so the plugin's own mask decides as well.
    if ((event->buttons.toInt() & m_nav) || (m_buttons.toInt() & m_nav) || m_holdDown) {
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

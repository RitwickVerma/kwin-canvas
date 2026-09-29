/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Spike: an LD_PRELOAD shim for kwin_wayland 6.7.5 that moves the pointer and
// touch chains into plane (canvas) coordinates, plane = (screen - o) / s, and
// lets the open kwin-canvas effect share the pointer with the windows.
//
// Every hook is an exported libkwin symbol whose callers go through a GOT slot
// (R_X86_64_GLOB_DAT, BIND_NOW), so a preloaded definition wins and the
// original is reached with dlsym(RTLD_NEXT).
//
// Transform source: the kwin-canvas effect object, found in-process with
// EffectsHandler::findEffect. The shim sets its planeInput property when it
// attaches, and reads planeLive, planeScale, planeOffsetX and planeOffsetY
// on every use. The transform is identity unless the effect object exists, is
// active (running, with views, screen not locked) and says planeLive, so an
// unloaded, closed or crashed effect leaves KWin stock. With
// KWIN_CANVAS_PRELOAD_FILE=1 in the environment (the spike harness) the file
// $XDG_RUNTIME_DIR/kwin-canvas-preload, one line "s ox oy", applies whenever
// the effect's transform does not; it is stat()ed per use. With
// KWIN_CANVAS_PRELOAD_ATTACH=0 the shim never attaches to the effect, so it
// loads and arms but KWin stays stock: the first step of a live trial.
//
// Input sharing while the effect's transform is live: a QuickSceneEffect
// grabs the keyboard and intercepts the mouse for as long as it runs. The
// shim answers hasKeyboardGrab() with false, so keys go to the focused
// window. For the pointer it asks the effect, through its planeTakes(x, y,
// window) function, whether the canvas takes the screen point; where it does
// not, isMouseInterception() answers false and EffectsHandler's pointer
// entry points pass the event on, so KWin's own chain routes it to the
// window at the plane point. A press latches the answer until every button
// is up. While an application popup holds a grab, every press goes on to
// KWin, whose popup filter dismisses the popup on a press outside it. The
// effect sees every event it takes, and every hover motion, at screen
// positions.
//
// KWin's pointer position is in plane coordinates while a transform is set.
// When the transform changes the shim warps the pointer so it keeps its
// screen position, and the cursor item, which the hardware cursor plane
// follows too, is drawn at the screen position. Screen edges are tested at
// the screen position.
//
// A popup is constrained to what its parent's output shows: KWin places an
// xdg_popup within the output's placement area, which the shim maps into the
// plane while the transform is live, so a menu opens beside its parent
// wherever the parent is on the plane.
//
// The shim is inert (every hook passes straight through) unless the process is
// kwin_wayland and libkwin's GNU build-id equals EXPECTED_BUILD_ID.
//
// Build: nest-preload.sh build. KWin's headers are used for types only: the
// shim does not link libkwin. Every libkwin function and variable it uses is
// resolved with dlsym in init(), after the process and build-id checks, and
// any symbol missing leaves the shim inert.

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <input.h>
#include <input_event.h>
#include <pointer_input.h>
#include <scene/item.h>
#include <scene/workspacescene.h>
#include <window.h>
#include <workspace.h>

#include <QCoreApplication>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QPointer>
#include <QTimer>

#include <dlfcn.h>
#include <link.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// KWin::WorkspaceScene::updateCursor(), hooked below.
extern "C" void _ZN4KWin14WorkspaceScene12updateCursorEv(KWin::WorkspaceScene *self);

namespace {

constexpr const char *EXPECTED_BUILD_ID = "b4a7f7ab673a25da5e0253361baa08b4f6ef6394"; // kwin 6.7.5-1 (Arch)

struct Rect { int left, top, right, bottom; };        // KWin::Rect, right/bottom exclusive
struct RectF { double left, top, right, bottom; };    // KWin::RectF

// The hooked symbols, in the order of the definitions below. Their originals
// come from dlsym(RTLD_NEXT) in init(); any missing leaves the shim inert. A
// hook only runs when libkwin calls its symbol, so a missing original is
// never needed, and each hook returns a default if it is.
enum Hook {
    FindToplevel,
    MotionAbsolute,
    Motion,
    Button,
    Axis,
    TouchDown,
    TouchMotion,
    UpdatePosition,
    SetActiveOutput,
    OutputGeometry,
    OutputGeometryF,
    Warp,
    EdgesMotion,
    UpdateCursor,
    IsMouseInterception,
    HasKeyboardGrab,
    EffectsMotion,
    EffectsButton,
    EffectsAxis,
    EffectsTouchDown,
    EffectsTouchMotion,
    ClientArea,
    PopupPlacement,
    HookCount
};
const char *const s_hooks[HookCount] = {
    "_ZN4KWin16InputRedirection12findToplevelERK7QPointF",
    "_ZN4KWin23PointerInputRedirection21processMotionAbsoluteERK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE",
    "_ZN4KWin23PointerInputRedirection13processMotionERK7QPointFS3_NSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE",
    "_ZN4KWin23PointerInputRedirection13processButtonEjNS_18PointerButtonStateENSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE",
    "_ZN4KWin23PointerInputRedirection11processAxisENS_11PointerAxisEdiNS_17PointerAxisSourceEbNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE",
    "_ZN4KWin21TouchInputRedirection11processDownEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE",
    "_ZN4KWin21TouchInputRedirection13processMotionEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE",
    "_ZN4KWin23PointerInputRedirection14updatePositionERK7QPointFS3_NSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE",
    "_ZN4KWin9Workspace15setActiveOutputERK7QPointF",
    "_ZNK4KWin13LogicalOutput8geometryEv",
    "_ZNK4KWin13LogicalOutput9geometryFEv",
    "_ZN4KWin23PointerInputRedirection4warpERK7QPointF",
    "_ZN4KWin11ScreenEdges19handlePointerMotionERK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE",
    "_ZN4KWin14WorkspaceScene12updateCursorEv",
    "_ZNK4KWin14EffectsHandler19isMouseInterceptionEv",
    "_ZNK4KWin14EffectsHandler15hasKeyboardGrabEv",
    "_ZN4KWin14EffectsHandler13pointerMotionEPNS_18PointerMotionEventE",
    "_ZN4KWin14EffectsHandler13pointerButtonEPNS_18PointerButtonEventE",
    "_ZN4KWin14EffectsHandler11pointerAxisEPNS_16PointerAxisEventE",
    "_ZN4KWin14EffectsHandler9touchDownEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE",
    "_ZN4KWin14EffectsHandler11touchMotionEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE",
    "_ZNK4KWin9Workspace10clientAreaENS_16clientAreaOptionEPKNS_6WindowE",
    "_ZNK4KWin13XdgPositioner9placementERKNS_5RectFE",
};
void *g_orig[HookCount];

template<typename Fn>
Fn orig(Hook h)
{
    return reinterpret_cast<Fn>(g_orig[h]);
}

// What the shim calls or reads in libkwin, from dlsym(RTLD_DEFAULT).
struct Api {
    KWin::EffectsHandler **effects = nullptr;
    KWin::InputRedirection **input = nullptr;
    KWin::Workspace **workspace = nullptr;
    KWin::Effect *(*findEffect)(const KWin::EffectsHandler *, const QString &) = nullptr;
    QPointF (*globalPointer)(const KWin::InputRedirection *) = nullptr;
    KWin::Rect (*workspaceGeometry)(const KWin::Workspace *) = nullptr;
    KWin::Item *(*cursorItem)(const KWin::WorkspaceScene *) = nullptr;
    QPointF (*itemPosition)(const KWin::Item *) = nullptr;
    void (*itemSetPosition)(KWin::Item *, const QPointF &) = nullptr;
    bool (*itemIsVisible)(const KWin::Item *) = nullptr;
};
Api g_api;

KWin::InputRedirection *input()
{
    return *g_api.input;
}

bool g_armed = false;          // process, build-id and symbol checks passed; cleared at quit
bool g_fileEnabled = false;    // KWIN_CANVAS_PRELOAD_FILE=1
bool g_attachEnabled = true;   // KWIN_CANVAS_PRELOAD_ATTACH is not 0
thread_local bool g_relax = false;  // inside PointerInputRedirection::updatePosition
thread_local bool g_inEdges = false; // inside ScreenEdges::handlePointerMotion
thread_local bool g_probe = false;   // findToplevel on the shim's own behalf
thread_local const QPointF *g_findPos = nullptr; // the point findToplevel is looking at

struct Transform {
    bool active = false;
    double s = 1, ox = 0, oy = 0;
    bool operator==(const Transform &o) const
    {
        return active == o.active && (!active || (s == o.s && ox == o.ox && oy == o.oy));
    }
    QPointF toPlane(const QPointF &p) const { return active ? QPointF((p.x() - ox) / s, (p.y() - oy) / s) : p; }
    QPointF toScreen(const QPointF &p) const { return active ? QPointF(p.x() * s + ox, p.y() * s + oy) : p; }
};

bool sane(double s, double ox, double oy)
{
    return s > 0.01 && s < 100 && std::isfinite(ox) && std::isfinite(oy);
}

// The transform KWin's pointer position was last expressed in.
Transform g_posTf;
// A GPU reset or compositor restart replaces the scene.
QPointer<KWin::WorkspaceScene> g_scene;

void logf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("kwin-canvas-preload: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

// ---- the harness file ----------------------------------------------------------

char g_path[512];
Transform g_fileTf;
timespec g_mtime{};
off_t g_size = -1;

// Rereads the transform file when it changed. Cheap enough per event: one stat().
const Transform &fileTransform()
{
    struct stat st;
    if (stat(g_path, &st) != 0) {
        g_size = -1;
        g_fileTf = Transform{};
        return g_fileTf;
    }
    if (st.st_size == g_size && st.st_mtim.tv_sec == g_mtime.tv_sec && st.st_mtim.tv_nsec == g_mtime.tv_nsec) {
        return g_fileTf;
    }
    g_size = st.st_size;
    g_mtime = st.st_mtim;
    Transform t;
    if (FILE *f = fopen(g_path, "r")) {
        double s, ox, oy;
        if (fscanf(f, "%lf %lf %lf", &s, &ox, &oy) == 3 && sane(s, ox, oy)) {
            t = Transform{ true, s, ox, oy };
        }
        fclose(f);
    }
    g_fileTf = t;
    return g_fileTf;
}

// ---- the canvas effect ------------------------------------------------------------

struct Canvas {
    QPointer<QObject> object;
    KWin::Effect *effect = nullptr;
    QMetaProperty live, scale, offsetX, offsetY, nav;
    bool warned = false;
};
Canvas g_canvas;

// The buttons the canvas owns while they are down, from the effect: its
// planeNavButtons, the same mask its pan handlers take, as a mask of
// Qt::MouseButton values. Read at each gesture start rather than cached, so a
// rebinding takes effect at once; a button in the mask is the canvas's
// wherever the pointer is, which is what makes a held button a portal into the
// canvas (drag a window on the plane, drag the ground, push an edge and keep
// going).
uint navButtons()
{
    if (!g_canvas.object || !g_canvas.nav.isValid()) {
        return 0;
    }
    return g_canvas.nav.read(g_canvas.object).toUInt();
}

QTimer *g_attachTimer = nullptr;
QTimer *g_nudge = nullptr;
QTimer *g_logFlush = nullptr;
bool g_timersMade = false;
unsigned long g_serial = 0; // bumped per pointer event and per transform change

void reanchor();
void logTransform(bool force);

// Finds the kwin-canvas effect and checks it carries the plane interface.
void attach()
{
    if (!g_armed || !g_attachEnabled || g_canvas.object || !*g_api.effects) {
        return;
    }
    KWin::Effect *e = g_api.findEffect(*g_api.effects, QStringLiteral("kwin-canvas"));
    if (!e) {
        return;
    }
    const QMetaObject *mo = e->metaObject();
    auto prop = [mo](const char *name) {
        const int i = mo->indexOfProperty(name);
        return i < 0 ? QMetaProperty() : mo->property(i);
    };
    Canvas c;
    c.live = prop("planeLive");
    c.scale = prop("planeScale");
    c.offsetX = prop("planeOffsetX");
    c.offsetY = prop("planeOffsetY");
    c.nav = prop("planeNavButtons");
    const QMetaProperty input = prop("planeInput");
    if (!c.live.isValid() || !c.scale.isValid() || !c.offsetX.isValid() || !c.offsetY.isValid() || !c.nav.isValid() || !input.isValid()
        || mo->indexOfMethod("planeTakes(QVariant,QVariant,QVariant)") < 0) {
        if (!g_canvas.warned) {
            logf("kwin-canvas effect has no plane interface; not attached");
            g_canvas.warned = true;
        }
        return;
    }
    c.object = e;
    c.effect = e;
    c.warned = g_canvas.warned;
    g_canvas = c;
    input.write(e, true);
    // A camera change warps the pointer to keep its screen position and moves
    // the drawn cursor; coalesced to one per event loop turn.
    const QMetaMethod start = g_nudge->metaObject()->method(g_nudge->metaObject()->indexOfSlot("start()"));
    for (const QMetaProperty &p : { c.live, c.scale, c.offsetX, c.offsetY }) {
        QObject::connect(e, p.notifySignal(), g_nudge, start);
    }
    logf("attached to the kwin-canvas effect");
}

// At quit the shim disarms, so nothing touches KWin objects while they go.
void shutdown()
{
    g_armed = false;
    for (QTimer **t : { &g_attachTimer, &g_nudge, &g_logFlush }) {
        delete *t;
        *t = nullptr;
    }
}

// Timers live on the main thread and are created on the first hook call,
// when the application object exists. The first attach waits for the event
// loop, so the effect's JS never runs from inside a paint or an input filter.
void ensureTimers()
{
    if (g_timersMade || !QCoreApplication::instance()) {
        return;
    }
    g_timersMade = true;
    QObject::connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, shutdown);
    g_nudge = new QTimer;
    g_nudge->setSingleShot(true);
    g_nudge->setInterval(0);
    QObject::connect(g_nudge, &QTimer::timeout, [] {
        ++g_serial;
        reanchor();
    });
    g_logFlush = new QTimer;
    g_logFlush->setSingleShot(true);
    g_logFlush->setInterval(200);
    QObject::connect(g_logFlush, &QTimer::timeout, [] { logTransform(true); });
    g_attachTimer = new QTimer;
    g_attachTimer->setInterval(1000);
    QObject::connect(g_attachTimer, &QTimer::timeout, [] {
        attach();
        reanchor();
    });
    g_attachTimer->start();
    QTimer::singleShot(0, [] {
        attach();
        reanchor();
    });
}

// The effect's transform: identity unless the effect object is alive,
// active and live, and its numbers are sane.
Transform canvasTransform()
{
    QObject *o = g_canvas.object.data();
    if (!o || !g_canvas.effect->isActive() || !g_canvas.live.read(o).toBool()) {
        return Transform{};
    }
    const double s = g_canvas.scale.read(o).toDouble();
    const double ox = g_canvas.offsetX.read(o).toDouble();
    const double oy = g_canvas.offsetY.read(o).toDouble();
    if (!sane(s, ox, oy)) {
        return Transform{};
    }
    return Transform{ true, s, ox, oy };
}

bool engaged()
{
    return g_armed && canvasTransform().active;
}

Transform effective()
{
    if (!g_armed) {
        return Transform{};
    }
    const Transform c = canvasTransform();
    if (c.active || !g_fileEnabled) {
        return c;
    }
    return fileTransform();
}

long long nowMs()
{
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

// One line when the transform is set or cleared; while it moves, at most one
// a second, and the value it settles on 200 ms later.
Transform g_logged;
long long g_loggedAt = 0;
void logTransform(bool force)
{
    const Transform t = g_posTf;
    if (t == g_logged) {
        return;
    }
    const long long now = nowMs();
    if (!force && t.active == g_logged.active && now - g_loggedAt < 1000) {
        if (g_logFlush && !g_logFlush->isActive()) {
            g_logFlush->start();
        }
        return;
    }
    if (t.active) {
        logf("transform s=%g o=(%g,%g)", t.s, t.ox, t.oy);
    } else {
        logf("transform cleared");
    }
    g_logged = t;
    g_loggedAt = now;
}

enum class Owner { None, Canvas, Kwin };
Owner g_owner = Owner::None; // of the gesture in progress, latched at the first press

// Re-expresses KWin's pointer position in the current transform, so the
// pointer keeps its screen position when the transform changes.
void reanchor()
{
    if (!g_armed) {
        return;
    }
    const Transform t = effective();
    if (t == g_posTf) {
        return;
    }
    const Transform old = g_posTf;
    g_posTf = t;
    if (t.active != old.active) {
        g_owner = Owner::None;
    }
    logTransform(false);
    KWin::InputRedirection *in = input();
    if (in && in->pointer()) {
        const QPointF p = g_api.globalPointer(in);
        const QPointF q = t.toPlane(old.toScreen(p));
        if (q != p) {
            orig<void (*)(KWin::PointerInputRedirection *, const QPointF &)>(Warp)(in->pointer(), q);
        }
    }
    if (g_scene) {
        _ZN4KWin14WorkspaceScene12updateCursorEv(g_scene.data());
    }
}

// ---- who takes the pointer --------------------------------------------------------

struct Answer { unsigned long serial = ~0ul; QPointF pos; bool take = true; };
Answer g_answer;

// Asks the effect whether the canvas takes the pointer at a plane point. A
// call that arrives while the effect's JS is answering gets the last answer.
bool canvasTakes(const QPointF &plane)
{
    static bool busy = false;
    if (busy || (g_answer.serial == g_serial && g_answer.pos == plane)) {
        return g_answer.take;
    }
    busy = true;
    const QPointF screen = g_posTf.toScreen(plane);
    g_probe = true;
    KWin::Window *w = static_cast<KWin::Window *>(
        orig<void *(*)(KWin::InputRedirection *, const QPointF &)>(FindToplevel)(input(), plane));
    g_probe = false;
    QVariant ret;
    const bool ok = QMetaObject::invokeMethod(g_canvas.object.data(), "planeTakes", Qt::DirectConnection,
                                              Q_RETURN_ARG(QVariant, ret),
                                              Q_ARG(QVariant, QVariant(screen.x())), Q_ARG(QVariant, QVariant(screen.y())),
                                              Q_ARG(QVariant, QVariant::fromValue<QObject *>(w)));
    // Anything but a boolean false is the canvas's.
    const bool take = !ok || ret.metaType().id() != QMetaType::Bool || ret.toBool();
    g_answer = Answer{ g_serial, plane, take };
    busy = false;
    return take;
}

// An application popup holds a grab (an open menu or combo list). KWin's
// popup filter, which runs after the effects filter, closes it on a press
// outside it and consumes the press.
bool popupGrabbed()
{
    KWin::Workspace *ws = *g_api.workspace;
    if (!ws) {
        return false;
    }
    const QList<KWin::Window *> windows = ws->windows();
    return std::any_of(windows.cbegin(), windows.cend(), [](const KWin::Window *w) {
        return w->hasPopupGrab();
    });
}

bool toKwin(const QPointF &plane)
{
    switch (g_owner) {
    case Owner::Kwin:
        return true;
    case Owner::Canvas:
        return false;
    case Owner::None:
        break;
    }
    return !canvasTakes(plane);
}

// Runs fn with the event's position at the screen point, as the effect's
// scene expects it.
template<typename Event, typename Fn>
bool deliver(Event *event, Fn fn)
{
    const QPointF plane = event->position;
    event->position = g_posTf.toScreen(plane);
    const bool r = fn();
    event->position = plane;
    return r;
}

void pointerEntry()
{
    ensureTimers();
    ++g_serial;
    reanchor();
}

int buildIdMatches(dl_phdr_info *info, size_t, void *data)
{
    if (!strstr(info->dlpi_name, "libkwin.so.6")) {
        return 0;
    }
    bool *ok = static_cast<bool *>(data);
    for (int i = 0; i < info->dlpi_phnum; ++i) {
        const ElfW(Phdr) &ph = info->dlpi_phdr[i];
        if (ph.p_type != PT_NOTE) {
            continue;
        }
        auto *p = reinterpret_cast<const char *>(info->dlpi_addr + ph.p_vaddr);
        const char *end = p + ph.p_memsz;
        while (p + sizeof(ElfW(Nhdr)) <= end) {
            auto *nh = reinterpret_cast<const ElfW(Nhdr) *>(p);
            const char *name = p + sizeof(*nh);
            const unsigned char *desc = reinterpret_cast<const unsigned char *>(name + ((nh->n_namesz + 3) & ~3u));
            if (nh->n_type == NT_GNU_BUILD_ID && nh->n_namesz == 4 && memcmp(name, "GNU", 4) == 0) {
                char hex[2 * 64 + 1] = {};
                for (unsigned j = 0; j < nh->n_descsz && j < 64; ++j) {
                    snprintf(hex + 2 * j, 3, "%02x", desc[j]);
                }
                *ok = strcmp(hex, EXPECTED_BUILD_ID) == 0;
                if (!*ok) {
                    logf("libkwin build-id %s != expected %s; inert", hex, EXPECTED_BUILD_ID);
                }
                return 1;
            }
            p = reinterpret_cast<const char *>(desc) + ((nh->n_descsz + 3) & ~3u);
        }
    }
    return 1;
}

template<typename T>
bool resolve(T &slot, const char *name)
{
    slot = reinterpret_cast<T>(dlsym(RTLD_DEFAULT, name));
    if (!slot) {
        logf("libkwin has no %s; inert", name);
    }
    return slot;
}

__attribute__((constructor)) void init()
{
    // A launcher in front of KWin (kwin_wayland_wrapper, a PATH script) keeps
    // LD_PRELOAD so it reaches kwin_wayland; kwin_wayland drops it so its own
    // children (Xwayland, autostarted clients) do not inherit the shim.
    char exe[256] = {};
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    const char *base = n > 0 ? strrchr(exe, '/') : nullptr;
    if (!base || strcmp(base + 1, "kwin_wayland") != 0) {
        return;
    }
    unsetenv("LD_PRELOAD");
    // The originals first: every hook passes through to them, armed or not.
    bool all = true;
    for (int h = 0; h < HookCount; ++h) {
        g_orig[h] = dlsym(RTLD_NEXT, s_hooks[h]);
        if (!g_orig[h]) {
            logf("libkwin has no %s; inert", s_hooks[h]);
            all = false;
        }
    }
    // kwin_wayland_wrapper sets KWIN_RESTART_COUNT when it restarts KWin after
    // a crash; a restarted KWin runs stock.
    if (const char *rc = getenv("KWIN_RESTART_COUNT"); rc && atoi(rc) > 0) {
        logf("KWIN_RESTART_COUNT=%s; inert", rc);
        return;
    }
    bool ok = false;
    dl_iterate_phdr(buildIdMatches, &ok);
    if (!ok || !all) {
        return;
    }
    Api a;
    if (!resolve(a.effects, "_ZN4KWin7effectsE") || !resolve(a.input, "_ZN4KWin16InputRedirection6s_selfE")
        || !resolve(a.workspace, "_ZN4KWin9Workspace5_selfE")
        || !resolve(a.findEffect, "_ZNK4KWin14EffectsHandler10findEffectERK7QString")
        || !resolve(a.globalPointer, "_ZNK4KWin16InputRedirection13globalPointerEv")
        || !resolve(a.workspaceGeometry, "_ZNK4KWin9Workspace8geometryEv")
        || !resolve(a.cursorItem, "_ZNK4KWin14WorkspaceScene10cursorItemEv")
        || !resolve(a.itemPosition, "_ZNK4KWin4Item8positionEv")
        || !resolve(a.itemSetPosition, "_ZN4KWin4Item11setPositionERK7QPointF")
        || !resolve(a.itemIsVisible, "_ZNK4KWin4Item9isVisibleEv")) {
        return;
    }
    g_api = a;
    const char *fe = getenv("KWIN_CANVAS_PRELOAD_FILE");
    g_fileEnabled = fe && strcmp(fe, "1") == 0;
    unsetenv("KWIN_CANVAS_PRELOAD_FILE");
    const char *rt = getenv("XDG_RUNTIME_DIR");
    if (g_fileEnabled && !(rt && *rt)) {
        logf("XDG_RUNTIME_DIR unset; no transform file");
        g_fileEnabled = false;
    }
    if (g_fileEnabled) {
        snprintf(g_path, sizeof(g_path), "%s/kwin-canvas-preload", rt);
    }
    const char *ae = getenv("KWIN_CANVAS_PRELOAD_ATTACH");
    g_attachEnabled = !(ae && strcmp(ae, "0") == 0);
    unsetenv("KWIN_CANVAS_PRELOAD_ATTACH");
    g_armed = true;
    logf("armed (pid %d, transform from %s%s%s)", getpid(), g_attachEnabled ? "the kwin-canvas effect" : "nothing",
         g_fileEnabled ? ", else " : "", g_fileEnabled ? g_path : "");
}

unsigned long g_findCalls = 0;

// The last Workspace::clientArea(option, window) answer, for the popup
// placement that follows it.
thread_local RectF g_lastArea;
thread_local bool g_haveLastArea = false;

} // namespace

extern "C" {

// ---- the pointer and touch chains -----------------------------------------------------

// KWin::InputRedirection::findToplevel(QPointF const&)
void *_ZN4KWin16InputRedirection12findToplevelERK7QPointF(void *self, const QPointF &pos)
{
    using Fn = void *(*)(void *, const QPointF &);
    const Fn fn = orig<Fn>(FindToplevel);
    if (!fn) {
        return nullptr;
    }
    const QPointF *outer = g_findPos;
    g_findPos = &pos;
    void *w = fn(self, pos);
    g_findPos = outer;
    if (g_armed && g_posTf.active && (++g_findCalls <= 5 || g_findCalls % 200 == 0)) {
        logf("findToplevel #%lu (%.1f,%.1f) -> %p", g_findCalls, pos.x(), pos.y(), w);
    }
    return w;
}

// KWin::PointerInputRedirection::processMotionAbsolute(QPointF const&, microseconds, InputDevice*)
void _ZN4KWin23PointerInputRedirection21processMotionAbsoluteERK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, const QPointF &pos, long time, void *device)
{
    using Fn = void (*)(void *, const QPointF &, long, void *);
    const Fn fn = orig<Fn>(MotionAbsolute);
    if (!fn) {
        return;
    }
    if (g_armed) {
        pointerEntry();
        return fn(self, g_posTf.toPlane(pos), time, device);
    }
    fn(self, pos, time, device);
}

// KWin::PointerInputRedirection::processMotion(QPointF const& delta, QPointF const& deltaNonAccelerated, microseconds, InputDevice*)
// The accelerated delta moves the plane position, so it is divided by s. The
// unaccelerated delta feeds relative-pointer clients and stays in device units.
void _ZN4KWin23PointerInputRedirection13processMotionERK7QPointFS3_NSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, const QPointF &delta, const QPointF &deltaRaw, long time, void *device)
{
    using Fn = void (*)(void *, const QPointF &, const QPointF &, long, void *);
    const Fn fn = orig<Fn>(Motion);
    if (!fn) {
        return;
    }
    if (g_armed) {
        pointerEntry();
        if (g_posTf.active) {
            return fn(self, delta / g_posTf.s, deltaRaw, time, device);
        }
    }
    fn(self, delta, deltaRaw, time, device);
}

// KWin::PointerInputRedirection::processButton(unsigned int, PointerButtonState, microseconds, InputDevice*)
void _ZN4KWin23PointerInputRedirection13processButtonEjNS_18PointerButtonStateENSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, unsigned button, int state, long time, void *device)
{
    using Fn = void (*)(void *, unsigned, int, long, void *);
    const Fn fn = orig<Fn>(Button);
    if (!fn) {
        return;
    }
    if (g_armed) {
        pointerEntry();
    }
    fn(self, button, state, time, device);
}

// KWin::PointerInputRedirection::processAxis(PointerAxis, double, int, PointerAxisSource, bool, microseconds, InputDevice*)
void _ZN4KWin23PointerInputRedirection11processAxisENS_11PointerAxisEdiNS_17PointerAxisSourceEbNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, int axis, double delta, int deltaV120, int source, bool inverted, long time, void *device)
{
    using Fn = void (*)(void *, int, double, int, int, bool, long, void *);
    const Fn fn = orig<Fn>(Axis);
    if (!fn) {
        return;
    }
    if (g_armed) {
        pointerEntry();
    }
    fn(self, axis, delta, deltaV120, source, inverted, time, device);
}

// KWin::TouchInputRedirection::processDown(int, QPointF const&, microseconds, InputDevice*)
void _ZN4KWin21TouchInputRedirection11processDownEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, int id, const QPointF &pos, long time, void *device)
{
    using Fn = void (*)(void *, int, const QPointF &, long, void *);
    const Fn fn = orig<Fn>(TouchDown);
    if (!fn) {
        return;
    }
    fn(self, id, g_armed ? effective().toPlane(pos) : pos, time, device);
}

// KWin::TouchInputRedirection::processMotion(int, QPointF const&, microseconds, InputDevice*)
void _ZN4KWin21TouchInputRedirection13processMotionEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, int id, const QPointF &pos, long time, void *device)
{
    using Fn = void (*)(void *, int, const QPointF &, long, void *);
    const Fn fn = orig<Fn>(TouchMotion);
    if (!fn) {
        return;
    }
    fn(self, id, g_armed ? effective().toPlane(pos) : pos, time, device);
}

// KWin::PointerInputRedirection::updatePosition(QPointF const&, QPointF const&, microseconds)
// Its output clamp (confineToBoundingBox, screenContainsPos, applyEdgeBarrier)
// reads LogicalOutput::geometry()/geometryF() through the GOT; while g_relax is
// set those return the output's image in the plane, so the pointer is confined
// to what the output shows instead of to the output's own rectangle.
void _ZN4KWin23PointerInputRedirection14updatePositionERK7QPointFS3_NSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE(
    void *self, const QPointF &pos, const QPointF &rel, long time)
{
    using Fn = void (*)(void *, const QPointF &, const QPointF &, long);
    const Fn fn = orig<Fn>(UpdatePosition);
    if (!fn) {
        return;
    }
    g_relax = g_armed && g_posTf.active;
    fn(self, pos, rel, time);
    g_relax = false;
}

// KWin::Workspace::setActiveOutput(QPointF const&)
// updatePosition calls this right after its clamp and before it emits
// globalPointerChanged; relaxation ends here so no slot sees plane geometry.
void _ZN4KWin9Workspace15setActiveOutputERK7QPointF(void *self, const QPointF &pos)
{
    using Fn = void (*)(void *, const QPointF &);
    const Fn fn = orig<Fn>(SetActiveOutput);
    if (!fn) {
        return;
    }
    g_relax = false;
    fn(self, pos);
}

// KWin::LogicalOutput::geometry() const
Rect _ZNK4KWin13LogicalOutput8geometryEv(const void *self)
{
    using Fn = Rect (*)(const void *);
    const Fn fn = orig<Fn>(OutputGeometry);
    if (!fn) {
        return {};
    }
    Rect r = fn(self);
    if (g_relax) {
        const Transform &t = g_posTf;
        auto edge = [](double v) { return int(std::clamp(v, -1e9, 1e9)); };
        r = Rect{ edge(std::floor((r.left - t.ox) / t.s)), edge(std::floor((r.top - t.oy) / t.s)),
                  edge(std::ceil((r.right - t.ox) / t.s)), edge(std::ceil((r.bottom - t.oy) / t.s)) };
    }
    return r;
}

// KWin::LogicalOutput::geometryF() const
RectF _ZNK4KWin13LogicalOutput9geometryFEv(const void *self)
{
    using Fn = RectF (*)(const void *);
    const Fn fn = orig<Fn>(OutputGeometryF);
    if (!fn) {
        return {};
    }
    RectF r = fn(self);
    if (g_relax) {
        const Transform &t = g_posTf;
        r = RectF{ (r.left - t.ox) / t.s, (r.top - t.oy) / t.s, (r.right - t.ox) / t.s, (r.bottom - t.oy) / t.s };
    }
    return r;
}

// KWin::PointerInputRedirection::warp(QPointF const&)
// A screen edge pushes the cursor back to a screen point.
void _ZN4KWin23PointerInputRedirection4warpERK7QPointF(void *self, const QPointF &pos)
{
    using Fn = void (*)(void *, const QPointF &);
    const Fn fn = orig<Fn>(Warp);
    if (!fn) {
        return;
    }
    fn(self, g_inEdges ? g_posTf.toPlane(pos) : pos);
}

// KWin::ScreenEdges::handlePointerMotion(QPointF const&, microseconds)
// Edges and hot corners belong to the screen: they see the pointer's screen
// position, held inside the workspace so the output's border is reachable.
void _ZN4KWin11ScreenEdges19handlePointerMotionERK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE(
    void *self, const QPointF &pos, long time)
{
    using Fn = void (*)(void *, const QPointF &, long);
    const Fn fn = orig<Fn>(EdgesMotion);
    if (!fn) {
        return;
    }
    if (!g_armed || !g_posTf.active) {
        return fn(self, pos, time);
    }
    const KWin::Rect ws = g_api.workspaceGeometry(*g_api.workspace);
    QPointF s = g_posTf.toScreen(pos);
    s.setX(std::clamp(s.x(), double(ws.left()), double(ws.right() - 1)));
    s.setY(std::clamp(s.y(), double(ws.top()), double(ws.bottom() - 1)));
    g_inEdges = true;
    fn(self, s, time);
    g_inEdges = false;
}

// ---- the cursor ---------------------------------------------------------------------

// KWin::WorkspaceScene::updateCursor()
// The cursor item sits at the pointer's plane position; draw it at the screen
// position instead.
void _ZN4KWin14WorkspaceScene12updateCursorEv(KWin::WorkspaceScene *self)
{
    using Fn = void (*)(KWin::WorkspaceScene *);
    const Fn fn = orig<Fn>(UpdateCursor);
    if (!fn) {
        return;
    }
    fn(self);
    if (!g_armed) {
        return;
    }
    g_scene = self;
    ensureTimers();
    // The item's position is the hotspot; the image sits at -hotspot inside
    // it, unscaled. The hardware cursor plane follows the item too
    // (compositor.cpp: an ItemTreeView of the cursor item on the cursor layer).
    KWin::Item *cursor = g_api.cursorItem(self);
    if (g_posTf.active && cursor && g_api.itemIsVisible(cursor)) {
        g_api.itemSetPosition(cursor, g_posTf.toScreen(g_api.itemPosition(cursor)));
    }
}

// ---- the effect's input grab ----------------------------------------------------------

// KWin::EffectsHandler::isMouseInterception() const
// findToplevel() finds no window and the cursor is the effect's while this is
// true; it is false where the pointer goes to a window.
bool _ZNK4KWin14EffectsHandler19isMouseInterceptionEv(const void *self)
{
    using Fn = bool (*)(const void *);
    const Fn fn = orig<Fn>(IsMouseInterception);
    if (!fn) {
        return false;
    }
    if (g_probe) {
        return false;
    }
    const bool r = fn(self);
    if (!r || !engaged()) {
        return r;
    }
    const QPointF pos = g_findPos ? *g_findPos : g_api.globalPointer(input());
    return !toKwin(pos);
}

// KWin::EffectsHandler::hasKeyboardGrab() const
bool _ZNK4KWin14EffectsHandler15hasKeyboardGrabEv(const void *self)
{
    using Fn = bool (*)(const void *);
    const Fn fn = orig<Fn>(HasKeyboardGrab);
    if (!fn) {
        return false;
    }
    return fn(self) && !engaged();
}

// KWin::EffectsHandler::pointerMotion(PointerMotionEvent*)
// Hover goes to the effect wherever the pointer is; outside a gesture the
// event also continues to the window when the canvas does not take the point.
bool _ZN4KWin14EffectsHandler13pointerMotionEPNS_18PointerMotionEventE(void *self, KWin::PointerMotionEvent *event)
{
    using Fn = bool (*)(void *, KWin::PointerMotionEvent *);
    const Fn fn = orig<Fn>(EffectsMotion);
    if (!fn) {
        return false;
    }
    if (!engaged()) {
        g_owner = Owner::None;
        return fn(self, event);
    }
    if (g_owner == Owner::Kwin) {
        return false;
    }
    const bool pass = toKwin(event->position);
    const bool r = deliver(event, [&] { return fn(self, event); });
    return r && !pass;
}

// KWin::EffectsHandler::pointerButton(PointerButtonEvent*)
bool _ZN4KWin14EffectsHandler13pointerButtonEPNS_18PointerButtonEventE(void *self, KWin::PointerButtonEvent *event)
{
    using Fn = bool (*)(void *, KWin::PointerButtonEvent *);
    const Fn fn = orig<Fn>(EffectsButton);
    if (!fn) {
        return false;
    }
    if (!engaged()) {
        g_owner = Owner::None;
        return fn(self, event);
    }
    // A press of the only button down starts a gesture, whatever a filter
    // ahead of this one did with the last release. A canvas button is the
    // canvas's wherever the pointer is, client areas included - that is what
    // makes a held button a portal into the canvas rather than something the
    // window under it sees. While an application popup holds a grab, a press
    // the canvas would take goes on to KWin, which dismisses the popup as it
    // does anywhere outside it.
    if (event->state == KWin::PointerButtonState::Pressed && event->buttons == event->button) {
        const bool nav = (uint(event->button) & navButtons()) != 0;
        g_owner = !popupGrabbed() && (nav || canvasTakes(event->position)) ? Owner::Canvas : Owner::Kwin;
    }
    const bool r = g_owner == Owner::Kwin ? false : deliver(event, [&] { return fn(self, event); });
    if (event->buttons == Qt::NoButton) {
        g_owner = Owner::None;
    }
    return r;
}

// KWin::EffectsHandler::pointerAxis(PointerAxisEvent*)
bool _ZN4KWin14EffectsHandler11pointerAxisEPNS_16PointerAxisEventE(void *self, KWin::PointerAxisEvent *event)
{
    using Fn = bool (*)(void *, KWin::PointerAxisEvent *);
    const Fn fn = orig<Fn>(EffectsAxis);
    if (!fn) {
        return false;
    }
    if (!engaged()) {
        return fn(self, event);
    }
    if (toKwin(event->position)) {
        return false;
    }
    return deliver(event, [&] { return fn(self, event); });
}

// KWin::EffectsHandler::touchDown(int, QPointF const&, microseconds)
// Touch stays the canvas's while it is open; it sees screen positions.
bool _ZN4KWin14EffectsHandler9touchDownEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE(
    void *self, int id, const QPointF &pos, long time)
{
    using Fn = bool (*)(void *, int, const QPointF &, long);
    const Fn fn = orig<Fn>(EffectsTouchDown);
    if (!fn) {
        return false;
    }
    return fn(self, id, engaged() ? effective().toScreen(pos) : pos, time);
}

// KWin::EffectsHandler::touchMotion(int, QPointF const&, microseconds)
bool _ZN4KWin14EffectsHandler11touchMotionEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE(
    void *self, int id, const QPointF &pos, long time)
{
    using Fn = bool (*)(void *, int, const QPointF &, long);
    const Fn fn = orig<Fn>(EffectsTouchMotion);
    if (!fn) {
        return false;
    }
    return fn(self, id, engaged() ? effective().toScreen(pos) : pos, time);
}

// ---- popup placement ------------------------------------------------------------------

// KWin::Workspace::clientArea(clientAreaOption, Window const*) const
// XdgPopupWindow::updateRelativePlacement() asks this for the parent's
// placement area and passes it, relative to the parent, straight to
// XdgPositioner::placement().
RectF _ZNK4KWin9Workspace10clientAreaENS_16clientAreaOptionEPKNS_6WindowE(const void *self, int option, const void *window)
{
    using Fn = RectF (*)(const void *, int, const void *);
    const Fn fn = orig<Fn>(ClientArea);
    if (!fn) {
        return {};
    }
    const RectF r = fn(self, option, window);
    g_lastArea = r;
    g_haveLastArea = g_armed;
    return r;
}

// KWin::XdgPositioner::placement(RectF const& bounds) const
// bounds is the parent's placement area relative to the parent; while the
// transform is live it becomes the area's image in the plane, so the popup
// is kept within what the output shows. The parent's position is the offset
// between the area and bounds; bounds that do not match the last area pass
// through.
RectF _ZNK4KWin13XdgPositioner9placementERKNS_5RectFE(const void *self, const RectF &bounds)
{
    using Fn = RectF (*)(const void *, const RectF &);
    const Fn fn = orig<Fn>(PopupPlacement);
    if (!fn) {
        return {};
    }
    const bool have = g_haveLastArea;
    g_haveLastArea = false;
    const Transform t = engaged() ? effective() : Transform{};
    const RectF &a = g_lastArea;
    const auto same = [](double x, double y) { return std::abs(x - y) < 1e-6; };
    if (!have || !t.active || !same(a.right - a.left, bounds.right - bounds.left)
        || !same(a.bottom - a.top, bounds.bottom - bounds.top)) {
        return fn(self, bounds);
    }
    const double px = a.left - bounds.left, py = a.top - bounds.top;
    const RectF mapped{ (a.left - t.ox) / t.s - px, (a.top - t.oy) / t.s - py,
                        (a.right - t.ox) / t.s - px, (a.bottom - t.oy) / t.s - py };
    return fn(self, mapped);
}

} // extern "C"

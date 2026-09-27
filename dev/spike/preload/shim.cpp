/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Spike: an LD_PRELOAD shim for kwin_wayland 6.7.5 that moves the pointer and
// touch chains into plane (canvas) coordinates, plane = (screen - o) / s.
//
// Every hook is an exported libkwin symbol whose callers go through a GOT slot
// (R_X86_64_GLOB_DAT, BIND_NOW), so a preloaded definition wins and the
// original is reached with dlsym(RTLD_NEXT).
//
// Transform source: $XDG_RUNTIME_DIR/kwin-canvas-preload, one line "s ox oy".
// Missing, empty or unparsable means identity. The file is stat()ed on each
// motion event and reread when its mtime or size changes.
//
// The shim is inert (every hook passes straight through) unless the process is
// kwin_wayland and libkwin's GNU build-id equals EXPECTED_BUILD_ID.
//
// Build: g++ -O2 -fPIC -shared -o shim.so shim.cpp -ldl

#include <dlfcn.h>
#include <link.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

constexpr const char *EXPECTED_BUILD_ID = "b4a7f7ab673a25da5e0253361baa08b4f6ef6394"; // kwin 6.7.5-1 (Arch)

struct PointF { double x, y; };            // QPointF
struct Rect { int left, top, right, bottom; };        // KWin::Rect, right/bottom exclusive
struct RectF { double left, top, right, bottom; };    // KWin::RectF

bool g_armed = false;          // process and build-id checks passed
thread_local bool g_relax = false;  // inside PointerInputRedirection::updatePosition

struct Transform { bool active = false; double s = 1, ox = 0, oy = 0; };
Transform g_tf;
char g_path[512];
timespec g_mtime{};
off_t g_size = -1;

void logf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("kwin-canvas-preload: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

void *orig(const char *name)
{
    void *p = dlsym(RTLD_NEXT, name);
    if (!p) {
        logf("dlsym(%s) failed: %s", name, dlerror());
        abort();
    }
    return p;
}

// Rereads the transform file when it changed. Cheap enough per event: one stat().
const Transform &transform()
{
    struct stat st;
    if (stat(g_path, &st) != 0) {
        if (g_size != -1) {
            g_size = -1;
            g_tf = Transform{};
            logf("transform cleared (file gone)");
        }
        return g_tf;
    }
    if (st.st_size == g_size && st.st_mtim.tv_sec == g_mtime.tv_sec && st.st_mtim.tv_nsec == g_mtime.tv_nsec) {
        return g_tf;
    }
    g_size = st.st_size;
    g_mtime = st.st_mtim;
    Transform t;
    if (FILE *f = fopen(g_path, "r")) {
        double s, ox, oy;
        if (fscanf(f, "%lf %lf %lf", &s, &ox, &oy) == 3 && s > 0.01 && s < 100) {
            t = Transform{ true, s, ox, oy };
        }
        fclose(f);
    }
    g_tf = t;
    if (t.active) {
        logf("transform s=%g o=(%g,%g)", t.s, t.ox, t.oy);
    } else {
        logf("transform cleared");
    }
    return g_tf;
}

PointF toPlane(const PointF &p, const Transform &t)
{
    return PointF{ (p.x - t.ox) / t.s, (p.y - t.oy) / t.s };
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

__attribute__((constructor)) void init()
{
    // A launcher in front of KWin (kwin_wayland_wrapper, a PATH script) keeps
    // LD_PRELOAD so it reaches kwin_wayland; kwin_wayland drops it so its own
    // children (Xwayland, autostarted clients) do not inherit the shim.
    char exe[256] = {};
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0 || !strstr(exe, "/kwin_wayland") || strstr(exe, "wrapper")) {
        return;
    }
    unsetenv("LD_PRELOAD");
    // kwin_wayland_wrapper sets KWIN_RESTART_COUNT when it restarts KWin after
    // a crash; a restarted KWin runs stock.
    if (const char *rc = getenv("KWIN_RESTART_COUNT"); rc && atoi(rc) > 0) {
        logf("KWIN_RESTART_COUNT=%s; inert", rc);
        return;
    }
    bool ok = false;
    dl_iterate_phdr(buildIdMatches, &ok);
    if (!ok) {
        return;
    }
    const char *rt = getenv("XDG_RUNTIME_DIR");
    snprintf(g_path, sizeof(g_path), "%s/kwin-canvas-preload", rt ? rt : "/tmp");
    g_armed = true;
    logf("armed (pid %d, transform file %s)", getpid(), g_path);
}

unsigned long g_findCalls = 0;

} // namespace

extern "C" {

// KWin::InputRedirection::findToplevel(QPointF const&)
void *_ZN4KWin16InputRedirection12findToplevelERK7QPointF(void *self, const PointF &pos)
{
    using Fn = void *(*)(void *, const PointF &);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    void *w = fn(self, pos);
    if (g_armed && (++g_findCalls <= 5 || g_findCalls % 200 == 0)) {
        logf("findToplevel #%lu (%.1f,%.1f) -> %p", g_findCalls, pos.x, pos.y, w);
    }
    return w;
}

// KWin::PointerInputRedirection::processMotionAbsolute(QPointF const&, microseconds, InputDevice*)
void _ZN4KWin23PointerInputRedirection21processMotionAbsoluteERK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, const PointF &pos, long time, void *device)
{
    using Fn = void (*)(void *, const PointF &, long, void *);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    if (g_armed) {
        const Transform &t = transform();
        if (t.active) {
            const PointF p = toPlane(pos, t);
            logf("motionAbsolute screen (%.1f,%.1f) -> plane (%.1f,%.1f)", pos.x, pos.y, p.x, p.y);
            return fn(self, p, time, device);
        }
    }
    fn(self, pos, time, device);
}

// KWin::PointerInputRedirection::processMotion(QPointF const& delta, QPointF const& deltaNonAccelerated, microseconds, InputDevice*)
// The accelerated delta moves the plane position, so it is divided by s. The
// unaccelerated delta feeds relative-pointer clients and stays in device units.
void _ZN4KWin23PointerInputRedirection13processMotionERK7QPointFS3_NSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, const PointF &delta, const PointF &deltaRaw, long time, void *device)
{
    using Fn = void (*)(void *, const PointF &, const PointF &, long, void *);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    if (g_armed) {
        const Transform &t = transform();
        if (t.active) {
            const PointF d{ delta.x / t.s, delta.y / t.s };
            return fn(self, d, deltaRaw, time, device);
        }
    }
    fn(self, delta, deltaRaw, time, device);
}

// KWin::TouchInputRedirection::processDown(int, QPointF const&, microseconds, InputDevice*)
void _ZN4KWin21TouchInputRedirection11processDownEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, int id, const PointF &pos, long time, void *device)
{
    using Fn = void (*)(void *, int, const PointF &, long, void *);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    if (g_armed) {
        const Transform &t = transform();
        if (t.active) {
            return fn(self, id, toPlane(pos, t), time, device);
        }
    }
    fn(self, id, pos, time, device);
}

// KWin::TouchInputRedirection::processMotion(int, QPointF const&, microseconds, InputDevice*)
void _ZN4KWin21TouchInputRedirection13processMotionEiRK7QPointFNSt6chrono8durationIlSt5ratioILl1ELl1000000EEEEPNS_11InputDeviceE(
    void *self, int id, const PointF &pos, long time, void *device)
{
    using Fn = void (*)(void *, int, const PointF &, long, void *);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    if (g_armed) {
        const Transform &t = transform();
        if (t.active) {
            return fn(self, id, toPlane(pos, t), time, device);
        }
    }
    fn(self, id, pos, time, device);
}

// KWin::PointerInputRedirection::updatePosition(QPointF const&, QPointF const&, microseconds)
// Its output clamp (confineToBoundingBox, screenContainsPos, applyEdgeBarrier)
// reads LogicalOutput::geometry()/geometryF() through the GOT; while g_relax is
// set those return the output's image in the plane, so the pointer is confined
// to what the output shows instead of to the output's own rectangle.
void _ZN4KWin23PointerInputRedirection14updatePositionERK7QPointFS3_NSt6chrono8durationIlSt5ratioILl1ELl1000000EEEE(
    void *self, const PointF &pos, const PointF &rel, long time)
{
    using Fn = void (*)(void *, const PointF &, const PointF &, long);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    g_relax = g_armed && transform().active;
    fn(self, pos, rel, time);
    g_relax = false;
}

// KWin::Workspace::setActiveOutput(QPointF const&)
// updatePosition calls this right after its clamp and before it emits
// globalPointerChanged; relaxation ends here so no slot sees plane geometry.
void _ZN4KWin9Workspace15setActiveOutputERK7QPointF(void *self, const PointF &pos)
{
    using Fn = void (*)(void *, const PointF &);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    g_relax = false;
    fn(self, pos);
}

// KWin::LogicalOutput::geometry() const
Rect _ZNK4KWin13LogicalOutput8geometryEv(const void *self)
{
    using Fn = Rect (*)(const void *);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    Rect r = fn(self);
    if (g_relax) {
        const Transform &t = g_tf;
        r = Rect{ int(std::floor((r.left - t.ox) / t.s)), int(std::floor((r.top - t.oy) / t.s)),
                  int(std::ceil((r.right - t.ox) / t.s)), int(std::ceil((r.bottom - t.oy) / t.s)) };
    }
    return r;
}

// KWin::LogicalOutput::geometryF() const
RectF _ZNK4KWin13LogicalOutput9geometryFEv(const void *self)
{
    using Fn = RectF (*)(const void *);
    static Fn fn = reinterpret_cast<Fn>(orig(__func__));
    RectF r = fn(self);
    if (g_relax) {
        const Transform &t = g_tf;
        r = RectF{ (r.left - t.ox) / t.s, (r.top - t.oy) / t.s, (r.right - t.ox) / t.s, (r.bottom - t.oy) / t.s };
    }
    return r;
}

} // extern "C"

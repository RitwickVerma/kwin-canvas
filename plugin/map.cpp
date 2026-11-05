/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "map.h"

#include <effect/effecthandler.h>
#include <window.h>
#include <workspace.h>

#include <QMetaMethod>
#include <QMetaProperty>
#include <QVariant>

using namespace KWin;

CanvasMap::CanvasMap(QObject *parent)
    : QObject(parent)
{
    // The first change starts the clock and the rest of the burst rides it,
    // so a window dragged at the screen's rate still moves on the map ten
    // times a second instead of only when the hand stops.
    m_pending.setSingleShot(true);
    m_pending.setInterval(100);
    connect(&m_pending, &QTimer::timeout, this, &CanvasMap::changed);
}

QObject *CanvasMap::canvas() const
{
    return effects ? effects->findEffect(QStringLiteral("kwin-canvas")) : nullptr;
}

void CanvasMap::touch()
{
    if (!m_pending.isActive()) {
        m_pending.start();
    }
}

void CanvasMap::watch(Window *window)
{
    connect(window, &Window::frameGeometryChanged, this, &CanvasMap::touch);
    connect(window, &Window::minimizedChanged, this, &CanvasMap::touch);
    connect(window, &Window::hiddenChanged, this, &CanvasMap::touch);
    connect(window, &Window::desktopsChanged, this, &CanvasMap::touch);
    connect(window, &Window::activitiesChanged, this, &CanvasMap::touch);
    connect(window, &Window::captionChanged, this, &CanvasMap::touch);
}

// The effect's own changes: the camera (the view and the zoom, which move a
// closed desk on a commit and the open canvas on every frame), the entries
// (revision), the screens and the canvas opening or closing. Each is a QML
// property with a notify signal; one missing from an older effect is skipped.
void CanvasMap::watchCanvas(QObject *effect)
{
    if (m_canvas) {
        disconnect(m_canvas, nullptr, this, nullptr);
    }
    m_canvas = effect;
    const QMetaObject *mo = effect->metaObject();
    const QMetaMethod slot = metaObject()->method(metaObject()->indexOfSlot("touch()"));
    for (const char *name : {"viewX", "viewY", "zoom", "revision", "screensRev", "visible", "quiet", "currentActivity"}) {
        const int i = mo->indexOfProperty(name);
        if (i >= 0 && mo->property(i).hasNotifySignal()) {
            connect(effect, mo->property(i).notifySignal(), this, slot);
        }
    }
}

QString CanvasMap::read()
{
    QObject *effect = canvas();
    if (!effect) {
        return QString();
    }
    if (!m_watching) {
        m_watching = true;
        for (Window *w : workspace()->windows()) {
            watch(w);
        }
        connect(workspace(), &Workspace::windowAdded, this, [this](Window *w) {
            watch(w);
            touch();
        });
        connect(workspace(), &Workspace::windowRemoved, this, &CanvasMap::touch);
        connect(workspace(), &Workspace::windowActivated, this, &CanvasMap::touch);
        connect(workspace(), &Workspace::stackingOrderChanged, this, &CanvasMap::touch);
        connect(workspace(), &Workspace::currentDesktopChanged, this, &CanvasMap::touch);
        connect(workspace(), &Workspace::outputsChanged, this, &CanvasMap::touch);
    }
    if (m_canvas != effect) {
        watchCanvas(effect);
    }
    QVariant plane;
    if (!QMetaObject::invokeMethod(effect, "mapPlane", Q_RETURN_ARG(QVariant, plane))) {
        return QString();
    }
    return plane.toString();
}

void CanvasMap::go(double x, double y)
{
    if (QObject *effect = canvas()) {
        QMetaObject::invokeMethod(effect, "mapGo", Q_ARG(QVariant, x), Q_ARG(QVariant, y));
    }
}

void CanvasMap::focus(const QString &id)
{
    if (QObject *effect = canvas()) {
        QMetaObject::invokeMethod(effect, "mapFocus", Q_ARG(QVariant, id));
    }
}

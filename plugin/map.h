/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QObject>
#include <QPointer>
#include <QString>
#include <QTimer>

namespace KWin
{
class Window;
}

/**
 * The plane as a map, for the map widget (applet-map), on KWin's D-Bus name at
 * /KWinCanvas/Map, interface org.kde.kwin.canvas.Map.
 *
 * The effect is the one authority on where things sit on the plane, so this
 * object asks it (its mapPlane, in process) rather than repeating the mapping,
 * and only relays: read() answers the effect's JSON, go() and focus() hand the
 * widget's clicks to the effect. What it adds is the change signal. The effect
 * notices a window's move only while the canvas is open, so the map watches
 * KWin's windows itself, and the effect's camera and entries, and says
 * changed() at most once per 100 ms. It starts watching at the first read: a
 * session without the widget pays nothing.
 */
class CanvasMap : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwin.canvas.Map")

public:
    explicit CanvasMap(QObject *parent = nullptr);

public Q_SLOTS:
    /**
     * The plane as JSON: {"open": the canvas is open, "camera": [[x, y, w, h], ...] one per
     * screen, "frames": [[x, y, w, h, colour, current], ...], "windows": [{"id", "caption",
     * "x", "y", "w", "h", "active", "here"}, ...] bottom to top}, in plane coordinates. Empty
     * when the canvas effect is not loaded.
     */
    Q_SCRIPTABLE QString read();
    /** Bring the plane point (x, y) to the centre of the screen the pointer is on. */
    Q_SCRIPTABLE void go(double x, double y);
    /** Fly to the window with this internalId and focus it. */
    Q_SCRIPTABLE void focus(const QString &id);

Q_SIGNALS:
    /** Something on the map moved: at most one per 100 ms, and only after a first read. */
    Q_SCRIPTABLE void changed();

private Q_SLOTS:
    void touch();

private:
    QObject *canvas() const;
    void watch(KWin::Window *window);
    void watchCanvas(QObject *canvas);

    bool m_watching = false;
    /** The effect whose notify signals are connected (a reloaded effect is a new object). */
    QPointer<QObject> m_canvas;
    QTimer m_pending;
};

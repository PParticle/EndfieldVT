#pragma once

#include <QPlatformSurfaceEvent>
#include <QDebug>
#include <QGuiApplication>
#include <QObject>
#include <QPointer>
#include <QSizeF>
#include <QWindow>
#include <QtQml/qqmlregistration.h>
#include <cmath>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <commctrl.h>
#endif

// Constrain the native drag rectangle before Windows applies it. Insets
// describe the QML chrome in logical pixels; the canvas keeps its ratio.
class WindowAspectRatio : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QWindow* window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(qreal ratio MEMBER m_ratio NOTIFY ratioChanged)
    Q_PROPERTY(QSizeF insets MEMBER m_insets NOTIFY insetsChanged)

public:
    explicit WindowAspectRatio(QObject* parent = nullptr) : QObject(parent) {}
    ~WindowAspectRatio() override { detach(); }

    QWindow* window() const { return m_window; }
    void setWindow(QWindow* value)
    {
        if (m_window == value) return;
        detach();
        if (m_window) m_window->removeEventFilter(this);
        m_window = value;
        if (m_window) {
            m_window->installEventFilter(this);
            attach();
        }
        emit windowChanged();
    }

signals:
    void windowChanged();
    void ratioChanged();
    void insetsChanged();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override
    {
        if (watched == m_window && event->type() == QEvent::PlatformSurface) {
            const auto type = static_cast<QPlatformSurfaceEvent*>(event)->surfaceEventType();
            if (type == QPlatformSurfaceEvent::SurfaceCreated) attach();
            else if (type == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) detach();
        }
        return QObject::eventFilter(watched, event);
    }

private:
    void attach()
    {
#ifdef Q_OS_WIN
        if (QGuiApplication::platformName() != "windows" || m_hwnd || !m_window || !m_window->handle()) return;
        const HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
        if (SetWindowSubclass(hwnd, windowProc, reinterpret_cast<UINT_PTR>(this),
                              reinterpret_cast<DWORD_PTR>(this))) m_hwnd = hwnd;
        else qWarning("Could not install window aspect-ratio constraint");
#endif
    }
    void detach()
    {
#ifdef Q_OS_WIN
        if (m_hwnd) RemoveWindowSubclass(m_hwnd, windowProc, reinterpret_cast<UINT_PTR>(this));
        m_hwnd = nullptr;
#endif
    }

#ifdef Q_OS_WIN
    // Qt 6.12 excludes WM_SIZING from application-wide native event filters.
    // A per-HWND subclass also handles the system's modal resize loop.
    static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM edge, LPARAM data,
                                       UINT_PTR id, DWORD_PTR ref)
    {
        auto* self = reinterpret_cast<WindowAspectRatio*>(ref);
        if (message == WM_SIZING && self->m_window && self->m_ratio > 0
            && self->constrain(hwnd, int(edge), *reinterpret_cast<RECT*>(data))) return TRUE;
        if (message == WM_NCDESTROY) {
            RemoveWindowSubclass(hwnd, windowProc, id);
            self->m_hwnd = nullptr;
        }
        return DefSubclassProc(hwnd, message, edge, data);
    }

    bool constrain(HWND hwnd, int edge, RECT& rect) const
    {
        RECT current{}, client{};
        if (!GetWindowRect(hwnd, &current) || !GetClientRect(hwnd, &client)) return false;
        const qreal scale = m_window->devicePixelRatio();
        const int extraW = current.right - current.left - client.right + client.left
                         + qRound(m_insets.width() * scale);
        const int extraH = current.bottom - current.top - client.bottom + client.top
                         + qRound(m_insets.height() * scale);
        const bool left = edge == WMSZ_LEFT || edge == WMSZ_TOPLEFT || edge == WMSZ_BOTTOMLEFT;
        const bool top = edge == WMSZ_TOP || edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT;
        const bool horizontal = edge == WMSZ_LEFT || edge == WMSZ_RIGHT;
        const bool vertical = edge == WMSZ_TOP || edge == WMSZ_BOTTOM;
        const qreal deltaW = std::abs((rect.right - rect.left) - (current.right - current.left));
        const qreal deltaH = std::abs((rect.bottom - rect.top) - (current.bottom - current.top));
        const bool byHeight = vertical || (!horizontal && deltaH * m_ratio > deltaW);
        qreal width = byHeight ? (rect.bottom - rect.top - extraH) * m_ratio
                              : rect.right - rect.left - extraW;
        const qreal minWidth = qMax(qreal(m_window->minimumWidth()) * scale - extraW,
                                   (m_window->minimumHeight() * scale - extraH) * m_ratio);
        const qreal maxWidth = qMin(qreal(m_window->maximumWidth()) * scale - extraW,
                                   (m_window->maximumHeight() * scale - extraH) * m_ratio);
        width = qBound(qMax(qreal(1), minWidth), width, qMax(minWidth, maxWidth));
        const int outerW = qRound(width) + extraW;
        const int outerH = qRound(width / m_ratio) + extraH;
        if (left) rect.left = rect.right - outerW;
        else rect.right = rect.left + outerW;
        if (top) rect.top = rect.bottom - outerH;
        else rect.bottom = rect.top + outerH;
        return true;
    }
    HWND m_hwnd = nullptr;
#endif

    QPointer<QWindow> m_window;
    qreal m_ratio = 1;
    QSizeF m_insets;
};

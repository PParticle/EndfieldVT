#pragma once

#include <QObject>
#include <QPointer>
#include <QRect>
#include <QTimer>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

// Follows the game's window (Endfield.exe) for the in-game overlay, and
// keeps the overlay window above it.
//
// Placement: the overlay covers the game's client area, in Qt's logical
// pixels. Borderless fullscreen and windowed mode are the same case; only
// the rectangle differs.
//
// Stacking: while the game is the foreground window the overlay is topmost
// (nothing else is in front then anyway). Otherwise it is not topmost and
// sits directly above the game in the z-order, so other windows cover both,
// as they would the game alone. Hidden while the game is minimized or gone.
//
// The overlay window itself is made click-through and never takes focus,
// and stays off the taskbar and Alt+Tab.
class GameWindow : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    // The overlay window to manage; set once.
    Q_PROPERTY(QWindow* overlay READ overlay WRITE setOverlay NOTIFY overlayChanged)
    // Show while the game is not the foreground window too (default: yes;
    // it then stays just above the game, under whatever covers the game).
    Q_PROPERTY(bool showInBackground MEMBER m_showInBackground NOTIFY showInBackgroundChanged)
    // Off: the overlay stays hidden whatever the game does.
    Q_PROPERTY(bool enabled MEMBER m_enabled NOTIFY enabledChanged)
    // "none" (not running), "minimized", "background", "foreground"
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString stateText READ stateText NOTIFY changed)
    Q_PROPERTY(QRect rect READ rect NOTIFY changed)          // logical pixels
    Q_PROPERTY(QSize nativeSize READ nativeSize NOTIFY changed) // device pixels: the game's resolution
    Q_PROPERTY(bool fullscreen READ fullscreen NOTIFY changed)  // covers its whole monitor (borderless)
    Q_PROPERTY(bool visible READ visible NOTIFY changed)     // overlay shown now

public:
    explicit GameWindow(QObject* parent = nullptr);
    ~GameWindow() override;

    QWindow* overlay() const { return m_overlay; }
    void setOverlay(QWindow* window);
    QString state() const { return m_state; }
    QString stateText() const;
    QRect rect() const { return m_rect; }
    QSize nativeSize() const { return m_nativeSize; }
    bool fullscreen() const { return m_fullscreen; }
    bool visible() const { return m_visible; }

signals:
    void overlayChanged();
    void showInBackgroundChanged();
    void enabledChanged();
    void changed();

private:
    void poll();
    void prepareOverlay();
    void apply();

    QPointer<QWindow> m_overlay;
    QTimer m_timer;
    bool m_showInBackground = true;
    bool m_enabled = true;
    QString m_state = "none";
    QRect m_rect;
    QSize m_nativeSize;
    bool m_fullscreen = false;
    bool m_visible = false;
    bool m_topmost = false;
    quintptr m_game = 0;   // HWND
    int m_searchIn = 0;    // polls until the next window search
};

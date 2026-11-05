#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include "gamewindow.h"

#include <QGuiApplication>
#include <QScreen>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {

constexpr int kPollMs = 50;         // follow moves and focus changes at 20 Hz
constexpr int kSearchEvery = 20;    // look for the game once a second while it is not found

#ifdef Q_OS_WIN
bool IsEndfield(HWND hwnd)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return false;
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    const bool ok = QueryFullProcessImageNameW(process, 0, path, &size) != 0;
    CloseHandle(process);
    if (!ok) return false;
    const wchar_t* name = wcsrchr(path, L'\\');
    return _wcsicmp(name ? name + 1 : path, L"Endfield.exe") == 0;
}

// The game's main window: a visible top-level Unity window of Endfield.exe.
BOOL CALLBACK FindGame(HWND hwnd, LPARAM out)
{
    wchar_t cls[32];
    if (IsWindowVisible(hwnd) && !GetWindow(hwnd, GW_OWNER) && GetClassNameW(hwnd, cls, 32)
        && wcscmp(cls, L"UnityWndClass") == 0 && IsEndfield(hwnd)) {
        *reinterpret_cast<HWND*>(out) = hwnd;
        return FALSE;
    }
    return TRUE;
}
#endif

} // namespace

GameWindow::GameWindow(QObject* parent) : QObject(parent)
{
    connect(&m_timer, &QTimer::timeout, this, &GameWindow::poll);
    connect(this, &GameWindow::enabledChanged, this, &GameWindow::apply);
    connect(this, &GameWindow::showInBackgroundChanged, this, &GameWindow::apply);
    m_timer.start(kPollMs);
}

GameWindow::~GameWindow() = default;

void GameWindow::setOverlay(QWindow* window)
{
    if (m_overlay == window) return;
    m_overlay = window;
    emit overlayChanged();
}

QString GameWindow::stateText() const
{
    if (m_state == "foreground") return QString("游戏位于前台 · %1×%2%3").arg(m_nativeSize.width()).arg(m_nativeSize.height()).arg(m_fullscreen ? " 无边框全屏" : " 窗口化");
    if (m_state == "background") return QString("游戏位于后台 · %1×%2%3").arg(m_nativeSize.width()).arg(m_nativeSize.height()).arg(m_fullscreen ? " 无边框全屏" : " 窗口化");
    if (m_state == "minimized") return "游戏已最小化";
    return "未检测到游戏窗口";
}

// Never activated, off the taskbar and Alt+Tab. Click-through comes from the
// window's Qt::WindowTransparentForInput flag (set in OverlayWindow.qml):
// Qt makes the window layered and WS_EX_TRANSPARENT and keeps it consistent.
void GameWindow::prepareOverlay()
{
    if (!m_overlay) return;
#ifdef Q_OS_WIN
    // Checked every time: Qt may recreate the native window (style changes).
    if (QGuiApplication::platformName() == "windows") {
        const HWND hwnd = reinterpret_cast<HWND>(m_overlay->winId());
        const LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        const LONG_PTR want = (ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW) & ~LONG_PTR(WS_EX_APPWINDOW);
        if (want != ex) SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
    }
#endif
}

#ifdef Q_OS_WIN
namespace {

// Device pixels -> Qt's logical pixels. Qt keeps each screen's origin at its
// device position and scales inside it, so find the screen by its device
// rectangle, then scale relative to its origin.
QRect ToLogical(const QRect& device)
{
    QScreen* screen = nullptr;
    for (QScreen* s : QGuiApplication::screens()) {
        const QRect g = s->geometry();
        const QRect native(g.topLeft(), g.size() * s->devicePixelRatio());
        if (native.contains(device.center())) { screen = s; break; }
    }
    if (!screen) screen = QGuiApplication::primaryScreen();
    if (!screen) return device;
    const qreal dpr = screen->devicePixelRatio();
    const QPoint o = screen->geometry().topLeft();
    return QRect(QPoint(o.x() + qRound((device.x() - o.x()) / dpr), o.y() + qRound((device.y() - o.y()) / dpr)),
                 QSize(qRound(device.width() / dpr), qRound(device.height() / dpr)));
}

bool IsTopmost(HWND hwnd) { return (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0; }

} // namespace
#endif

void GameWindow::poll()
{
    QString state = "none";
    QRect rect;
    QSize native;
    bool fullscreen = false;
#ifdef Q_OS_WIN
    HWND game = reinterpret_cast<HWND>(m_game);
    if (game && !IsWindow(game)) game = nullptr;
    if (!game && --m_searchIn <= 0) {
        m_searchIn = kSearchEvery;
        EnumWindows(FindGame, reinterpret_cast<LPARAM>(&game));
    }
    m_game = reinterpret_cast<quintptr>(game);
    if (game) {
        RECT client{};
        POINT origin{};
        if (IsIconic(game)) {
            state = "minimized";
        } else if (GetClientRect(game, &client) && ClientToScreen(game, &origin) && client.right > 0 && client.bottom > 0) {
            const HWND fg = GetForegroundWindow();
            const HWND self = m_overlay && m_overlay->handle() ? reinterpret_cast<HWND>(m_overlay->winId()) : nullptr;
            state = fg == game || (fg && fg == self) ? "foreground" : "background";
            native = QSize(client.right, client.bottom);
            const QRect device(origin.x, origin.y, client.right, client.bottom);
            // Borderless fullscreen: the client area is the whole monitor.
            MONITORINFO mi{sizeof(mi)};
            if (GetMonitorInfoW(MonitorFromWindow(game, MONITOR_DEFAULTTONEAREST), &mi)) {
                const RECT& m = mi.rcMonitor;
                fullscreen = device == QRect(m.left, m.top, m.right - m.left, m.bottom - m.top);
            }
            rect = ToLogical(device);
        }
    }
#endif
    const bool moved = rect != m_rect || native != m_nativeSize || fullscreen != m_fullscreen;
    const bool stateChanged = state != m_state;
    m_state = state;
    m_rect = rect;
    m_nativeSize = native;
    m_fullscreen = fullscreen;
    if (moved || stateChanged) emit changed();
    apply();
}

void GameWindow::apply()
{
    if (!m_overlay) return;
    const bool show = m_enabled && (m_state == "foreground" || (m_state == "background" && m_showInBackground));
    if (show) {
        prepareOverlay();
        if (m_overlay->geometry() != m_rect) m_overlay->setGeometry(m_rect);
        if (!m_overlay->isVisible()) m_overlay->show();
#ifdef Q_OS_WIN
        const HWND self = reinterpret_cast<HWND>(m_overlay->winId());
        const HWND game = reinterpret_cast<HWND>(m_game);
        const bool topmost = m_state == "foreground";
        const UINT keep = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
        if (topmost) {
            if (!m_topmost || !IsTopmost(self)) SetWindowPos(self, HWND_TOPMOST, 0, 0, 0, 0, keep);
        } else {
            if (m_topmost || IsTopmost(self)) SetWindowPos(self, HWND_NOTOPMOST, 0, 0, 0, 0, keep);
            // Directly above the game: below the window that is just above it.
            // Placing it after a topmost window would make it topmost too, so
            // when that is what is above the game, go to the top of the
            // normal windows instead.
            const HWND above = GetWindow(game, GW_HWNDPREV);
            if (above != self)
                SetWindowPos(self, above && !IsTopmost(above) ? above : HWND_TOP, 0, 0, 0, 0, keep);
        }
        m_topmost = topmost;
#endif
    } else if (m_overlay->isVisible()) {
        m_overlay->hide();
    }
    if (show != m_visible) {
        m_visible = show;
        emit changed();
    }
}

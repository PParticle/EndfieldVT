#include <QFont>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

int main(int argc, char* argv[])
{
    QGuiApplication app(argc, argv);
    // The system's text rasterizer: crisper than the scene graph's own at
    // 12-14 px UI text.
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
    // The in-game overlay is a see-through window: windows need an alpha
    // channel, and this has to be set before the first one is created.
    QQuickWindow::setDefaultAlphaBuffer(true);
    // CJK first, then Latin; sizes are in Theme.qml. QML's font has no
    // family list, so this is the application default the controls inherit.
    QFont font;
    font.setFamilies({"Microsoft YaHei UI", "Segoe UI"});
    QGuiApplication::setFont(font);

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("EndfieldVT", "Main");
    return app.exec();
}

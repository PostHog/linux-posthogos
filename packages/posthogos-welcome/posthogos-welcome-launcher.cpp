// posthogos-welcome-launcher: gives the welcome window a proper Plasma
// app_id so KWin matches it to posthogos-welcome.desktop and renders the
// branded icon in the titlebar/taskbar. Plain qml6 sets app_id to "qml".
// Qt requires setDesktopFileName() to be called programmatically (no env
// var works), hence this shim. Compiled in posthogos-welcome's PKGBUILD
// build() against the build container's Qt6 headers; ships pre-built in
// the package. QML side stays at welcome.qml; exit codes pass through
// to the bash wrapper.

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QUrl>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    // setDesktopFileName drives the Wayland app_id; setWindowIcon is
    // belt-and-suspenders for X11. applicationName also seeds the
    // QtCore.Settings path (~/.config/PostHog/posthogos-welcome.conf).
    app.setOrganizationName("PostHog");
    app.setApplicationName("posthogos-welcome");
    app.setDesktopFileName("posthogos-welcome");
    app.setWindowIcon(QIcon::fromTheme("posthogos-welcome"));

    QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile("/usr/share/posthogos/welcome.qml"));
    if (engine.rootObjects().isEmpty()) {
        return 2;  // matches qml6's own exit code for load failure
    }
    return app.exec();
}

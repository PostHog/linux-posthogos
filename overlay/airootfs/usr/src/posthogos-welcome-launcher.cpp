// posthogos-welcome-launcher — replaces a plain `qml6 welcome.qml` call so
// the welcome window gets a proper application identity in Plasma.
//
// Without this shim, qml6 sets QGuiApplication::applicationName() to "qml"
// and never calls setDesktopFileName(). On Wayland that means the
// xdg_toplevel.set_app_id() call announces "qml" to the compositor; KWin
// can't match that to /usr/share/applications/posthogos-welcome.desktop,
// so the titlebar + taskbar entry both render a generic Qt fallback icon.
//
// Qt's QT_QPA_APP_DESKTOP_FILE_NAME env var is a myth I invented in a
// previous iteration — Qt docs say setDesktopFileName() "must be set
// programmatically". This file is that programmatic set.
//
// Compiled in the chroot by scripts/posthogos-customize.sh (where gcc +
// qt6-declarative headers are both present from pacstrap). Source removed
// after compile to keep the airootfs lean.
//
// QML side stays at /usr/share/posthogos/welcome.qml — we just load it
// from a properly-identified host process.
//
// Exit codes: pass-through from the QML side (welcome.qml uses Qt.exit(N)
// for "Install to disk" = 10, "Open terminal" = 11; the bash wrapper at
// /usr/local/bin/posthogos-welcome dispatches on those).

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QUrl>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    // These three lines are the whole point of this file.
    // applicationName: appears in window-manager listings, file paths
    //   like ~/.config/<org>/<appname>.conf for QtCore.Settings, etc.
    // setDesktopFileName: announces the .desktop file association to
    //   the compositor (Wayland app_id) so the right icon resolves.
    // setWindowIcon: belt-and-suspenders for X11 / contexts where
    //   compositor doesn't honor the desktop file association.
    app.setOrganizationName("PostHog");
    app.setApplicationName("posthogos-welcome");
    app.setDesktopFileName("posthogos-welcome");
    app.setWindowIcon(QIcon::fromTheme("posthogos-welcome"));

    QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile("/usr/share/posthogos/welcome.qml"));
    if (engine.rootObjects().isEmpty()) {
        // QML failed to load (missing module, syntax error, etc.). Exit 2
        // matches qml6's own exit code for the same failure mode.
        return 2;
    }
    return app.exec();
}

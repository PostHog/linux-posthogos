/*
 * PosthogOS splash screen (LIGHT variant).
 *
 * Shown for ~1-3 seconds between SDDM/plasmalogin and the Plasma desktop
 * appearing. Plasma drives the `stage` property 1→5 as boot progresses:
 *
 *   1  splash appears (right after login)
 *   2  user services up (dbus, kwallet, etc.)
 *   3  kded / kwin starting
 *   4  Plasma core ready (desktop about to appear)
 *   5  Plasma fully loaded — splash fades out and dismisses
 *
 * Plasma reads this file automatically because it sits at the
 * Plasma-convention path: `<LAF>/contents/splash/Splash.qml`. No metadata,
 * no extra config — picked up whenever the parent LAF is the active theme.
 *
 * Colors match PosthogosLight.colors:
 *   bg   #eeefe9 (Window/BackgroundNormal)
 *   text #23251d (Window/ForegroundNormal)
 */
import QtQuick

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#eeefe9"

    // Plasma updates this 1→5 as boot stages complete. We re-evaluate the
    // logo + text opacity/scale animations in onStageChanged below.
    property int stage

    Image {
        id: logo
        source: "file:///usr/share/icons/hicolor/512x512/apps/posthogos.png"
        anchors.centerIn: parent
        width: 256
        height: 256
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        // Start tucked + invisible; the stage 1 transition animates these
        // up to (1.0, 1.0) and the stage 5 transition fades opacity back to 0.
        opacity: 0
        scale: 0.92

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
        }
    }

    Text {
        text: "PosthogOS"
        font.family: "Inter"
        font.pixelSize: 36
        font.weight: Font.Medium
        color: "#23251d"
        opacity: logo.opacity   // co-animate with the logo
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: logo.bottom
        anchors.topMargin: 32
    }

    onStageChanged: {
        if (stage >= 1) { logo.opacity = 1; logo.scale = 1.0 }
        if (stage >= 5) { logo.opacity = 0 }
    }
}

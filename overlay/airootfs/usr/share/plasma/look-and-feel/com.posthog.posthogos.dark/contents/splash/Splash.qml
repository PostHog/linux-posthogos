/*
 * PosthogOS splash screen (DARK variant).
 *
 * See com.posthog.posthogos/contents/splash/Splash.qml for the full
 * stage-progression docstring. This is the dark twin, with the
 * background swapped to the PosthogosDark body bg and the title text
 * swapped to the light cream foreground. Logo PNG is shared (it's a
 * multi-color logomark that reads on both bgs; the near-black corner
 * triangle blends slightly into dark bg but the orange/blue/yellow
 * triangles still carry the brand mark legibly).
 *
 * Colors:
 *   bg   #333732 (warm dark grey)
 *   text #edeef4 (PosthogosDark Window/ForegroundNormal)
 */
import QtQuick

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#333732"

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
        color: "#edeef4"
        opacity: logo.opacity
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: logo.bottom
        anchors.topMargin: 32
    }

    onStageChanged: {
        if (stage >= 1) { logo.opacity = 1; logo.scale = 1.0 }
        if (stage >= 5) { logo.opacity = 0 }
    }
}

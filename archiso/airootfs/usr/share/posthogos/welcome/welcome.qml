import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root

    width: 920
    height: 620
    minimumWidth: 820
    minimumHeight: 560
    visible: true
    title: "PostHogOS"
    color: "#e1d7c2"
    x: Math.round((Screen.width - width) / 2)
    y: Math.round((Screen.height - height) / 2)

    function choose(action) {
        console.log("POSTHOGOS_ACTION:" + action)
        Qt.callLater(Qt.quit)
    }

    Image {
        anchors.fill: parent
        source: "file:///usr/share/wallpapers/PostHogOS/contents/images/source-assets/keyboard_garden_bg_light.png"
        fillMode: Image.Tile
        opacity: 0.72
    }

    Image {
        source: "file:///usr/share/wallpapers/PostHogOS/contents/images/source-assets/keyboard_garden_light.png"
        width: 340
        fillMode: Image.PreserveAspectFit
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 26
        anchors.bottomMargin: 12
        opacity: 0.96
    }

    Rectangle {
        id: card

        width: 610
        height: 468
        radius: 7
        color: "#fdfdf8"
        border.color: "#bfc1b7"
        border.width: 1
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 48
        anchors.topMargin: 56

        Rectangle {
            id: titlebar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 46
            radius: 7
            color: "#e4e3d8"
            border.color: "#bfc1b7"
            border.width: 1

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 8
                color: titlebar.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                Image {
                    source: "file:///usr/share/wallpapers/PostHogOS/contents/images/source-assets/posthog-logomark.svg"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 24
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: "PostHogOS"
                    color: "#23251d"
                    font.family: "IBM Plex Sans"
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Text {
                    text: "CachyOS base. PostHog batteries included."
                    color: "#65675e"
                    font.family: "IBM Plex Sans"
                    font.pixelSize: 12
                }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titlebar.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 26
            spacing: 18

            Text {
                text: "Ready to build"
                color: "#111827"
                font.family: "IBM Plex Sans"
                font.pixelSize: 30
                font.weight: Font.Bold
                Layout.fillWidth: true
            }

            Text {
                text: "PostHog code and the dev tools are already on this image. Pick a starting point."
                color: "#4d4f46"
                wrapMode: Text.WordWrap
                font.family: "IBM Plex Sans"
                font.pixelSize: 15
                lineHeight: 1.25
                Layout.fillWidth: true
            }

            GridLayout {
                columns: 2
                columnSpacing: 12
                rowSpacing: 12
                Layout.fillWidth: true

                Repeater {
                    model: ListModel {
                        ListElement { label: "Install PostHogOS"; detail: "Launch the installer"; action: "install"; primary: true }
                        ListElement { label: "Open PostHog code"; detail: "Browse the repo"; action: "code"; primary: false }
                        ListElement { label: "Open in Cursor"; detail: "Start editing"; action: "cursor"; primary: false }
                        ListElement { label: "Terminal in repo"; detail: "Run pnpm, tests, tools"; action: "terminal"; primary: false }
                        ListElement { label: "Claude Code"; detail: "CLI in the repo"; action: "claude-code"; primary: false }
                        ListElement { label: "Codex CLI"; detail: "CLI in the repo"; action: "codex-cli"; primary: false }
                        ListElement { label: "GitHub Desktop"; detail: "Open GitHub GUI"; action: "github"; primary: false }
                        ListElement { label: "Docker Desktop"; detail: "Start Docker"; action: "docker"; primary: false }
                    }

                    delegate: Button {
                        id: actionButton

                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        hoverEnabled: true
                        focusPolicy: Qt.StrongFocus
                        onClicked: root.choose(action)

                        background: Rectangle {
                            radius: 6
                            color: primary ? (actionButton.hovered ? "#f4ad32" : "#eb9d2a") : (actionButton.hovered ? "#fff2d8" : "#fdfdf8")
                            border.color: actionButton.activeFocus ? "#f54e00" : (primary ? "#9f6a14" : "#c9bca5")
                            border.width: actionButton.activeFocus ? 2 : 1
                        }

                        contentItem: ColumnLayout {
                            spacing: 1

                            Text {
                                text: label
                                color: primary ? "#111827" : "#23251d"
                                font.family: "IBM Plex Sans"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: detail
                                color: primary ? "#3b2d13" : "#65675e"
                                font.family: "IBM Plex Sans"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "/opt/posthogos/code/posthog"
                    color: "#65675e"
                    font.family: "IBM Plex Mono"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Button {
                    text: "Docs"
                    onClicked: root.choose("docs")
                }
            }
        }
    }
}

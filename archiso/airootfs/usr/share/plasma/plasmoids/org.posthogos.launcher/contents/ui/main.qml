import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    id: root

    function launch(action) {
        runner.run("/usr/local/bin/posthogos-welcome --action " + action)
        plasmoid.expanded = false
    }

    function matches(label, detail, keywords) {
        var needle = searchField.text.toLowerCase().trim()
        if (needle.length === 0) {
            return true
        }

        return (label + " " + detail + " " + keywords).toLowerCase().indexOf(needle) !== -1
    }

    Plasma5Support.DataSource {
        id: runner

        engine: "executable"
        connectedSources: []

        function run(command) {
            connectSource(command)
        }

        onNewData: function(sourceName) {
            disconnectSource(sourceName)
        }
    }

    component LauncherButton: Controls.Button {
        id: launcherButton

        property string labelText
        property string detailText
        property string actionName
        property string iconName
        property string keywords
        property bool primaryAction: false
        property bool matched: root.matches(labelText, detailText, keywords)

        visible: true
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        onClicked: root.launch(actionName)

        background: Rectangle {
            radius: 6
            color: primaryAction ? (launcherButton.hovered ? "#f4ad32" : "#eb9d2a") : (launcherButton.hovered ? "#fff2d8" : "#fdfdf8")
            border.color: launcherButton.activeFocus ? "#f54e00" : (primaryAction ? "#9f6a14" : "#c9bca5")
            border.width: launcherButton.activeFocus ? 2 : 1
        }

        contentItem: RowLayout {
            spacing: 10

            Kirigami.Icon {
                source: launcherButton.iconName
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: launcherButton.labelText
                    color: launcherButton.primaryAction ? "#111827" : "#23251d"
                    font.family: "IBM Plex Sans"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: launcherButton.detailText
                    color: launcherButton.primaryAction ? "#3b2d13" : "#65675e"
                    font.family: "IBM Plex Sans"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }

    compactRepresentation: Item {
        implicitWidth: 44
        implicitHeight: 44

        Rectangle {
            anchors.fill: parent
            color: mouseArea.containsMouse ? "#f3d49c" : "transparent"
            radius: 3
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 30
            height: 30
            source: "posthogos"
        }

        MouseArea {
            id: mouseArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: plasmoid.expanded = !plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: 600
        Layout.preferredHeight: 430
        implicitWidth: 600
        implicitHeight: 430

        Rectangle {
            anchors.fill: parent
            color: "#fdfdf8"
            radius: 7
            border.color: "#bfc1b7"
            border.width: 1

            Image {
                anchors.fill: parent
                source: "file:///usr/share/wallpapers/PostHogOS/contents/images/source-assets/keyboard_garden_bg_light.png"
                fillMode: Image.Tile
                opacity: 0.22
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 6
                color: "#e4e3d8"
                border.color: "#bfc1b7"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Image {
                        source: "file:///usr/share/wallpapers/PostHogOS/contents/images/source-assets/posthog-logomark.svg"
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 26
                        fillMode: Image.PreserveAspectFit
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: "PostHogOS"
                            color: "#23251d"
                            font.family: "IBM Plex Sans"
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "CachyOS base. PostHog batteries included."
                            color: "#65675e"
                            font.family: "IBM Plex Sans"
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Controls.TextField {
                id: searchField

                Layout.fillWidth: true
                Layout.preferredHeight: 38
                placeholderText: "Search PostHogOS"
                color: "#23251d"
                selectedTextColor: "#23251d"
                selectionColor: "#f3d49c"
                font.family: "IBM Plex Sans"
                font.pixelSize: 14
                leftPadding: 14
                rightPadding: 14

                background: Rectangle {
                    color: "#fdfdf8"
                    radius: 6
                    border.color: searchField.activeFocus ? "#f54e00" : "#bfc1b7"
                    border.width: searchField.activeFocus ? 2 : 1
                }
            }

            GridLayout {
                columns: 2
                columnSpacing: 10
                rowSpacing: 8
                Layout.fillWidth: true
                Layout.fillHeight: true

                LauncherButton { labelText: "PostHogOS welcome"; detailText: "Native launchpad"; actionName: "welcome"; iconName: "posthogos-welcome"; primaryAction: true; keywords: "home launchpad start" }
                LauncherButton { labelText: "Install PostHogOS"; detailText: "Launch installer"; actionName: "install"; iconName: "posthogos"; keywords: "calamares setup install" }
                LauncherButton { labelText: "PostHog code"; detailText: "Browse repo"; actionName: "code"; iconName: "posthogos"; keywords: "source repository dolphin" }
                LauncherButton { labelText: "Open in Cursor"; detailText: "Start editing"; actionName: "cursor"; iconName: "posthogos-cursor"; keywords: "ide editor" }
                LauncherButton { labelText: "Claude Code"; detailText: "CLI in repo"; actionName: "claude-code"; iconName: "posthogos-claude-code"; keywords: "terminal ai cli" }
                LauncherButton { labelText: "Codex CLI"; detailText: "CLI in repo"; actionName: "codex-cli"; iconName: "posthogos-codex"; keywords: "terminal ai cli" }
                LauncherButton { labelText: "GitHub Desktop"; detailText: "Open Git GUI"; actionName: "github"; iconName: "posthogos-github"; keywords: "git version control" }
                LauncherButton { labelText: "Docker Desktop"; detailText: "Start Docker"; actionName: "docker"; iconName: "posthogos-docker"; keywords: "containers compose" }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "/opt/posthogos/code/posthog"
                    color: "#65675e"
                    font.family: "IBM Plex Mono"
                    font.pixelSize: 12
                    elide: Text.ElideLeft
                    Layout.fillWidth: true
                }

                Controls.Button {
                    text: "Docs"
                    onClicked: root.launch("docs")
                }
            }
        }
    }
}

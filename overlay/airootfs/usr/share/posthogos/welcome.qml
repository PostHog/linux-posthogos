/*
 * PosthogOS Welcome app — a friendly first-boot landing page with
 * quick-action buttons for the things a new user actually wants to do.
 *
 * Pure QtQuick 2 / QML. Run via `qml6` (qt6-declarative). No compilation
 * step — the wrapper script at /usr/local/bin/posthogos-welcome just
 * `exec qml6 /usr/share/posthogos/welcome.qml` and inspects the exit
 * code on quit to launch any follow-up action (e.g. Calamares).
 *
 * Exit codes:
 *   0   normal close
 *   10  "Install to disk" — wrapper launches Calamares
 *   11  "Open terminal"   — wrapper launches Ghostty
 *   12  "Install dev toolkit" — wrapper launches posthogos-toolkit-install
 *        in Ghostty. Skip-categories are persisted via Settings.toolkitSkip
 *        and read by the wrapper to assemble --skip=... before launching.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtCore

ApplicationWindow {
    id: root
    width: 760
    height: 680
    minimumWidth: 640
    minimumHeight: 560
    visible: true
    title: "Welcome to PosthogOS"
    color: "#EEEFE9"
    // Taskbar / launcher / titlebar icon comes from the .desktop file's
    // Icon= field (posthogos-welcome → /usr/share/icons/hicolor/<size>/apps/
    // posthogos-welcome.png, generated in scripts/build-assets.sh from the
    // Professor Hog asset). ApplicationWindow has no `icon` property in
    // Qt6 QML — assigning one made qml6 exit 2 silently before any window
    // could draw.

    // Brand palette
    readonly property color brandText:      "#151515"
    readonly property color brandTextMuted: "#666666"
    readonly property color brandOrange:    "#F9BD2B"
    readonly property color brandRed:       "#F54E00"
    readonly property color brandBlue:      "#1D4AFF"
    readonly property color cardBg:         "#FFFFFF"
    readonly property color cardBorder:     "#E5E7E0"

    // Persistent prefs via Qt6 QtCore.Settings — auto-writes to
    // ~/.config/PostHog/PosthogOS-Welcome.conf. The shell wrapper reads
    // this same file to decide whether to skip on next autostart.
    Settings {
        id: prefs
        category: "Startup"
        property bool showOnStartup: true
        property string toolkitSkip: ""
        property bool isLiveIso: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 36
        spacing: 18

        // --- Header ------------------------------------------------------
        Image {
            source: "file:///usr/share/icons/hicolor/512x512/apps/posthogos.png"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 96
            Layout.preferredWidth: 96
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }

        Text {
            text: "Welcome to PosthogOS"
            font.pixelSize: 30
            font.weight: Font.Bold
            color: root.brandText
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "A CachyOS-based desktop, PostHog-branded."
            font.pixelSize: 14
            color: root.brandTextMuted
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 8
        }

        // --- Action grid -------------------------------------------------
        GridLayout {
            columns: 2
            rowSpacing: 12
            columnSpacing: 12
            Layout.fillWidth: true

            // Each tile is a clickable card.
            component ActionTile: Rectangle {
                id: tile
                property string label: ""
                property string description: ""
                property string accent: root.brandOrange
                signal clicked()

                Layout.fillWidth: true
                Layout.preferredHeight: 84
                color: cardBg
                radius: 10
                border.color: ma.containsMouse ? accent : root.cardBorder
                border.width: 1

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.clicked()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 2
                    Text {
                        text: tile.label
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: root.brandText
                    }
                    Text {
                        text: tile.description
                        font.pixelSize: 12
                        color: root.brandTextMuted
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            ActionTile {
                Layout.columnSpan: 2
                label:       prefs.isLiveIso ? "Install to disk"                       : "Install dev toolkit"
                description: prefs.isLiveIso ? "Run the Calamares installer"           : "AI CLIs and tools"
                accent:      prefs.isLiveIso ? root.brandOrange                        : root.brandRed
                onClicked:   prefs.isLiveIso ? Qt.exit(10)                             : toolkitDialog.open()
            }

            ActionTile {
                label: "Open terminal"
                description: "Launch Ghostty"
                accent: root.brandBlue
                onClicked: Qt.exit(11)
            }

            ActionTile {
                label: "Install docs"
                description: "wiki.cachyos.org/installation"
                accent: root.brandBlue
                onClicked: Qt.openUrlExternally("https://wiki.cachyos.org/installation/installation/")
            }

            ActionTile {
                label: "Source code"
                description: "github.com/posthog/linux-posthogos"
                accent: root.brandOrange
                onClicked: Qt.openUrlExternally("https://github.com/posthog/linux-posthogos")
            }
        }

        // ── Dev toolkit category picker ──────────────────────────────────
        // Modal dialog opened by the "Install dev toolkit" button
        Dialog {
            id: toolkitDialog
            anchors.centerIn: parent
            modal: true
            width: 520
            title: "Install dev toolkit"

            footer: DialogButtonBox {
                Button {
                    text: "Install"
                    DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                    background: Rectangle {
                        color: parent.down ? Qt.darker(root.brandRed, 1.2) : root.brandRed
                        radius: 6
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#FFFFFF"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 18
                        rightPadding: 18
                    }
                }
                Button {
                    text: "Cancel"
                    DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                }
            }

            onAccepted: {
                // Build the skip list from any unchecked categories.
                var skip = []
                if (!cbAi.checked)         skip.push("ai")
                if (!cbDev.checked)        skip.push("dev")
                if (!cbContainers.checked) skip.push("containers")
                if (!cbExtras.checked)     skip.push("extras")
                prefs.toolkitSkip = skip.join(",")
                Qt.exit(12)
            }

            contentItem: ColumnLayout {
                spacing: 10
                Text {
                    text: "Pick what to install. The installer runs in a terminal so you can watch the output."
                    wrapMode: Text.WordWrap
                    color: root.brandTextMuted
                    font.pixelSize: 12
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                }

                CheckBox {
                    id: cbAi
                    text: "AI CLIs"
                    checked: true
                }
                CheckBox {
                    id: cbDev
                    text: "Modern Unix tools"
                    checked: true
                }
                CheckBox {
                    id: cbContainers
                    text: "Containers"
                    checked: true
                }
                CheckBox {
                    id: cbExtras
                    text: "Extras"
                    checked: true
                }

                Text {
                    text: "You'll be prompted for your password."
                    wrapMode: Text.WordWrap
                    color: root.brandTextMuted
                    font.pixelSize: 11
                    font.italic: true
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                }
            }
        }

        Item { Layout.fillHeight: true }   // pushes footer to the bottom

        // --- Footer ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true

            CheckBox {
                text: "Show on next startup"
                checked: prefs.showOnStartup
                onCheckedChanged: prefs.showOnStartup = checked
                contentItem: Text {
                    text: parent.text
                    color: root.brandTextMuted
                    font.pixelSize: 13
                    leftPadding: parent.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "Close"
                onClicked: Qt.quit()
                background: Rectangle {
                    color: parent.down ? Qt.darker(root.brandRed, 1.2) : root.brandRed
                    radius: 6
                }
                contentItem: Text {
                    text: parent.text
                    color: "#FFFFFF"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 18
                    rightPadding: 18
                }
            }
        }
    }
}

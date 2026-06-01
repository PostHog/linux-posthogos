/*
 * PosthogOS Welcome app: a friendly first-boot landing page with
 * quick-action buttons for the things a new user actually wants to do.
 *
 * Pure QtQuick 2 / QML. Run via `qml6` (qt6-declarative). No compilation
 * step. The wrapper script at /usr/local/bin/posthogos-welcome just
 * `exec qml6 /usr/share/posthogos/welcome.qml` and inspects the exit
 * code on quit to launch any follow-up action (e.g. Calamares).
 *
 * Exit codes:
 *   0   normal close
 *   10  "Install to disk":     wrapper launches Calamares
 *   12  "Install dev toolkit": wrapper launches posthogos-toolkit-install
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
    height: 600
    minimumWidth: 640
    minimumHeight: 520
    visible: true
    title: "Welcome to PosthogOS"
    color: "#EEEFE9"
    // Window icon comes from the .desktop file's Icon= field, not from
    // QML. Qt6's ApplicationWindow has no `icon` property; setting one
    // made qml6 exit 2 silently.

    // Brand palette
    readonly property color brandText:      "#151515"
    readonly property color brandTextMuted: "#666666"
    readonly property color brandOrange:    "#F9BD2B"
    readonly property color brandRed:       "#F54E00"
    readonly property color brandBlue:      "#1D4AFF"
    readonly property color cardBg:         "#FFFFFF"
    readonly property color cardBorder:     "#E5E7E0"

    // Persistent prefs via Qt6 QtCore.Settings. The path is derived from the
    // launcher's organizationName + applicationName, so it's
    // ~/.config/PostHog/posthogos-welcome.conf (lowercase). The shell wrapper
    // reads/writes this SAME file — isLiveIso (live-vs-installed hero tile)
    // and showOnStartup (autostart skip) — so the casing must match exactly.
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

        // --- Hero tile (primary CTA) -------------------------------------
        // Same component as before but standalone (not inside a 2-col grid)
        // so it can size itself to full width without sibling pressure.
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
            label:       prefs.isLiveIso ? "Install to disk"                       : "Install dev toolkit"
            description: prefs.isLiveIso ? "Run the Calamares installer"           : "AI CLIs, modern Unix tools, containers, version managers (opt-in)"
            accent:      prefs.isLiveIso ? root.brandOrange                        : root.brandRed
            onClicked:   prefs.isLiveIso ? Qt.exit(10)                             : toolkitDialog.open()
        }

        // --- Section grid: PostHog + CachyOS links -----------------------
        // Two columns, each a labelled section of compact buttons. Mirrors
        // the layout style of CachyOS's stock Welcome window but with our
        // own taxonomy.
        component SectionHeader: Text {
            Layout.fillWidth: true
            font.pixelSize: 11
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: root.brandTextMuted
            Layout.topMargin: 6
        }

        // Compact label-only button. Smaller than ActionTile, no
        // description, used for the link sections below.
        component LinkButton: Rectangle {
            id: lbtn
            property string label: ""
            property string url: ""
            property string accent: root.brandBlue
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: cardBg
            radius: 6
            border.color: lma.containsMouse ? accent : root.cardBorder
            border.width: 1

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                text: lbtn.label
                font.pixelSize: 13
                color: lma.containsMouse ? lbtn.accent : root.brandText
            }
            // External-link glyph on the right hints these are web links.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 12
                text: "↗"
                font.pixelSize: 12
                color: root.brandTextMuted
                visible: lbtn.url.length > 0
            }

            MouseArea {
                id: lma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (lbtn.url) Qt.openUrlExternally(lbtn.url)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // --- PostHog column ------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                SectionHeader { text: "PostHog" }
                LinkButton {
                    label: "Docs"
                    url: "https://posthog.com/docs"
                    accent: root.brandBlue
                }
                LinkButton {
                    label: "Website"
                    url: "https://posthog.com"
                    accent: root.brandBlue
                }
                LinkButton {
                    label: "Blog"
                    url: "https://posthog.com/blog"
                    accent: root.brandBlue
                }
            }

            // --- CachyOS column ------------------------------------------
            // PosthogOS is a CachyOS spin; users who want to understand
            // the underlying system / get install help / ask base-OS
            // questions need upstream's resources, not posthog.com.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                SectionHeader { text: "CachyOS" }
                LinkButton {
                    label: "Wiki"
                    url: "https://wiki.cachyos.org"
                    accent: root.brandOrange
                }
                LinkButton {
                    label: "Install guide"
                    url: "https://wiki.cachyos.org/installation/installation/"
                    accent: root.brandOrange
                }
                LinkButton {
                    label: "Forums"
                    url: "https://discuss.cachyos.org/"
                    accent: root.brandOrange
                }
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
                    text: "zsh + pure prompt + modern Unix tools"
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
        // PosthogOS-project links sit on the LEFT as quiet text chips
        // (Source / Issues / Releases), matching CachyOS Welcome's social-
        // icon row position but using plain-text instead of brand-bundled
        // SVGs (we don't ship icon assets for GitHub etc., and unicode
        // emoji look unprofessional in Plasma chrome).
        component FooterLink: Text {
            id: flink
            property string url: ""
            color: fma.containsMouse ? root.brandBlue : root.brandTextMuted
            font.pixelSize: 12
            font.underline: fma.containsMouse
            HoverHandler { id: fma; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: if (flink.url) Qt.openUrlExternally(flink.url)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            FooterLink {
                text: "Source"
                url: "https://github.com/posthog/linux-posthogos"
            }
            FooterLink {
                text: "Issues"
                url: "https://github.com/posthog/linux-posthogos/issues"
            }
            FooterLink {
                text: "Releases"
                url: "https://github.com/posthog/linux-posthogos/releases"
            }

            Item { Layout.fillWidth: true }

            CheckBox {
                text: "Show on next startup"
                checked: prefs.showOnStartup
                onCheckedChanged: prefs.showOnStartup = checked
                contentItem: Text {
                    text: parent.text
                    color: root.brandTextMuted
                    font.pixelSize: 12
                    leftPadding: parent.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

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

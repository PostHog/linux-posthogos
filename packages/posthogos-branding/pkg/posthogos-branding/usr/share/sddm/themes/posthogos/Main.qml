/*
 * PosthogOS SDDM login theme.
 *
 * Minimal: blurred Keyboard Garden background, centered login card with
 * PostHog logomark, username/password fields, session selector + power
 * controls in the bottom bar.
 *
 * Reads accent / font / paths from theme.conf via `config` global.
 */

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.color || "#151515"

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    TextConstants { id: textConstants }

    // ---- Background -----------------------------------------------------
    Image {
        anchors.fill: parent
        source: config.background || ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        visible: source != ""
    }

    // Darken overlay so the card has contrast regardless of wallpaper.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.45
    }

    // ---- SDDM callbacks -------------------------------------------------
    Connections {
        target: sddm
        function onLoginSucceeded() {
            errorMessage.color = "#1D4AFF"
            errorMessage.text = textConstants.loginSucceeded
        }
        function onLoginFailed() {
            errorMessage.color = config.accent || "#DC2626"
            errorMessage.text = textConstants.loginFailed
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
    }

    function attemptLogin() {
        sddm.login(userField.currentText, passwordField.text, sessionField.currentIndex)
    }

    // ---- Centered login card --------------------------------------------
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 380
        height: 460
        color: config.cardBackground || "#1A1A1A"
        radius: 16
        border.color: config.cardBorder || "#2C2C2C"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 14

            Image {
                source: "logo.png"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 72
                fillMode: Image.PreserveAspectFit
            }

            Text {
                text: "PosthogOS"
                color: config.foreground || "#EEEFE9"
                font.pixelSize: 22
                font.family: config.font || "Inter"
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 8
            }

            ComboBox {
                id: userField
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
                Layout.fillWidth: true
                font.family: config.font || "Inter"
            }

            TextField {
                id: passwordField
                placeholderText: textConstants.password
                echoMode: TextInput.Password
                Layout.fillWidth: true
                font.family: config.font || "Inter"
                Keys.onReturnPressed: attemptLogin()
                Keys.onEnterPressed:  attemptLogin()
            }

            Button {
                id: loginButton
                text: textConstants.login
                Layout.fillWidth: true
                onClicked: attemptLogin()
                font.family: config.font || "Inter"
                background: Rectangle {
                    color: loginButton.down
                        ? Qt.darker(config.accent || "#EB9D2A", 1.2)
                        : (config.accent || "#EB9D2A")
                    radius: 6
                }
                contentItem: Text {
                    text: loginButton.text
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: loginButton.font
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                id: errorMessage
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: config.accent || "#DC2626"
                font.pixelSize: 12
                font.family: config.font || "Inter"
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- Bottom bar: session selector + power controls ------------------
    RowLayout {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 12

        ComboBox {
            id: sessionField
            model: sessionModel
            textRole: "name"
            currentIndex: sessionModel.lastIndex
            Layout.preferredWidth: 220
            font.family: config.font || "Inter"
        }

        Item { Layout.fillWidth: true }

        Button { text: textConstants.suspend;  onClicked: sddm.suspend();   visible: sddm.canSuspend }
        Button { text: textConstants.reboot;   onClicked: sddm.reboot() }
        Button { text: textConstants.shutdown; onClicked: sddm.powerOff() }
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}

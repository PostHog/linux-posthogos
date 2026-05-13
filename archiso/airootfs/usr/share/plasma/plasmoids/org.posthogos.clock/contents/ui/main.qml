import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    id: root

    property date now: new Date()

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    component ClockFace: Item {
        Layout.minimumWidth: 122
        Layout.preferredWidth: 122
        Layout.maximumWidth: 122
        Layout.minimumHeight: 48
        Layout.preferredHeight: 48
        implicitWidth: 122
        implicitHeight: 48

        Column {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 7
            spacing: -3

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: Qt.formatTime(root.now, "HH:mm")
                color: "#23251d"
                font.family: "IBM Plex Sans"
                font.pixelSize: 20
                font.weight: Font.Medium
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: Qt.formatDate(root.now, "dd MM yyyy")
                color: "#23251d"
                font.family: "IBM Plex Sans"
                font.pixelSize: 17
                font.weight: Font.Normal
            }
        }
    }

    compactRepresentation: ClockFace {}
    fullRepresentation: ClockFace {}
}

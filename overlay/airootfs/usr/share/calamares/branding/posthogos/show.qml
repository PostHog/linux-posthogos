/*
 * PosthogOS Calamares installer slideshow.
 *
 * Walks the hoglife illustration set, ~6s per frame, with cross-fade.
 * Filenames come from scripts/build-assets.sh slugify rule:
 *   "Final Destination.png" → slideshow/final-destination.png
 */
import QtQuick 2.5;
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    Timer {
        interval: 6000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            source: "slideshow/christmas-card.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }
        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 24
            text: "Welcome to PosthogOS"
            color: "#151515"
            font.pixelSize: 22
            font.weight: Font.Medium
        }
    }
    Slide { Image { source: "slideshow/vibecoding.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/gardening.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/llm-analytics.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/research-mode.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/lumberjacks.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/noir.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/looking-back.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/final-destination.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/this-is-fine.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }
    Slide { Image { source: "slideshow/zombi.png"; anchors.fill: parent; fillMode: Image.PreserveAspectFit; mipmap: true } }

    function onActivate() {}
    function onLeave() {}
}

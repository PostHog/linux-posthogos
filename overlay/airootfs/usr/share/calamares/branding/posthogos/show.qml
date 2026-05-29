/*
 * PosthogOS Calamares installer slideshow.
 *
 * Walks the hoglife illustration set, ~6s per frame, with cross-fade.
 * Filenames come from scripts/build-assets.sh slugify rule:
 *   "Final Destination.png" → slideshow/final-destination.png
 *
 * NOTE on sizing: calamares' Slide.qml defines a Slide as a *text content
 * area* — it sits at x=5%/y=20% of the window and is only 90%x70% in size.
 * An Image with `anchors.fill: parent` therefore fills that small box, not
 * the window, so screenshots render small and float in the upper area. We
 * override each Slide's geometry (x/y/width/height) to fill the whole
 * presentation and use PreserveAspectCrop so the 16:9 art covers the
 * (wider) window edge-to-edge instead of letterboxing.
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
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            source: "slideshow/christmas-card.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
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
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/vibecoding.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/gardening.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/llm-analytics.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/research-mode.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/lumberjacks.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/noir.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/looking-back.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/final-destination.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/this-is-fine.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }
    Slide { x: 0; y: 0; width: parent.width; height: parent.height; Image { source: "slideshow/zombi.png"; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; mipmap: true } }

    function onActivate() {}
    function onLeave() {}
}

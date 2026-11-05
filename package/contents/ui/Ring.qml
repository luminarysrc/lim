import QtQuick
import org.kde.kirigami as Kirigami
import "rings.js" as Rings

// One provider ring: a section per quota, each a gauge that empties as the quota is used.
Item {
    id: ring

    // [{remaining: 0..1, color: "#rrggbb"}]
    property var sections: []
    property color trackColor: Qt.alpha(Kirigami.Theme.textColor, 0.15)
    property real lineWidth: Math.max(2, width * 0.13)

    onSectionsChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const size = Math.min(width, height)
            const radius = (size - ring.lineWidth) / 2
            if (radius <= 0) return
            const arcs = Rings.drawnArcs(ring.sections.length, 8, ring.lineWidth, radius)
            // Canvas angles start at 3 o'clock; ours start at 12.
            const rad = deg => (deg - 90) * Math.PI / 180
            ctx.lineWidth = ring.lineWidth
            ctx.lineCap = ring.sections.length > 1 ? "round" : "butt"

            ring.sections.forEach((section, i) => {
                const arc = arcs[i]
                ctx.strokeStyle = ring.trackColor
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, radius, rad(arc.start), rad(arc.end), false)
                ctx.stroke()

                if (section.remaining <= 0 || arc.end <= arc.start) return
                ctx.strokeStyle = section.color
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, radius, rad(arc.start),
                        rad(arc.start + (arc.end - arc.start) * section.remaining), false)
                ctx.stroke()
            })
        }
    }
}

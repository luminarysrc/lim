import QtQuick
import org.kde.kirigami as Kirigami
import "rings.js" as Rings

// Tray icon: one ring per provider, nested (Claude outer, Codex middle, Antigravity inner),
// or the plain icon when there is nothing to draw.
MouseArea {
    id: compact

    // From Rings.ringsFor: [{id, sections: [{key, label, remaining, color}]}]
    property var rings: []
    // Ring diameter as % of the icon size, line width as % of ring diameter
    property int sizePercent: 100
    property int linePercent: 13

    readonly property real iconSize: Math.min(width, height)
    readonly property bool showIcon: rings.length === 0
    readonly property var metrics: Rings.ringMetrics(iconSize, sizePercent, linePercent, true)

    hoverEnabled: true

    Kirigami.Icon {
        anchors.fill: parent
        visible: compact.showIcon
        source: Qt.resolvedUrl("../icons/lim-symbolic.svg")
        isMask: true
        color: Kirigami.Theme.textColor
        active: compact.containsMouse
    }

    Item {
        anchors.centerIn: parent
        width: compact.metrics.diameter
        height: compact.metrics.diameter
        visible: !compact.showIcon

        Repeater {
            model: compact.rings

            delegate: Ring {
                required property var modelData
                required property int index

                anchors.centerIn: parent
                width: parent.width * (1 - index * 0.3)
                height: width
                lineWidth: compact.metrics.lineWidth
                sections: modelData.sections
            }
        }
    }
}

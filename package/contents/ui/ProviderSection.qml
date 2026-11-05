import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: section

    property string name
    property var limits: []
    property string error: ""

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        level: 4
        text: section.name
        Layout.fillWidth: true
    }

    PlasmaComponents.Label {
        visible: section.error !== ""
        text: section.error
        opacity: 0.7
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    Repeater {
        model: section.limits

        delegate: LimitBar {
            required property var modelData

            label: modelData.label
            used: modelData.used
            resetsAt: modelData.resets_at ?? 0
            Layout.fillWidth: true
        }
    }
}

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "format.js" as Format

// One limit: name, percentage, progress bar and time until reset.
ColumnLayout {
    id: bar

    property string label
    property int used: 0
    property real resetsAt: 0

    spacing: 0

    RowLayout {
        PlasmaComponents.Label {
            text: bar.label
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            text: i18nc("usage percent", "%1%", bar.used)
            color: Format.usageColor(bar.used, Kirigami.Theme)
            font.weight: Font.DemiBold
        }
    }

    PlasmaComponents.ProgressBar {
        from: 0
        to: 100
        value: bar.used
        Layout.fillWidth: true
    }

    PlasmaComponents.Label {
        visible: bar.resetsAt > 0
        text: i18n("Resets in %1", Format.timeUntil(bar.resetsAt))
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }
}

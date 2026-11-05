import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

// Popup view: one section per provider, a footer with the refresh button.
ColumnLayout {
    id: full

    property var providers: []
    property string errorText: ""
    property real updated: 0
    property bool busy: false

    signal refreshRequested()

    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    spacing: Kirigami.Units.largeSpacing

    PlasmaExtras.PlaceholderMessage {
        visible: full.errorText !== ""
        iconName: "dialog-error"
        text: i18n("Could not read usage")
        explanation: full.errorText
        Layout.fillWidth: true
    }

    Repeater {
        model: full.providers

        delegate: ProviderSection {
            required property var modelData

            name: modelData.name
            limits: modelData.limits
            error: modelData.error ?? ""
            Layout.fillWidth: true
        }
    }

    RowLayout {
        PlasmaComponents.Label {
            text: full.updated > 0
                ? i18n("Updated at %1", new Date(full.updated * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
                : ""
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            enabled: !full.busy
            onClicked: full.refreshRequested()

            PlasmaComponents.ToolTip.text: i18n("Refresh")
            PlasmaComponents.ToolTip.visible: hovered
        }
    }
}

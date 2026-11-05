import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import "rings.js" as Rings

// Settings for one provider's ring: base color, and per section visibility and color.
ColumnLayout {
    id: provider

    property string providerId
    property string name
    property string baseColor: ""   // configured value; empty = default
    property var groups: []
    property var hidden: []
    property var overrides: ({})

    signal baseColorEdited(string color)
    signal hiddenEdited(var hidden)
    signal overridesEdited(var overrides)

    readonly property string effectiveBase: baseColor || Rings.DEFAULT_COLORS[providerId] || Kirigami.Theme.textColor.toString()

    function hexOf(color) {
        return Rings.shade(color.toString(), 0)
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            color: provider.effectiveBase
            showAlphaChannel: false
            dialogTitle: i18n("%1 color", provider.name)
            onAccepted: color => provider.baseColorEdited(provider.hexOf(color))
        }

        QQC2.Button {
            text: i18n("Default")
            icon.name: "edit-undo"
            enabled: provider.baseColor !== Rings.DEFAULT_COLORS[provider.providerId]
            onClicked: provider.baseColorEdited(Rings.DEFAULT_COLORS[provider.providerId])
        }
    }

    QQC2.Label {
        visible: provider.groups.length === 0
        text: i18n("Sections appear here after the first refresh.")
        opacity: 0.7
    }

    Repeater {
        model: provider.groups

        delegate: RowLayout {
            id: row

            required property string modelData
            required property int index
            readonly property string key: Rings.sectionKey(provider.providerId, modelData)
            readonly property bool overridden: !!provider.overrides[key]

            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                text: row.modelData
                checked: !provider.hidden.includes(row.key)
                Layout.minimumWidth: Kirigami.Units.gridUnit * 9
                QQC2.ToolTip.text: i18n("Show in panel")
                QQC2.ToolTip.visible: hovered
                onToggled: provider.hiddenEdited(checked
                    ? provider.hidden.filter(key => key !== row.key)
                    : provider.hidden.concat([row.key]))
            }

            KQuickControls.ColorButton {
                color: provider.overrides[row.key] || Rings.shade(provider.effectiveBase, row.index)
                showAlphaChannel: false
                dialogTitle: i18n("%1 color", row.modelData)
                onAccepted: color => {
                    const next = Object.assign({}, provider.overrides)
                    next[row.key] = provider.hexOf(color)
                    provider.overridesEdited(next)
                }
            }

            QQC2.ToolButton {
                icon.name: "edit-undo"
                enabled: row.overridden
                QQC2.ToolTip.text: i18n("Use the shade of the %1 color", provider.name)
                QQC2.ToolTip.visible: hovered
                onClicked: {
                    const next = Object.assign({}, provider.overrides)
                    delete next[row.key]
                    provider.overridesEdited(next)
                }
            }
        }
    }
}

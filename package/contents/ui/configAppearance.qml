import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "rings.js" as Rings

KCM.SimpleKCM {
    id: page

    property int cfg_ringSize
    property int cfg_lineThickness
    property string cfg_colorClaude
    property string cfg_colorCodex
    property string cfg_colorAntigravity
    property string cfg_sectionColors
    property var cfg_hiddenSections: []
    property string cfg_knownSections

    readonly property var names: ({claude: "Claude Code", codex: "Codex", antigravity: "Antigravity"})

    function parseJson(text) {
        try {
            return JSON.parse(text || "{}")
        } catch (e) {
            return {}
        }
    }

    function colorOf(id) {
        return {claude: cfg_colorClaude, codex: cfg_colorCodex, antigravity: cfg_colorAntigravity}[id]
    }

    function setColorOf(id, color) {
        if (id === "claude") cfg_colorClaude = color
        else if (id === "codex") cfg_colorCodex = color
        else cfg_colorAntigravity = color
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Ring size:")
            from: Rings.SIZE_RANGE[0]
            to: Rings.SIZE_RANGE[1]
            stepSize: 5
            value: page.cfg_ringSize
            textFromValue: value => i18nc("percent of icon size", "%1%", value)
            valueFromText: text => parseInt(text)
            onValueModified: page.cfg_ringSize = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Line thickness:")
            from: Rings.LINE_RANGE[0]
            to: Rings.LINE_RANGE[1]
            value: page.cfg_lineThickness
            textFromValue: value => i18nc("percent of ring size", "%1%", value)
            valueFromText: text => parseInt(text)
            onValueModified: page.cfg_lineThickness = value
        }

        Repeater {
            model: Rings.PROVIDER_ORDER

            delegate: ProviderAppearance {
                required property string modelData

                Kirigami.FormData.label: page.names[modelData] + ":"
                Kirigami.FormData.labelAlignment: Qt.AlignTop
                providerId: modelData
                name: page.names[modelData]
                baseColor: page.colorOf(modelData)
                groups: page.parseJson(page.cfg_knownSections)[modelData] ?? []
                hidden: page.cfg_hiddenSections
                overrides: page.parseJson(page.cfg_sectionColors)

                onBaseColorEdited: color => page.setColorOf(modelData, color)
                onHiddenEdited: hidden => page.cfg_hiddenSections = hidden
                onOverridesEdited: overrides => page.cfg_sectionColors = JSON.stringify(overrides)
            }
        }
    }
}

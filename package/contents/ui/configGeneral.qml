import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_refreshMinutes: refreshMinutes.value
    property alias cfg_showClaude: showClaude.checked
    property alias cfg_showCodex: showCodex.checked
    property alias cfg_showAntigravity: showAntigravity.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: refreshMinutes
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 1
            to: 60
            textFromValue: value => i18np("%1 minute", "%1 minutes", value)
            valueFromText: text => parseInt(text)
        }

        QQC2.CheckBox {
            id: showClaude
            Kirigami.FormData.label: i18n("Show:")
            text: "Claude Code"
        }

        QQC2.CheckBox {
            id: showCodex
            text: "Codex"
        }

        QQC2.CheckBox {
            id: showAntigravity
            text: "Antigravity"
        }
    }
}

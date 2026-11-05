import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "rings.js" as Rings

PlasmoidItem {
    id: root

    property var providers: []
    property string errorText: ""
    property real updated: 0
    property bool busy: false

    readonly property string script: decodeURIComponent(Qt.resolvedUrl("../code/ai-limits.sh").toString().replace("file://", ""))
    readonly property var enabledProviders: [
        Plasmoid.configuration.showClaude ? "claude" : "",
        Plasmoid.configuration.showCodex ? "codex" : "",
        Plasmoid.configuration.showAntigravity ? "antigravity" : "",
    ].filter(Boolean)
    readonly property var rings: Rings.ringsFor(providers, {
        hidden: Plasmoid.configuration.hiddenSections,
        colors: {
            claude: Plasmoid.configuration.colorClaude,
            codex: Plasmoid.configuration.colorCodex,
            antigravity: Plasmoid.configuration.colorAntigravity,
        },
        overrides: parseJson(Plasmoid.configuration.sectionColors),
        textColor: Kirigami.Theme.textColor.toString(),
        scriptFailed: errorText !== "",
    })

    // Highest usage among a provider's limits, -1 when there is none.
    function peak(limits) {
        return Math.max(-1, ...limits.map(limit => limit.used))
    }

    function parseJson(text) {
        try {
            return JSON.parse(text || "{}")
        } catch (e) {
            return {}
        }
    }

    // Remember which sections exist, for the settings page.
    function rememberSections(providers) {
        const known = JSON.stringify(Rings.mergeKnownSections(parseJson(Plasmoid.configuration.knownSections), providers))
        if (known !== Plasmoid.configuration.knownSections)
            Plasmoid.configuration.knownSections = known
    }

    function refresh() {
        if (enabledProviders.length === 0) {
            providers = []
            return
        }
        busy = true
        executable.connectSource(`bash '${script}' ${enabledProviders.join(" ")}`)
    }

    onEnabledProvidersChanged: refresh()

    P5Support.DataSource {
        id: executable
        engine: "executable"

        onNewData: (source, data) => {
            disconnectSource(source)
            root.busy = false
            try {
                const result = JSON.parse(data.stdout)
                root.providers = result.providers
                root.updated = result.updated
                root.errorText = ""
                root.rememberSections(result.providers)
            } catch (e) {
                root.errorText = data.stderr || i18n("The helper script returned no data.")
            }
        }
    }

    Timer {
        interval: Plasmoid.configuration.refreshMinutes * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    toolTipMainText: i18n("AI Limits")
    toolTipSubText: providers.map(provider => {
        const usage = peak(provider.limits)
        return `${provider.name}: ${provider.error ?? (usage < 0 ? "–" : usage + "%")}`
    }).join("\n")

    compactRepresentation: CompactRepresentation {
        rings: root.rings
        sizePercent: Plasmoid.configuration.ringSize
        linePercent: Plasmoid.configuration.lineThickness
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {
        providers: root.providers
        errorText: root.errorText
        updated: root.updated
        busy: root.busy
        onRefreshRequested: root.refresh()
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]
}

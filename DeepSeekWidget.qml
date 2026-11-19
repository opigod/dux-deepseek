import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "lib/schedule.js" as Schedule
import "lib/format.js" as Format

PluginComponent {
    id: root

    layerNamespacePlugin: "deepseek"

    PluginGlobalVar {
        id: snapshotVar
        varName: "deepseekSnapshot"
        defaultValue: ({})
    }

    readonly property var snapshot: snapshotVar.value || ({})
    readonly property string provider: String(pluginData.provider || "deepseek")
    readonly property bool showOllama: pluginData.showOllama !== false
    readonly property string displayMode: String(pluginData.displayMode || "peakBalance")
    readonly property bool showProgress: pluginData.showProgress !== false
    readonly property bool offlineOnly: pluginData.offlineOnly === true
    readonly property int refreshMinutes: Math.max(1, Math.min(60, Number(pluginData.refreshMinutes ?? 5)))
    readonly property string apiKey: String(pluginData.apiKey || Quickshell.env("DEEPSEEK_API_KEY") || "").trim()
    readonly property string platformAuth: String(pluginData.platformAuth || "").trim()
    readonly property bool hasApiKey: apiKey.length > 0
    readonly property bool hasPlatformToken: platformAuth.length > 0
    readonly property bool hasSources: hasApiKey || hasPlatformToken
    readonly property string customSourceUrl: String(pluginData.customSourceUrl || "").trim()
    readonly property string pricingUrl: customSourceUrl.length > 0
        ? customSourceUrl
        : Schedule.sourceUrl(provider)

    readonly property color peakColor: pluginData.peakColor || Theme.error
    readonly property color offPeakColor: pluginData.offPeakColor || Theme.success
    readonly property color driftColor: pluginData.driftColor || Theme.warning

    readonly property real pillDotSize: Theme.spacingS
    readonly property real gaugeWidth: Theme.spacingXL * 2 + Theme.spacingS
    readonly property real gaugeThickness: Theme.spacingXXS
    readonly property real popoutBodyHeight: Math.max(Theme.spacingXL * 12, popoutHeight - Theme.spacingXL * 3)

    property double nowMs: Date.now()
    property double lastRefreshRequest: 0
    property double lastDiffAt: 0
    property bool diffVisible: false
    property int popoutTab: 0

    readonly property var peak: Schedule.snapshot(nowMs, provider)
    readonly property bool driftActive: snapshot.drift && snapshot.drift.state === "drift"
    readonly property color stateColor: driftActive
        ? driftColor
        : (peak.isPeak ? peakColor : offPeakColor)
    readonly property var balance: snapshot.balance || null
    readonly property bool hasBalance: balance !== null && balance !== undefined && isFinite(balance.total)
    readonly property string balanceText: hasBalance
        ? Format.formatMoney(balance.total, balance.currency)
        : ""
    readonly property string balanceCompact: hasBalance
        ? Format.formatCompactMoney(balance.total, balance.currency)
        : ""
    readonly property string diffText: hasBalance
        ? Format.formatSignedMoney(snapshot.diff || 0, balance.currency)
        : ""
    readonly property color diffColor: (snapshot.diff || 0) >= 0 ? Theme.success : Theme.error

    readonly property string countdownText: Schedule.formatCountdown(peak.secondsToNext)
    readonly property string peakText: displayMode === "full"
        ? (peak.isPeak ? "PEAK 2x" : "OFF-PEAK") + " · " + countdownText
        : countdownText
    readonly property bool peakTextVisible: displayMode !== "icon" && displayMode !== "balance"
    readonly property bool balanceVisible: hasBalance
        && (displayMode === "peakBalance" || displayMode === "balance")
    readonly property bool showGauge: showProgress
        && (displayMode === "peakBalance" || displayMode === "peak" || displayMode === "full")
    readonly property bool diffShowing: diffVisible && hasBalance
        && Math.abs(snapshot.diff || 0) > 0.000001
    readonly property string balanceLabel: diffShowing ? diffText : balanceText
    readonly property color balanceColor: diffShowing ? diffColor : Theme.primary
    readonly property string verticalText: hasBalance
        && (displayMode === "peakBalance" || displayMode === "balance")
        ? balanceCompact
        : Schedule.formatShortCountdown(peak.secondsToNext)

    readonly property string popoutSubtitle: {
        var parts = [];
        if (snapshot.busy === true)
            parts.push("Refreshing…");
        if (driftActive)
            parts.push("Pricing drift");
        parts.push(peak.isPeak ? "Peak 2x" : "Off-peak");
        if (hasBalance)
            parts.push(balanceText);
        parts.push(countdownText + (peak.isPeak ? " to off-peak" : " to peak"));
        return parts.join(" · ");
    }

    function requestRefresh() {
        if (!pluginService || !pluginId)
            return;
        lastRefreshRequest = Date.now();
        pluginService.setGlobalVar(pluginId, "deepseekCommand", {
            id: Date.now(),
            action: "refresh"
        });
    }

    function requestPricing() {
        if (!pluginService || !pluginId)
            return;
        pluginService.setGlobalVar(pluginId, "deepseekCommand", {
            id: Date.now(),
            action: "checkPricing"
        });
    }

    function switchProvider(name) {
        if (name !== "deepseek" && name !== "ollama")
            return;
        pluginService.savePluginData(pluginId, "provider", name);
    }

    function openSettings() {
        PluginService.pendingSettingsRevealPluginId = pluginId;
        PopoutService.openSettingsWithTab("plugins");
    }

    function openUrl(url) {
        if (url)
            Qt.openUrlExternally(url);
    }

    function maybeAutoRefresh() {
        if (!hasSources || snapshot.busy === true || offlineOnly)
            return;
        var age = Date.now() - (snapshot.updatedAt || 0);
        if (age < refreshMinutes * 60000)
            return;
        if (Date.now() - lastRefreshRequest < 60000)
            return;
        requestRefresh();
    }

    onSnapshotChanged: {
        if (snapshot && snapshot.diffAt && snapshot.diffAt !== lastDiffAt) {
            lastDiffAt = snapshot.diffAt;
            diffVisible = true;
            diffTimer.restart();
        }
    }

    onInteractionActiveChanged: {
        if (interactionActive)
            maybeAutoRefresh();
    }

    onShowOllamaChanged: {
        if (!showOllama && provider === "ollama")
            switchProvider("deepseek");
    }

    onProviderChanged: {
        if (!showOllama && provider === "ollama")
            switchProvider("deepseek");
    }

    Timer {
        id: ticker
        interval: root.interactionActive ? 1000 : 15000
        repeat: true
        running: root.surfaceLive || root.interactionActive
        triggeredOnStart: true
        onTriggered: {
            root.nowMs = Date.now();
            if (root.interactionActive)
                root.maybeAutoRefresh();
        }
    }

    Timer {
        id: diffTimer
        interval: 5000
        repeat: false
        onTriggered: root.diffVisible = false
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Rectangle {
                width: root.pillDotSize
                height: root.pillDotSize
                radius: width / 2
                color: root.stateColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                Row {
                    spacing: Theme.spacingXS

                    StyledText {
                        visible: root.peakTextVisible
                        text: root.peakText
                        font.pixelSize: root.textSize
                        font.weight: Theme.fontWeightMedium
                        color: root.stateColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        visible: root.peakTextVisible && root.balanceVisible
                        text: "·"
                        font.pixelSize: root.textSize
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        visible: root.balanceVisible
                        text: root.balanceLabel
                        font.pixelSize: root.textSize
                        font.weight: Theme.fontWeightMedium
                        color: root.balanceColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    visible: root.showGauge
                    width: root.gaugeWidth
                    height: root.gaugeThickness
                    radius: height / 2
                    color: Theme.withAlpha(Theme.surfaceText, 0.14)

                    Rectangle {
                        width: parent.width * (root.peak.progress || 0)
                        height: parent.height
                        radius: height / 2
                        color: root.stateColor
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            Rectangle {
                width: root.pillDotSize
                height: root.pillDotSize
                radius: width / 2
                color: root.stateColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.displayMode !== "icon"
                text: root.verticalText
                font.pixelSize: Theme.fontSizeXSmall
                font.weight: Theme.fontWeightMedium
                color: root.stateColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 560

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "DeepSeek"
            detailsText: root.popoutSubtitle

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    DIconButton {
                        iconName: "refresh"
                        tooltipText: "Refresh now"
                        enabled: root.snapshot.busy !== true && !root.offlineOnly
                        onClicked: root.requestRefresh()
                    }
                }
            }

            Connections {
                target: popout.parentPopout

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible) {
                        Qt.callLater(function () {
                            popoutFlickable.contentY = 0;
                        });
                    }
                }
            }

            DFlickable {
                id: popoutFlickable

                width: parent.width
                height: root.popoutBodyHeight
                contentWidth: width
                contentHeight: contentColumn.height
                clip: true

                Component.onCompleted: Qt.callLater(function () {
                    popoutFlickable.contentY = 0;
                })

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.spacingM

                    DTabBar {
                        width: parent.width
                        model: [
                            { text: "Peak", icon: "bolt" },
                            { text: "Usage", icon: "bar_chart" }
                        ]
                        currentIndex: root.popoutTab
                        onTabClicked: index => {
                            root.popoutTab = index;
                            popoutFlickable.contentY = 0;
                        }
                    }

                    Loader {
                        width: parent.width
                        sourceComponent: root.popoutTab === 0 ? peakTabComponent : usageTabComponent
                    }
                }
            }
        }
    }

    Component {
        id: peakTabComponent

        DeepSeekPeakTab {
            width: parent ? parent.width : implicitWidth
            snapshot: root.snapshot
            peak: root.peak
            provider: root.provider
            showOllama: root.showOllama
            nowMs: root.nowMs
            drift: root.snapshot.drift || ({})
            busy: root.snapshot.busy === true
            offlineOnly: root.offlineOnly
            peakColor: root.peakColor
            offPeakColor: root.offPeakColor
            driftColor: root.driftColor
            pricingUrl: root.pricingUrl
            onProviderRequested: name => root.switchProvider(name)
            onRefreshRequested: root.requestRefresh()
            onPricingRequested: root.requestPricing()
            onSettingsRequested: root.openSettings()
            onUrlRequested: url => root.openUrl(url)
        }
    }

    Component {
        id: usageTabComponent

        DeepSeekUsageTab {
            width: parent ? parent.width : implicitWidth
            snapshot: root.snapshot
            busy: root.snapshot.busy === true
            nowMs: root.nowMs
            hasApiKey: root.hasApiKey
            hasPlatformToken: root.hasPlatformToken
            offlineOnly: root.offlineOnly
            onRefreshRequested: root.requestRefresh()
            onSettingsRequested: root.openSettings()
            onUrlRequested: url => root.openUrl(url)
        }
    }

    pillRightClickAction: () => root.requestRefresh()
}
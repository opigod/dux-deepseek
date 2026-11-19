import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "lib/schedule.js" as Schedule
import "lib/format.js" as Format

Column {
    id: root

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingM

    property var snapshot: ({})
    property var peak: ({})
    property string provider: "deepseek"
    property bool showOllama: true
    property double nowMs: Date.now()
    property var drift: ({})
    property bool busy: false
    property bool offlineOnly: false
    property string pricingUrl: ""
    property color peakColor: Theme.error
    property color offPeakColor: Theme.success
    property color driftColor: Theme.warning

    readonly property real statusDotSize: Theme.spacingS + Theme.spacingXXS
    readonly property real inlineDotSize: Theme.spacingS
    readonly property real progressThickness: Theme.spacingXS + Theme.spacingXXS
    readonly property real providerRowHeight: Theme.spacingXL + Theme.spacingM + Theme.spacingXXS
    readonly property real scheduleLabelWidth: Theme.spacingXL * 2 + Theme.spacingL

    signal providerRequested(string provider)
    signal refreshRequested()
    signal pricingRequested()
    signal settingsRequested()
    signal urlRequested(string url)

    readonly property bool driftActive: drift && drift.state === "drift"
    readonly property color stateColor: driftActive
        ? driftColor
        : (peak && peak.isPeak ? peakColor : offPeakColor)
    readonly property var holiday: provider === "deepseek" ? Schedule.holidayRange(nowMs) : null

    readonly property var scheduleRows: {
        var rows = [];
        rows.push({
            label: "Local",
            value: Schedule.windowLine(nowMs, provider, "local") || "off-peak all day"
        });
        rows.push({
            label: "UTC",
            value: Schedule.windowLine(nowMs, provider, "utc") || "off-peak all day"
        });
        rows.push({
            label: "Beijing",
            value: Schedule.windowLine(nowMs, provider, "beijing") || "off-peak all day"
        });
        rows.push({
            label: "Bundled",
            value: Schedule.scheduleText(provider)
        });
        if (holiday)
            rows.push({ label: "Holiday", value: holiday.text });
        var holidayWarning = Schedule.holidayDataWarning(nowMs, provider);
        if (holidayWarning)
            rows.push({ label: "Holiday data", value: holidayWarning });
        return rows;
    }

    readonly property var providerRows: {
        var rows = [{
            key: "deepseek",
            name: Schedule.providerName("deepseek"),
            snapshot: Schedule.snapshot(nowMs, "deepseek")
        }];
        if (showOllama) {
            rows.push({
                key: "ollama",
                name: Schedule.providerName("ollama"),
                snapshot: Schedule.snapshot(nowMs, "ollama")
            });
        }
        return rows;
    }

    function providerColor(entry) {
        return entry.snapshot.isPeak ? root.peakColor : root.offPeakColor;
    }

    function providerState(entry) {
        return (entry.snapshot.isPeak ? "Peak" : "Off-peak")
            + " · " + Schedule.formatCountdown(entry.snapshot.secondsToNext);
    }

    function nextFlipText() {
        if (!peak || !peak.nextFlipAt)
            return "";
        var local = Schedule.formatHM(peak.nextFlipAt, "local");
        var utc = Schedule.formatHM(peak.nextFlipAt, "utc");
        return "Next change " + local + " local · " + utc + " UTC";
    }

    // Status card
    StyledRect {
        width: parent.width
        height: statusColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh
        border.width: Theme.outlineWidth
        border.color: Theme.withAlpha(root.stateColor, 0.35)

        Column {
            id: statusColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingXS

            Row {
                spacing: Theme.spacingS

                Rectangle {
                    width: root.statusDotSize
                    height: root.statusDotSize
                    radius: width / 2
                    color: root.stateColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.peak.isPeak ? "Peak · 2x" : "Off-peak"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: root.stateColor
                }

                StyledText {
                    text: Schedule.providerName(root.provider)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: (root.peak.isPeak ? "Off-peak in " : "Peak in ")
                    + Schedule.formatBigCountdown(root.peak.secondsToNext)
                font.pixelSize: Theme.fontSizeXXLarge
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                text: root.nextFlipText()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Rectangle {
                width: parent.width
                height: root.progressThickness
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceText, 0.12)

                Rectangle {
                    width: parent.width * (root.peak.progress || 0)
                    height: parent.height
                    radius: height / 2
                    color: root.stateColor
                }
            }
        }
    }

    // Both providers
    StyledRect {
        width: parent.width
        height: providersColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh

        Column {
            id: providersColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: "Providers"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: root.providerRows

                delegate: Rectangle {
                    width: parent.width
                    height: root.providerRowHeight
                    radius: Theme.cornerRadiusS
                    color: root.provider === modelData.key
                        ? Theme.withAlpha(Theme.primary, 0.14)
                        : "transparent"
                    border.width: Theme.outlineWidth
                    border.color: root.provider === modelData.key
                        ? Theme.withAlpha(Theme.primary, 0.35)
                        : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        Rectangle {
                            width: root.inlineDotSize
                            height: root.inlineDotSize
                            radius: width / 2
                            color: root.providerColor(modelData)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.name
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.providerState(modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.providerColor(modelData)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.providerRequested(modelData.key)
                    }
                }
            }
        }
    }

    // Schedule
    StyledRect {
        width: parent.width
        height: scheduleColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh

        Column {
            id: scheduleColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: "Peak windows"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: root.scheduleRows

                delegate: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: root.scheduleLabelWidth
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        width: parent.width - root.scheduleLabelWidth - parent.spacing
                        text: modelData.value
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                width: parent.width
                text: "Off-peak applies on weekends"
                    + (root.provider === "deepseek" ? " and Chinese public holidays" : "")
                    + ". Rates are half of peak where the provider bills that way."
                font.pixelSize: Theme.fontSizeXSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    // Pricing drift / check status
    StyledRect {
        width: parent.width
        height: driftColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: root.driftActive
            ? Theme.withAlpha(root.driftColor, 0.12)
            : Theme.surfaceContainerHigh
        border.width: root.driftActive ? Theme.outlineWidth : 0
        border.color: Theme.withAlpha(root.driftColor, 0.5)

        Column {
            id: driftColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingXS

            StyledText {
                text: root.driftActive
                    ? "Pricing page changed"
                    : (root.drift && root.drift.state === "ok"
                        ? "Pricing matches the bundled schedule"
                        : "Pricing check not available yet")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: root.driftActive ? root.driftColor : Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: {
                    if (root.driftActive) {
                        var published = (root.drift.found || []).join(", ") || "unknown";
                        var bundled = (root.drift.expected || []).join(", ") || "unknown";
                        return "Published: " + published + " UTC\nBundled: " + bundled + " UTC";
                    }
                    if (root.drift && root.drift.error)
                        return root.drift.error;
                    return "Checked " + Format.relativeTime(root.nowMs, root.drift ? root.drift.checkedAt : 0);
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                visible: root.driftActive
                text: "Open the pricing page before trusting the countdown."
                font.pixelSize: Theme.fontSizeXSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    // Actions
    Row {
        width: parent.width
        spacing: Theme.spacingS

        DButton {
            width: (parent.width - parent.spacing) / 2
            maximumWidth: width
            text: "Refresh"
            iconName: "refresh"
            variant: "tonal"
            busy: root.busy
            enabled: !root.busy && !root.offlineOnly
            onClicked: root.refreshRequested()
        }

        DButton {
            width: (parent.width - parent.spacing) / 2
            maximumWidth: width
            text: "Check pricing"
            iconName: "fact_check"
            variant: "text"
            enabled: !root.offlineOnly
            onClicked: root.pricingRequested()
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        DButton {
            width: (parent.width - parent.spacing) / 2
            maximumWidth: width
            text: "Pricing page"
            iconName: "open_in_new"
            variant: "text"
            onClicked: root.urlRequested(root.pricingUrl || Schedule.sourceUrl(root.provider))
        }

        DButton {
            width: (parent.width - parent.spacing) / 2
            maximumWidth: width
            text: "Settings"
            iconName: "settings"
            variant: "text"
            onClicked: root.settingsRequested()
        }
    }

    StyledText {
        width: parent.width
        text: "Data updated " + Format.relativeTime(root.nowMs, root.snapshot.updatedAt || 0)
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.surfaceVariantText
        horizontalAlignment: Text.AlignHCenter
    }
}

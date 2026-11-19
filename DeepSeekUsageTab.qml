import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "lib/format.js" as Format

Column {
    id: root

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingM

    property var snapshot: ({})
    property bool busy: false
    property double nowMs: Date.now()
    property bool hasApiKey: false
    property bool hasPlatformToken: false
    property bool offlineOnly: false
    property color chartInputColor: Theme.primary
    property color chartOutputColor: Theme.tertiary

    readonly property real sparklineHeight: Theme.spacingXL * 2
    readonly property real chartHeight: Theme.spacingXL * 6
    readonly property real legendWidth: Theme.spacingS + Theme.spacingXXS
    readonly property real legendHeight: Theme.spacingS
    readonly property real tightSpacing: Math.round(Theme.spacingXXS / 2)
    readonly property real historyMonthWidth: Theme.spacingXL * 3 + Theme.spacingS
    readonly property real historyValueWidth: Theme.spacingXL * 2 + Theme.spacingM

    signal refreshRequested()
    signal settingsRequested()
    signal urlRequested(string url)

    readonly property var balance: snapshot.balance || null
    readonly property var platform: snapshot.platform || null
    readonly property var summary: platform ? platform.summary : null
    readonly property var current: platform ? platform.current : null
    readonly property var daily: platform && platform.daily ? platform.daily : []
    readonly property var months: platform && platform.months ? platform.months : []
    readonly property var trends: snapshot.trends || ({ day: null, month: null, sparkline: [] })
    readonly property bool hasBalance: balance !== null && balance !== undefined && isFinite(balance.total)
    readonly property bool authExpired: platform !== null && platform.expired === true
    readonly property bool noCredentials: !hasApiKey && !hasPlatformToken
    // The official balance and the platform wallet can disagree (for example a
    // USD API balance with a CNY platform wallet). Never format platform costs
    // with the balance currency or vice versa.
    readonly property string balanceCurrency: balance && balance.currency
        ? balance.currency
        : "CNY"
    readonly property string platformCurrency: platform && platform.currency
        ? platform.currency
        : (summary && summary.currency ? summary.currency : balanceCurrency)
    readonly property string monthTitle: current
        ? Format.monthLabel(current.year, current.month)
        : "This month"
    readonly property real tokenTotal: current ? (current.input || 0) + (current.output || 0) : 0

    readonly property var monthMetrics: [
        {
            label: "Input",
            value: current ? Format.formatTokens(current.input) : "—",
            color: Theme.primary
        },
        {
            label: "Output",
            value: current ? Format.formatTokens(current.output) : "—",
            color: Theme.tertiary
        },
        {
            label: "Cost",
            value: current && current.cost !== null && current.cost !== undefined
                ? Format.formatMoney(current.cost, root.platformCurrency)
                : "—",
            color: Theme.warning
        },
        {
            label: "Tokens",
            value: current ? Format.formatTokens(root.tokenTotal) : "—",
            color: Theme.surfaceText
        }
    ]

    function trendValue(trend) {
        return trend && isFinite(trend.value)
            ? Format.formatSignedMoney(trend.value, root.balanceCurrency)
            : "—";
    }

    function trendColor(trend) {
        if (!trend || !isFinite(trend.value))
            return Theme.surfaceVariantText;
        return trend.value >= 0 ? Theme.success : Theme.error;
    }

    // No credentials at all
    StyledRect {
        width: parent.width
        height: setupColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.withAlpha(Theme.primary, 0.08)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.3)
        visible: root.noCredentials

        Column {
            id: setupColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: "Set up your DeepSeek account"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.primary
            }

            StyledText {
                width: parent.width
                text: "Add an API key for balance, and optionally a platform session token for monthly tokens, cost and the daily chart."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            DButton {
                text: "Open settings"
                iconName: "settings"
                variant: "tonal"
                onClicked: root.settingsRequested()
            }
        }
    }

    // Balance
    StyledRect {
        width: parent.width
        height: balanceColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh
        visible: root.hasBalance

        Column {
            id: balanceColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: root.hasBalance ? Format.formatMoney(root.balance.total, root.balanceCurrency) : "—"
                font.pixelSize: Theme.fontSizeXXLarge
                font.weight: Theme.fontWeightMedium
                color: Theme.primary
            }

            StyledText {
                text: "Total balance"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM

                Repeater {
                    model: [
                        {
                            label: "Topped up",
                            value: root.hasBalance ? Format.formatMoney(root.balance.toppedUp, root.balanceCurrency) : "—"
                        },
                        {
                            label: "Granted",
                            value: root.hasBalance ? Format.formatMoney(root.balance.granted, root.balanceCurrency) : "—"
                        },
                        {
                            label: "Token estimate",
                            value: root.hasBalance && root.balance.tokenEstimation > 0
                                ? Format.formatTokens(root.balance.tokenEstimation)
                                : "—"
                        }
                    ]

                    delegate: Column {
                        width: (parent.width - parent.spacing * 2) / 3
                        spacing: root.tightSpacing

                        StyledText {
                            width: parent.width
                            text: modelData.value
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // Balance trend
    StyledRect {
        width: parent.width
        height: trendColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh
        visible: root.hasBalance

        Column {
            id: trendColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingL

                Column {
                    width: (parent.width - parent.spacing) / 2
                    spacing: root.tightSpacing

                    StyledText {
                        text: root.trendValue(root.trends.day)
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: root.trendColor(root.trends.day)
                    }

                    StyledText {
                        text: "24h change"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }

                Column {
                    width: (parent.width - parent.spacing) / 2
                    spacing: root.tightSpacing

                    StyledText {
                        text: root.trendValue(root.trends.month)
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: root.trendColor(root.trends.month)
                    }

                    StyledText {
                        text: "This month"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            // Small inline balance sparkline
            Item {
                width: parent.width
                height: root.sparklineHeight
                visible: root.trends.sparkline && root.trends.sparkline.length > 1

                Canvas {
                    id: sparkCanvas
                    anchors.fill: parent
                    antialiasing: true

                    property var values: root.trends.sparkline || []
                    property color lineColor: Theme.primary

                    onValuesChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onLineColorChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        var data = values;
                        if (!data || data.length < 2)
                            return;

                        var min = data[0];
                        var max = data[0];
                        for (var i = 1; i < data.length; i++) {
                            if (data[i] < min) min = data[i];
                            if (data[i] > max) max = data[i];
                        }
                        var span = Math.max(0.000001, max - min);
                        var step = width / (data.length - 1);
                        var inset = Theme.spacingXS;
                        var top = inset;
                        var bottom = height - inset;

                        ctx.beginPath();
                        for (var p = 0; p < data.length; p++) {
                            var x = p * step;
                            var y = bottom - ((data[p] - min) / span) * (bottom - top);
                            if (p === 0)
                                ctx.moveTo(x, y);
                            else
                                ctx.lineTo(x, y);
                        }
                        ctx.strokeStyle = lineColor.toString();
                        ctx.lineWidth = Theme.outlineWidthFocused;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        ctx.stroke();
                    }
                }
            }
        }
    }

    // Platform setup / expired state
    StyledRect {
        width: parent.width
        height: platformColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: root.authExpired
            ? Theme.withAlpha(Theme.error, 0.12)
            : Theme.withAlpha(Theme.primary, 0.08)
        border.width: 1
        border.color: root.authExpired
            ? Theme.withAlpha(Theme.error, 0.4)
            : Theme.withAlpha(Theme.primary, 0.25)
        visible: !root.noCredentials && (!root.hasPlatformToken || root.authExpired)

        Column {
            id: platformColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: root.authExpired ? "Platform session expired" : "Platform token not set"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: root.authExpired ? Theme.error : Theme.primary
            }

            StyledText {
                width: parent.width
                text: root.authExpired
                    ? "Paste a new authorization header or cookie in settings to restore monthly tokens, cost and the daily chart."
                    : "Monthly token usage, cost and the daily chart need a session token from platform.deepseek.com. Open Usage, inspect get_user_summary, and copy the authorization header."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: Theme.spacingS

                DButton {
                    text: "Open settings"
                    iconName: "settings"
                    variant: "tonal"
                    onClicked: root.settingsRequested()
                }

                DButton {
                    text: "Open platform"
                    iconName: "open_in_new"
                    variant: "text"
                    onClicked: root.urlRequested("https://platform.deepseek.com/usage")
                }
            }
        }
    }

    // Current month
    StyledRect {
        width: parent.width
        height: monthColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh
        visible: root.current !== null

        Column {
            id: monthColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Usage · " + root.monthTitle
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceVariantText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.monthMetrics

                    delegate: Column {
                        width: (parent.width - parent.spacing * 3) / 4
                        spacing: root.tightSpacing

                        StyledText {
                            width: parent.width
                            text: modelData.value
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: modelData.color
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // Daily chart
    StyledRect {
        width: parent.width
        height: chartColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh
        visible: root.current !== null

        Column {
            id: chartColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: "Daily tokens · " + root.monthTitle
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceVariantText
            }

            DeepSeekUsageChart {
                width: parent.width
                height: root.chartHeight
                visible: root.daily.length > 0
                days: root.daily
                inputColor: root.chartInputColor
                outputColor: root.chartOutputColor
            }

            StyledText {
                visible: root.daily.length === 0
                text: "No daily data for this month yet."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Row {
                spacing: Theme.spacingM

                Row {
                    spacing: Theme.spacingXS

                    Rectangle {
                        width: root.legendWidth
                        height: root.legendHeight
                        radius: Math.min(Theme.cornerRadiusXXS, height / 2)
                        color: root.chartInputColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Input"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }

                Row {
                    spacing: Theme.spacingXS

                    Rectangle {
                        width: root.legendWidth
                        height: root.legendHeight
                        radius: Math.min(Theme.cornerRadiusXXS, height / 2)
                        color: root.chartOutputColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Output"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    // Monthly history
    StyledRect {
        width: parent.width
        height: historyColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHigh
        visible: root.months.length > 1

        Column {
            id: historyColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: "Monthly history"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceVariantText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    width: root.historyMonthWidth
                    text: "Month"
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    width: root.historyValueWidth
                    text: "Input"
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignRight
                }
                StyledText {
                    width: root.historyValueWidth
                    text: "Output"
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignRight
                }
                StyledText {
                    width: parent.width - root.historyMonthWidth - root.historyValueWidth * 2 - parent.spacing * 3
                    text: "Cost"
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignRight
                }
            }

            Repeater {
                model: root.months

                delegate: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: root.historyMonthWidth
                        text: Format.monthLabel(modelData.year, modelData.month)
                            + (modelData.current ? " · now" : "")
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.current ? Theme.primary : Theme.surfaceText
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: root.historyValueWidth
                        text: Format.formatTokens(modelData.input)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignRight
                    }
                    StyledText {
                        width: root.historyValueWidth
                        text: Format.formatTokens(modelData.output)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignRight
                    }
                    StyledText {
                        width: parent.width - root.historyMonthWidth - root.historyValueWidth * 2 - parent.spacing * 3
                        text: modelData.cost !== null && modelData.cost !== undefined
                            ? Format.formatMoney(modelData.cost, root.platformCurrency)
                            : "—"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }

    // Links
    Row {
        width: parent.width
        spacing: Theme.spacingS

        DButton {
            width: (parent.width - parent.spacing) / 2
            maximumWidth: width
            text: "Usage page"
            iconName: "open_in_new"
            variant: "text"
            onClicked: root.urlRequested("https://platform.deepseek.com/usage")
        }

        DButton {
            width: (parent.width - parent.spacing) / 2
            maximumWidth: width
            text: "API keys"
            iconName: "key"
            variant: "text"
            onClicked: root.urlRequested("https://platform.deepseek.com/api_keys")
        }
    }

    DButton {
        width: parent.width
        maximumWidth: width
        text: root.busy ? "Refreshing…" : "Refresh now"
        iconName: "refresh"
        variant: "tonal"
        busy: root.busy
        enabled: !root.busy && !root.offlineOnly
        onClicked: root.refreshRequested()
    }

    StyledText {
        width: parent.width
        visible: !root.noCredentials && root.snapshot.error && root.snapshot.error.length > 0
        text: root.snapshot.error || ""
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.error
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Updated " + Format.relativeTime(root.nowMs, root.snapshot.updatedAt || 0)
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.surfaceVariantText
        horizontalAlignment: Text.AlignHCenter
    }
}

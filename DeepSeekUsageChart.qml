import QtQuick
import qs.Common
import "lib/format.js" as Format

Item {
    id: root

    property var days: []
    property color inputColor: Theme.primary
    property color outputColor: Theme.tertiary
    property color textColor: Theme.surfaceVariantText
    property color gridColor: Theme.withAlpha(Theme.surfaceText, 0.08)
    readonly property string labelFont: Math.round(Theme.fontSizeXSmall) + "px '" + Theme.fontFamily + "'"
    readonly property string emptyFont: Math.round(Theme.fontSizeSmall) + "px '" + Theme.fontFamily + "'"

    onDaysChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onInputColorChanged: canvas.requestPaint()
    onOutputColorChanged: canvas.requestPaint()
    onTextColorChanged: canvas.requestPaint()
    onGridColorChanged: canvas.requestPaint()
    onLabelFontChanged: canvas.requestPaint()
    onEmptyFontChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var data = root.days || [];
            if (!data.length) {
                ctx.fillStyle = root.textColor.toString();
                ctx.font = root.emptyFont;
                ctx.textAlign = "center";
                ctx.fillText("No daily data", width / 2, height / 2);
                return;
            }

            var padLeft = Theme.spacingXL + Theme.spacingM;
            var padRight = Theme.spacingXS;
            var padTop = Theme.spacingXS + Theme.spacingXXS;
            var padBottom = Theme.spacingL;
            var chartWidth = Math.max(1, width - padLeft - padRight);
            var chartHeight = Math.max(1, height - padTop - padBottom);
            var labelInset = Theme.spacingXS;

            var maxTotal = 1;
            for (var i = 0; i < data.length; i++) {
                var total = (data[i].input || 0) + (data[i].output || 0);
                if (total > maxTotal)
                    maxTotal = total;
            }

            ctx.strokeStyle = root.gridColor.toString();
            ctx.lineWidth = 1;
            for (var grid = 0; grid <= 4; grid++) {
                var gridY = padTop + chartHeight * (1 - grid / 4);
                ctx.beginPath();
                ctx.moveTo(padLeft, gridY);
                ctx.lineTo(width - padRight, gridY);
                ctx.stroke();

                ctx.fillStyle = root.textColor.toString();
                ctx.font = root.labelFont;
                ctx.textAlign = "right";
                ctx.fillText(Format.formatTokens(maxTotal * grid / 4), padLeft - labelInset, gridY + labelInset);
            }

            var slots = Math.max(data.length, 1);
            var gap = chartWidth / slots;
            var barWidth = Math.max(Theme.spacingXXS, Math.min(gap * 0.68, Theme.spacingL + Theme.spacingXXS));
            var baseY = padTop + chartHeight;

            for (var dayIndex = 0; dayIndex < data.length; dayIndex++) {
                var item = data[dayIndex];
                var input = item.input || 0;
                var output = item.output || 0;
                var inputHeight = chartHeight * input / maxTotal;
                var outputHeight = chartHeight * output / maxTotal;
                var centerX = padLeft + gap * dayIndex + gap / 2;
                var barX = centerX - barWidth / 2;

                ctx.fillStyle = root.outputColor.toString();
                ctx.fillRect(barX, baseY - outputHeight, barWidth, outputHeight);

                ctx.fillStyle = root.inputColor.toString();
                ctx.fillRect(barX, baseY - outputHeight - inputHeight, barWidth, inputHeight);

                if (item.day === 1 || item.day % 5 === 0) {
                    ctx.fillStyle = root.textColor.toString();
                    ctx.font = root.labelFont;
                    ctx.textAlign = "center";
                    ctx.fillText(String(item.day), centerX, height - labelInset);
                }
            }
        }
    }
}

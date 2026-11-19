// Formatting helpers shared by the widget, popout and tests.

function numberValue(value, fallback) {
    var parsed = Number(value);
    return isFinite(parsed) ? parsed : (fallback === undefined ? 0 : fallback);
}

function currencySymbol(currency) {
    switch (String(currency || "").toUpperCase()) {
    case "CNY":
    case "RMB":
        return "¥";
    case "USD":
        return "$";
    case "EUR":
        return "€";
    default:
        return currency ? String(currency) + " " : "";
    }
}

function formatMoney(value, currency) {
    var amount = numberValue(value, 0);
    var formatted = Math.abs(amount).toFixed(2);
    return currencySymbol(currency) + formatted;
}

function formatSignedMoney(value, currency) {
    var amount = numberValue(value, 0);
    var sign = amount >= 0 ? "+" : "-";
    return sign + currencySymbol(currency) + Math.abs(amount).toFixed(2);
}

function formatCompactMoney(value, currency) {
    var amount = numberValue(value, 0);
    if (Math.abs(amount) >= 1000)
        return currencySymbol(currency) + (amount / 1000).toFixed(1) + "K";
    if (Math.abs(amount) >= 100)
        return currencySymbol(currency) + Math.round(amount);
    return currencySymbol(currency) + (Math.round(amount * 10) / 10).toFixed(1);
}

function formatTokens(value) {
    var amount = numberValue(value, 0);
    if (!isFinite(amount))
        return "-";
    var abs = Math.abs(amount);
    if (abs >= 1e9)
        return (amount / 1e9).toFixed(1) + "B";
    if (abs >= 1e6)
        return (amount / 1e6).toFixed(1) + "M";
    if (abs >= 1e3)
        return (amount / 1e3).toFixed(1) + "K";
    return String(Math.round(amount));
}

function formatPercent(value, digits) {
    var amount = numberValue(value, 0);
    return amount.toFixed(digits === undefined ? 0 : digits) + "%";
}

function monthKey(year, month) {
    return String(year) + "-" + (month < 10 ? "0" : "") + String(month);
}

function monthLabel(year, month) {
    var names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var index = Math.max(0, Math.min(11, Number(month) - 1));
    return names[index] + " " + String(year);
}

function relativeTime(nowMs, thenMs) {
    if (!thenMs || thenMs <= 0)
        return "never";
    var seconds = Math.max(0, Math.floor((nowMs - thenMs) / 1000));
    if (seconds < 60)
        return "just now";
    var minutes = Math.floor(seconds / 60);
    if (minutes < 60)
        return minutes + "m ago";
    var hours = Math.floor(minutes / 60);
    if (hours < 24)
        return hours + "h ago";
    var date = new Date(thenMs);
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[date.getMonth()] + " " + date.getDate()
        + " " + pad2(date.getHours())
        + ":" + pad2(date.getMinutes());
}

function pad2(value) {
    return value < 10 ? "0" + value : String(value);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        numberValue: numberValue,
        currencySymbol: currencySymbol,
        formatMoney: formatMoney,
        formatSignedMoney: formatSignedMoney,
        formatCompactMoney: formatCompactMoney,
        formatTokens: formatTokens,
        formatPercent: formatPercent,
        monthKey: monthKey,
        monthLabel: monthLabel,
        relativeTime: relativeTime
    };
}

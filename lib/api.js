// DeepSeek endpoint URLs and request headers. Never logs credentials.

var API_BASE = "https://api.deepseek.com";
var PLATFORM_BASE = "https://platform.deepseek.com";
// Identifies the plugin when fetching public pricing pages. Platform requests
// authenticate with the pasted Authorization value and send no browser headers.
var USER_AGENT = "dux-deepseek/1.0 (+https://github.com/opigod/dux-deepseek)";

function balanceUrl() {
    return API_BASE + "/user/balance";
}

function summaryUrl() {
    return PLATFORM_BASE + "/api/v0/users/get_user_summary";
}

function amountUrl(year, month, groupByDay) {
    var url = PLATFORM_BASE + "/api/v0/usage/amount?year=" + year + "&month=" + month;
    if (groupByDay)
        url += "&group_by=day";
    return url;
}

function costUrl(year, month) {
    return PLATFORM_BASE + "/api/v0/usage/cost?year=" + year + "&month=" + month;
}

function officialHeaders(apiKey) {
    return {
        "Accept": "application/json",
        "Authorization": "Bearer " + String(apiKey || "").trim()
    };
}

function platformHeaders(auth) {
    var value = String(auth || "").trim();
    // Devtools shows the header as a row; accept both the value and the row.
    value = value.replace(/^authorization\s*:\s*/i, "").trim();
    // Qt's QML XMLHttpRequest silently drops Cookie and Referer headers, so
    // the only credential this plugin can send is the Authorization value.
    if (!/^(bearer|basic)\s+/i.test(value))
        value = "Bearer " + value;
    return {
        "Accept": "application/json",
        "Authorization": value
    };
}

function pricingHeaders() {
    return {
        "Accept": "text/html,application/xhtml+xml",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "User-Agent": USER_AGENT
    };
}

function monthInfo(offset) {
    var reference = new Date();
    var date = new Date(Date.UTC(reference.getUTCFullYear(), reference.getUTCMonth() + (offset || 0), 1));
    return {
        year: date.getUTCFullYear(),
        month: date.getUTCMonth() + 1,
        key: date.getUTCFullYear() + "-" + (date.getUTCMonth() + 1 < 10 ? "0" : "") + (date.getUTCMonth() + 1)
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        API_BASE: API_BASE,
        PLATFORM_BASE: PLATFORM_BASE,
        balanceUrl: balanceUrl,
        summaryUrl: summaryUrl,
        amountUrl: amountUrl,
        costUrl: costUrl,
        officialHeaders: officialHeaders,
        platformHeaders: platformHeaders,
        pricingHeaders: pricingHeaders,
        monthInfo: monthInfo
    };
}

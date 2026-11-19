// DeepSeek endpoint URLs and request headers. Never logs credentials.

var API_BASE = "https://api.deepseek.com";
var PLATFORM_BASE = "https://platform.deepseek.com";
var USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

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
    var headers = {
        "Accept": "application/json",
        "Origin": PLATFORM_BASE,
        "Referer": PLATFORM_BASE + "/usage",
        "User-Agent": USER_AGENT
    };
    if (/^bearer\s+/i.test(value)) {
        headers.Authorization = value;
    } else if (value.indexOf(";") >= 0 || /^[A-Za-z0-9_\-]+=/.test(value)) {
        headers.Cookie = value;
    } else {
        headers.Authorization = "Bearer " + value;
    }
    return headers;
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

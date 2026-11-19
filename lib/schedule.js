// DeepSeek / Ollama peak-window schedule, holidays and price-page parsing.
// Pure JavaScript so the same file runs inside QML and under Bun tests.

var DAY_MS = 86400000;
var BEIJING_OFFSET_MS = 8 * 3600000;

var PROVIDERS = {
    deepseek: {
        name: "DeepSeek",
        windows: [[60, 240], [360, 600]],
        weekendMode: "beijing",
        holidayOffPeak: true,
        sourceUrl: "https://api-docs.deepseek.com/quick_start/pricing/",
        fallbackUrls: [
            "https://api-docs.deepseek.com/quick_start/pricing/",
            "https://www.deepseek.com/en/pricing"
        ]
    },
    ollama: {
        name: "Ollama Cloud",
        windows: [[720, 1080]],
        weekendMode: "utc",
        holidayOffPeak: false,
        sourceUrl: "https://ollama.com/pricing",
        fallbackUrls: ["https://ollama.com/pricing", "https://docs.ollama.com/cloud"]
    }
};

// Chinese public holidays (Beijing calendar). Off-peak all day under the
// providers that bill holidays that way.
var HOLIDAYS = {
    "2025": [
        "2025-01-01",
        "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31",
        "2025-02-01", "2025-02-02", "2025-02-03", "2025-02-04",
        "2025-04-04", "2025-04-05", "2025-04-06",
        "2025-05-01", "2025-05-02", "2025-05-03", "2025-05-04", "2025-05-05",
        "2025-05-31", "2025-06-01", "2025-06-02",
        "2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04",
        "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08"
    ],
    "2026": [
        "2026-01-01", "2026-01-02", "2026-01-03",
        "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18",
        "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
        "2026-04-04", "2026-04-05", "2026-04-06",
        "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
        "2026-06-19", "2026-06-20", "2026-06-21",
        "2026-09-25", "2026-09-26", "2026-09-27",
        "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04",
        "2026-10-05", "2026-10-06", "2026-10-07"
    ],
    // Estimated from the lunar calendar; replace with the official State
    // Council arrangement once it is published.
    "2027": [
        "2027-01-01", "2027-01-02", "2027-01-03",
        "2027-02-05", "2027-02-06", "2027-02-07", "2027-02-08",
        "2027-02-09", "2027-02-10", "2027-02-11", "2027-02-12",
        "2027-04-03", "2027-04-04", "2027-04-05",
        "2027-05-01", "2027-05-02", "2027-05-03", "2027-05-04", "2027-05-05",
        "2027-06-09", "2027-06-10", "2027-06-11",
        "2027-09-15", "2027-09-16", "2027-09-17",
        "2027-10-01", "2027-10-02", "2027-10-03", "2027-10-04",
        "2027-10-05", "2027-10-06", "2027-10-07"
    ]
};

// Years in HOLIDAYS that are guesses rather than the published schedule.
var PROVISIONAL_HOLIDAY_YEARS = {
    "2027": true
};

var holidayMapCache = null;
var holidayDaysCache = null;
var candidateCache = {};
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function pad2(n) {
    return n < 10 ? "0" + n : String(n);
}

function toMinutes(hhmm) {
    var parts = String(hhmm).split(":");
    return Number(parts[0]) * 60 + Number(parts[1]);
}

function providerProfile(provider) {
    return PROVIDERS[provider] || PROVIDERS.deepseek;
}

function providerName(provider) {
    return providerProfile(provider).name;
}

function sourceUrl(provider) {
    return providerProfile(provider).sourceUrl;
}

function fallbackUrls(provider) {
    return providerProfile(provider).fallbackUrls || [];
}

function utcDayNumber(ms) {
    return Math.floor(ms / DAY_MS);
}

function beijingDayNumber(ms) {
    return Math.floor((ms + BEIJING_OFFSET_MS) / DAY_MS);
}

// 0 = Sunday, 6 = Saturday. 1970-01-01 was a Thursday (4).
function weekdayFromDay(dayNumber) {
    return ((dayNumber + 4) % 7 + 7) % 7;
}

function holidayMap() {
    if (holidayMapCache !== null)
        return holidayMapCache;
    holidayMapCache = {};
    for (var year in HOLIDAYS) {
        var days = HOLIDAYS[year];
        for (var i = 0; i < days.length; i++) {
            var parts = days[i].split("-");
            var ms = Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
            holidayMapCache[Math.floor(ms / DAY_MS)] = true;
        }
    }
    return holidayMapCache;
}

function holidayDays() {
    if (holidayDaysCache !== null)
        return holidayDaysCache;
    var map = holidayMap();
    var out = [];
    for (var key in map)
        out.push(Number(key));
    out.sort(function (a, b) { return a - b; });
    holidayDaysCache = out;
    return out;
}

function isWeekend(nowMs, provider) {
    var profile = providerProfile(provider);
    var day = profile.weekendMode === "utc" ? utcDayNumber(nowMs) : beijingDayNumber(nowMs);
    var weekday = weekdayFromDay(day);
    return weekday === 0 || weekday === 6;
}

function isHoliday(nowMs, provider) {
    var profile = providerProfile(provider);
    if (!profile.holidayOffPeak)
        return false;
    return holidayMap()[beijingDayNumber(nowMs)] === true;
}

function offDayInfo(nowMs, provider) {
    if (isWeekend(nowMs, provider))
        return { off: true, reason: "weekend" };
    if (isHoliday(nowMs, provider))
        return { off: true, reason: "holiday" };
    return { off: false, reason: "" };
}

// Empty when the current Beijing year has published holiday data.
function holidayDataWarning(nowMs, provider) {
    var profile = providerProfile(provider);
    if (!profile.holidayOffPeak)
        return "";
    var year = new Date(beijingDayNumber(nowMs) * DAY_MS).getUTCFullYear();
    if (!HOLIDAYS[String(year)])
        return "No " + year + " holiday data · holidays count as peak";
    if (PROVISIONAL_HOLIDAY_YEARS[String(year)])
        return year + " holiday dates are provisional · may change";
    return "";
}

function isPeakAt(nowMs, provider) {
    if (offDayInfo(nowMs, provider).off)
        return false;
    var profile = providerProfile(provider);
    var dayStart = utcDayNumber(nowMs) * DAY_MS;
    var minute = Math.floor((nowMs - dayStart) / 60000);
    for (var i = 0; i < profile.windows.length; i++) {
        var slot = profile.windows[i];
        if (minute >= slot[0] && minute < slot[1])
            return true;
    }
    return false;
}

function candidateList(nowMs, provider) {
    var day = utcDayNumber(nowMs);
    var key = provider + ":" + day;
    var cached = candidateCache[key];
    if (cached)
        return cached;

    var profile = providerProfile(provider);
    var seen = {};
    var out = [];
    function add(value) {
        if (seen[value])
            return;
        seen[value] = true;
        out.push(value);
    }
    for (var d = day - 14; d <= day + 14; d++) {
        var utcMid = d * DAY_MS;
        add(utcMid);
        add(utcMid - BEIJING_OFFSET_MS);
        for (var i = 0; i < profile.windows.length; i++) {
            var slot = profile.windows[i];
            add(utcMid + slot[0] * 60000);
            add(utcMid + slot[1] * 60000);
        }
    }
    out.sort(function (a, b) { return a - b; });
    candidateCache[key] = out;
    return out;
}

function nextFlip(nowMs, provider) {
    var tier = isPeakAt(nowMs, provider);
    var candidates = candidateList(nowMs, provider);
    for (var i = 0; i < candidates.length; i++) {
        var candidate = candidates[i];
        if (candidate > nowMs && isPeakAt(candidate, provider) !== tier)
            return candidate;
    }
    return nowMs + 10 * DAY_MS;
}

function previousFlip(nowMs, provider) {
    var tier = isPeakAt(nowMs, provider);
    var candidates = candidateList(nowMs, provider);
    for (var i = candidates.length - 1; i >= 0; i--) {
        var candidate = candidates[i];
        if (candidate <= nowMs
                && isPeakAt(candidate, provider) === tier
                && isPeakAt(candidate - 1, provider) !== tier)
            return candidate;
    }
    return nowMs - 10 * DAY_MS;
}

function snapshot(nowMs, provider) {
    var tier = isPeakAt(nowMs, provider);
    var start = previousFlip(nowMs, provider);
    var end = nextFlip(nowMs, provider);
    var total = end - start;
    var ratio = total > 0 ? (nowMs - start) / total : 0;
    if (ratio < 0)
        ratio = 0;
    if (ratio > 1)
        ratio = 1;
    return {
        provider: provider,
        isPeak: tier,
        secondsToNext: Math.max(0, Math.floor((end - nowMs) / 1000)),
        progress: ratio,
        blockStart: start,
        blockEnd: end,
        nextFlipAt: end
    };
}

function formatCountdown(seconds) {
    if (!isFinite(seconds) || seconds < 0)
        return "-";
    var totalMinutes = Math.floor(seconds / 60);
    var hours = Math.floor(totalMinutes / 60);
    var minutes = totalMinutes % 60;
    if (hours >= 24) {
        var days = Math.floor(hours / 24);
        return days + "d" + (hours % 24) + "h";
    }
    if (hours > 0)
        return hours + "h" + minutes + "m";
    if (minutes > 0)
        return minutes + "m";
    return "<1m";
}

function formatBigCountdown(seconds) {
    if (!isFinite(seconds) || seconds < 0)
        return "--";
    if (seconds >= 86400) {
        var totalMinutes = Math.floor(seconds / 60);
        var days = Math.floor(totalMinutes / 1440);
        var hours = Math.floor((totalMinutes % 1440) / 60);
        var minutes = totalMinutes % 60;
        return days + "d " + hours + "h " + minutes + "m";
    }
    return formatHMS(seconds);
}

function formatShortCountdown(seconds) {
    if (!isFinite(seconds) || seconds < 0)
        return "-";
    var totalMinutes = Math.floor(seconds / 60);
    if (totalMinutes >= 1440)
        return Math.floor(totalMinutes / 1440) + "d";
    if (totalMinutes >= 60)
        return Math.floor(totalMinutes / 60) + "h";
    return Math.max(1, totalMinutes) + "m";
}

function formatHMS(seconds) {
    if (!isFinite(seconds) || seconds < 0)
        return "--:--:--";
    var total = Math.floor(seconds);
    var hours = Math.floor(total / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    var secs = total % 60;
    return pad2(hours) + ":" + pad2(minutes) + ":" + pad2(secs);
}

function formatHM(utcMs, timezone) {
    if (timezone === "utc") {
        var utcDate = new Date(utcMs);
        return pad2(utcDate.getUTCHours()) + ":" + pad2(utcDate.getUTCMinutes());
    }
    if (timezone === "beijing") {
        var bjDate = new Date(utcMs + BEIJING_OFFSET_MS);
        return pad2(bjDate.getUTCHours()) + ":" + pad2(bjDate.getUTCMinutes());
    }
    var localDate = new Date(utcMs);
    return pad2(localDate.getHours()) + ":" + pad2(localDate.getMinutes());
}

// nil when the relevant day is a weekend or holiday (off-peak all day).
function windowLine(nowMs, provider, timezone) {
    if (offDayInfo(nowMs, provider).off)
        return null;
    var profile = providerProfile(provider);
    var dayStart = utcDayNumber(nowMs) * DAY_MS;
    var parts = [];
    for (var i = 0; i < profile.windows.length; i++) {
        var slot = profile.windows[i];
        parts.push(formatHM(dayStart + slot[0] * 60000, timezone)
            + "-" + formatHM(dayStart + slot[1] * 60000, timezone));
    }
    return parts.join(" · ");
}

function scheduleWindows(provider) {
    var profile = providerProfile(provider);
    var out = [];
    for (var i = 0; i < profile.windows.length; i++) {
        var slot = profile.windows[i];
        out.push(pad2(Math.floor(slot[0] / 60)) + ":" + pad2(slot[0] % 60)
            + "-" + pad2(Math.floor(slot[1] / 60)) + ":" + pad2(slot[1] % 60));
    }
    return out;
}

function scheduleText(provider) {
    return scheduleWindows(provider).join(", ") + " UTC";
}

function formatDay(dayNumber) {
    var date = new Date(dayNumber * DAY_MS);
    return MONTHS[date.getUTCMonth()] + " " + date.getUTCDate();
}

function holidayRange(nowMs) {
    var all = holidayDays();
    if (all.length === 0)
        return null;
    var bjDay = beijingDayNumber(nowMs);
    var idx = 0;
    while (idx < all.length && all[idx] < bjDay)
        idx++;
    if (idx >= all.length)
        return null;

    var startIdx = idx;
    var endIdx = idx;
    if (all[idx] === bjDay) {
        while (startIdx > 0 && all[startIdx - 1] === all[startIdx] - 1)
            startIdx--;
        while (endIdx + 1 < all.length && all[endIdx + 1] === all[endIdx] + 1)
            endIdx++;
        return {
            active: true,
            startDay: all[startIdx],
            endDay: all[endIdx],
            inDays: 0,
            text: "Holiday · off-peak until " + formatDay(all[endIdx] + 1)
        };
    }

    while (endIdx + 1 < all.length && all[endIdx + 1] === all[endIdx] + 1)
        endIdx++;
    var inDays = all[startIdx] - bjDay;
    if (inDays > 7)
        return null;
    var label;
    if (all[startIdx] === all[endIdx]) {
        label = formatDay(all[startIdx]);
    } else {
        var startDate = new Date(all[startIdx] * DAY_MS);
        var endDate = new Date(all[endIdx] * DAY_MS);
        label = startDate.getUTCMonth() === endDate.getUTCMonth()
            ? MONTHS[startDate.getUTCMonth()] + " " + startDate.getUTCDate() + "-" + endDate.getUTCDate()
            : formatDay(all[startIdx]) + "-" + formatDay(all[endIdx]);
    }
    return {
        active: false,
        startDay: all[startIdx],
        endDay: all[endIdx],
        inDays: inDays,
        text: "Next holiday " + label + " · in " + inDays + "d"
    };
}

function windowsFromPage(text, provider) {
    if (typeof text !== "string" || text.length === 0)
        return null;
    var normalized = text.replace(/[\u2013\u2014]/g, "-");
    var lower = normalized.toLowerCase();
    var found = [];

    if (provider === "ollama") {
        var at = lower.indexOf("outside");
        if (at < 0)
            at = lower.indexOf("between");
        if (at >= 0) {
            var fragment = normalized.substring(Math.max(0, at - 30), at + 220);
            var match = fragment.match(/(\d{1,2}):(\d{2})\s+(?:and|to)\s+(\d{1,2}):(\d{2})\s*UTC/i);
            if (match) {
                found.push(pad2(Number(match[1])) + ":" + match[2]
                    + "-" + pad2(Number(match[3])) + ":" + match[4]);
            }
        }
    } else {
        var marker = lower.indexOf("peak hours are");
        if (marker < 0)
            marker = lower.indexOf("peak hours");
        if (marker >= 0) {
            var chunk = normalized.substring(marker, marker + 320);
            var regex = /(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})/g;
            var item = regex.exec(chunk);
            while (item) {
                found.push(pad2(Number(item[1])) + ":" + item[2]
                    + "-" + pad2(Number(item[3])) + ":" + item[4]);
                item = regex.exec(chunk);
            }
        }
    }

    if (found.length === 0)
        return null;
    found.sort();
    var unique = [];
    for (var i = 0; i < found.length; i++) {
        if (i === 0 || found[i] !== found[i - 1])
            unique.push(found[i]);
    }
    return unique;
}

function sameWindows(left, right) {
    function key(list) {
        if (!list)
            return "";
        var copy = list.slice();
        copy.sort();
        return copy.join(",");
    }
    return key(left) === key(right);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DAY_MS: DAY_MS,
        BEIJING_OFFSET_MS: BEIJING_OFFSET_MS,
        PROVIDERS: PROVIDERS,
        HOLIDAYS: HOLIDAYS,
        PROVISIONAL_HOLIDAY_YEARS: PROVISIONAL_HOLIDAY_YEARS,
        providerProfile: providerProfile,
        providerName: providerName,
        sourceUrl: sourceUrl,
        fallbackUrls: fallbackUrls,
        utcDayNumber: utcDayNumber,
        beijingDayNumber: beijingDayNumber,
        weekdayFromDay: weekdayFromDay,
        isWeekend: isWeekend,
        isHoliday: isHoliday,
        offDayInfo: offDayInfo,
        holidayDataWarning: holidayDataWarning,
        isPeakAt: isPeakAt,
        candidateList: candidateList,
        nextFlip: nextFlip,
        previousFlip: previousFlip,
        snapshot: snapshot,
        formatCountdown: formatCountdown,
        formatShortCountdown: formatShortCountdown,
        formatBigCountdown: formatBigCountdown,
        formatHMS: formatHMS,
        formatHM: formatHM,
        windowLine: windowLine,
        scheduleWindows: scheduleWindows,
        scheduleText: scheduleText,
        holidayRange: holidayRange,
        formatDay: formatDay,
        windowsFromPage: windowsFromPage,
        sameWindows: sameWindows
    };
}

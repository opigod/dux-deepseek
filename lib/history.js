// Balance history and trend calculations. History is a small array of
// { t: epoch ms, b: total balance } points, capped at one point per hour.

var DAY_MS = 86400000;
var MAX_POINTS = 1000;
var KEEP_MS = 32 * DAY_MS;

function clean(history, nowMs) {
    if (!history || history.length === undefined)
        return [];
    var cutoff = (nowMs || Date.now()) - KEEP_MS;
    var out = [];
    for (var i = 0; i < history.length; i++) {
        var point = history[i];
        if (!point || !isFinite(point.t) || !isFinite(point.b))
            continue;
        if (point.t < cutoff)
            continue;
        out.push({ t: Number(point.t), b: Number(point.b) });
    }
    out.sort(function (a, b) { return a.t - b.t; });
    if (out.length > MAX_POINTS)
        out = out.slice(out.length - MAX_POINTS);
    return out;
}

function append(history, total, nowMs) {
    if (!isFinite(total))
        return clean(history, nowMs);
    var points = clean(history, nowMs);
    if (points.length > 0) {
        var last = points[points.length - 1];
        if (last.b === Number(total) && nowMs - last.t < 3600000)
            return points;
        if (last.t === nowMs) {
            points[points.length - 1] = { t: nowMs, b: Number(total) };
            return points;
        }
    }
    points.push({ t: nowMs, b: Number(total) });
    return clean(points, nowMs);
}

function valueNear(history, targetMs, toleranceMs, notAfterMs) {
    if (!history || !history.length)
        return null;
    var bestBefore = null;
    var bestAfter = null;
    for (var i = 0; i < history.length; i++) {
        var point = history[i];
        if (point.t > notAfterMs)
            continue;
        var distance = Math.abs(point.t - targetMs);
        if (distance > toleranceMs)
            continue;
        if (point.t <= targetMs) {
            if (bestBefore === null || point.t > bestBefore.t)
                bestBefore = point;
        } else if (bestAfter === null || point.t < bestAfter.t) {
            bestAfter = point;
        }
    }
    return bestBefore || bestAfter;
}

function change(history, currentTotal, targetMs, toleranceMs, nowMs) {
    var base = valueNear(history, targetMs, toleranceMs, nowMs);
    if (base === null)
        return null;
    return {
        value: currentTotal - base.b,
        base: base.b,
        at: base.t
    };
}

function monthStart(nowMs) {
    var date = new Date(nowMs);
    return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1);
}

function sparkline(history, nowMs, days, maxPoints) {
    if (!history || !history.length)
        return [];
    var cutoff = nowMs - (days || 7) * DAY_MS;
    var points = [];
    for (var i = 0; i < history.length; i++) {
        if (history[i].t >= cutoff)
            points.push(history[i].b);
    }
    if (points.length === 0)
        return [];
    var limit = maxPoints || 48;
    if (points.length <= limit)
        return points;
    var sampled = [];
    for (var s = 0; s < limit; s++) {
        var index = Math.round(s * (points.length - 1) / (limit - 1));
        sampled.push(points[index]);
    }
    return sampled;
}

function trends(history, currentTotal, nowMs) {
    return {
        day: change(history, currentTotal, nowMs - DAY_MS, 2 * 3600000, nowMs),
        month: change(history, currentTotal, monthStart(nowMs), 3 * DAY_MS, nowMs),
        sparkline: sparkline(history, nowMs, 7, 48)
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        clean: clean,
        append: append,
        valueNear: valueNear,
        change: change,
        monthStart: monthStart,
        sparkline: sparkline,
        trends: trends
    };
}

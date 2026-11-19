// Defensive parsing for the official balance endpoint and the platform usage
// endpoints. Platform responses are wrapped in { code, msg, data }.

function num(value) {
    var parsed = Number(value);
    return isFinite(parsed) ? parsed : 0;
}

function unwrap(json) {
    if (json === null || json === undefined)
        return { ok: false, authExpired: false, error: "empty response", data: null };
    if (typeof json !== "object")
        return { ok: false, authExpired: false, error: "unexpected response", data: null };

    var code = json.code;
    if (code !== undefined && code !== null && Number(code) !== 0) {
        var message = String(json.msg || json.message || ("code " + code));
        var authExpired = Number(code) === 40002
            || message.toLowerCase().indexOf("missing token") >= 0
            || message.toLowerCase().indexOf("token") >= 0 && message.toLowerCase().indexOf("expired") >= 0;
        return { ok: false, authExpired: authExpired, error: message, data: null };
    }

    var data = json.data;
    if (data && typeof data === "object" && data.biz_data !== undefined)
        return { ok: true, authExpired: false, error: "", data: data.biz_data, wrapper: data };
    return { ok: true, authExpired: false, error: "", data: data !== undefined ? data : json, wrapper: data };
}

function parseBalance(json) {
    if (!json || !json.balance_infos)
        return { ok: false, error: "unexpected balance response" };
    var infos = json.balance_infos;
    if (!infos.length)
        return { ok: false, error: "no balance information" };
    var info = infos[0];
    return {
        ok: true,
        available: json.is_available !== false,
        currency: info.currency || "CNY",
        total: num(info.total_balance),
        granted: num(info.granted_balance),
        toppedUp: num(info.topped_up_balance),
        source: "api"
    };
}

function firstWallet(list) {
    if (!list || !list.length)
        return null;
    return list[0];
}

function sumCosts(list) {
    if (!list || !list.length)
        return 0;
    var total = 0;
    for (var i = 0; i < list.length; i++) {
        var value = list[i];
        if (typeof value === "number") {
            total += value;
        } else if (value && typeof value === "object") {
            total += num(value.amount !== undefined ? value.amount : value.cost);
        }
    }
    return total;
}

function parsePlatformSummary(json) {
    var env = unwrap(json);
    if (!env.ok)
        return { ok: false, authExpired: env.authExpired, error: env.error };
    var biz = env.data;
    if (!biz || typeof biz !== "object")
        return { ok: false, authExpired: false, error: "unexpected summary response" };

    var normalWallet = firstWallet(biz.normal_wallets);
    var bonusWallet = firstWallet(biz.bonus_wallets);
    var normal = normalWallet ? num(normalWallet.balance) : 0;
    var bonus = bonusWallet ? num(bonusWallet.balance) : 0;
    var currency = (normalWallet && normalWallet.currency) || (bonusWallet && bonusWallet.currency) || "CNY";
    var costs = biz.monthly_costs || [];
    var monthlyCost = sumCosts(costs);

    return {
        ok: true,
        authExpired: false,
        error: "",
        currency: currency,
        normal: normal,
        bonus: bonus,
        total: normal + bonus,
        tokenEstimation: num(biz.total_available_token_estimation),
        monthlyTokenUsage: num(biz.monthly_token_usage),
        monthlyCost: monthlyCost,
        monthlyCosts: costs
    };
}

function classifyType(type) {
    var name = String(type || "").toUpperCase();
    if (name.indexOf("PROMPT") >= 0 || name.indexOf("INPUT") >= 0 || name.indexOf("CACHE") >= 0)
        return "input";
    if (name.indexOf("RESPONSE") >= 0 || name.indexOf("COMPLETION") >= 0
            || name.indexOf("OUTPUT") >= 0 || name.indexOf("REASONING") >= 0
            || name.indexOf("THINKING") >= 0)
        return "output";
    return "other";
}

function parseModelEntries(entries) {
    var result = { input: 0, output: 0, other: 0, models: [] };
    if (!entries || !entries.length)
        return result;

    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i] || {};
        var modelName = entry.model || entry.model_name || entry.name || "model";
        var usage = entry.usage || entry.usages || [];
        var model = { model: modelName, input: 0, output: 0, other: 0 };
        for (var u = 0; u < usage.length; u++) {
            var item = usage[u] || {};
            var amount = num(item.amount !== undefined ? item.amount : item.tokens);
            var kind = classifyType(item.type || item.token_type);
            if (kind === "input") {
                result.input += amount;
                model.input += amount;
            } else if (kind === "output") {
                result.output += amount;
                model.output += amount;
            } else {
                result.other += amount;
                model.other += amount;
            }
        }
        result.models.push(model);
    }
    return result;
}

function parseUsageAmount(json) {
    var env = unwrap(json);
    if (!env.ok)
        return { ok: false, authExpired: env.authExpired, error: env.error };
    var biz = env.data;
    if (!biz || typeof biz !== "object")
        return { ok: false, authExpired: false, error: "unexpected usage response" };

    var parsed;
    if (biz.total && biz.total.length !== undefined) {
        parsed = parseModelEntries(biz.total);
    } else {
        parsed = {
            input: num(biz.prompt_tokens !== undefined ? biz.prompt_tokens : biz.input_tokens),
            output: num(biz.completion_tokens !== undefined ? biz.completion_tokens : biz.output_tokens),
            other: 0,
            models: []
        };
    }
    return {
        ok: true,
        authExpired: false,
        error: "",
        input: parsed.input,
        output: parsed.output,
        other: parsed.other,
        models: parsed.models
    };
}

function parseDaily(json) {
    var env = unwrap(json);
    if (!env.ok)
        return { ok: false, authExpired: env.authExpired, error: env.error, days: [] };
    var biz = env.data;
    if (!biz || typeof biz !== "object")
        return { ok: false, authExpired: false, error: "unexpected daily response", days: [] };

    var raw = biz.days || [];
    var days = [];
    for (var i = 0; i < raw.length; i++) {
        var entry = raw[i] || {};
        var date = String(entry.date || "");
        var parts = date.split("-");
        var day = Number(parts[2]);
        if (!isFinite(day) || day < 1 || day > 31)
            continue;
        var parsed = parseModelEntries(entry.data || entry.models || []);
        days.push({
            day: day,
            date: date,
            input: parsed.input,
            output: parsed.output
        });
    }
    days.sort(function (a, b) { return a.day - b.day; });
    return { ok: true, authExpired: false, error: "", days: days };
}

function sumUsageAmounts(entries) {
    var total = 0;
    if (!entries || !entries.length)
        return total;
    for (var i = 0; i < entries.length; i++) {
        var usage = entries[i] && entries[i].usage ? entries[i].usage : [];
        for (var u = 0; u < usage.length; u++) {
            var item = usage[u] || {};
            total += num(item.amount !== undefined ? item.amount : item.cost);
        }
    }
    return total;
}

function parseCost(json) {
    var env = unwrap(json);
    if (!env.ok)
        return { ok: false, authExpired: env.authExpired, error: env.error, cost: 0 };
    var biz = env.data;
    if (biz === null || biz === undefined)
        return { ok: false, authExpired: false, error: "unexpected cost response", cost: 0 };

    if (biz.length !== undefined) {
        var total = 0;
        for (var i = 0; i < biz.length; i++)
            total += sumUsageAmounts(biz[i] && biz[i].total ? biz[i].total : []);
        return { ok: true, authExpired: false, error: "", cost: total };
    }

    if (typeof biz !== "object")
        return { ok: false, authExpired: false, error: "unexpected cost response", cost: 0 };

    var cost = 0;
    if (biz.total && biz.total.length !== undefined) {
        cost += sumUsageAmounts(biz.total);
    } else if (biz.costs && biz.costs.length !== undefined) {
        cost += sumCosts(biz.costs);
    } else if (biz.amount !== undefined) {
        cost += num(biz.amount);
    } else if (biz.total_cost !== undefined) {
        cost += num(biz.total_cost);
    }
    return { ok: true, authExpired: false, error: "", cost: cost };
}

function parseCurrentMonth(amountJson, costJson) {
    var amount = parseUsageAmount(amountJson);
    if (!amount.ok)
        return { ok: false, authExpired: amount.authExpired, error: amount.error };
    var cost = parseCost(costJson);
    return {
        ok: true,
        authExpired: amount.authExpired || cost.authExpired,
        error: cost.ok ? "" : cost.error,
        input: amount.input,
        output: amount.output,
        other: amount.other,
        models: amount.models,
        cost: cost.ok ? cost.cost : null
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        num: num,
        unwrap: unwrap,
        parseBalance: parseBalance,
        parsePlatformSummary: parsePlatformSummary,
        classifyType: classifyType,
        parseModelEntries: parseModelEntries,
        parseUsageAmount: parseUsageAmount,
        parseDaily: parseDaily,
        parseCost: parseCost,
        parseCurrentMonth: parseCurrentMonth
    };
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "lib/schedule.js" as Schedule
import "lib/api.js" as Api
import "lib/http.js" as Http
import "lib/parse.js" as Parse
import "lib/history.js" as History

PluginComponent {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string apiKey: String(pluginData.apiKey || Quickshell.env("DEEPSEEK_API_KEY") || "").trim()
    readonly property string platformAuth: String(pluginData.platformAuth || "").trim()
    readonly property bool offlineOnly: pluginData.offlineOnly === true
    readonly property int refreshMinutes: Math.max(1, Math.min(60, Number(pluginData.refreshMinutes ?? 5)))
    readonly property int historyMonths: Math.max(1, Math.min(6, Number(pluginData.historyMonths ?? 3)))
    readonly property string provider: String(pluginData.provider || "deepseek")
    readonly property bool showOllama: pluginData.showOllama !== false
    readonly property bool autoCheck: pluginData.autoCheck !== false
    readonly property int checkIntervalH: Math.max(1, Math.min(168, Number(pluginData.checkIntervalH ?? 6)))
    readonly property string customSourceUrl: String(pluginData.customSourceUrl || "").trim()

    readonly property bool hasBalanceSource: apiKey.length > 0
    readonly property bool hasPlatformSource: platformAuth.length > 0
    readonly property bool hasAnySource: hasBalanceSource || hasPlatformSource
    readonly property int refreshMs: refreshMinutes * 60000

    property var snapshot: ({
        ok: false,
        busy: false,
        updatedAt: 0,
        error: "",
        balance: null,
        platform: null,
        trends: { day: null, month: null, sparkline: [] },
        drift: { state: "unknown", checkedAt: 0, source: "", found: [], expected: [] },
        diff: 0,
        diffAt: 0
    })
    property var balanceHistory: []
    property var platformHistory: ({})
    property var drift: ({
        state: "unknown",
        checkedAt: 0,
        source: "",
        found: [],
        expected: [],
        error: ""
    })
    property bool busy: false
    property bool pricingBusy: false
    property bool pendingRefresh: false
    property bool platformAuthExpired: false
    property bool balanceAuthInvalid: false
    property bool started: false
    property bool notifiedDrift: false
    property int generation: 0
    property int pricingGeneration: 0

    function merge(base, patch) {
        return Object.assign({}, base || ({}), patch || ({}));
    }

    function emptySnapshot() {
        return {
            ok: false,
            busy: false,
            updatedAt: 0,
            error: "",
            balance: null,
            platform: null,
            trends: { day: null, month: null, sparkline: [] },
            drift: { state: "unknown", checkedAt: 0, source: "", found: [], expected: [] },
            diff: 0,
            diffAt: 0
        };
    }

    function loadState() {
        if (!pluginService || !pluginId)
            return;

        var cached = pluginService.loadPluginState(pluginId, "snapshot", null);
        if (cached && typeof cached === "object") {
            snapshot = merge(emptySnapshot(), cached);
            snapshot.busy = false;
        }

        var history = pluginService.loadPluginState(pluginId, "balanceHistory", []);
        balanceHistory = History.clean(Array.isArray(history) ? history : [], Date.now());

        // The platform summary is only a fallback for accounts without an API
        // key. If a key is configured, never paint the platform wallet first:
        // that is what made the bar flip from USD to CNY on startup.
        if (hasBalanceSource && snapshot.balance && snapshot.balance.source === "platform") {
            snapshot.balance = null;
            snapshot.trends = { day: null, month: null, sparkline: [] };
            snapshot.diff = 0;
            snapshot.diffAt = 0;
            balanceHistory = [];
        }

        var months = pluginService.loadPluginState(pluginId, "platformHistory", {});
        platformHistory = (months && typeof months === "object" && !Array.isArray(months)) ? months : ({});

        var storedDrift = pluginService.loadPluginState(pluginId, "drift", null);
        if (storedDrift && typeof storedDrift === "object") {
            drift = merge(drift, storedDrift);
            snapshot = merge(snapshot, { drift: drift });
        } else {
            snapshot = merge(snapshot, {
                drift: { state: "unknown", checkedAt: 0, source: "", found: [], expected: Schedule.scheduleWindows(provider), error: "" }
            });
        }
        snapshot.provider = provider;
    }

    function publish(next) {
        snapshot = next;
        if (pluginService && pluginId)
            pluginService.setGlobalVar(pluginId, "deepseekSnapshot", snapshot);
    }

    function saveState() {
        if (!pluginService || !pluginId)
            return;
        pluginService.savePluginState(pluginId, "snapshot", snapshot);
        pluginService.savePluginState(pluginId, "balanceHistory", balanceHistory);
        pluginService.savePluginState(pluginId, "platformHistory", platformHistory);
        pluginService.savePluginState(pluginId, "drift", drift);
    }

    function start() {
        if (started)
            return;
        started = true;
        loadState();
        publish(snapshot);
        Qt.callLater(function () {
            refresh(false);
        });
    }

    function scheduleRefresh() {
        if (!started)
            return;
        settingsDebounce.restart();
    }

    function refresh(force) {
        if (offlineOnly) {
            publish(merge(snapshot, {
                busy: false,
                error: "Offline only is enabled",
                provider: provider
            }));
            return;
        }
        if (busy) {
            if (force)
                pendingRefresh = true;
            return;
        }
        if (!hasBalanceSource && !hasPlatformSource) {
            publish(merge(snapshot, {
                busy: false,
                error: "Add an API key or a platform token in settings",
                provider: provider,
                balance: null,
                platform: null,
                trends: { day: null, month: null, sparkline: [] },
                diff: 0,
                diffAt: 0
            }));
            return;
        }

        busy = true;
        pendingRefresh = false;
        var runGeneration = ++generation;
        publish(merge(snapshot, { busy: true, error: "", provider: provider }));
        watchdog.restart();

        var pending = 0;
        var results = {
            balance: null,
            summary: null,
            currentAmount: null,
            currentCost: null,
            daily: null,
            months: {},
            errors: [],
            authExpired: false
        };
        var nowMonth = Api.monthInfo(0);

        function addError(message) {
            if (message)
                results.errors.push(message);
        }

        function jobStarted() {
            pending++;
        }

        function jobFinished() {
            pending--;
            if (pending === 0)
                finalizeFetch(runGeneration, results, nowMonth);
        }

        function markAuthExpired() {
            platformAuthExpired = true;
            results.authExpired = true;
        }

        if (hasBalanceSource && (!balanceAuthInvalid || force)) {
            jobStarted();
            var preferredBalanceCurrency = snapshot.balance && snapshot.balance.source === "api"
                ? snapshot.balance.currency
                : null;
            Http.getJson(Api.balanceUrl(), Api.officialHeaders(apiKey), 15000, function (response) {
                if (runGeneration !== generation)
                    return;
                if (response.ok && response.json) {
                    var parsed = Parse.parseBalance(response.json, preferredBalanceCurrency);
                    if (parsed.ok) {
                        results.balance = parsed;
                        balanceAuthInvalid = false;
                    } else {
                        addError("Balance: " + parsed.error);
                    }
                } else {
                    if (response.status === 401 || response.status === 403) {
                        balanceAuthInvalid = true;
                        addError("API key rejected");
                    } else {
                        addError("Balance: " + (response.error || "request failed"));
                    }
                }
                jobFinished();
            });
        }

        if (hasPlatformSource && (!platformAuthExpired || force)) {
            jobStarted();
            Http.getJson(Api.summaryUrl(), Api.platformHeaders(platformAuth), 20000, function (response) {
                if (runGeneration !== generation)
                    return;
                if (response.ok && response.json) {
                    var parsed = Parse.parsePlatformSummary(response.json);
                    if (parsed.ok) {
                        results.summary = parsed;
                        platformAuthExpired = false;
                    } else {
                        if (parsed.authExpired)
                            markAuthExpired();
                        addError("Platform: " + parsed.error);
                    }
                } else {
                    if (response.status === 401 || response.status === 403)
                        markAuthExpired();
                    addError("Platform: " + (response.error || "request failed"));
                }
                jobFinished();
            });

            jobStarted();
            Http.getJson(Api.amountUrl(nowMonth.year, nowMonth.month, false), Api.platformHeaders(platformAuth), 20000, function (response) {
                if (runGeneration !== generation)
                    return;
                if (response.ok && response.json) {
                    var parsed = Parse.parseUsageAmount(response.json);
                    if (parsed.ok)
                        results.currentAmount = parsed;
                    else {
                        if (parsed.authExpired)
                            markAuthExpired();
                        addError("Usage: " + parsed.error);
                    }
                } else {
                    if (response.status === 401 || response.status === 403)
                        markAuthExpired();
                }
                jobFinished();
            });

            jobStarted();
            Http.getJson(Api.costUrl(nowMonth.year, nowMonth.month), Api.platformHeaders(platformAuth), 20000, function (response) {
                if (runGeneration !== generation)
                    return;
                if (response.ok && response.json) {
                    var parsed = Parse.parseCost(response.json);
                    if (parsed.ok)
                        results.currentCost = parsed;
                    else if (parsed.authExpired)
                        markAuthExpired();
                } else if (response.status === 401 || response.status === 403) {
                    markAuthExpired();
                }
                jobFinished();
            });

            jobStarted();
            Http.getJson(Api.amountUrl(nowMonth.year, nowMonth.month, true), Api.platformHeaders(platformAuth), 20000, function (response) {
                if (runGeneration !== generation)
                    return;
                if (response.ok && response.json) {
                    var parsed = Parse.parseDaily(response.json);
                    if (parsed.ok)
                        results.daily = parsed;
                    else if (parsed.authExpired)
                        markAuthExpired();
                } else if (response.status === 401 || response.status === 403) {
                    markAuthExpired();
                }
                jobFinished();
            });

            var now = Date.now();
            for (var offset = 1; offset < historyMonths; offset++) {
                var info = Api.monthInfo(-offset);
                var cachedMonth = platformHistory[info.key];
                if (cachedMonth && cachedMonth.fetchedAt && now - cachedMonth.fetchedAt < 86400000)
                    continue;
                fetchHistoryMonth(info, runGeneration, results, jobStarted, jobFinished, markAuthExpired);
            }
        }

        if (pending === 0)
            finalizeFetch(runGeneration, results, nowMonth);
    }

    function fetchHistoryMonth(info, runGeneration, results, jobStarted, jobFinished, markAuthExpired) {
        var entry = { input: 0, output: 0, cost: null, fetchedAt: 0 };
        var innerPending = 2;
        var amountOk = false;
        var costOk = false;

        function innerDone() {
            innerPending--;
            if (innerPending === 0) {
                // A partial month retries after an hour instead of a full day.
                entry.fetchedAt = amountOk && costOk
                    ? Date.now()
                    : Date.now() - 23 * 3600000;
                results.months[info.key] = entry;
                jobFinished();
            }
        }

        jobStarted();

        Http.getJson(Api.amountUrl(info.year, info.month, false), Api.platformHeaders(platformAuth), 20000, function (response) {
            if (runGeneration !== generation)
                return;
            if (response.ok && response.json) {
                var parsed = Parse.parseUsageAmount(response.json);
                if (parsed.ok) {
                    entry.input = parsed.input;
                    entry.output = parsed.output;
                    amountOk = true;
                } else if (parsed.authExpired) {
                    markAuthExpired();
                }
            } else if (response.status === 401 || response.status === 403) {
                markAuthExpired();
            }
            innerDone();
        });

        Http.getJson(Api.costUrl(info.year, info.month), Api.platformHeaders(platformAuth), 20000, function (response) {
            if (runGeneration !== generation)
                return;
            if (response.ok && response.json) {
                var parsed = Parse.parseCost(response.json);
                if (parsed.ok) {
                    entry.cost = parsed.cost;
                    costOk = true;
                } else if (parsed.authExpired) {
                    markAuthExpired();
                }
            } else if (response.status === 401 || response.status === 403) {
                markAuthExpired();
            }
            innerDone();
        });
    }

    function finalizeFetch(runGeneration, results, nowMonth) {
        if (runGeneration !== generation)
            return;

        watchdog.stop();
        busy = false;

        var now = Date.now();
        var old = snapshot || emptySnapshot();
        var next = merge(old, {
            busy: false,
            provider: provider,
            drift: drift
        });

        var newBalance = null;
        if (results.balance) {
            newBalance = merge(results.balance, {
                available: results.balance.available,
                source: "api",
                infos: results.balance.infos || []
            });
        } else if (hasBalanceSource) {
            // Keep the last official balance while the key request is failing.
            // Do not replace it with the platform wallet, and do not show a
            // previously cached platform wallet now that a key exists.
            newBalance = old.balance && old.balance.source !== "platform"
                ? old.balance
                : null;
        } else if (results.summary) {
            newBalance = {
                available: true,
                currency: results.summary.currency,
                total: results.summary.total,
                granted: results.summary.bonus,
                toppedUp: results.summary.normal,
                tokenEstimation: results.summary.tokenEstimation,
                monthlyCost: results.summary.monthlyCost,
                source: "platform"
            };
        } else if (old.balance) {
            newBalance = old.balance;
        }

        if (results.summary || results.currentAmount || results.daily) {
            var oldCurrent = old.platform && old.platform.current ? old.platform.current : null;
            var monthChanged = !oldCurrent
                || oldCurrent.year !== nowMonth.year
                || oldCurrent.month !== nowMonth.month;
            var current = null;
            if (results.currentAmount) {
                var costValue = results.currentCost
                    ? results.currentCost.cost
                    : (monthChanged ? null : (oldCurrent ? oldCurrent.cost : null));
                if (costValue === null && results.summary)
                    costValue = results.summary.monthlyCost;
                current = {
                    year: nowMonth.year,
                    month: nowMonth.month,
                    input: results.currentAmount.input,
                    output: results.currentAmount.output,
                    cost: costValue
                };
            } else if (!monthChanged) {
                current = oldCurrent;
            }
            if (current && (current.cost === null || current.cost === undefined) && results.summary)
                current.cost = results.summary.monthlyCost;

            var daily = results.daily
                ? results.daily.days
                : (monthChanged ? [] : (old.platform ? old.platform.daily : []));

            var mergedHistory = Object.assign({}, platformHistory);
            for (var key in results.months)
                mergedHistory[key] = results.months[key];
            platformHistory = mergedHistory;

            var months = [];
            for (var i = 0; i < historyMonths; i++) {
                var info = Api.monthInfo(-i);
                if (i === 0) {
                    months.push({
                        year: info.year,
                        month: info.month,
                        key: info.key,
                        input: current ? current.input : 0,
                        output: current ? current.output : 0,
                        cost: current ? current.cost : null,
                        current: true
                    });
                } else if (platformHistory[info.key]) {
                    var stored = platformHistory[info.key];
                    months.push({
                        year: info.year,
                        month: info.month,
                        key: info.key,
                        input: stored.input || 0,
                        output: stored.output || 0,
                        cost: stored.cost,
                        current: false
                    });
                }
            }

            next.platform = {
                auth: true,
                expired: platformAuthExpired,
                error: results.authExpired ? "Platform session expired" : "",
                currency: results.summary
                    ? results.summary.currency
                    : (old.platform ? old.platform.currency : null),
                summary: results.summary || (old.platform ? old.platform.summary : null),
                current: current,
                daily: daily || [],
                months: months,
                updatedAt: now
            };
        } else if (!hasPlatformSource) {
            next.platform = null;
        }

        if (!hasBalanceSource && !hasPlatformSource && !results.balance && !results.summary)
            newBalance = old.balance;

        if (newBalance && results.summary && newBalance.source === "api")
            newBalance.tokenEstimation = results.summary.tokenEstimation;

        next.balance = newBalance;

        if (next.platform && hasPlatformSource) {
            next.platform = Object.assign({}, next.platform, {
                expired: platformAuthExpired,
                error: results.authExpired
                    ? "Platform session expired"
                    : (next.platform.error || "")
            });
        }

        // Never compare balances across currencies or across the official and
        // platform sources. That used to produce a fake jump and a stale trend
        // when the session token and the API key were both configured.
        var oldCurrency = old.balance ? old.balance.currency : null;
        var newCurrency = newBalance ? newBalance.currency : null;
        var oldSource = old.balance ? old.balance.source : null;
        var newSource = newBalance ? newBalance.source : null;
        var historyReset = (oldCurrency && newCurrency && oldCurrency !== newCurrency)
            || (oldSource && newSource && oldSource !== newSource);
        if (historyReset) {
            balanceHistory = [];
            next.diff = 0;
            next.diffAt = 0;
        }

        var newTotal = newBalance ? newBalance.total : null;
        var oldTotal = historyReset ? null : (old.balance ? old.balance.total : null);
        if (newTotal !== null && isFinite(newTotal)) {
            balanceHistory = History.append(balanceHistory, newTotal, now);
            if (oldTotal !== null && isFinite(oldTotal) && Math.abs(newTotal - oldTotal) > 0.000001) {
                next.diff = newTotal - oldTotal;
                next.diffAt = now;
            } else if (old.diffAt) {
                next.diff = old.diff || 0;
                next.diffAt = old.diffAt;
            }
            next.trends = History.trends(balanceHistory, newTotal, now);
        } else {
            next.trends = { day: null, month: null, sparkline: [] };
            next.diff = 0;
            next.diffAt = 0;
        }

        var errors = results.errors.slice();
        if (platformAuthExpired && hasPlatformSource)
            errors.push("Platform session expired — paste a new token in settings");
        if (balanceAuthInvalid && hasBalanceSource)
            errors.push("API key rejected — update it in settings");
        next.error = errors.join("; ");
        next.ok = !!(next.balance || (next.platform && next.platform.summary));
        next.updatedAt = (results.balance || results.summary || results.currentAmount || results.daily) ? now : (old.updatedAt || 0);

        publish(next);
        saveState();

        if (pendingRefresh) {
            pendingRefresh = false;
            Qt.callLater(function () {
                refresh(true);
            });
        }
    }

    function checkPricing(force) {
        if (offlineOnly)
            return;
        if (!autoCheck && !force)
            return;
        if (pricingBusy)
            return;

        pricingBusy = true;
        var runGeneration = ++pricingGeneration;
        var expected = Schedule.scheduleWindows(provider);
        var urls = [];
        if (customSourceUrl) {
            urls.push(customSourceUrl);
        } else {
            urls.push(Schedule.sourceUrl(provider));
            var fallbacks = Schedule.fallbackUrls(provider);
            for (var i = 0; i < fallbacks.length; i++) {
                if (fallbacks[i] !== urls[0])
                    urls.push(fallbacks[i]);
            }
        }

        function finishPricing(state, found, url, error) {
            if (runGeneration !== pricingGeneration)
                return;
            pricingBusy = false;
            var now = Date.now();
            var previous = drift.state;
            drift = {
                state: state,
                checkedAt: state === "unknown" ? (drift.checkedAt || 0) : now,
                source: url || drift.source || "",
                found: found || [],
                expected: expected,
                error: error || ""
            };
            if (state === "drift" && previous !== "drift") {
                ToastService.showWarning(
                    "DeepSeek pricing policy may have changed",
                    "Peak windows now read " + (found || []).join(", ") + " UTC. Check the pricing page."
                );
            }
            publish(merge(snapshot, { drift: drift, provider: provider }));
            saveState();
        }

        function tryUrl(index) {
            if (index >= urls.length) {
                finishPricing("unknown", [], "", "Could not read the pricing page");
                return;
            }
            Http.getText(urls[index], Api.pricingHeaders(), 20000, function (response) {
                if (runGeneration !== pricingGeneration)
                    return;
                if (!response.ok) {
                    tryUrl(index + 1);
                    return;
                }
                var found = Schedule.windowsFromPage(response.body, provider);
                if (!found || found.length === 0) {
                    tryUrl(index + 1);
                    return;
                }
                finishPricing(Schedule.sameWindows(found, expected) ? "ok" : "drift", found, urls[index], "");
            });
        }

        tryUrl(0);
    }

    function publicStatus() {
        var peak = Schedule.snapshot(Date.now(), provider);
        return {
            ok: snapshot.ok === true,
            busy: busy,
            updatedAt: snapshot.updatedAt || 0,
            provider: provider,
            balance: snapshot.balance ? {
                currency: snapshot.balance.currency,
                total: snapshot.balance.total,
                granted: snapshot.balance.granted,
                toppedUp: snapshot.balance.toppedUp,
                source: snapshot.balance.source
            } : null,
            platform: snapshot.platform ? {
                expired: snapshot.platform.expired === true,
                current: snapshot.platform.current,
                months: snapshot.platform.months ? snapshot.platform.months.length : 0,
                daily: snapshot.platform.daily ? snapshot.platform.daily.length : 0
            } : null,
            peak: peak,
            drift: drift,
            error: snapshot.error || ""
        };
    }

    Timer {
        id: startTimer
        interval: 0
        repeat: false
        onTriggered: root.start()
    }

    Timer {
        id: settingsDebounce
        interval: 500
        repeat: false
        onTriggered: root.refresh(true)
    }

    Timer {
        id: refreshTimer
        interval: root.refreshMs
        repeat: true
        running: root.started && !root.offlineOnly && root.hasAnySource
        triggeredOnStart: false
        onTriggered: root.refresh(false)
    }

    Timer {
        id: pricingTimer
        interval: root.checkIntervalH * 3600000
        repeat: true
        running: root.started && root.autoCheck && !root.offlineOnly
        triggeredOnStart: true
        onTriggered: root.checkPricing(false)
    }

    Timer {
        id: watchdog
        interval: 45000
        repeat: false
        onTriggered: {
            if (!root.busy)
                return;
            root.generation++;
            root.busy = false;
            root.publish(root.merge(root.snapshot, {
                busy: false,
                error: "Request timed out"
            }));
        }
    }

    Connections {
        target: PluginService

        function onGlobalVarChanged(pid, name) {
            if (pid !== root.pluginId || name !== "deepseekCommand")
                return;
            var command = PluginService.getGlobalVar(root.pluginId, "deepseekCommand", null);
            if (!command)
                return;
            if (command.action === "refresh")
                root.refresh(true);
            else if (command.action === "checkPricing")
                root.checkPricing(true);
        }
    }

    IpcHandler {
        target: "deepseek"

        function status(): string {
            return JSON.stringify(root.publicStatus());
        }

        function refresh(): string {
            root.refresh(true);
            return "REFRESH_STARTED";
        }

        function checkPricing(): string {
            root.checkPricing(true);
            return "PRICING_CHECK_STARTED";
        }

        function getProvider(): string {
            return root.provider;
        }

        function setProvider(name: string): string {
            if (name !== "deepseek" && name !== "ollama")
                return "INVALID_PROVIDER";
            if (!root.pluginService)
                return "PLUGIN_SERVICE_UNAVAILABLE";
            root.pluginService.savePluginData(root.pluginId, "provider", name);
            return "PROVIDER_SET";
        }
    }

    Component.onCompleted: {
        startTimer.start();
    }

    onApiKeyChanged: {
        balanceAuthInvalid = false;
        scheduleRefresh();
    }

    onPlatformAuthChanged: {
        platformAuthExpired = false;
        scheduleRefresh();
    }

    onOfflineOnlyChanged: {
        if (offlineOnly) {
            generation++;
            pricingGeneration++;
            busy = false;
            pricingBusy = false;
            pendingRefresh = false;
            watchdog.stop();
            publish(merge(snapshot, { busy: false, error: "Offline only is enabled" }));
        } else {
            scheduleRefresh();
        }
    }

    onHistoryMonthsChanged: {
        scheduleRefresh();
    }

    onShowOllamaChanged: {
        if (!showOllama && provider === "ollama" && pluginService && pluginId)
            pluginService.savePluginData(pluginId, "provider", "deepseek");
    }

    onProviderChanged: {
        if (!showOllama && provider === "ollama") {
            if (pluginService && pluginId)
                pluginService.savePluginData(pluginId, "provider", "deepseek");
            return;
        }
        pricingGeneration++;
        pricingBusy = false;
        drift = {
            state: "unknown",
            checkedAt: 0,
            source: "",
            found: [],
            expected: Schedule.scheduleWindows(provider),
            error: ""
        };
        publish(merge(snapshot, { drift: drift, provider: provider }));
        if (started)
            checkPricing(true);
    }

    onCustomSourceUrlChanged: {
        pricingGeneration++;
        pricingBusy = false;
        if (started)
            checkPricing(true);
    }

    onAutoCheckChanged: {
        pricingGeneration++;
        pricingBusy = false;
        if (started && autoCheck && !offlineOnly)
            checkPricing(true);
    }

    onPluginDataChanged: {
        // Settings are read through the bindings above; this handler only
        // ensures a first fetch after settings arrive.
        if (started && hasAnySource && !busy && snapshot.updatedAt === 0)
            scheduleRefresh();
    }
}

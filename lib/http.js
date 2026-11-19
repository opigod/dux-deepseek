// Minimal Qt QML XMLHttpRequest wrapper. No subprocesses, no external tools.

function available() {
    return typeof XMLHttpRequest !== "undefined";
}

function request(options, callback) {
    if (!available()) {
        callback({
            ok: false,
            status: 0,
            body: "",
            error: "XMLHttpRequest is not available"
        });
        return;
    }

    var xhr = new XMLHttpRequest();
    var finished = false;

    function finish(ok, status, body, error) {
        if (finished)
            return;
        finished = true;
        callback({
            ok: ok,
            status: status,
            body: body || "",
            error: error || ""
        });
    }

    try {
        xhr.open(options.method || "GET", options.url, true);
        if (options.timeout)
            xhr.timeout = options.timeout;
        var headers = options.headers || {};
        for (var name in headers) {
            try {
                xhr.setRequestHeader(name, headers[name]);
            } catch (headerError) {
                // A header the engine refuses to set is not fatal.
            }
        }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4)
                return;
            var status = xhr.status || 0;
            var body = xhr.responseText || "";
            if (status >= 200 && status < 300)
                finish(true, status, body, "");
            else
                finish(false, status, body, status === 0 ? "network error" : "HTTP " + status);
        };
        xhr.onerror = function () {
            finish(false, xhr.status || 0, xhr.responseText || "", "network error");
        };
        xhr.ontimeout = function () {
            finish(false, 0, "", "timeout");
        };
        xhr.send(options.body || null);
    } catch (error) {
        finish(false, 0, "", String(error));
    }
}

function getJson(url, headers, timeout, callback) {
    request({
        url: url,
        method: "GET",
        headers: headers || {},
        timeout: timeout || 15000
    }, function (response) {
        var parsed = null;
        if (response.body) {
            try {
                parsed = JSON.parse(response.body);
            } catch (error) {
                parsed = null;
            }
        }
        callback({
            ok: response.ok,
            status: response.status,
            json: parsed,
            body: response.body,
            error: response.error
        });
    });
}

function getText(url, headers, timeout, callback) {
    request({
        url: url,
        method: "GET",
        headers: headers || {},
        timeout: timeout || 15000
    }, function (response) {
        callback(response);
    });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        available: available,
        request: request,
        getJson: getJson,
        getText: getText
    };
}

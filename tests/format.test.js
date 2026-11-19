process.env.TZ = "Europe/Prague";

const { describe, it, expect } = require("bun:test");
const F = require("../lib/format.js");

describe("money formatting", () => {
    it("detects currency symbols", () => {
        expect(F.currencySymbol("CNY")).toBe("¥");
        expect(F.currencySymbol("USD")).toBe("$");
        expect(F.currencySymbol("EUR")).toBe("€");
        expect(F.currencySymbol("GBP")).toBe("GBP ");
    });

    it("formats balances and signed changes", () => {
        expect(F.formatMoney(42.5, "CNY")).toBe("¥42.50");
        expect(F.formatSignedMoney(-0.34, "CNY")).toBe("-¥0.34");
        expect(F.formatSignedMoney(12, "USD")).toBe("+$12.00");
        expect(F.formatCompactMoney(1234.5, "CNY")).toBe("¥1.2K");
    });
});

describe("token formatting", () => {
    it("uses K, M and B suffixes", () => {
        expect(F.formatTokens(999)).toBe("999");
        expect(F.formatTokens(1500)).toBe("1.5K");
        expect(F.formatTokens(15200000)).toBe("15.2M");
        expect(F.formatTokens(1200000000)).toBe("1.2B");
    });
});

describe("time formatting", () => {
    it("formats relative times", () => {
        const now = Date.UTC(2026, 10, 19, 12, 0);
        expect(F.relativeTime(now, now - 5000)).toBe("just now");
        expect(F.relativeTime(now, now - 5 * 60000)).toBe("5m ago");
        expect(F.relativeTime(now, now - 3 * 3600000)).toBe("3h ago");
        expect(F.relativeTime(now, 0)).toBe("never");
    });

    it("labels months", () => {
        expect(F.monthLabel(2026, 11)).toBe("Nov 2026");
        expect(F.monthKey(2026, 1)).toBe("2026-01");
    });
});

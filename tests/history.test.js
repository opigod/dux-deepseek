const { describe, it, expect } = require("bun:test");
const H = require("../lib/history.js");

const HOUR = 3600000;
const DAY = 86400000;
const NOW = Date.UTC(2026, 10, 19, 12, 0);

describe("balance history", () => {
    it("adds a point when the balance changes", () => {
        const history = H.append([], 42.5, NOW - HOUR);
        const next = H.append(history, 42.1, NOW);
        expect(next.length).toBe(2);
        expect(next[1].b).toBe(42.1);
    });

    it("throttles unchanged points to one per hour", () => {
        const history = H.append([], 42.5, NOW - 10 * 60000);
        const next = H.append(history, 42.5, NOW);
        expect(next.length).toBe(1);
    });

    it("prunes old points", () => {
        const history = [{ t: NOW - 40 * DAY, b: 30 }, { t: NOW - DAY, b: 40 }];
        const next = H.append(history, 41, NOW);
        expect(next.length).toBe(2);
        expect(next[1].b).toBe(41);
    });
});

describe("trends", () => {
    it("computes a 24h change from the nearest point", () => {
        const history = [
            { t: NOW - 25 * HOUR, b: 50 },
            { t: NOW - 12 * HOUR, b: 45 },
            { t: NOW, b: 42 }
        ];
        const trend = H.change(history, 42, NOW - 24 * HOUR, 2 * HOUR, NOW);
        expect(trend).not.toBeNull();
        expect(trend.value).toBeCloseTo(-8, 5);
    });

    it("returns null when history does not reach back far enough", () => {
        const history = [{ t: NOW - 2 * HOUR, b: 50 }, { t: NOW, b: 42 }];
        expect(H.change(history, 42, NOW - 24 * HOUR, 2 * HOUR, NOW)).toBeNull();
    });

    it("builds a downsampled sparkline", () => {
        const history = [];
        for (let i = 0; i < 100; i++)
            history.push({ t: NOW - i * HOUR, b: 50 - i * 0.01 });
        const values = H.sparkline(history, NOW, 7, 24);
        expect(values.length).toBe(24);
    });
});

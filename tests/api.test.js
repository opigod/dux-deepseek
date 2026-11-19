const { describe, it, expect } = require("bun:test");
const Api = require("../lib/api.js");

describe("platform request headers", () => {
    it("keeps a pasted bearer value", () => {
        const headers = Api.platformHeaders("Bearer abc.def");
        expect(headers.Authorization).toBe("Bearer abc.def");
    });

    it("adds Bearer to a raw token", () => {
        const headers = Api.platformHeaders("abc.def");
        expect(headers.Authorization).toBe("Bearer abc.def");
    });

    it("accepts a full authorization header row", () => {
        const headers = Api.platformHeaders("authorization: Bearer abc.def");
        expect(headers.Authorization).toBe("Bearer abc.def");
    });

    it("sends no cookie or browser-only headers", () => {
        const headers = Api.platformHeaders("session=abc; other=def");
        expect(headers.Cookie).toBeUndefined();
        expect(headers.Referer).toBeUndefined();
        expect(headers["User-Agent"]).toBeUndefined();
        expect(headers.Origin).toBeUndefined();
    });
});

describe("pricing request headers", () => {
    it("identifies the plugin instead of spoofing a browser", () => {
        const headers = Api.pricingHeaders();
        expect(headers["User-Agent"]).toContain("dux-deepseek");
        expect(headers.Cookie).toBeUndefined();
        expect(headers.Authorization).toBeUndefined();
    });
});

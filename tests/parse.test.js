const { describe, it, expect } = require("bun:test");
const P = require("../lib/parse.js");

const balanceJson = {
    is_available: true,
    balance_infos: [{
        currency: "CNY",
        total_balance: "42.50",
        granted_balance: "5.00",
        topped_up_balance: "37.50"
    }]
};

const multiBalanceJson = {
    is_available: true,
    balance_infos: [
        {
            currency: "USD",
            total_balance: "10.00",
            granted_balance: "0.00",
            topped_up_balance: "10.00"
        },
        {
            currency: "CNY",
            total_balance: "50.00",
            granted_balance: "5.00",
            topped_up_balance: "45.00"
        }
    ]
};

const zeroCnyBalanceJson = {
    is_available: true,
    balance_infos: [
        {
            currency: "CNY",
            total_balance: "0.00",
            granted_balance: "0.00",
            topped_up_balance: "0.00"
        },
        {
            currency: "USD",
            total_balance: "6.07",
            granted_balance: "0.00",
            topped_up_balance: "6.07"
        }
    ]
};

const summaryJson = {
    code: 0,
    msg: "ok",
    data: {
        biz_data: {
            normal_wallets: [{ currency: "CNY", balance: "37.50" }],
            bonus_wallets: [{ currency: "CNY", balance: "5.00" }],
            total_available_token_estimation: "15200000",
            monthly_token_usage: "1234567",
            monthly_costs: [{ amount: "8.12" }]
        }
    }
};

const amountJson = {
    code: 0,
    data: {
        biz_data: {
            total: [
                {
                    model: "deepseek-flash",
                    usage: [
                        { type: "PROMPT_CACHE_HIT_TOKEN", amount: "1000" },
                        { type: "PROMPT_CACHE_MISS_TOKEN", amount: "2000" },
                        { type: "RESPONSE_TOKEN", amount: "3000" }
                    ]
                },
                {
                    model: "deepseek-v4-pro",
                    usage: [
                        { type: "PROMPT_CACHE_HIT_TOKEN", amount: "500" },
                        { type: "RESPONSE_TOKEN", amount: "700" }
                    ]
                }
            ]
        }
    }
};

const dailyJson = {
    code: 0,
    data: {
        biz_data: {
            days: [
                {
                    date: "2026-11-02",
                    data: [
                        { model: "deepseek-flash", usage: [
                            { type: "PROMPT_CACHE_MISS_TOKEN", amount: "100" },
                            { type: "RESPONSE_TOKEN", amount: "200" }
                        ] }
                    ]
                },
                {
                    date: "2026-11-01",
                    data: [
                        { model: "deepseek-flash", usage: [
                            { type: "PROMPT_CACHE_HIT_TOKEN", amount: "50" },
                            { type: "RESPONSE_TOKEN", amount: "70" }
                        ] }
                    ]
                }
            ]
        }
    }
};

const costJson = {
    code: 0,
    data: {
        biz_data: [
            {
                total: [
                    { model: "deepseek-flash", usage: [{ type: "PROMPT_CACHE_HIT_COST", amount: "0.01" }] },
                    { model: "deepseek-v4-pro", usage: [{ type: "RESPONSE_COST", amount: "0.02" }] }
                ]
            },
            {
                total: [
                    { model: "deepseek-flash", usage: [{ type: "PROMPT_CACHE_MISS_COST", amount: "0.03" }] }
                ]
            }
        ]
    }
};

describe("official balance", () => {
    it("parses the balance endpoint", () => {
        const parsed = P.parseBalance(balanceJson);
        expect(parsed.ok).toBe(true);
        expect(parsed.currency).toBe("CNY");
        expect(parsed.total).toBe(42.5);
        expect(parsed.granted).toBe(5);
        expect(parsed.toppedUp).toBe(37.5);
        expect(parsed.available).toBe(true);
    });

    it("rejects an unexpected payload", () => {
        expect(P.parseBalance({}).ok).toBe(false);
    });

    it("selects the wallet matching the platform currency", () => {
        const usd = P.parseBalance(multiBalanceJson, "USD");
        expect(usd.currency).toBe("USD");
        expect(usd.total).toBe(10);
        expect(usd.infos.length).toBe(2);

        const cny = P.parseBalance(multiBalanceJson, "cny");
        expect(cny.currency).toBe("CNY");
        expect(cny.total).toBe(50);
    });

    it("uses a stable primary wallet without a preference", () => {
        const parsed = P.parseBalance(multiBalanceJson);
        expect(parsed.currency).toBe("CNY");
        expect(parsed.total).toBe(50);
    });

    it("ignores a stale zero-balance preferred wallet", () => {
        const parsed = P.parseBalance(zeroCnyBalanceJson, "CNY");
        expect(parsed.currency).toBe("USD");
        expect(parsed.total).toBe(6.07);
    });

    it("keeps a positive preferred wallet", () => {
        const parsed = P.parseBalance(multiBalanceJson, "USD");
        expect(parsed.currency).toBe("USD");
        expect(parsed.total).toBe(10);
    });
});

describe("platform summary", () => {
    it("parses wallets and monthly summary", () => {
        const parsed = P.parsePlatformSummary(summaryJson);
        expect(parsed.ok).toBe(true);
        expect(parsed.normal).toBe(37.5);
        expect(parsed.bonus).toBe(5);
        expect(parsed.total).toBe(42.5);
        expect(parsed.tokenEstimation).toBe(15200000);
        expect(parsed.monthlyTokenUsage).toBe(1234567);
        expect(parsed.monthlyCost).toBeCloseTo(8.12, 2);
    });

    it("recognises an expired session", () => {
        const parsed = P.parsePlatformSummary({ code: 40002, msg: "Missing Token", data: null });
        expect(parsed.ok).toBe(false);
        expect(parsed.authExpired).toBe(true);
    });
});

describe("usage", () => {
    it("sums input and output tokens by type", () => {
        const parsed = P.parseUsageAmount(amountJson);
        expect(parsed.ok).toBe(true);
        expect(parsed.input).toBe(3500);
        expect(parsed.output).toBe(3700);
        expect(parsed.models.length).toBe(2);
    });

    it("sorts daily points and parses both models", () => {
        const parsed = P.parseDaily(dailyJson);
        expect(parsed.ok).toBe(true);
        expect(parsed.days.length).toBe(2);
        expect(parsed.days[0].day).toBe(1);
        expect(parsed.days[0].input).toBe(50);
        expect(parsed.days[0].output).toBe(70);
        expect(parsed.days[1].day).toBe(2);
    });

    it("sums cost periods", () => {
        const parsed = P.parseCost(costJson);
        expect(parsed.ok).toBe(true);
        expect(parsed.cost).toBeCloseTo(0.06, 5);
    });

    it("combines amount and cost", () => {
        const parsed = P.parseCurrentMonth(amountJson, costJson);
        expect(parsed.ok).toBe(true);
        expect(parsed.input).toBe(3500);
        expect(parsed.output).toBe(3700);
        expect(parsed.cost).toBeCloseTo(0.06, 5);
    });
});

describe("type classification", () => {
    it("classifies known and future token types", () => {
        expect(P.classifyType("PROMPT_CACHE_HIT_TOKEN")).toBe("input");
        expect(P.classifyType("PROMPT_CACHE_MISS_TOKEN")).toBe("input");
        expect(P.classifyType("RESPONSE_TOKEN")).toBe("output");
        expect(P.classifyType("COMPLETION_TOKENS")).toBe("output");
        expect(P.classifyType("REASONING_TOKEN")).toBe("output");
        expect(P.classifyType("SOMETHING_NEW")).toBe("other");
    });
});

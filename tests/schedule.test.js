process.env.TZ = "Europe/Prague";

const { describe, it, expect } = require("bun:test");
const S = require("../lib/schedule.js");

const THU_0100 = Date.UTC(2026, 10, 19, 1, 0); // Thu 2026-11-19
const THU_0059 = Date.UTC(2026, 10, 19, 0, 59);
const THU_0400 = Date.UTC(2026, 10, 19, 4, 0);
const THU_0600 = Date.UTC(2026, 10, 19, 6, 0);
const THU_1000 = Date.UTC(2026, 10, 19, 10, 0);
const THU_0259 = Date.UTC(2026, 10, 19, 2, 59);

describe("DeepSeek peak windows", () => {
    it("is off-peak before 01:00 UTC", () => {
        expect(S.isPeakAt(THU_0059, "deepseek")).toBe(false);
    });

    it("is peak from 01:00 to 04:00 UTC", () => {
        expect(S.isPeakAt(THU_0100, "deepseek")).toBe(true);
        expect(S.isPeakAt(THU_0259, "deepseek")).toBe(true);
        expect(S.isPeakAt(THU_0400, "deepseek")).toBe(false);
    });

    it("is peak from 06:00 to 10:00 UTC", () => {
        expect(S.isPeakAt(THU_0600, "deepseek")).toBe(true);
        expect(S.isPeakAt(THU_1000, "deepseek")).toBe(false);
    });

    it("is off-peak all weekend", () => {
        const saturday = Date.UTC(2026, 10, 21, 2, 0);
        const sunday = Date.UTC(2026, 10, 22, 8, 0);
        expect(S.isPeakAt(saturday, "deepseek")).toBe(false);
        expect(S.isPeakAt(sunday, "deepseek")).toBe(false);
    });

    it("is off-peak on Chinese public holidays", () => {
        expect(S.isPeakAt(Date.UTC(2026, 9, 1, 2, 0), "deepseek")).toBe(false);
        expect(S.isPeakAt(Date.UTC(2026, 1, 17, 2, 0), "deepseek")).toBe(false);
    });

    it("is off-peak on the 2027 holiday estimate", () => {
        // Mon 2027-02-08 inside the estimated Spring Festival break.
        expect(S.isPeakAt(Date.UTC(2027, 1, 8, 2, 0), "deepseek")).toBe(false);
    });
});

describe("holiday data coverage", () => {
    it("warns that 2027 dates are provisional", () => {
        expect(S.holidayDataWarning(Date.UTC(2027, 1, 8, 2, 0), "deepseek")).toContain("provisional");
    });

    it("is quiet for published years", () => {
        expect(S.holidayDataWarning(Date.UTC(2026, 10, 19, 3, 0), "deepseek")).toBe("");
    });

    it("warns when a year has no holiday data", () => {
        expect(S.holidayDataWarning(Date.UTC(2028, 0, 5, 2, 0), "deepseek")).toContain("No 2028 holiday data");
    });

    it("is quiet for providers that bill holidays as peak", () => {
        expect(S.holidayDataWarning(Date.UTC(2027, 1, 8, 2, 0), "ollama")).toBe("");
    });
});

describe("Ollama peak windows", () => {
    it("is peak from 12:00 to 18:00 UTC on weekdays", () => {
        expect(S.isPeakAt(Date.UTC(2026, 10, 19, 12, 0), "ollama")).toBe(true);
        expect(S.isPeakAt(Date.UTC(2026, 10, 19, 18, 0), "ollama")).toBe(false);
    });

    it("is off-peak on weekends", () => {
        expect(S.isPeakAt(Date.UTC(2026, 10, 21, 13, 0), "ollama")).toBe(false);
    });
});

describe("snapshot", () => {
    it("counts down to the next tier flip", () => {
        const snap = S.snapshot(Date.UTC(2026, 10, 19, 3, 0), "deepseek");
        expect(snap.isPeak).toBe(true);
        expect(snap.secondsToNext).toBe(3600);
        expect(snap.progress).toBeCloseTo(2 / 3, 2);
    });

    it("spans the weekend for the Friday 10:00 off-peak block", () => {
        const friday = Date.UTC(2026, 10, 20, 10, 0);
        const monday = Date.UTC(2026, 10, 23, 1, 0);
        const snap = S.snapshot(friday, "deepseek");
        expect(snap.isPeak).toBe(false);
        expect(snap.secondsToNext).toBe((monday - friday) / 1000);
    });

    it("reports progress inside a short off-peak gap", () => {
        const snap = S.snapshot(Date.UTC(2026, 10, 19, 5, 0), "deepseek");
        expect(snap.isPeak).toBe(false);
        expect(snap.progress).toBeCloseTo(0.5, 2);
    });
});

describe("timezone window lines", () => {
    it("formats UTC, Beijing and local Prague time", () => {
        expect(S.windowLine(THU_0100, "deepseek", "utc"))
            .toBe("01:00-04:00 · 06:00-10:00");
        expect(S.windowLine(THU_0100, "deepseek", "beijing"))
            .toBe("09:00-12:00 · 14:00-18:00");
        // 2026-11-19 is CET (UTC+1).
        expect(S.windowLine(THU_0100, "deepseek", "local"))
            .toBe("02:00-05:00 · 07:00-11:00");
    });

    it("handles summer time", () => {
        const summer = Date.UTC(2026, 6, 1, 2, 0); // Wednesday, CEST (UTC+2)
        expect(S.windowLine(summer, "deepseek", "local"))
            .toBe("03:00-06:00 · 08:00-12:00");
    });

    it("returns nil on off days", () => {
        expect(S.windowLine(Date.UTC(2026, 10, 21, 2, 0), "deepseek", "utc")).toBeNull();
    });
});

describe("holiday ranges", () => {
    it("detects an active holiday", () => {
        const info = S.holidayRange(Date.UTC(2026, 9, 2, 12, 0));
        expect(info.active).toBe(true);
        expect(info.endDay).toBe(Math.floor(Date.UTC(2026, 9, 7) / 86400000));
        expect(info.text).toContain("until Oct 8");
    });

    it("finds the next upcoming holiday", () => {
        const info = S.holidayRange(Date.UTC(2026, 8, 28, 12, 0));
        expect(info.active).toBe(false);
        expect(info.inDays).toBe(3);
        expect(info.text).toContain("Oct 1-7");
    });
});

describe("pricing page parsing", () => {
    const deepseekPage = "Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday, excluding Chinese public holidays.";
    const ollamaPage = "Off-peak pricing apply outside 12:00 and 18:00 UTC on weekdays and all day on weekends.";

    it("reads DeepSeek peak windows", () => {
        expect(S.windowsFromPage(deepseekPage, "deepseek"))
            .toEqual(["01:00-04:00", "06:00-10:00"]);
    });

    it("reads Ollama peak windows", () => {
        expect(S.windowsFromPage(ollamaPage, "ollama")).toEqual(["12:00-18:00"]);
    });

    it("compares order independent window sets", () => {
        expect(S.sameWindows(["06:00-10:00", "01:00-04:00"], ["01:00-04:00", "06:00-10:00"]))
            .toBe(true);
        expect(S.sameWindows(["01:00-04:00"], S.scheduleWindows("deepseek"))).toBe(false);
    });

    it("returns nil when no windows are present", () => {
        expect(S.windowsFromPage("nothing here", "deepseek")).toBeNull();
    });
});

describe("formatting", () => {
    it("formats countdowns and clocks", () => {
        expect(S.formatCountdown(0)).toBe("<1m");
        expect(S.formatCountdown(65)).toBe("1m");
        expect(S.formatCountdown(3660)).toBe("1h1m");
        expect(S.formatCountdown(90000)).toBe("1d1h");
        expect(S.formatBigCountdown(90000)).toBe("1d 1h 0m");
        expect(S.formatHMS(3661)).toBe("01:01:01");
    });
});

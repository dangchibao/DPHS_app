import { readFileSync } from "node:fs";
import { it, expect } from "vitest";
import { parseTailorConfig, tailorFee } from "../src/tailoring";
const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/tailoring-surcharge.json", "utf8"),
) as Record<string, unknown>[];
for (const v of vectors)
  it(String(v.name), () => {
    const run = () => {
      const config = parseTailorConfig({
        base_fee: v.base_fee ?? 10000,
        rates: { chest: { threshold: 1000, step: 50, amount: 15000 } },
        options: { rush: { label: "May gấp", amount: 20000 } },
      });
      const measurements: Record<string, number> = {
        chest: Number(v.chest),
        waist: 800,
        hips: 1000,
        shirt_length: 700,
        trousers_length: 900,
        shoulder: 450,
        height: 1700,
        weight: 70000,
      };
      if (v.omit) delete measurements[String(v.omit)];
      return tailorFee(config, measurements, v.options ?? []);
    };
    if (v.reject) expect(run).toThrow();
    else expect(run()).toBe(v.expected);
  });
it("Phụ thu cân nặng dùng gram và cộng cùng số đo khác", () => {
  const config = parseTailorConfig({
    base_fee: 0,
    rates: {
      weight: { threshold: 70000, step: 5000, amount: 10000 },
      chest: { threshold: 1000, step: 50, amount: 15000 },
    },
    options: {},
  });
  expect(
    tailorFee(
      config,
      {
        chest: 1001,
        waist: 800,
        hips: 1000,
        shirt_length: 700,
        trousers_length: 900,
        shoulder: 450,
        height: 1700,
        weight: 75001,
      },
      [],
    ),
  ).toBe(35000);
  expect(() =>
    parseTailorConfig({
      base_fee: 0,
      rates: { chest: { threshold: 1, step: 0, amount: 1 } },
      options: {},
    }),
  ).toThrow();
});

import { defineConfig } from "vitest/config";
export default defineConfig({
  test: { include: ["load/**/*.test.ts"], testTimeout: 120000 },
});

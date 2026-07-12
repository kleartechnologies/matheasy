import { defineConfig } from "vitest/config";

// Tests live in `test/` (outside `src/`) so the `tsc` build never compiles them
// into the deployed `lib/` bundle.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});

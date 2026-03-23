import { defineWorkspace } from "vitest/config"

export default defineWorkspace([
  {
    test: {
      include: ["packages/**/*.{test,spec}.{js,mjs,cjs,ts,tsx}"],
      passWithNoTests: true,
    },
  },
])

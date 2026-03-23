import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          include: ["packages/**/*.{test,spec}.{js,mjs,cjs,ts,tsx}"],
          passWithNoTests: true,
        },
      },
    ],
  },
})

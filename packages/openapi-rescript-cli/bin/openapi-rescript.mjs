#!/usr/bin/env node

import { main } from "./Bin.bs.js";

function structuredDiagnostic(message) {
  return {
    path: [],
    message,
  };
}

main().catch((error) => {
  process.stderr.write(
    `${JSON.stringify(structuredDiagnostic(error instanceof Error ? error.message : String(error)))}\n`,
  );
  process.exitCode = 1;
});

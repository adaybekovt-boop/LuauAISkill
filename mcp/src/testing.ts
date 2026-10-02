// Test-only entry: exposes the pure modules so test/parity.test.mjs can compare them with tools/*.py.
export { deprecatedOf, lookup, search } from "./api";
export { readDoc, listDocs } from "./docs";
export { formatFindings, scan } from "./legacy";
export { searchSkill, sections, stem } from "./search";
export { meta } from "./generated/data.js";

import { describe, expect, it } from "vitest";
import { TOOLS, TOOL_META, type Tool } from "./tools";

describe("TOOLS / TOOL_META", () => {
  it("expose 8 outils DevOps", () => {
    expect(TOOLS).toHaveLength(8);
    expect(TOOLS).toContain("kubernetes");
    expect(TOOLS).toContain("terraform");
  });

  it("fournit un label et un blurb pour chaque outil", () => {
    for (const tool of TOOLS) {
      const meta = TOOL_META[tool as Tool];
      expect(meta.label.length).toBeGreaterThan(0);
      expect(meta.blurb.length).toBeGreaterThan(0);
    }
  });

  it("n'a pas de clé orpheline dans TOOL_META", () => {
    expect(Object.keys(TOOL_META).sort()).toEqual([...TOOLS].sort());
  });
});

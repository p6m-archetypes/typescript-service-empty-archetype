--- The p6m overlay standards (E1–E7), held against the TypeScript "empty" archetype — a platform
--- overlay that retrofits an EXISTING application. See prova-p6m-standards docs/standards.md §2b.
---
--- Every expectation comes from the `p6m` oracle, parameterized by the SAME tactical answers the
--- archetype renders from — never from this file. That is the point: all six language overlays are
--- held to one bar, and no one of them can quietly define its own.
---
--- Nothing here builds or boots. An overlay generates no project, so there is no code to compile
--- and no service to probe; the suite renders and inspects, and a runner needs prova and nothing
--- else (E7). What it holds instead are the seams a retrofit actually breaks on: writing project
--- scaffolding into someone else's repo, clobbering the application's own files, and CI/CD
--- artifacts that disagree with each other about the image name.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

local p6m = require("p6m")

-- Two variants, covering both axes an overlay actually has. A hollow REST rendering is the
-- retrofit most legacy applications get; the gRPC rendering with the full resource set flips the
-- injected port variable, the declared port protocol, the port defaults, and every
-- resourceRequirement — and uses a single-word application name, where a name-derivation bug that
-- a two-word name hides will show.
local VARIANTS = {
  {
    application = "Example Service",
    solution = "acme-platform",
    protocol = "REST",
  },
  {
    application = "Billing",
    solution = "acme-payments",
    protocol = "gRPC",
    persistence = "PostgreSQL",
    cache = "Redis",
    messaging = "Kafka",
    messaging_access = "consume",
  },
}

local specs = {}
for i, v in ipairs(VARIANTS) do
  specs[i] = p6m.empty.spec{
    language = "typescript",
    application = v.application,
    solution = v.solution,
    registry = "ghcr.io/acme",
    protocol = v.protocol,
    persistence = v.persistence,
    cache = v.cache,
    messaging = v.messaging,
    messaging_access = v.messaging_access,
  }
end

for _, overlay in ipairs(specs) do
  prova.group(overlay.label, { tags = { "standards" } }, function(g)
    p6m.empty.standards.rendering(g, p6m.empty.render(overlay), overlay)
  end)
end

-- E2 and E7 are properties of the archetype repo, not of a variant — held once.
prova.group("typescript-empty: the archetype itself", { tags = { "standards" } }, function(g)
  -- No pin_spec: prova-p6m-standards v1.7 shipped the overlay layer on 2026-07-27 and this suite
  -- is pinned to the released @v1 tag, so E7's released-tag assertion is a full proof.
  p6m.empty.standards.archetype(g, specs[1])
end)

-- TypeScript Service Platform Overlay ("empty" archetype).
--
-- Generates ONLY the platform servicing layer — CI/CD, Kubernetes platform
-- manifests, container builds, and repo hygiene files — with no project
-- scaffolding and no domain code. Run it against an EXISTING project to
-- retrofit it: everything renders in place at the destination root.
--
--   archetect render .../typescript-service-empty-archetype /path/to/existing-project
--
-- See docs/specs/empty-service-archetype.md in the archetype-ecosystem repo.

local context = Context.new()

-- Identity (feeds manifest names + image path; NOT used as an output subdir)
require("author").prompt(context)
require("org").prompt(context)

context:set("suffix_options", { "Service", "Orchestrator", "Adapter", "Router", "Gateway" })
context:set("suffix_default", "Service")
require("project").prompt(context)

context:set("repo_name", context:get("project-name"))
context:set("github_owner", context:get("org-solution-name"))

-- No TypeScript-specific identity prompt: nothing the overlay renders (CI,
-- Dockerfiles, platform manifests) references a language identity key (the
-- typescript-ci workflows use only version-level/secrets; the Dockerfiles use
-- only the ports), so prompting would be noise.

-- Service configuration
require("ports").prompt(context, { ports = { { "service", help = "HTTP port for the service" }, "management", "debug" } })

-- Resources — prompted to drive the platform manifests' resourceRequirements
-- ONLY. No connection code is woven (that's a project concern, and this overlay
-- never touches project code). object_storage is omitted: it produces no
-- platform manifest artifact.
context:prompt_select("Persistence:", "persistence", {
    "None", "PostgreSQL", "MySQL",
}, { default = "None" })

context:prompt_select("Cache:", "cache", {
    "None", "Redis",
}, { default = "None" })

context:prompt_select("Messaging:", "messaging", {
    "None", "Kafka", "Pulsar",
}, { default = "None" })

if context:get("messaging") ~= "None" then
    context:prompt_select("Messaging Access:", "messaging_access", {
        "produce", "consume",
    }, { default = "produce" })
else
    context:set("messaging_access", "produce")
end

context:set("has_persistence", context:get("persistence") ~= "None")
context:set("has_cache",       context:get("cache")       ~= "None")
context:set("has_messaging",   context:get("messaging")   ~= "None")

-- EditorConfig + gitignore (pre-seeded; library skips interactive prompt)
local editor_config = require("editor-config")
editor_config.prompt(context, {
    languages     = { "JavaScript", "YAML", "Markdown" },
    gitattributes = true,
})

local gitignore = require("gitignore")
gitignore.prompt(context, {
    ignores = { "JavaScript", "Claude", "IDEA", "VSCode", "macOS" },
})

-- SCM (opt-in: default = None)
local scm = require("scm")
scm.prompt(context)

if archetype.switches.is_enabled("debug-context") then
    log.info(archetype.description .. " Context:")
    output.print(format.yaml(context))
end

-- Everything renders IN PLACE at the destination root (no project-name subdir).
local dest = {}

-- Container builds (the only files the archetype carries directly)
directory.render("contents/base", context)

-- CI workflows
local ci = require("typescript-ci")
ci.render(context, dest)

-- Platform manifests (+ resourceRequirements from the resource prompts above)
context:set("protocol", "REST")
local platform = require("platform-application-manifests")
platform.prompt(context)
platform.finalize(context, dest)

-- EditorConfig, gitignore, SCM finalize (side effects last)
editor_config.finalize(context, dest)
gitignore.finalize(context, dest)
scm.finalize(context)

-- Archive (zip / tarball switches for Ybor Studio)
require("archiver").finalize(context)

return context

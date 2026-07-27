-- TypeScript Service Platform Overlay ("empty" archetype).
--
-- Generates ONLY the platform servicing layer — CI/CD workflows, Kubernetes platform
-- manifests, container builds, and repo hygiene files — with no project
-- scaffolding and no domain code. Run it against an EXISTING project to retrofit it:
-- everything renders in place at the destination root.
--
--   archetect render .../typescript-service-empty-archetype /path/to/existing-project
--
-- The prompt surface is the TACTICAL MINIMUM (prova-p6m-standards docs/standards.md
-- §2b, E1–E2): the deployment facts the rendered CI/CD actually consumes, and nothing
-- else. No author identity, no org × solution split, no project prefix/suffix — a
-- service archetype needs those to name code it is generating, and this generates none.
-- The overlay's own suite holds that bar: it renders from the tactical answers with no
-- defaults fallback, so a prompt whose answer nothing reads fails the build.

local context = Context.new()

-- E1: the application name is the ONLY name asked. It is at once the container image
-- name, the PlatformApplication name, the directory CD writes into in the platform
-- manifests repo, and the Tilt resource. Cases.programming() derives project-name /
-- project_name / ProjectName — every shape the carried files and the composed CI and
-- platform-manifest libraries reference.
context:prompt_text("Application Name:", "project_name", {
    cases       = Cases.programming(),
    placeholder = "billing-service",
    help        = "Kebab-case. The container image name, the PlatformApplication name, and "
        .. "the directory CD writes into in the platform manifests repo.",
})

-- The namespace prefix. The platform operator derives the solution and the environment
-- back out of `{solution}-{application}-{env}`, which is what lets Shared resources
-- (e.g. a Pulsar topic) be shared across applications in the same solution + environment.
context:prompt_text("Solution Slug:", "org_solution_name", {
    cases       = Cases.programming(),
    placeholder = "acme-payments",
    help        = "Kebab-case. Prefixes the Kubernetes namespace: {solution}-{application}-{env}.",
})

-- Where CI publishes the image to. No default — registry hostnames are company-specific.
context:prompt_text("Image Registry:", "image_registry", {
    placeholder = "ghcr.io",
    help        = "Container image registry hostname (e.g. ghcr.io, "
        .. "123456789.dkr.ecr.us-east-1.amazonaws.com).",
})

-- The transport the existing application already speaks. It decides which port variable
-- the manifests inject (SERVER_PORT vs GRPC_PORT) and the protocol the ports declare —
-- so a gRPC service being platform-ized gets a correct manifest, not an HTTP one.
context:prompt_select("Protocol:", "protocol", {
    "REST", "gRPC", "GraphQL",
}, { default = "REST" })

-- The ports the manifests publish and the readiness probe targets. `debug` is not asked:
-- nothing the overlay renders publishes it.
require("ports").prompt(context, {
    ports = {
        { "service", help = "The port the application already serves traffic on" },
        { "management", help = "The port /health and /metrics are served on" },
    },
})

-- Platform resources. These drive the platform manifests' resourceRequirements ONLY —
-- the platform provisions them and injects connection secrets. No connection code is
-- woven: that is project code, and this overlay never touches project code.
-- object_storage is omitted: it produces no platform manifest artifact.
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

-- The platform manifest names a database as `{{ prefix_name }}_{{ suffix_name }}`. A
-- service archetype fills those from its identity prompts; an overlay has none, so it
-- names the platform-provisioned database after the application: `<application>_db`.
-- One rule, no special case for single-word application names, and unmistakably distinct
-- from whatever database the legacy application may already carry.
context:set("prefix_name", context:get("project_name"))
context:set("suffix_name", "db")

-- SCM publishing (opt-in, default None) addresses the repository by these; both derive
-- from the answers above rather than asking again.
context:set("repo_name", context:get("project-name"))
context:set("github_owner", context:get("org-solution-name"))

-- EditorConfig + gitignore (pre-seeded; the libraries skip their interactive prompt).
-- On a retrofit these land only if the application does not already have its own —
-- archetect never overwrites an existing path (E4).
local editor_config = require("editor-config")
editor_config.prompt(context, {
    languages     = { "JavaScript", "YAML", "Markdown" },
    gitattributes = true,
})

local gitignore = require("gitignore")
gitignore.prompt(context, {
    ignores = { "JavaScript", "Claude", "IDEA", "VSCode", "macOS" },
})

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

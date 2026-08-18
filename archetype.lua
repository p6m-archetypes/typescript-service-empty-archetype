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

-- Identity (S1). One library, one implementation — the same surface every service shape asks,
-- so an overlay and a service archetype cannot drift on what a project or a solution is called.
--
-- E1 still holds: the project name is the ONLY name asked, and it is at once the container image
-- name, the PlatformApplication name, the directory CD writes into in the platform manifests repo,
-- and the Tilt resource. The solution slug prefixes the Kubernetes namespace
-- (`{solution}-{application}-{env}`), which is what lets Shared resources be shared across
-- applications in the same solution and environment.
--
-- `entity = false`: an overlay generates no domain code, so a CRUD entity would be a prompt whose
-- answer nothing reads (E2 / S1b).
local identity = require("p6m-identity")
identity.prompt(context, { entity = false })

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

-- How to build and run the EXISTING application. These two are the only facts about the
-- application's internals the overlay needs, and it cannot guess them: a retrofit target may be a
-- single crate or a workspace, a flat module or a multi-module build, src/ layout or not. Defaults
-- match what this language's own p6m service archetype produces, so a greenfield-shaped repo needs
-- no answer; anything else overrides one line instead of rewriting a Dockerfile.
context:prompt_text("Build Command:", "build_command", {
    default = "pnpm build",
    help    = "Built inside the builder image, after the package manager install.",
})

context:prompt_text("Runtime Artifact:", "runtime_artifact", {
    default = "dist/index.js",
    help    = "Entry module the build produced, run with node.",
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

-- The platform-provisioned database. An overlay retrofits an EXISTING application, which may
-- already carry a database of its own, so it names this one `<application>_db` — unmistakably
-- distinct, with no special case for single-word application names. (This used to be smuggled
-- through `prefix_name` + `suffix_name`, an identity decomposition that meant nothing here;
-- `database_name` is the manifests library's own key for it.)
context:set("database_name", context:get("project_name") .. "_db")

-- SCM publishing (opt-in, default None) addresses the repository by these; both derive
-- from the answers above rather than asking again.

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

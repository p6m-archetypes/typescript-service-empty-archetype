local context = Context.new()

-- The prompt surface is laid out in PAGES and SECTIONS — the author's grouping intent, carried to
-- every renderer: a wizard step in Ybor Studio, a titled heading in the terminal, a block comment
-- in an answers template. Keys are PINNED because a wizard routes on them while titles are display
-- text, and pages appear and disappear between rounds of the hybrid drive.
--
-- The page and section keys are the FLEET's, shared with every service archetype so a form reads
-- identically whatever the shape. What differs here is what an overlay actually asks: no entity
-- (it generates no domain code), and a Container Build page no service archetype needs, because a
-- retrofit cannot assume the application's internal layout (E1b).
local identity = require("p6m-identity")

context:page({ title = "Project", key = "project",
               help = "The application being platform-ized." }, function(ctx)
    -- E1: the project name is the ONLY name asked. It is at once the container image name, the
    -- PlatformApplication name, the directory CD writes into in the platform manifests repo, and
    -- the Tilt resource. `entity = false`: an overlay generates no domain code, so a CRUD entity
    -- would be a prompt whose answer nothing reads (E2 / S1b).
    identity.prompt_project(ctx, { entity = false })

    ctx:section({ title = "Platform", key = "platform",
                  help = "Where this application deploys and publishes." }, function(ctx)
        -- The solution slug prefixes the Kubernetes namespace (`{solution}-{application}-{env}`),
        -- which is what lets Shared resources be shared across a solution and environment.
        identity.prompt_solution(ctx)

        -- The registry prompt comes from the manifests library, the same as every other shape.
        -- It used to be a second copy here, and the copies drifted: this one carried a `ghcr.io`
        -- placeholder while the library's said `registry.example.com`, so a placeholder-driven
        -- form filler produced different values for the same field depending on the flavor.
        require("platform-application-manifests").prompt_registry(ctx)
    end)

    ctx:section({ title = "Service", key = "service",
                  help = "How the existing application serves traffic." }, function(ctx)
        -- The transport the existing application already speaks. It decides which port variable
        -- the manifests inject (SERVER_PORT vs GRPC_PORT) and the protocol the ports declare — so
        -- a gRPC service being platform-ized gets a correct manifest, not an HTTP one.
        ctx:prompt_select("Protocol:", "protocol", { "REST", "gRPC", "GraphQL" },
            { default = "REST" })

        -- The ports the manifests publish and the readiness probe targets. `debug` is not asked:
        -- nothing the overlay renders publishes it.
        require("ports").prompt(ctx, {
            ports = {
                { "service", help = "The port the application already serves traffic on" },
                { "management", help = "The port /health and /metrics are served on" },
            },
        })
    end)
end)

context:page({ title = "Container Build", key = "container_build",
               help = "How to build and run the EXISTING application. An overlay retrofits a repo "
                   .. "it did not generate, so it cannot assume the layout (E1b)." }, function(ctx)
    ctx:prompt_text("Build Command:", "build_command", {
        default = "pnpm build",
        help    = "Built inside the builder image, after the package manager install.",
    })

    -- OPTIONAL with a placeholder, like every other overlay: blank means the
    -- conventional value. Half the overlays had a literal default here and half a
    -- derived one, so the field looked pre-answered in three flavors and empty in
    -- three — the same prompt reading two different ways.
    ctx:prompt_text("Runtime Artifact:", "runtime_artifact", {
        optional    = true,
        placeholder = "dist/index.js",
        help        = "Entry module the build produced, run with node. Leave blank to use dist/index.js.",
    })
    if ctx:get("runtime_artifact") == nil or ctx:get("runtime_artifact") == "" then
        ctx:set("runtime_artifact", "dist/index.js")
    end
end)

context:page({ title = "Resources", key = "resources",
               help = "Platform-provisioned backing services. These drive the manifests' resourceRequirements only — no connection code is woven into the application." }, function(ctx)
    -- Platform resources. These drive the platform manifests' resourceRequirements ONLY —
    -- the platform provisions them and injects connection secrets. No connection code is
    -- woven: that is project code, and this overlay never touches project code.
    -- object_storage is omitted: it produces no platform manifest artifact.
    ctx:prompt_select("Persistence:", "persistence", {
        "None", "PostgreSQL", "MySQL",
    }, { default = "None" })

    ctx:prompt_select("Cache:", "cache", {
        "None", "Redis",
    }, { default = "None" })

    ctx:prompt_select("Messaging:", "messaging", {
        "None", "Kafka", "Pulsar",
    }, { default = "None" })

    if ctx:get("messaging") ~= "None" then
        ctx:prompt_select("Messaging Access:", "messaging_access", {
            "produce", "consume",
        }, { default = "produce" })
    else
        ctx:set("messaging_access", "produce")
    end
end)
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
context:page({ title = "Source Control", key = "source_control",
               help = "Optionally create and publish the repository." }, function(ctx)
    scm.prompt(ctx)
end)

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

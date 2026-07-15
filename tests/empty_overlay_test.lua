--- Acceptance suite for the TypeScript "empty" service archetype - a platform overlay. Unlike the
--- service archetypes, this one generates NO project scaffolding and NO domain code: run against an
--- existing project, it renders only the platform servicing layer (CI/CD workflows, Kubernetes
--- platform manifests, container builds, repo hygiene files) IN PLACE at the destination root.
---
--- There is therefore nothing to build or boot - the suite is purely static: it verifies the overlay
--- renders the expected platform files, that it does NOT emit any project scaffolding, that the
--- generated manifests parse and are wired with the project identity, and that no template markers
--- leak through. No toolchain required.
---
--- prova's in-process archetect engine renders once per run (prova.toml pins jobs = 1); the suite
--- shares that single rendered tree.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

local SRC = "."

local ANSWERS = {
  author_name    = "Test Author",
  author_email   = "test@example.com",
  org_name       = "acme",
  solution_name  = "platform",
  prefix_name    = "Example",
  suffix_name    = "Service",
  image_registry = "ghcr.io/acme",
}

-- The overlay renders in place at the destination root (project-name is example-service, used for
-- manifest names and the image path - NOT as an output subdirectory).
local PROJECT_NAME = "example-service"

local EXPECTED_FILES = {
  ".editorconfig",
  ".gitattributes",
  ".gitignore",
  ".github/workflows/build.yaml",
  ".github/workflows/cut-tag.yaml",
  ".platform/docker/local/Dockerfile",
  ".platform/docker/prd/Dockerfile",
  ".platform/kubernetes/base/application.yaml",
  ".platform/kubernetes/base/application_customizations.yaml",
  ".platform/kubernetes/base/kustomization.yaml",
  ".platform/kubernetes/dev/kustomization.yaml",
  ".platform/kubernetes/dev/namespace.yaml",
  ".platform/kubernetes/stg/kustomization.yaml",
  ".platform/kubernetes/prd/kustomization.yaml",
}

-- Files that would exist for a full service archetype but MUST NOT for an overlay - proving this
-- archetype only lays down the platform layer and never touches project code.
local ABSENT_FILES = {
  "package.json",
  "tsconfig.json",
  "src",
  "tests",
}

-- Render once for the whole suite. The overlay renders in place, so the render tree root IS the
-- retrofitted project directory (no project-name subdir).
local project = prova.fixture("typescript-empty:project", Scope.Suite, function(ctx)
  return archetect.render{
    source = SRC,
    answers = ANSWERS,
    destination = ctx:tempdir(),
    defaults = true,
  }
end)

prova.group("typescript-empty overlay", function(g)
  g:test("renders the platform servicing layer in place", function(t)
    local root = t:use(project).path
    t:expect_all(function()
      for _, f in ipairs(EXPECTED_FILES) do
        t:expect(fs.exists(root .. "/" .. f), f):is_true()
      end
    end)
  end)

  g:test("emits no project scaffolding or domain code", function(t)
    local root = t:use(project).path
    t:expect_all(function()
      for _, f in ipairs(ABSENT_FILES) do
        t:expect(fs.exists(root .. "/" .. f), f .. " absent"):is_false()
      end
    end)
  end)

  g:test("wires project identity and image registry into the platform manifest", function(t)
    local root = t:use(project).path
    local app = yaml.parse(fs.read(root .. "/.platform/kubernetes/base/application.yaml"))
    t:expect(app.kind, "manifest kind"):equals("PlatformApplication")
    t:expect(app.metadata.name, "manifest name"):equals(PROJECT_NAME)
    -- The image path is assembled from the image registry + org/solution + project-name.
    t:expect(app.spec.deployment.image, "image path"):contains("ghcr.io/acme")
    t:expect(app.spec.deployment.image, "image path"):contains(PROJECT_NAME)
  end)

  g:test("renders valid, non-empty kubernetes manifests", function(t)
    local root = t:use(project).path
    local manifests = fs.glob(root, ".platform/kubernetes/**/*.yaml")
    t:expect(#manifests > 0, "at least one k8s manifest"):is_true()
    t:expect_all(function()
      for _, m in ipairs(manifests) do
        local docs = yaml.parse_all(fs.read(m))
        t:expect(#docs > 0, m .. " has ≥1 document"):is_true()
      end
    end)
  end)

  g:test("leaves no unrendered template markers", function(t)
    t:expect(t:use(project)):is_fully_rendered()
  end)
end)

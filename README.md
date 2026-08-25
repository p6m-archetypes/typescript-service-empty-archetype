# typescript-service-empty-archetype

TypeScript **Retrofit Overlay** — generates only the platform *servicing layer* for a
service and nothing else. Run it against an **existing** TypeScript project to retrofit it with:

- `.github/workflows/` — CI build + cut-tag (`typescript-ci`)
- `.platform/kubernetes/**` — PlatformApplication CRD + dev/stg/prd kustomize overlays
  (`platform-application-manifests`), including `resourceRequirements` when you select a
  resource
- `.platform/docker/{local,prd}/Dockerfile` — container image builds (idiomatic starting
  points; adapt to your build)
- `.editorconfig`, `.gitattributes`, `.gitignore`

It generates **no** project scaffolding and **no** domain code — no `package.json`, no
`tsconfig.json`, no `src/`, no `tests/`. Everything renders **in place** at the destination
root.

```bash
archetect render git@github.com:p6m-archetypes/typescript-service-empty-archetype.git#dev /path/to/existing-project
```

## Prompts — the tactical minimum

You are asked for the deployment facts the generated CI/CD actually consumes, and nothing
else. There is no author identity, no organization × solution split and no project
prefix/suffix: a *service* archetype needs those to name code it is generating, and this
generates none.

| Prompt | Consumed by |
|---|---|
| **Application Name** | the image name, the `PlatformApplication` name, the directory CD writes into in the platform manifests repo, the Tilt resource |
| **Solution Slug** | the image path, and the `{solution}-{application}-{env}` namespace the platform reads the solution and environment back out of |
| **Image Registry** | the image path |
| **Protocol** (REST/gRPC/GraphQL) | whether the manifests inject `SERVER_PORT` or `GRPC_PORT`, and the protocol the ports declare |
| **Service / Management Port** | the published ports, the container `EXPOSE`, the readiness probe |
| **Persistence / Cache / Messaging** | the manifests' `resourceRequirements` |
| **Source Control** | the optional publish-the-repository step |

Those first three are the only answers with no default, so a headless render needs just:

```bash
archetect render <source> /path/to/existing-project --headless \
  -a project_name=billing-service -a org_solution_name=acme-payments -a image_registry=ghcr.io
```

## Resources

You are prompted for persistence / cache / messaging so the PlatformApplication can
declare the matching `resourceRequirements`. **No connection code is generated** — this
overlay never touches project source. (Object storage is intentionally omitted: it drives
only code weaving, which does not apply to a retrofit.)

See `docs/specs/empty-service-archetype.md` in the archetype-ecosystem repo for the full
contract. This is the empty-tier sibling of `typescript-rest-service-archetype` (full) and
`typescript-service-basic-archetype` (minimal complete service).

## Acceptance tests

```bash
prova            # from the repo root
prova specs      # the open spec surface — contracts stated but not yet held
```

The suite renders this archetype and inspects the result; it holds the **p6m overlay
standards E1–E7** from [`prova-p6m-standards`](https://github.com/p6m-archetypes/prova-p6m-standards)
(`docs/standards.md` §2b) — the same shared suite every language's overlay is held to, so
none of them can define its own bar. Notably it proves the render is *confined* to the
platform layer (an allowlist, so scaffolding in any language fails), that a retrofit leaves
the application's own files alone, that the prompt surface is the table above and no more,
and that the image name agrees across the workflow, the manifest and the CD dispatch.

Nothing builds or boots — an overlay generates no project — so no language toolchain is
needed, only prova. CI runs the identical suite via `prova-rs/run-action@v1`.

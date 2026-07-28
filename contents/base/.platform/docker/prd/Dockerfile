# prd/Dockerfile — the artifact CI publishes and the platform deploys
#
# Layout-agnostic on purpose: this overlay retrofits an EXISTING application, so it copies the whole
# repo and runs the application's OWN build command rather than assuming a module name, a crate, a
# src/ layout or an output path. `build_command` and `runtime_artifact` are answers; their defaults
# match what this language's p6m service archetype produces, so a greenfield-shaped repo needs
# neither.

FROM node:22-alpine AS builder
WORKDIR /app
RUN npm install -g pnpm
COPY . .
RUN pnpm install --prefer-frozen-lockfile
RUN {{ build_command }}

FROM node:22-alpine
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app ./
USER appuser
EXPOSE {{ service_port }} {{ management_port }}
ENTRYPOINT ["node", "{{ runtime_artifact }}"]

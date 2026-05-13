# ESO Config Demo

Prototype for TSX-924. Four branches explore variants of the same flow:

`GitHub -> Argo CD -> Helm -> optional ConfigMap + ExternalSecret -> Kubernetes Secret -> mounted files -> .NET app`

Every variant produces the same Kubernetes outputs: a `ConfigMap` for
non-secret config and an ESO-managed `Secret` for resolved secrets. The app
loads them in the same order. The variants differ in where the schema lives,
who composes connection strings, and how much the chart template iterates
over values vs. enumerates by hand.

At this point, the prototype has effectively narrowed to two serious options:

- `main` — strict chart-owned schema, string connection strings composed in Helm
- `split-connection-strings` — strict chart-owned schema, structured connection strings composed by .NET

The other two branches are still useful as contrast, but they are mostly
documented here as ruled-out alternatives.

## Consistent across branches

- Non-secret per-env config lives in Git. Helm renders it into `appsettings.global.json` when `config.useConfigMap=true`.
- External Secrets Operator resolves sensitive material into individual secret-backed files under `/app/secrets`.
- The app doesn't call AWS Secrets Manager directly.
- Mount paths are fixed: `/app/appsettings.global.json` and `/app/secrets`. No env-suffixed filenames.
- `config.useConfigMap` is available as a temporary rollout toggle.
- Shared chart defaults express `remoteKey` values as AWS-style secret paths. The local demo bootstrap injects a temporary override so the Kubernetes provider can read seeded local Secret names.
- Resource-shaped Secrets Manager secrets (`/databases/postgres/dev`, `/auth/jwt/dev`, …). Multiple bindings can share one source.
- Runtime config layering:
  1. `/app/appsettings.json` — per-service base, baked into the image
  2. `/app/appsettings.global.json` — Helm-rendered ConfigMap when enabled
  3. `/app/secrets/*` — ESO-managed Secret entries loaded with .NET `AddKeyPerFile`
  4. environment variables

Sections like `Temporal`, `MarketDataApi`, and `ElasticSearch` mix non-secret
fields (`Address`, `BaseUrl`, `Url`) with secret fields (`ApiKey`, `Token`,
`Password`). See [Realistic split example](#realistic-split-example).

## Preferred approaches

| Axis                          | `main`                | `chart-template`             | `data-driven-template`       | `split-connection-strings`     |
|-------------------------------|-----------------------|------------------------------|------------------------------|--------------------------------|
| Schema-of-record              | chart template        | values (`secrets.template`)  | values (`secrets.*` tree)    | chart template                 |
| Add a new binding             | chart PR              | values change                | values change                | chart PR                       |
| Connection-string composition | chart Helm            | values string                | chart Helm (special-cased)   | .NET driver builder            |
| Connection-string tuning      | `secrets.…`           | inline in the values string  | `secrets.…`                  | `appsettings.…`                |
| Chart-template complexity     | medium / verbose      | tiny                         | high (recursive helpers)     | medium                         |
| Startup validation            | none                  | none                         | none                         | `ValidateOnStart`              |

### `main` — enumerated schema

The external secret template hand-writes the secret-backed config keys and
the `data:` block. Helm composes `ConnectionStrings.*`
(`Username={{ .topstepUsername }};…;Database=dev;…`). Scalar bindings
hardcode their source-prefix names (`{{ .jwtSecret }}`,
`{{ .temporalApiKey }}`). The `secrets` values tree mirrors the .NET section
layout and carries templated `remoteKey` values plus per-binding parameters.

- **Pros:** Reads top-to-bottom. The JSON literal *is* the schema, so env
  values can't add a binding the app would read.
- **Cons:** Adding a binding edits two parallel blocks (the templated secret
  entries and the `data:` list) that can drift inside the chart. Postgres
  connection-string syntax lives in Helm.

- **Current position:** Preferred baseline. This is the simplest strict
  approach and best preserves the current app contract.

### `split-connection-strings` — driver-built connection strings

The schema enumeration matches `main`, but `ConnectionStrings.*` come
through as structured objects (`{Host, Port, Username, Password, Database}`)
in the secret config instead of composed strings. The app binds each section
into a named `NpgsqlConnectionStringBuilder` with `ValidateOnStart` for
`Host`, `Username`, `Password`, and `Database`. Non-secret tuning
(`IncludeErrorDetail`, `CommandTimeout`, pool sizes) moves to
`appsettings.ConnectionStrings.<Name>` and merges into the same section
before the builder reads it.

- **Pros:** The chart doesn't know Postgres connection-string syntax.
  Non-secret tuning lives in `appsettings:` with the rest of the non-secret
  config. Startup validation catches missing required fields with named
  errors.
- **Cons:** The app depends on `Npgsql` (or one builder per driver flavor).
  Each new driver family needs its own options binding.
- **Current position:** Preferred advanced option. Stronger runtime contract,
  but it asks the app to own more of the connection-string composition model.

## Other approaches considered

### `chart-template` — schema in values

The external secret template is effectively two lines: `toPrettyJson` on
`secrets.template` for the JSON body, and a `range` over `secrets.vars` for
the `data:` block. The entire app-facing secret shape lives under
`secrets.template` in values, with ESO placeholders inline. `secrets.vars`
is a flat map from `secretKey` to `{remoteKey, property}`.

- **Pros:** The chart template is tiny. Adding or reshaping a binding is a
  values change. The whole secret shape sits in one block.
- **Cons:** The schema lives in env-mutable values, so a values PR can
  declare a binding the app doesn't read, or omit one it does.
  Connection-string syntax inside a YAML string is hard to review.
  `secrets.template` and `secrets.vars` stay in sync by convention only.
- **Why it fell behind:** Too much schema flexibility at the env layer, and
  two sources of truth inside the same values model.

### `data-driven-template` — recursive values walk

Helpers in `_helpers.tpl` (`renderSecretJsonMembers`,
`renderSecretDataEntries`, `pathToken`, `secretNodeIsLeaf`, …) walk
`secrets.<Section>` recursively and emit both the JSON section and the
matching `data:` entries. Source-prefix names come from the YAML path.
`remoteKey` inherits down a subtree, so one Secrets Manager secret can back
many bindings (`GatewayApi.AllowedApplications.<GUID>.SecretKey` works
without chart changes). The template special-cases `ConnectionStrings` and
still composes it in Helm.

- **Pros:** Adding bindings, including nested ones, is a values change.
  Inherited `remoteKey` fits the "one resource, many leaves" case.
  `property` defaults to the YAML key name.
- **Cons:** The chart template is the most complex of the four. You have to
  walk the recursion to know what JSON comes out. The schema-in-values
  weakness is the same as `chart-template`. `ConnectionStrings` doesn't fit
  the walk, so the chart still hand-writes that section.
- **Why it fell behind:** Too clever for a shared config system that people
  will need to debug quickly under pressure.

### Open questions

Two decisions, mostly independent:

- **Where does the schema live?** The prototype outcome strongly favors the
  chart (`main`, `split-connection-strings`), which keeps the schema next to
  the consuming code and prevents values files from inventing bindings.
- **Where does connection-string syntax live?** A Helm template (`main`) or
  the .NET driver (`split-connection-strings`).


## Repository layout

- `app/` — minimal ASP.NET app
- `charts/topstepx/` — shared chart, modeled after the real shared `topstepx` chart in Argo
- `envs/demo/` — production-shaped environment chart with AWS-style secret paths
- `envs/demo-override/` — production-shaped override environment chart with AWS-style secret paths
- `apps/*.yaml` — Argo `Application` manifests for both demo environments
- `scripts/` — local bootstrap helpers for `k3d`/`k3s`, Argo CD, ESO, and seed secrets

## Run it locally

### Prerequisites

- Docker
- `k3d`
- `kubectl`
- `helm`
- a GitHub repository that contains this project (Argo CD points at it)

### Bootstrap

Set the GitHub repository URL that Argo CD watches, and then run the
bootstrap script:

```bash
export REPO_URL="https://github.com/<org-or-user>/eso-config-demo.git"
./scripts/bootstrap-demo.sh
```

The scripts pin all `kubectl` and `helm` commands to the
`k3d-eso-config-demo` context, so they don't affect your ambient context.

After bootstrap:

- Argo CD runs in `argocd`
- ESO runs in `external-secrets-system`
- the base demo app runs in `demo`
- the override demo app runs in `demo-override`

The bootstrap keeps the env charts production-shaped and injects a
demo-only Helm values overlay into the Argo `Application` resources so the
Kubernetes provider still reads seeded local Secret names.

### Local secret source

The local prototype uses ESO's Kubernetes provider instead of AWS Secrets
Manager. `bootstrap-demo.sh` seeds Kubernetes Secrets into the `eso-seed`
namespace. The chart's `SecretStore` lets ESO read those and generate the
application-facing key-per-file secret entries in each app namespace.

In the AWS-backed implementation, `remoteKey` values are resource-shaped
Secrets Manager paths such as
`/databases/postgres/{{ .Values.config.secretsEnv }}` and
`/auth/jwt/{{ .Values.config.secretsEnv }}`. For the local Kubernetes
provider, the bootstrap injects a demo-only Helm values override so Argo
renders seeded Secret names such as `databases-postgres-demo` and
`auth-jwt-demo` without changing the env charts themselves.

### Verify the deployment

```bash
kubectl --context k3d-eso-config-demo get applications -n argocd
kubectl --context k3d-eso-config-demo get externalsecret -n demo
kubectl --context k3d-eso-config-demo get externalsecret -n demo-override
kubectl --context k3d-eso-config-demo get secret appsettings-secrets -n demo -o jsonpath='{.data.ConnectionStrings__Topstep}' | base64 -d
kubectl --context k3d-eso-config-demo get secret appsettings-secrets -n demo -o jsonpath='{.data.Temporal__ApiKey}' | base64 -d
kubectl --context k3d-eso-config-demo get configmap appsettings-global -n demo -o jsonpath='{.data.appsettings\.global\.json}'
kubectl --context k3d-eso-config-demo get configmap appsettings-global -n demo-override -o jsonpath='{.data.appsettings\.global\.json}'
kubectl --context k3d-eso-config-demo logs deploy/demo-app -n demo
kubectl --context k3d-eso-config-demo logs deploy/demo-app -n demo-override
```

## Realistic split example

How a section's non-secret and secret fields divide across the two sources.
The YAML below uses `main`'s authoring shape — the other branches reach the
same result differently.

The app carries a default in [app/appsettings.json](app/appsettings.json):

```json
"HedgeDetection": {
  "ImmediateEnforcementThreshold": 8
}
```

The shared chart carries dev-wide non-secret defaults in
[charts/topstepx/values.yaml](charts/topstepx/values.yaml):

```yaml
appsettings:
  FeatureFlags:
    AllowAnonymousRegistration: false
    EnableHubspotEmails: false
  Temporal:
    Address: topstepx-dev.tmprl.cloud:7233
    Namespace: topstepx-dev
    TaskQueues:
      - topstepx-temporal-worker-queue
  MarketDataApi:
    BaseUrl: http://webapi.marketdata.svc.cluster.local
    EventHubUrl: http://webapi.marketdata.svc.cluster.local/hubs/event
  Strapi:
    BaseUrl: https://strapi-cms.topstep.com/api/
  ElasticSearch:
    Url: https://topstepx.es.us-east-2.aws.elastic-cloud.com/
    Username: elastic
    CloudId: topstepx-demo:ZXMtdXM...==
```

Both environments inherit these unless they explicitly override them. A
section like `Temporal` has non-secret and secret siblings:

- `appsettings.Temporal.Address`
- `appsettings.Temporal.Namespace`
- `appsettings.Temporal.TaskQueues`
- `secrets.Temporal.ApiKey`

`ElasticSearch` shares one secret source across multiple secret leaves:

- `appsettings.ElasticSearch.Url`
- `appsettings.ElasticSearch.Username`
- `appsettings.ElasticSearch.CloudId`
- `secrets.ElasticSearch.remoteKey`
- `secrets.ElasticSearch.Password.property`
- `secrets.ElasticSearch.CloudApiKey.property`

At runtime those secret leaves appear as key-per-file entries such as:

- `ElasticSearch__Password`
- `ElasticSearch__CloudApiKey`
- `Temporal__ApiKey`
- `ConnectionStrings__Topstep`

`demo` keeps the app default for
`HedgeDetection.ImmediateEnforcementThreshold` (`8`). `demo-override` sets
it to `12` in
[envs/demo-override/values.yaml](envs/demo-override/values.yaml):

```yaml
appsettings:
  HedgeDetection:
    ImmediateEnforcementThreshold: 12
```

So between the two environments:

- app default only: `demo` → `8`
- env override: `demo-override` → `12`
- shared dev defaults: both environments inherit the same `FeatureFlags`

A realistic app-facing secret shape on `main`:

```yaml
secrets:
  ConnectionStrings:
    Topstep:
      remoteKey: /databases/postgres/dev
      database: dev
      includeErrorDetail: true
  Jwt:
    remoteKey: /auth/jwt/dev
    Secret: { property: secret }
  Temporal:
    remoteKey: /temporal/dev
    ApiKey: { property: apiKey }
  MarketDataApi:
    remoteKey: /apis/marketdata/dev
    ApiKey: { property: apiKey }
  ElasticSearch:
    remoteKey: /elasticsearch/topstepx
    Password:
      property: password
    CloudApiKey:
      property: cloudApiKey
```

In the local demo, those `remoteKey` values point at Kubernetes Secrets in
`eso-seed`. In the AWS-backed implementation they map directly to AWS
Secrets Manager.

A minimal env override only needs to carry the fields that truly vary by
environment. In this prototype that mostly means `config.secretsEnv`,
non-secret `appsettings` overrides, and the database names:

```yaml
topstepx:
  config:
    secretsEnv: demo-override

  appsettings:
    Demo:
      EnvironmentName: demo-override

  secrets:
    ConnectionStrings:
      Topstep:
        database: demo_override
      TopstepReadOnly:
        database: demo_override
      Chart:
        database: cqg-contract-bars-demo-override
```

The rest of the secret contract stays in the shared chart:
`remoteKey` templates, property names, ESO store wiring, and refresh policy.

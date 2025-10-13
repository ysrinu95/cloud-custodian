# Cloud Custodian AI Coding Instructions

## Architecture Overview

Cloud Custodian is a multi-cloud policy engine with a modular provider architecture:
- **Core (`c7n/`)**: Policy execution engine, schema validation, and resource management
- **Providers (`tools/c7n_aws/`, `c7n_azure/`, `c7n_gcp/`)**: Cloud-specific resource implementations
- **Tools (`tools/`)**: Specialized utilities like `c7n_left` (IaC scanning), `c7n_org` (multi-account), `c7n_kube` (Kubernetes)
- **Serverless Runtime (`c7n/handler.py`, `c7n/mu.py`)**: Lambda/Function deployment and execution

## Key Development Patterns

### Policy Structure
Policies are YAML with strict schema validation via `c7n/structure.py`:
```yaml
policies:
  - name: policy-name
    resource: aws.ec2  # Provider.resource_type pattern
    filters:
      - type: filter-name
    actions:
      - type: action-name
```

### Resource Implementation Pattern
All resources inherit from `c7n.query.QueryResourceManager`:
- **Filters**: Inherit from `c7n.filters.core.Filter` (value, boolean, regex patterns)
- **Actions**: Inherit from `c7n.actions.core.Action` with `process()` method
- **Registry**: Use `@resources.register('resource-name')` decorator

### Provider Integration
- Each provider implements `Provider` interface with `initialize()` and `get_session_factory()`
- Resources map via `resource_map` dictionary: `{'aws.ec2': 'c7n_aws.resources.ec2.Instance'}`
- Session factories handle cloud authentication and regional sessions

## Testing Conventions

### Core Testing (`tests/`)
- Inherit from `c7n.testing.CustodianTestCore` for policy loading utilities
- Use `self.load_policy()` for single policy tests with schema validation
- Mock cloud APIs with `unittest.mock` - never make real cloud calls in tests
- Policy validation: `policy.validate()` for schema errors, `policy.run()` for execution

## Cloud Custodian — Copilot instructions (concise)

Purpose: give an AI coding agent exactly the project-specific knowledge needed to be productive.

## Big picture (what to open first)
- Core engine: `c7n/` — policy parsing, schema, resource loading (`c7n/loader.py`, `c7n/structure.py`, `c7n/schema.py`).
- Providers & tools: look under `tools/` (e.g. `tools/c7n_aws/`) and provider packages like `c7n_aws` or `c7n_azure` for resource implementations.
- Policies and infra: `policies/` (policy YAMLs) and `terraform/` + `terraform-bootstrap/` (infra & bootstrapping scripts).

## Key, discoverable patterns (concrete)
- Policies are YAML lists under a top-level `policies:` key. Example: `policies/example-policies.yml` uses `resource: aws.ec2` style names.
- Resource modules inherit `c7n.query.QueryResourceManager`. Filters extend `c7n.filters.core.Filter`; actions extend `c7n.actions.core.Action` and implement `process()`.
- Registration: resources are exposed via `@resources.register('name')` and looked up via `resource_map` strings (search `@resources.register` to find implementations).
- Serverless packaging: `c7n/mu.py` builds deployment archives; runtime handler templates live near `c7n/handler.py`.

## Developer workflows (how to run & test)
- Run a policy locally: `custodian run -s output/ policy.yml` (project uses the `custodian` CLI installed in your environment).
- Dry-run: `custodian run --dryrun policy.yml`.
- Schema tooling: `custodian schema aws` generates provider schemas.
- IaC testing: `c7n-left` is used to run policies against Terraform/CFN modules (see `tools/c7n_left`).
- Tests: unit tests use `c7n.testing.CustodianTestCore` and helpers like `self.load_policy()` — open `tests/` to find examples.

## Project conventions and gotchas
- Policy files: must be `.yml`/`.yaml` and include `policies:`; many CI/checks assume that layout (see `policies/README.md`).
- Sessions: providers expose session factories — do not assume global boto3 session; search for `get_session_factory`.
- Naming: filter/action type names are schema-driven and case-sensitive; the string must match the schema registration.
- Packaging limits: Lambda packages are trimmed in `c7n/mu.py` — adding heavy deps needs checks there.

## Where to look for examples when implementing changes
- Policy parsing: `c7n/loader.py`, `c7n/structure.py`, `c7n/schema.py`.
- Resource/filter/action examples: `c7n_aws` or `tools/c7n_aws` resource files (search `@resources.register`).
- Packaging & serverless: `c7n/mu.py`, `c7n/handler.py`.
- IaC tooling and bootstrap: `terraform/` and `terraform-bootstrap/` (scripts like `bootstrap.sh` and `bootstrap.tf`).

If any section is unclear or you'd like me to add short examples (small patch) for one of the referenced files, tell me which part to expand. 
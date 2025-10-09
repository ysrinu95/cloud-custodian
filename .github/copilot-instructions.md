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

### Infrastructure as Code Testing (`c7n_left`)
Test policies against Terraform/CloudFormation:
```bash
c7n-left run -p policies/ -d terraform-module/ --summary
```

## Build and Development Workflows

### Core Commands
- **Policy Execution**: `custodian run -s output/ policy.yml`
- **Dry Run**: `custodian run --dryrun policy.yml`
- **Schema Generation**: `custodian schema aws` (for provider-specific schemas)
- **Multi-Account**: `c7n-org run -c accounts.yml -u policy.yml`

### Serverless Deployment
Policies with `mode` blocks auto-provision serverless functions:
```yaml
mode:
  type: periodic
  schedule: rate(1 day)
  # Creates Lambda function with CloudWatch Events trigger
```

### Docker Development
Use `tools/cask/` for containerized execution:
```bash
custodian-cask run -s output/ policy.yml
```

## Critical Implementation Details

### Policy Loading Pipeline
1. **YAML Parsing**: `c7n/loader.py` handles file loading and variable substitution
2. **Structure Validation**: `c7n/structure.py` validates policy structure before schema
3. **Schema Validation**: `c7n/schema.py` validates against provider schemas
4. **Resource Loading**: `c7n/resources/` registers and loads provider resources

### Lambda/Function Packaging
- **Archive Creation**: `c7n/mu.py` creates deployment packages with dependencies
- **Handler Template**: Each provider has handler template (e.g., `c7n/handler.py` for AWS)
- **Configuration Injection**: Runtime config embedded as `config.json` in package

### Multi-Provider Support
- **Provider Discovery**: Use `c7n.provider.clouds.get()` to instantiate providers
- **Resource Registration**: Providers register resources during import via decorators
- **Session Management**: Each provider handles authentication and API clients

## Essential File Patterns

- **Policy Files**: Always end in `.yml` or `.yaml`, contain `policies:` key
- **Resource Modules**: Follow `c7n_{provider}/c7n_{provider}/resources/{service}.py` pattern
- **Test Files**: `test_{module}.py` with class inheritance from testing base classes
- **Tool CLIs**: Entry points in `setup.py`, click-based command interfaces

## Common Pitfalls

1. **Schema Registration**: Forgot `@resources.register()` decorator breaks policy loading
2. **Session Scope**: Don't cache sessions across regions - use session factories
3. **Filter/Action Naming**: Must match schema definition exactly (case-sensitive)
4. **Provider Loading**: Missing provider imports cause "unknown resource" errors
5. **Lambda Limits**: Package size and dependency conflicts in serverless deployments

## Integration Points

- **Cloud APIs**: All cloud calls via provider-specific clients (boto3, Azure SDK, etc.)
- **Metrics**: CloudWatch/Azure Monitor integration via `c7n.actions.metric`
- **Notifications**: SNS/EventGrid via `c7n.actions.notify`
- **Configuration**: YAML-based with variable interpolation and includes support
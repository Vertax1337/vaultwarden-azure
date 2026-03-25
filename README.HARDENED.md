# Vaultwarden on Azure Container Apps (Hardened Defaults)

> **Note:** This document describes the hardened defaults already present in `main.json`. It is a supplement to the main [Readme.md](./Readme.md).

The current `main.json` template includes these production-hardened defaults:

- HTTP disabled by default (`allowInsecureHttp=false`)
- Vaultwarden image pinned by default (`vaultwardenImage=vaultwarden/server:1.35.3-alpine`)
- Self-registration disabled (`SIGNUPS_ALLOWED=false`)
- Password hints disabled (`SHOW_PASSWORD_HINT=false`)
- SSRF protection enabled (`HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=true`)
- Key Vault purge protection enabled
- TLS 1.2 minimum on storage account
- Diagnostic settings enabled for Key Vault and PostgreSQL
- Azure Files backup enabled by default
- PostgreSQL tier automatically derived from SKU name prefix

## Production recommendations
- `allowInsecureHttp`: `false`
- `allowAzureServicesToPostgres`: `true` (required for consumption-plan ACA; see [Hardening Tiers](./Readme.md#hardening-tiers-optional) for alternatives)
- `vaultwardenImage`: keep pinned; update intentionally during maintenance windows
- `adminPanelEnabled`: set to `false` after bootstrap

## Note on outbound IP
With a consumption Container App Environment, outbound IPs are dynamic. If you want to restrict PostgreSQL access to specific IPs, you must use a VNet-integrated environment with a NAT Gateway (Tier 1 hardening). See the [Hardening Tiers](./Readme.md#hardening-tiers-optional) section in the main README.

## Stale files
- `main.bicep` is an older reference and does **not** match `main.json`. It should not be used for deployment.

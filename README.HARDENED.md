# Vaultwarden on Azure Container Apps (Hardened Defaults)

This is a hardened variant of your original template:
- HTTP disabled by default (`allowInsecureHttp=false`)
- PostgreSQL "Allow Azure Services (0.0.0.0)" disabled by default (`allowAzureServicesToPostgres=false`)
- Vaultwarden image pinned by default (`vaultwardenImage=docker.io/vaultwarden/server:1.33.2`)
- CPU/RAM pairs enforced via `containerSku` (valid pairs only)

## Recommended parameters (production)
- `allowInsecureHttp`: `false`
- `allowAzureServicesToPostgres`: `false`
- `postgresFirewallStartIp` / `postgresFirewallEndIp`: set to your egress IP range (or migrate to private networking)
- `vaultwardenImage`: keep pinned; update intentionally during maintenance windows

## Note on outbound IP
With a consumption Container App Environment, outbound IPs can change. If you disable `allowAzureServicesToPostgres` you MUST allowlist a stable outbound IP (e.g., via NAT Gateway on a VNet-integrated environment) or use private endpoints.

# Vaultwarden auf Azure Container Apps (Gehärtete Defaults)

> **Hinweis:** Dieses Dokument beschreibt die gehärteten Defaults, die bereits in `main.json` enthalten sind. Es ergänzt die Haupt-[Readme.md](./Readme.md).

Das aktuelle `main.json`-Template enthält folgende produktionsgehärtete Defaults:

- HTTP standardmäßig deaktiviert (`allowInsecureHttp=false`)
- Vaultwarden-Image standardmäßig gepinnt (`vaultwardenImage=vaultwarden/server:1.35.3-alpine`)
- Self-Registrierung deaktiviert (`SIGNUPS_ALLOWED=false`)
- Passwort-Hints deaktiviert (`SHOW_PASSWORD_HINT=false`)
- SSRF-Schutz aktiviert (`HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=true`)
- Key-Vault-Purge-Protection aktiviert
- TLS 1.2 Minimum auf dem Storage Account
- Diagnostic Settings für Key Vault und PostgreSQL aktiviert
- Azure-Files-Backup standardmäßig aktiv
- PostgreSQL-Tier wird automatisch aus dem SKU-Namenspräfix abgeleitet

## Produktionsempfehlungen
- `allowInsecureHttp`: `false`
- `allowAzureServicesToPostgres`: `true` (erforderlich für Consumption-Plan-ACA; siehe [Härtungsstufen](./Readme.md#härtungsstufen) für Alternativen)
- `vaultwardenImage`: gepinnt lassen; bewusst im Wartungsfenster aktualisieren
- `adminPanelEnabled`: nach Bootstrap auf `false` setzen

## Hinweis zur Outbound-IP
Mit einem Consumption Container App Environment sind Outbound-IPs dynamisch. Wenn du den PostgreSQL-Zugriff auf bestimmte IPs einschränken willst, brauchst du ein VNet-integriertes Environment mit NAT Gateway (Härtungsstufe 1). Siehe den Abschnitt [Härtungsstufen](./Readme.md#härtungsstufen) in der Haupt-README.

## Veraltete Dateien
- `main.bicep` ist eine ältere Referenz und entspricht **nicht** `main.json`. Sie sollte nicht für Deployments verwendet werden.

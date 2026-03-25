# Changelog – `main.json`

Revisioniertes Änderungsprotokoll aller Änderungen und Optimierungen am ARM-Template `main.json` gegenüber der ursprünglichen Baseline.

> Letzte Aktualisierung: **2026-03-25**

---

## Revision 4 – 2026-03-25

### Bugfix

| Änderung | Detail |
|---|---|
| `useAcsFoundation` – Guard gegen leere Domain | Die Variable prüft jetzt zusätzlich, ob `acsDomainNameEffective` nicht leer ist (`and(acsDeployFoundation, not(empty(acsDomainNameEffective)))`). Vorher konnte `acsDeployFoundation=true` mit leeren `acsDomainName` **und** `mailRootDomain` dazu führen, dass ACS-Ressourcen mit einem leeren Domainnamen deployt wurden und das Deployment fehlschlug. |

### Verhalten

- `acsDeployFoundation=true` + Domain gesetzt → ACS wird deployt (wie bisher)
- `acsDeployFoundation=true` + keine Domain → ACS wird **nicht** deployt (neu: kein Fehlerpfad mehr)
- `acsDeployFoundation=false` → ACS wird nicht deployt (unverändert)

---

## Revision 3 – 2026-03-25

### Parameter

| Änderung | Detail |
|---|---|
| `appName` maxLength hinzugefügt | `maxLength: 10`, da Storage-Account-Namen aus `appName` abgeleitet werden und auf 24 Zeichen begrenzt sind |

### Beschreibungen

- Alle Parameter-Beschreibungen: Unicode-Escapes (`\u00fc`, `\u00e4`, …) durch korrekte UTF-8-Zeichen ersetzt

---

## Revision 2 – 2026-03-25

### Gesamtstruktur

| Änderung | Detail |
|---|---|
| Bicep-Version | `0.15.31` → `0.39.26` (neuer templateHash) |
| Template-Umfang | ~320 Zeilen → ~1.270 Zeilen; von Minimal-Template zu produktionsreifem Full-Stack |

### Parameter – neu hinzugefügt

| Parameter | Typ | Beschreibung |
|---|---|---|
| `location` | string | Azure-Region (Default: `resourceGroup().location`) |
| `environment` | string | Kosten-/Zuordnungstag: `prod` / `test` / `dev` |
| `bsseRef` | string | Traceability: BSSE Deploy-Ref (z. B. Git Tag oder Commit SHA) |
| `appName` | string | Name der Container App (Default: `vault`) |
| `vaultwardenImage` | string | Gepinntes Container-Image (Default: `vaultwarden/server:1.35.3-alpine`) |
| `allowInsecureHttp` | bool | HTTP erlauben (Default: `false`) |
| `diagnosticsEnabled` | bool | Diagnostic Settings für Key Vault und PostgreSQL (Default: `true`) |
| `deploymentScriptForceUpdateTag` | string | Kontrollierbarer Re-Run des Bootstrap-Scripts |
| `domainUrl` | string | Öffentliche Vaultwarden-URL (muss `https://` enthalten) |
| `adminPanelEnabled` | bool | ADMIN_TOKEN als ENV an die App durchreichen (Default: `true`) |
| `invitationOrgName` | string | → `INVITATION_ORG_NAME` |
| `signupsDomainsWhitelist` | string | → `SIGNUPS_DOMAINS_WHITELIST` |
| `orgCreationUsers` | string | → `ORG_CREATION_USERS` |
| `mailRootDomain` | string | Explizite Root-Domain für Mailrouting und Default-Absender |
| `smtpUseAuth` | bool | SMTP Auth vs. Direct Send (Default: `true`) |
| `smtpFrom` | string | → `SMTP_FROM` |
| `smtpFromName` | string | → `SMTP_FROM_NAME` |
| `heloName` | string | → `HELO_NAME` |
| `smtpHost` | string | SMTP Host (leer = automatisch) |
| `smtpPort` | string | SMTP Port (Default: `587`) |
| `smtpSecurity` | string | `starttls` / `force_tls` / `off` |
| `smtpUsername` | string | → `SMTP_USERNAME` |
| `smtpPassword` | securestring | → `SMTP_PASSWORD` |
| `smtpAuthMechanism` | string | → `SMTP_AUTH_MECHANISM` (mit `allowedValues`) |
| `ssoEnabled` | bool | SSO via OIDC (Default: `false`) |
| `ssoOnly` | bool | Nur SSO-Login, kein Master-Password (Default: `false`) |
| `ssoAuthority` | string | OIDC Authority/Issuer URL |
| `ssoClientId` | string | OIDC Client ID |
| `ssoClientSecret` | securestring | OIDC Client Secret |
| `ssoScopes` | string | OIDC Scopes |
| `pushEnabled` | bool | Mobile Push (Default: `false`) |
| `pushInstallationId` | securestring | Bitwarden Installation ID (Key Vault) |
| `pushInstallationKey` | securestring | Bitwarden Installation Key (Key Vault) |
| `pushUseEuServers` | bool | EU Push Relay verwenden (Default: `false`) |
| `acsDeployFoundation` | bool | ACS Foundation deployen (Default: `false`) |
| `acsDataLocation` | string | ACS-Geographie (Default: `Germany`) |
| `acsDomainName` | string | ACS Custom Domain |
| `azureFilesBackupEnabled` | bool | Azure Files Backup (Default: `true`) |
| `azureFilesBackupScheduleRunTime` | string | Backup-Zeitpunkt (Default: `05:30`) |
| `azureFilesBackupTimeZone` | string | Zeitzone (Default: `UTC`) |
| `azureFilesBackupDailyRetentionDays` | int | Tägliche Retention (Default: `30`) |
| `azureFilesBackupWeeklyDaysOfWeek` | array | Wochentage für wöchentliche Retention |
| `azureFilesBackupWeeklyRetentionWeeks` | int | Wöchentliche Retention (Default: `12`) |
| `postgresSkuName` | string | PostgreSQL SKU (Default: `Standard_B1ms`) |
| `postgresStorageGB` | int | PostgreSQL Storage in GB (Default: `32`) |
| `postgresBackupRetentionDays` | int | PITR-Retention 7–35 Tage (Default: `14`) |
| `allowAzureServicesToPostgres` | bool | Azure-Dienste-Firewall-Regel (Default: `true`) |
| `dbAdminUser` | string | PostgreSQL Admin Login (Default: `vaultwarden`) |

### Parameter – umbenannt

| Alt | Neu | Grund |
|---|---|---|
| `storageAccountSKU` | `storageAccountSku` | Einheitliche camelCase-Schreibweise |
| `cpuCore` | `cpuCores` | Plural korrekter; allowedValues entfernt |
| `Appname` | `appName` | camelCase-Konvention |
| `AdminAPIKEY` | _(entfernt)_ | Admin Token wird vom Deployment Script generiert und in Key Vault abgelegt |
| `DomainWhitelist` | `signupsDomainsWhitelist` | Mapping auf Vaultwarden-ENV `SIGNUPS_DOMAINS_WHITELIST` |
| `SignupsVerify` | _(entfernt)_ | Nicht mehr als separater Parameter; Verhalten wird über `SIGNUPS_DOMAINS_WHITELIST` gesteuert |
| `SignupsAllowed` | _(entfernt)_ | Default ist jetzt `SIGNUPS_ALLOWED=false` (hardcoded gehärtet) |

### Parameter – geändert

| Parameter | Änderung |
|---|---|
| `memorySize` | `allowedValues` entfernt; frei wählbar |
| `dbPassword` | Default: `concat(toUpper(newGuid()), newGuid())` statt ohne Default; wird nur bei Erstanlage gesetzt |

### Variablen – neu / geändert

| Variable | Detail |
|---|---|
| `storageAccountName` | Jetzt `take(format('{0}files{1}', appName, uniqueString), 24)` – sicher auf 24 Zeichen begrenzt |
| `postgresTier` | Dynamische Ableitung aus SKU-Präfix (`Standard_B` → Burstable, `Standard_D` → GeneralPurpose, `Standard_E` → MemoryOptimized) |
| `keyVaultName` | Neu: Key Vault für Secrets |
| `containerEnvName` | Ableitung aus `appName` statt hardcoded |
| `postgresServerName` | Ableitung aus `appName` statt hardcoded |
| `commonTags` | Tagging mit `Environment` und `bsse:ref` |
| `vwEnvBase` / `vwEnvSmtp*` / `vwEnvSso*` / `vwEnvPush*` | Saubere bedingte ENV-Modellierung für Vaultwarden |

### Ressourcen – neu

| Ressource | Typ | Zweck |
|---|---|---|
| Key Vault | `Microsoft.KeyVault/vaults` | RBAC-geschützter Secret Store für ADMIN_TOKEN, DATABASE_URL, SMTP, SSO, Push |
| User Assigned Managed Identity (App) | `Microsoft.ManagedIdentity/userAssignedIdentities` | App liest Secrets aus Key Vault |
| User Assigned Managed Identity (Script) | `Microsoft.ManagedIdentity/userAssignedIdentities` | Bootstrap-Script schreibt Secrets in Key Vault |
| RBAC – Secrets Officer | `Microsoft.Authorization/roleAssignments` | Script-MI bekommt Key Vault Secrets Officer |
| RBAC – Secrets User | `Microsoft.Authorization/roleAssignments` | App-MI bekommt Key Vault Secrets User |
| Deployment Script | `Microsoft.Resources/deploymentScripts` | Bootstrap: DB-App-User, DATABASE_URL, ADMIN_TOKEN, SMTP/SSO/Push Secrets, MX-Lookup |
| Recovery Services Vault | `Microsoft.RecoveryServices/vaults` | Azure Files Backup |
| Backup Policy | `Microsoft.RecoveryServices/vaults/backupPolicies` | Tägliche + wöchentliche Retention |
| Protection Container | `Microsoft.RecoveryServices/vaults/.../protectionContainers` | Storage-Registrierung |
| Protected Item | `Microsoft.RecoveryServices/vaults/.../protectedItems` | File-Share-Schutz |
| Diagnostic Settings (Key Vault) | `Microsoft.Insights/diagnosticSettings` | Audit-Logs → Log Analytics |
| Diagnostic Settings (PostgreSQL) | `Microsoft.Insights/diagnosticSettings` | Logs + Metriken → Log Analytics |
| ACS Email Service | `Microsoft.Communication/emailServices` | Optional: ACS Foundation |
| ACS Email Domain | `Microsoft.Communication/emailServices/domains` | Optional: Custom-Domain-Vorbereitung |
| ACS Communication Service | `Microsoft.Communication/communicationServices` | Optional: ACS Foundation |

### Ressourcen – geändert

| Ressource | Änderung |
|---|---|
| Container App | Startup-, Liveness- und Readiness-Probes auf `/alive` statt `/`; ENV-Variablen bedingt modelliert; Key-Vault-Secrets per SecretRef; Managed Identity statt hartcodierten Secrets |
| PostgreSQL Flexible Server | Tier dynamisch abgeleitet; PITR-Retention parametrierbar; Firewall-Regel bedingt |
| Storage Account | Name sicher auf 24 Zeichen begrenzt; TLS 1.2 Minimum; File Share Name als Variable |
| Log Analytics | Name aus `appName` abgeleitet statt hardcoded |

### Sicherheitshärtungen

| Maßnahme | Detail |
|---|---|
| `SIGNUPS_ALLOWED` | Hardcoded `false` (statt parametrierbar) |
| `SHOW_PASSWORD_HINT` | Hardcoded `false` |
| `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS` | Hardcoded `true` (SSRF-Schutz) |
| `allowInsecureHttp` | Default `false` |
| Key Vault Purge Protection | Aktiviert |
| `enabledForTemplateDeployment` | Deaktiviert am Key Vault |
| TLS 1.2 Minimum | Storage Account |
| Vaultwarden-Image | Standardmäßig gepinnt (`1.35.3-alpine`) |

### Outputs – neu

| Output | Bedingung | Beschreibung |
|---|---|---|
| `acsFoundationEnabled` | immer | Ob ACS Foundation deployt wurde |
| `acsEmailServiceName` | `acsDeployFoundation` | Name des Email Service |
| `acsCommunicationServiceName` | `acsDeployFoundation` | Name des Communication Service |
| `acsEmailDomain` | `acsDeployFoundation` | Vorbereitete E-Mail-Domain |
| `acsEmailDomainResourceId` | `acsDeployFoundation` | Resource ID der E-Mail-Domain |
| `acsNextSteps` | `acsDeployFoundation` | Manuelle Folgeschritte als Array |

---

## Revision 1 – Baseline (ursprüngliches Template)

Ursprüngliches Community-Template mit folgenden Ressourcen:

- Storage Account + File Share
- Log Analytics Workspace
- Container App Environment + Container App
- PostgreSQL Flexible Server + Datenbank + Firewall-Regel

Parameter: `storageAccountSKU`, `AdminAPIKEY`, `cpuCore`, `memorySize`, `dbPassword`, `Appname`, `DomainWhitelist`, `SignupsVerify`, `SignupsAllowed`

Kein Key Vault, keine Managed Identities, kein Deployment Script, kein Backup, keine Diagnostic Settings, keine ACS-Unterstützung.

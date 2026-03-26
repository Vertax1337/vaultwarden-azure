# Changelog – `main.json`

Revisioniertes Änderungsprotokoll aller Änderungen und Optimierungen am ARM-Template `main.json` gegenüber der ursprünglichen Baseline.

> Letzte Aktualisierung: **2026-03-26**

---


## Revision 13 – 2026-03-26

### Parameter

| Änderung | Detail |
|---|---|
| `postgresVersion` – neu | PostgreSQL-Majorversion parametrierbar (Default: `16`, erlaubt: `15`, `16`, `17`). Bestehende Server können nicht downgegradet werden. |

### Variablen / ENV

| Änderung | Detail |
|---|---|
| `IP_HEADER=X-Forwarded-For` in `vwEnvBase` | Korrekte Client-IP-Erkennung hinter ACA-Reverse-Proxy für Rate Limiting und Audit Logs. Ohne diesen Header sieht Vaultwarden die Proxy-IP statt der echten Client-IP. |

### Ressourcen

| Änderung | Detail |
|---|---|
| PostgreSQL Flexible Server | `version` nutzt jetzt `postgresVersion`-Parameter statt hardcoded `15` |
| Storage Account | `defaultToOAuthAuthentication: true` hinzugefügt für sicherere Portal-Nutzung |

### Dokumentation

| Änderung | Detail |
|---|---|
| HARDENING.md | `IP_HEADER`, `defaultToOAuthAuthentication`, `postgresVersion`, `signupsDomainsWhitelist`-Warnung ergänzt |
| Readme.md – Sicherheitshinweise | Key Vault Purge Protection Caveat, `signupsDomainsWhitelist`-Verhalten, Admin-Panel `/data/config.json`-Bereinigung, `IP_HEADER` dokumentiert |
| Readme.md – Go-Live-Checkliste | Neue Checkliste mit Pflicht- und empfohlenen Schritten vor produktivem Einsatz |
| Readme.md – Betriebs-Checkliste | Intervallbasierte Betriebsaufgaben (wöchentlich bis quartalsweise) |
| Readme.md – Bekannte Einschränkungen und Caveats | Key Vault Purge, `dbPassword` newGuid, `signupsDomainsWhitelist`, Azure Files Konsistenz, Einzelreplikat |
| Readme.md – Link-Korrektur | `README.HARDENED.md` → `HARDENING.md` (korrekter Dateiname) |
| docs/architecture.md – Link-Korrektur | `README.HARDENED.md` → `HARDENING.md` |

### Wrapper-Templates

| Änderung | Detail |
|---|---|
| `main.deploytoazure.json` | `postgresVersion`-Parameter hinzugefügt und an `main.json` weitergeleitet |
| `current/main.deploytoazure.json` | `postgresVersion`-Parameter hinzugefügt und an `main.json` weitergeleitet |

---


## Revision 12 – 2026-03-25

### Dokumentation
- Architektur-Diagramm um Azure-Service-Icons, End-User-Element und Internet-/Zugangspfad erweitert
- Zugriffspfad End User → Internet → Container App Ingress mit HTTPS (443) im Diagramm ergänzt
- Legende um „External access path“ erweitert
- draw.io-Quelldatei (`docs/diagrams/vaultwarden-aca-architecture.drawio`) auf die neue Diagrammversion aktualisiert
- `docs/architecture.md` um den externen Zugriffspfad im Abschnitt Datenflüsse ergänzt

---

## Revision 11 – 2026-03-25

### Dokumentation
- Architektur-Diagramm als SVG hinzugefügt (`docs/diagrams/vaultwarden-aca-architecture.svg`)
- Editierbare draw.io-Quelldatei hinzugefügt (`docs/diagrams/vaultwarden-aca-architecture.drawio`)
- Architektur-Dokumentation erstellt (`docs/architecture.md`) mit Ressourcen-Übersicht, Datenflüssen und Designentscheidungen
- `Readme.md` um Architektur-Diagramm-Abschnitt und Link auf `docs/architecture.md` erweitert

---

## Revision 10 – 2026-03-25

### Dokumentation

| Änderung | Detail |
|---|---|
| Operation-Playbook.md – Vollständige Überarbeitung | Komplettes Playbook redaktionell überarbeitet: saubere H1/H2/H3-Hierarchie, Inhaltsverzeichnis, Einleitung mit Zweck und Zielgruppe, konsistente deutsche Sprache (englische Fragmente übersetzt), neue Abschnitte „Voraussetzungen", „Manuelle Nacharbeiten", „Observability und Troubleshooting" (Log-Quellen, Quick Triage, KQL), „Vaultwarden-Update und Upgrade" (Image-Tag-Strategie, Downtime, Rollback), „Regelbetrieb und Prüfroutine", „Wann dieses Setup nicht geeignet ist". Screenshot-/Bild-Platzhalter an sinnvollen Stellen ergänzt. Checklisten und Tabellen für bessere Übersicht. |

---

## Revision 9 – 2026-03-25

### Dokumentation

| Änderung | Detail |
|---|---|
| Readme.md – „Observability / Troubleshooting" | Neuer Abschnitt: Log-Quellen (Container, ACA-System, Key Vault, PostgreSQL, Deployment-Script), Quick-Triage-Anleitung für typische Fehlerfälle, KQL-Beispielabfragen. |
| Readme.md – „Vaultwarden-Update / Upgrade-Konzept" | Neuer Abschnitt: Image-Tag-Strategie, schrittweiser Update-Ablauf, Downtime-Verhalten bei Single-Revision-Modus, Rollback-Anleitung inkl. PITR-Hinweis. |

---

## Revision 8 – 2026-03-25

### Dokumentation

| Änderung | Detail |
|---|---|
| Readme.md – „Wann dieses Template nicht geeignet ist" | Neuer Abschnitt: klare Abgrenzung, für welche Szenarien das Template nicht passt (Enterprise-Isolation, WAF-Pflicht, Multi-Region, >500 Nutzer). |
| Readme.md – „Bekannte Tradeoffs" | Neuer Abschnitt: konsolidierte Übersicht aller bewussten Architektur-Tradeoffs (Netzwerk, HA, WAF, Storage, Admin-Panel). |

---

## Revision 7 – 2026-03-25

### Deployment Script – Input-Validierung erweitert

| Prüfung | Detail |
|---|---|
| `acsDeployFoundation=true` ohne Domain | WARNING im Output, wenn weder `acsDomainName` noch `mailRootDomain` gesetzt ist. ACS-Ressourcen werden in diesem Fall nicht deployt. |

### Deployment Script – Umgebungsvariablen

| Variable | Typ | Zweck |
|---|---|---|
| `ACS_DEPLOY_FOUNDATION` | value | Weiterleitung von `acsDeployFoundation` an das Script für ACS-Warnung |
| `ACS_DOMAIN_NAME` | value | Weiterleitung von `acsDomainName` an das Script für ACS-Warnung |

### Dokumentation

| Änderung | Detail |
|---|---|
| Readme.md – ACS Foundation | Hinweis ergänzt: WARNING bei fehlendem `acsDomainName` / `mailRootDomain` |

---

## Revision 6 – 2026-03-25

### Deployment Script – Input-Validierung erweitert

| Prüfung | Detail |
|---|---|
| `ssoOnly=true` → `ssoEnabled=true` Pflicht | Script bricht mit Fehlermeldung ab, wenn `ssoOnly=true` ohne `ssoEnabled=true` gesetzt ist. |

### Deployment Script – Umgebungsvariablen

| Variable | Typ | Zweck |
|---|---|---|
| `SSO_ONLY` | value | Weiterleitung von `ssoOnly` an das Script für Eingabevalidierung |

### Dokumentation

| Änderung | Detail |
|---|---|
| Readme.md – SSO-Hinweise | Guardrail `ssoOnly=true` → `ssoEnabled=true` dokumentiert |

---

## Revision 5 – 2026-03-25

### Parameter

| Änderung | Detail |
|---|---|
| `domainUrl` – `minLength: 9` hinzugefügt | Verhindert leere oder zu kurze Werte auf ARM-Ebene (Minimum für `https://x`). |

### Deployment Script – Input-Validierung erweitert

| Prüfung | Detail |
|---|---|
| `domainUrl` muss mit `https://` beginnen | Script bricht mit Fehlermeldung ab, wenn das Präfix fehlt. |
| `ssoEnabled=true` → Pflichtparameter | `ssoAuthority`, `ssoClientId` und `ssoClientSecret` müssen gesetzt sein. |
| `pushEnabled=true` → Pflichtparameter | `pushInstallationId` und `pushInstallationKey` müssen gesetzt sein. |

### Deployment Script – Umgebungsvariablen

| Variable | Typ | Zweck |
|---|---|---|
| `SSO_AUTHORITY_INPUT` | value | Weiterleitung von `ssoAuthority` an das Script für Eingabevalidierung |
| `SSO_CLIENT_ID_INPUT` | value | Weiterleitung von `ssoClientId` an das Script für Eingabevalidierung |

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


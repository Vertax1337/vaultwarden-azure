# Parameter-Referenz – `main.json`

Vollständige Parameterliste des ARM-Templates `main.json` mit Zuordnung zu Azure-Ressourcen und Vaultwarden-ENV-Variablen.

Für die kompakte Übersicht siehe auch [Operations Playbook §23](../HowToInstall/Operation-Playbook.md#23-parameter-referenz).

---

## Azure-/Deploy-Parameter

Diese Parameter steuern Azure-Ressourcen, Sizing, Bootstrap und Azure-Dienste.

### Core / Deploy

| Parameter | Beschreibung |
|---|---|
| `location` | Azure-Region für alle Ressourcen |
| `environment` | Umgebungsbezeichnung (z. B. `prod`, `staging`) |
| `bsseRef` | BSSE-Referenz / Kundenkennung |
| `appName` | Anwendungsname (maximal 10 Zeichen; Storage-Account-Namen werden daraus abgeleitet und sind auf 24 Zeichen begrenzt) |
| `deploymentScriptForceUpdateTag` | Nur bewusst ändern, wenn das Bootstrap-Script erneut laufen soll |
| `diagnosticsEnabled` | Aktiviert Diagnostic Settings für Key Vault und PostgreSQL |
| `allowInsecureHttp` | HTTP-Zugriff erlauben (`false` = Produktion) |
| `edgeMode` | Betriebsmodus: `none` (Basic/Azure-only) oder `cloudflare-managed` (Production Wizard) |
| `enableIngressIpRestrictions` | Aktiviert ACA-Ingress-Restriktionen für den Production-Pfad |
| `ingressAllowedCidrs` | Liste der erlaubten CIDR-Ranges für ACA-Ingress (z. B. Cloudflare IPs) |
| `customHostname` | Optionaler Ziel-Hostname für den Kunden (vom Wizard genutzt) |
| `vaultwardenImage` | Container-Image (standardmäßig gepinnt; bewusst im Wartungsfenster aktualisieren) |
| `cpuCores` | CPU-Ressourcen für die Container App |
| `memorySize` | Speicher-Ressourcen für die Container App |

### Azure Files / Backup

| Parameter | Beschreibung |
|---|---|
| `storageAccountSku` | SKU für den Storage Account |
| `azureFilesBackupEnabled` | Azure-Files-Backup aktivieren |
| `azureFilesBackupScheduleRunTime` | Backup-Zeitplan (Uhrzeit) |
| `azureFilesBackupTimeZone` | Zeitzone für Backup-Zeitplan |
| `azureFilesBackupDailyRetentionDays` | Aufbewahrung täglicher Backups (Tage) |
| `azureFilesBackupWeeklyDaysOfWeek` | Wochentage für wöchentliche Backups |
| `azureFilesBackupWeeklyRetentionWeeks` | Aufbewahrung wöchentlicher Backups (Wochen) |

### PostgreSQL / Bootstrap-only

| Parameter | Beschreibung |
|---|---|
| `postgresSkuName` | PostgreSQL-SKU (Tier wird automatisch abgeleitet: `Standard_B*` = Burstable, `Standard_D*` = GeneralPurpose, `Standard_E*` = MemoryOptimized) |
| `postgresStorageGB` | Speichergröße für PostgreSQL |
| `postgresBackupRetentionDays` | PITR-Aufbewahrung (Tage) |
| `allowAzureServicesToPostgres` | `AllowAzureServices`-Firewallregel aktivieren (erforderlich für Consumption-Plan-ACA) |
| `dbAdminUser` | PostgreSQL-Admin-User (nur für Erstanlage und Bootstrap) |
| `dbPassword` | PostgreSQL-Admin-Passwort (nur für Erstanlage und Bootstrap) |

> **Hinweis:** `dbAdminUser` und `dbPassword` bleiben im Template, weil sie für die PostgreSQL-Server-Erstellung und das Bootstrap-Script benötigt werden. Sie sind **keine** produktiven Vaultwarden-App-Credentials; die App nutzt einen separaten Least-Privilege-User über `DATABASE_URL` aus Key Vault.

### ACS Foundation

| Parameter | Beschreibung |
|---|---|
| `acsDeployFoundation` | ACS-Ressourcen deployen (`true`/`false`) |
| `acsDataLocation` | Geography für ACS-Ressourcen |
| `acsDomainName` | Expliziter Domainname (sonst wird `mailRootDomain` verwendet) |

---

## Vaultwarden-Parameter / ENV-Mapping

Diese Parameter werden zu Vaultwarden-ENV-Werten oder steuern Vaultwarden-nahes Verhalten.

### Core / Instanzverhalten

| Parameter | ENV-Variable | Beschreibung |
|---|---|---|
| `domainUrl` | `DOMAIN` | Öffentliche URL der Vaultwarden-Instanz |
| `adminPanelEnabled` | – | Steuert, ob `ADMIN_TOKEN` an die App durchgereicht wird |

### Organisation / Signup / Richtlinien

| Parameter | ENV-Variable | Beschreibung |
|---|---|---|
| `invitationOrgName` | `INVITATION_ORG_NAME` | Organisationsname in Einladungsmails |
| `signupsDomainsWhitelist` | `SIGNUPS_DOMAINS_WHITELIST` | Domain-Whitelist für Self-Service-Registrierung |
| `orgCreationUsers` | `ORG_CREATION_USERS` | Benutzer, die Organisationen erstellen dürfen |

> **Wichtig:** `SIGNUPS_DOMAINS_WHITELIST` hat spezifisches Vaultwarden-Verhalten. Wenn gesetzt, den Self-Service-Signup-Prozess bewusst testen; Domain-Whitelist und Einladungs-/Org-Flows verhalten sich anders als bei offener Registrierung.

### Mail / SMTP

| Parameter | ENV-Variable | Beschreibung |
|---|---|---|
| `mailRootDomain` | – | Root-Domain für MX-Lookup (Direct Send) |
| `smtpUseAuth` | – | SMTP-Auth aktivieren (`true` = SMTP Auth, `false` = Direct Send) |
| `smtpFrom` | `SMTP_FROM` | Absenderadresse |
| `smtpFromName` | `SMTP_FROM_NAME` | Absendername |
| `heloName` | `HELO_NAME` | HELO-Name (leer = Host aus `DOMAIN`) |
| `smtpHost` | `SMTP_HOST` | SMTP-Server (leer = `smtp.office365.com` bei Auth; MX-Lookup bei Direct Send) |
| `smtpPort` | `SMTP_PORT` | SMTP-Port |
| `smtpSecurity` | `SMTP_SECURITY` | TLS-Modus (`starttls`, `force_tls`, `off`) |
| `smtpUsername` | `SMTP_USERNAME` | SMTP-Benutzername |
| `smtpPassword` | `SMTP_PASSWORD` | SMTP-Passwort (als Secret in Key Vault) |
| `smtpAuthMechanism` | `SMTP_AUTH_MECHANISM` | Auth-Mechanismus (`Login`, `Plain`, `Xoauth2`) |

### SSO / OIDC

| Parameter | ENV-Variable | Beschreibung |
|---|---|---|
| `ssoEnabled` | `SSO_ENABLED` | SSO/OIDC aktivieren |
| `ssoOnly` | `SSO_ONLY` | Nur SSO-Login erlauben (deaktiviert Master-Passwort) |
| `ssoAuthority` | `SSO_AUTHORITY` | OIDC-Authority-URL |
| `ssoClientId` | `SSO_CLIENT_ID` | OIDC-Client-ID |
| `ssoClientSecret` | `SSO_CLIENT_SECRET` | OIDC-Client-Secret (als Secret in Key Vault) |
| `ssoScopes` | `SSO_SCOPES` | OIDC-Scopes |

### Mobile Push

| Parameter | ENV-Variable | Beschreibung |
|---|---|---|
| `pushEnabled` | `PUSH_ENABLED` | Push-Benachrichtigungen aktivieren |
| `pushInstallationId` | `PUSH_INSTALLATION_ID` | Bitwarden Installation ID (als Secret in Key Vault) |
| `pushInstallationKey` | `PUSH_INSTALLATION_KEY` | Bitwarden Installation Key (als Secret in Key Vault) |
| `pushUseEuServers` | – | Setzt `PUSH_RELAY_URI` / `PUSH_IDENTITY_URI` für `.com` vs `.eu` |

---

## Weiterführende Dokumentation

- [Readme.md](../../Readme.md) – Einstiegsseite
- [Operations Playbook §23](../HowToInstall/Operation-Playbook.md#23-parameter-referenz) – Kompakte Parameterübersicht
- [Beispiel-Parameterdateien](../../examples/parameters/) – Szenariospezifische Vorlagen

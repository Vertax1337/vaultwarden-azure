# Vaultwarden auf Azure Container Apps (ACA)

Produktionsorientiertes ARM-Template für **Vaultwarden auf Azure Container Apps**, ausgelegt für KMUs.

## Architektur

Dieses Template deployt eine vollständige Vaultwarden-Umgebung als einzelnes ARM-Deployment:

| Komponente | Zweck |
|---|---|
| **Azure Container Apps** (Consumption Plan) | Vaultwarden-Laufzeit (einzelnes Replikat, gepinntes Image) |
| **Azure Files** | Persistentes `/data`-Volume (Attachments, Icons, Config) |
| **PostgreSQL Flexible Server** (Burstable B1ms) | Relationale Daten |
| **Azure Key Vault** (RBAC) | Secrets (`ADMIN_TOKEN`, `DATABASE_URL`, SMTP-/SSO-/Push-Credentials) |
| **User Assigned Managed Identities** | App liest Secrets; Bootstrap-Script schreibt Secrets |
| **Deployment Script** (AzureCLI) | Bootstrap: DB-App-User-Provisionierung, Secret-Seeding, MX-Lookup |
| **Recovery Services Vault** | Azure-Files-Backup (standardmäßig aktiv) |
| **Log Analytics + Diagnostic Settings** | Observability für Key Vault und PostgreSQL |
| **ACS Foundation** (optional) | Email Service, Email Domain, Communication Service |

### Designphilosophie

Dieses Repository richtet sich an **KMUs**, die einen sicheren, produktionsreifen Passwortmanager brauchen – ohne Enterprise-Kosten oder -Komplexität. Die Architektur nutzt bewusst:

- **ACA Direct Ingress** (kein Application Gateway oder Front Door als Default)
- **Öffentlichen PostgreSQL-Zugriff mit Firewall-Regeln** (kein VNet/Private Endpoint als Default)
- **Consumption-Tier ACA** (keine Workload Profiles als Default)
- **Alles in einem einzigen ARM-Template** für maximale Einfachheit

Diese bewussten Tradeoffs sind im Abschnitt [Härtungsstufen](#härtungsstufen-optional) dokumentiert.

### ACA-Netzwerk-Tradeoffs

Azure Container Apps im Consumption Plan bietet **keine feste Outbound-IP**. Das hat folgende Konsequenzen:

| Einschränkung | Auswirkung | Mitigation |
|---|---|---|
| Dynamische Outbound-IPs | Keine spezifische PostgreSQL-Firewall-Regel für ACA möglich | `allowAzureServicesToPostgres=true` (0.0.0.0-Regel) erlaubt allen Azure-Diensten den Zugriff |
| Kein statischer Egress | SMTP-Server von Drittanbietern, die IP-Allowlisting erwarten, können Verbindungen ablehnen | Microsoft 365 SMTP oder ACS SMTP verwenden – dort ist kein Sender-IP-Allowlisting nötig |
| Keine eingebaute WAF | Kein Request-Filtering am Edge | ACA HTTPS-Ingress liefert TLS-Terminierung; Vaultwarden hat eigenes Rate Limiting; für WAF siehe Härtungsstufen |

Der Default `allowAzureServicesToPostgres=true` ist für Consumption-Plan-ACA erforderlich. Er öffnet PostgreSQL für alle Azure-Dienste (nicht das öffentliche Internet) – ein akzeptabler Tradeoff für KMU-Einsatz. Für weitergehende Einschränkung siehe [Härtungsstufen](#härtungsstufen-optional).

## Deploy

Es gibt bewusst **nur einen** Deploy-Pfad. Alles, was sauber automatisierbar ist, steckt in `main.json`.

[![Deploy to Azure (ARM JSON)](
https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true
)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmain%2Fmain.json
)

> **Hinweis:** Wenn du dieses Repo forkst oder Owner/Branch änderst, muss die Raw-URL im Button oben angepasst werden.

Für ein lokales Deployment ohne GitHub-Hosting: Azure Portal → **Benutzerdefinierte Vorlage bereitstellen** → **Eigene Vorlage im Editor erstellen** und `main.json` einfügen.

**Bewusst manuell nachgelagerte Schritte:**
- ACA Custom Domain + TLS-Zertifikatsbindung
- ACS DNS-Verifikation der E-Mail-Domain
- ACS Domain-Linking auf den Communication Service
- ACS SMTP-Username + finale SMTP-Aktivierung

Diese Schritte erfordern DNS-Propagation und externe Verifikation und können nicht zuverlässig in einem einzelnen Deployment automatisiert werden. Sie sind im [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md) dokumentiert.

---

## Dokumentation

- [Vaultwarden – How to Use (BSSE)](./docs/HowToUse/HowToUse.pdf)
- [Operations Playbook / Runbook](./docs/HowToInstall/Operation-Playbook.md)

Ein PowerShell-Hilfsskript steht unter `scripts/deploy.ps1` für lokale CLI-basierte Deployments mit interaktiven Parameter-Prompts bereit. Der primär unterstützte Deployment-Pfad bleibt das ARM-Template über Azure Portal oder `az deployment group create`.

---

## Beispiel-Parameterdateien

Unter `./examples/parameters/` liegen einsatznahe Vorlagen für typische Szenarien:

- **`main.parameters.m365-smtp-auth.example.json`**
  M365-SMTP-Auth-Standardpfad (`smtp.office365.com`, Port 587, `starttls`).

- **`main.parameters.m365-smtp-auth-sso.example.json`**
  M365 SMTP Auth + Entra-ID-/OIDC-Parameter für SSO.

- **`main.parameters.m365-direct-send.example.json`**
  Direct Send ohne SMTP-Auth. Nur für bewusst begrenzte interne Szenarien.

- **`main.parameters.m365-smtp-auth-sso-push.example.json`**
  M365 SMTP Auth + Entra-ID-SSO + Bitwarden-Push-Parameter.

- **`main.parameters.acs-foundation-m365-dns-hosted.example.json`**
  ACS-Foundation-Deploy für eine kundeneigene Domain mit M365-gehostetem DNS.

Alle Dateien enthalten **nur Platzhalterwerte** und müssen vor dem produktiven Einsatz angepasst werden.

---

## Repo-Struktur

- **`main.json`** → Primäres ARM-Deployment-Template (alle Ressourcen)
- **`main.bicep`** → ⚠️ Ältere Bicep-Referenz – **nicht gepflegt**, entspricht nicht `main.json`; nicht für Deployments verwenden
- **`scripts/deploy.ps1`** → Optionaler PowerShell-Wrapper für CLI-basiertes Deployment
- **`docs/HowToInstall/Operation-Playbook.md`** → Go-Live, Betrieb, ACS, Backup/Recovery, Smoke-Tests
- **`examples/parameters/`** → Szenariospezifische Parameterdatei-Vorlagen

---

## Was `main.json` deployt

### Immer enthalten
- Azure Container Apps Environment + Log Analytics
- Azure Container App für Vaultwarden (mit Startup-, Liveness- und Readiness-Probes)
- Azure Storage Account + Azure Files Share (`/data`)
- Azure Database for PostgreSQL Flexible Server + Datenbank
- User Assigned Managed Identities (App-Reader + Script-Writer)
- Azure Key Vault (RBAC)
- Deployment Script für:
  - `ADMIN_TOKEN`-Generierung
  - DB-App-User + `DATABASE_URL`-Provisionierung
  - SMTP-Secret (bei aktiviertem SMTP-Auth)
  - SSO-Secret (optional)
  - Push-Secrets (optional; Installation ID + Key)
  - MX-Lookup für Direct Send (bei `smtpUseAuth=false`)
  - Kontrollierbarer Re-Run über `deploymentScriptForceUpdateTag`
- Azure-Files-Backup (standardmäßig aktiv über Recovery Services Vault)
- Diagnostic Settings für Key Vault und PostgreSQL (standardmäßig aktiv)

Das Bootstrap-Script hängt explizit von der optionalen PostgreSQL-Firewall-Regel `AllowAzure` ab, wenn `allowAzureServicesToPostgres=true`. Interne Warte-/Retry-Fenster sind auf 10 Minuten gesetzt, damit RBAC- und Firewall-Propagation nicht in Timing-Fehler laufen.

### Optional: ACS Foundation
Wenn `acsDeployFoundation = true`, deployt `main.json` zusätzlich:
- **Azure Communication Services Email Service**
- **ACS Email Domain Resource**
- **ACS Communication Service**

Damit ist die Grundinfrastruktur vorhanden. **Nicht** automatisiert sind DNS-Verifikation, Domain-Linking und SMTP-Username-Erstellung.

### Bewusst **nicht** automatisiert
- ACA Custom Domain / Zertifikatsbindung
- ACS Domain-Verifikation
- ACS `linkedDomains`
- ACS `smtpUsernames`
- ACS-RBAC für die SMTP-Entra-App

Diese Schritte bleiben **manuelle Post-Deploy-Aufgaben**. So bleibt der Core-Deploy bei einem Button-Klick, während Domain-/Mail-Aktivierung den dokumentierten Abläufen im Operations Playbook folgt.

---

## SMTP-Modi

### A) SMTP Auth (**Produktiv-Default**)
Empfohlener Standardpfad.

- `smtpUseAuth = true` (Default)
- Leerer `smtpHost` → `smtp.office365.com`
- `smtpPort = 587`
- `smtpSecurity = starttls`
- `smtpUsername` + `smtpPassword` erforderlich
- Optional `smtpAuthMechanism` (z. B. `Login`, `Plain`, `Xoauth2`)

#### Geeignet für
- Microsoft 365 SMTP Submission
- Eigenen SMTP-Relay / Mailgateway
- ACS SMTP **nach** ACS-Finalisierung

---

### B) Direct Send
Nur für klar begrenzte interne Szenarien.

- `smtpUseAuth = false`
- Leerer `smtpHost` → MX-Lookup über `mailRootDomain`
- Template setzt `SMTP_PORT=25` und `SMTP_SECURITY=starttls` für diesen Modus
- **`SMTP_USERNAME` darf nicht gesetzt sein**
- **`SMTP_PASSWORD` darf nicht gesetzt sein**
- **`SMTP_AUTH_MECHANISM` darf nicht gesetzt sein**

#### Vaultwarden-spezifisches Verhalten
Vaultwarden behandelt SMTP-Auth anhand der tatsächlich vorhandenen Settings, nicht nur deren Werte. Laut offizieller `.env.template`: Wenn `SMTP_USERNAME` gesetzt ist, ist `SMTP_PASSWORD` verpflichtend. Für Direct Send lässt das Template korrekt alle Auth-ENV-Variablen weg, wenn `smtpUseAuth=false`.

#### Admin-UI / `config.json`-Override-Warnung
Vaultwarden speichert Admin-UI-Änderungen persistent in `/data/config.json`. Diese können ENV-Werte für `SMTP_HOST`, `SMTP_SECURITY`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_USERNAME`, `SMTP_PASSWORD` etc. überlagern. **Beim Wechsel von SMTP Auth auf Direct Send** müssen auch die persistierten SMTP-Auth-Werte im Vaultwarden-Adminbereich bereinigt werden.

#### Geeignet für
- Internen Mailversand in kontrollierten Microsoft-365-Szenarien

#### Betriebsnotiz
Wenn `smtpHost` leer ist, muss `mailRootDomain` gesetzt sein, damit das Bootstrap-Script den MX-Record auflösen kann. Das Script installiert keine zusätzlichen OS-Pakete. Falls die Runtime weder `dig` noch `nslookup` hat, setze `smtpHost` für Direct Send explizit.

#### Nicht als Default empfohlen
Für produktiven Einsatz, bei dem E-Mail-Versand kritisch ist, sind SMTP Auth oder ACS SMTP robuster und planbarer.

---

### C) ACS SMTP
ACS kann jetzt **teilweise** über `main.json` vorbereitet werden.

#### Schritt 1 – Foundation mit `main.json`
Beim Deploy setzen:
- `acsDeployFoundation = true`
- `acsDataLocation` passend zur gewünschten Geography
- `acsDomainName` optional explizit, sonst wird `mailRootDomain` verwendet
- Das Repo nutzt bewusst nur den öffentlich dokumentierten ACS-Custom-Domain-Pfad `CustomerManaged`

Damit werden erstellt:
- Email Service
- Email Domain Resource
- Communication Service

#### Schritt 2 – Manuelle ACS-Finalisierung
Die vollständigen manuellen Schritte stehen im [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md) unter **„ACS Foundation + ACS SMTP"**. Kurzfassung:
1. DNS-Einträge der ACS-Domain im maßgeblichen DNS-System setzen
2. Warten, bis **Domain Status**, **SPF**, **DKIM** und **DKIM2** vollständig verified sind
3. Die verifizierte Domain mit dem Communication Service verknüpfen
4. Der Entra-Anwendung die Rolle **Communication and Email Service Owner** zuweisen
5. SMTP-Username anlegen und Status **Ready to use** abwarten
6. `main.json` erneut mit den finalen Werten deployen:
   - `smtpUseAuth = true`
   - `smtpHost = smtp.azurecomm.net`
   - `smtpPort = 587`
   - `smtpSecurity = starttls`
   - `smtpUsername = <ACS SMTP Username>`
   - `smtpPassword = <Client Secret der Entra App>`
   - Optional `smtpAuthMechanism = Xoauth2`

---

## Vaultwarden-spezifische Hinweise

1. **Mail-Service-Aktivierung**
   Der Vaultwarden-Maildienst aktiviert sich, wenn `SMTP_FROM` und entweder `SMTP_HOST` oder `USE_SENDMAIL` gesetzt sind. `DOMAIN` muss korrekt sein, damit E-Mail-Links auf den richtigen Host zeigen. Für Produktion `smtpFrom` explizit setzen statt auf den impliziten Default zu vertrauen.

2. **Direct Send: Auth-Variablen müssen fehlen**
   Für Direct Send dürfen `SMTP_USERNAME`, `SMTP_PASSWORD` und `SMTP_AUTH_MECHANISM` in der App-Konfiguration nicht vorhanden sein. Das Template lässt diese korrekt weg, wenn `smtpUseAuth=false`.

3. **Admin-UI kann Template-Werte überlagern**
   Vaultwarden speichert Admin-UI-Änderungen in `/data/config.json`. Wenn dort SMTP-Werte oder ein `admin_token` persistiert sind, überlagern sie ENV-Werte. Bei einem Moduswechsel oder beim Abschalten des Admin-Panels immer die Vaultwarden-Diagnoseansicht prüfen.

4. **Admin-Panel-Lifecycle ist bewusst zweistufig**
   Der vorgesehene Weg: Erstdeployment mit `adminPanelEnabled=true` für Bootstrap/Tests/Admin-Diagnose; danach Redeploy mit `adminPanelEnabled=false`, damit `ADMIN_TOKEN` nicht mehr an die App durchgereicht wird. **Wichtig:** Falls im Adminbereich gespeichert wurde, muss ein persistierter `admin_token` in `/data/config.json` ebenfalls entfernt werden, sonst bleibt das Admin-Panel trotz entfernter ENV-Variable aktiv.

5. **Optionale SMTP-Feinparameter**
   `SMTP_AUTH_MECHANISM`, `HELO_NAME`, `SMTP_EMBED_IMAGES`, `SMTP_DEBUG`, `SMTP_ACCEPT_INVALID_CERTS` und `SMTP_ACCEPT_INVALID_HOSTNAMES` sind echte Vaultwarden-Parameter. Das Template reicht aktuell nur `SMTP_AUTH_MECHANISM` und `HELO_NAME` durch. Die übrigen Optionen sind bewusst nicht automatisiert und gehören in Troubleshooting-/Sonderfälle.

6. **`/data/config.json`-Persistenzrisiko**
   Jede im Vaultwarden-Admin-UI geänderte Einstellung wird in `/data/config.json` auf dem Azure-Files-Share persistiert. Diese Werte haben bei nachfolgenden Container-Starts Vorrang vor ENV-Variablen. Das ist bekanntes Vaultwarden-Verhalten. Der sichere Ansatz ist:
   - Admin-Panel nur während Bootstrap nutzen
   - SMTP-Einstellungen nicht über das Admin-UI speichern (sie kommen aus ENV)
   - Nach dem Bootstrap das Admin-Panel deaktivieren und prüfen, dass keine veralteten Werte persistiert sind

7. **SSO / OIDC Hinweise**
   - `SSO_ONLY=true` deaktiviert den Master-Passwort-Login vollständig. SSO vorher gründlich testen.
   - Die OIDC-Callback-URL wird aus `DOMAIN` abgeleitet: `https://<domain>/identity/connect/oidc-signin`
   - Bei Entra ID die Redirect-URI in der App Registration hinterlegen.

8. **Push-Benachrichtigungen – externe Abhängigkeit**
   - Push-Benachrichtigungen erfordern eine gültige Bitwarden Installation ID und Key von https://bitwarden.com/host/
   - Beide Werte werden als Secrets behandelt und in Key Vault abgelegt
   - Ohne Push funktionieren Mobile-Clients weiter, aber ohne Echtzeit-Sync-Signale

---

## Wichtige Parameter in `main.json`

Die Parameter sind in zwei Richtungen zu lesen:
- **Azure-/Deploy-Parameter** = steuern Ressourcen, Sizing, Bootstrap und Azure-Dienste
- **Vaultwarden-Parameter** = werden zu Vaultwarden-ENV-Werten oder steuern Vaultwarden-nahes Verhalten

### Azure-/Deploy-Parameter

#### Core / Deploy
- `location`
- `environment`
- `bsseRef`
- `appName` (maximal 10 Zeichen; Storage-Account-Namen werden daraus abgeleitet und sind auf 24 Zeichen begrenzt)
- `deploymentScriptForceUpdateTag` (nur bewusst ändern, wenn das Bootstrap-Script erneut laufen soll)
- `diagnosticsEnabled`
- `allowInsecureHttp`
- `vaultwardenImage` (standardmäßig gepinnt; bewusst im Wartungsfenster aktualisieren)
- `cpuCores`
- `memorySize`

#### Azure Files / Backup
- `storageAccountSku`
- `azureFilesBackupEnabled`
- `azureFilesBackupScheduleRunTime`
- `azureFilesBackupTimeZone`
- `azureFilesBackupDailyRetentionDays`
- `azureFilesBackupWeeklyDaysOfWeek`
- `azureFilesBackupWeeklyRetentionWeeks`

#### PostgreSQL / Bootstrap-only
- `postgresSkuName` (Tier wird automatisch abgeleitet: `Standard_B*` = Burstable, `Standard_D*` = GeneralPurpose, `Standard_E*` = MemoryOptimized)
- `postgresStorageGB`
- `postgresBackupRetentionDays`
- `allowAzureServicesToPostgres`
- `dbAdminUser`
- `dbPassword`

`dbAdminUser` und `dbPassword` bleiben im Template, weil sie für die PostgreSQL-Server-Erstellung und das Bootstrap-Script benötigt werden. Sie sind **keine** produktiven Vaultwarden-App-Credentials; die App nutzt einen separaten Least-Privilege-User über `DATABASE_URL` aus Key Vault.

#### ACS Foundation
- `acsDeployFoundation`
- `acsDataLocation`
- `acsDomainName`

### Vaultwarden-Parameter / ENV-Mapping

#### Core / Instanzverhalten
- `domainUrl` → `DOMAIN`
- `adminPanelEnabled` → steuert, ob `ADMIN_TOKEN` an die App durchgereicht wird

#### Organisation / Signup / Richtlinien
- `invitationOrgName` → `INVITATION_ORG_NAME`
- `signupsDomainsWhitelist` → `SIGNUPS_DOMAINS_WHITELIST`
- `orgCreationUsers` → `ORG_CREATION_USERS`

**Wichtig:** `SIGNUPS_DOMAINS_WHITELIST` hat spezifisches Vaultwarden-Verhalten. Wenn gesetzt, den Self-Service-Signup-Prozess bewusst testen; Domain-Whitelist und Einladungs-/Org-Flows verhalten sich anders als bei offener Registrierung.

#### Mail / SMTP
- `mailRootDomain`
- `smtpUseAuth`
- `smtpFrom` → `SMTP_FROM`
- `smtpFromName` → `SMTP_FROM_NAME`
- `heloName` → `HELO_NAME` (leer = Host aus `DOMAIN`)
- `smtpHost` → `SMTP_HOST`
- `smtpPort` → `SMTP_PORT`
- `smtpSecurity` → `SMTP_SECURITY`
- `smtpUsername` → `SMTP_USERNAME`
- `smtpPassword` → `SMTP_PASSWORD`
- `smtpAuthMechanism` → `SMTP_AUTH_MECHANISM`

#### SSO / OIDC
- `ssoEnabled` → `SSO_ENABLED`
- `ssoOnly` → `SSO_ONLY`
- `ssoAuthority` → `SSO_AUTHORITY`
- `ssoClientId` → `SSO_CLIENT_ID`
- `ssoClientSecret` → `SSO_CLIENT_SECRET`
- `ssoScopes` → `SSO_SCOPES`

#### Mobile Push
- `pushEnabled` → `PUSH_ENABLED`
- `pushInstallationId` → `PUSH_INSTALLATION_ID`
- `pushInstallationKey` → `PUSH_INSTALLATION_KEY`
- `pushUseEuServers` → setzt `PUSH_RELAY_URI` / `PUSH_IDENTITY_URI` für `.com` vs `.eu`

Sowohl `pushInstallationId` als auch `pushInstallationKey` werden als Secrets in Key Vault abgelegt.

### Weiterführende Dokumentation
- Operations Playbook: [docs/HowToInstall/Operation-Playbook.md](./docs/HowToInstall/Operation-Playbook.md)
- Bitwarden Installation ID / Key: https://bitwarden.com/host/
- Bitwarden Hosting-FAQ: https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay: https://bitwarden.com/help/configure-push-relay/
- Vaultwarden SSO (Wiki): https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect

## Outputs

Wenn `acsDeployFoundation = true`, gibt das Deployment zusätzlich aus:
- `acsFoundationEnabled`
- `acsEmailServiceName`
- `acsCommunicationServiceName`
- `acsEmailDomain`
- `acsEmailDomainResourceId`
- `acsNextSteps`

Diese Outputs dienen als operative Brücke zwischen Core-Deploy und manueller ACS-Finalisierung.

---

## Redeploy- und Secret-Verhalten

### Gleiches Template erneut in dieselbe Resource Group deployen
- ARM arbeitet standardmäßig im **incremental**-Modus
- Bestehende PostgreSQL-/Azure-Files-/Vaultwarden-Daten bleiben erhalten
- Das Bootstrap-`deploymentScript` läuft **nicht automatisch erneut**, wenn sich in seiner Resource-Definition nichts geändert hat
- Für bewusste Re-Runs `deploymentScriptForceUpdateTag` nutzen

### Wann `deploymentScriptForceUpdateTag` sinnvoll ist
Diesen Parameter nur bewusst ändern, z. B. wenn:
- DB-App-User / `DATABASE_URL` erneut reconciled werden sollen
- SMTP-/SSO-/Push-Secrets trotz sonst identischer Template-Werte erneut geschrieben werden sollen
- Ein No-Op-Redeploy nicht ausreicht und das Bootstrap-Script sicher erneut laufen soll

### Key-Vault-Secrets in ACA
Die Container App nutzt versionlose Key-Vault-Secret-URIs. Neue Secret-Versionen können ohne Änderung der Secret-URI im Template übernommen werden.

Für **planbare Sofortwirkung** ist trotzdem sinnvoll:
- Gezielter Redeploy mit inhaltlicher Änderung
- Oder Restart / neue Revision nach sensiblen Secret-Änderungen

### Admin-Panel nach Bootstrap deaktivieren
Empfohlener Betriebsablauf:
1. Erstdeployment mit `adminPanelEnabled = true` (Default)
2. Bootstrap / Tests / Admin-Diagnose durchführen
3. Falls im Vaultwarden-Admin-UI gespeichert wurde: prüfen, dass kein persistierter `admin_token` in `/data/config.json` stehen bleibt
4. `main.json` mit `adminPanelEnabled = false` erneut deployen
5. Prüfen, dass das Admin-Panel nicht mehr erreichbar ist

Für spätere Wartung kann das Admin-Panel temporär wieder aktiviert werden, indem `adminPanelEnabled = true` gesetzt und nach Abschluss der Arbeiten wieder auf `false` zurückgestellt wird.

---

## Manuelle Schritte vor Go-Live

Diese Schritte sind **bewusst** nicht vollständig automatisiert.

### 1) Custom Domain + TLS für ACA
Wenn du nicht auf der Standard-URL `*.azurecontainerapps.io` bleiben willst:

1. Custom Domain am Container-App-Ingress hinzufügen
2. DNS-Records setzen
3. Zertifikat binden (Managed Certificate oder eigenes)
4. Unter der finalen Ziel-URL testen

> `domainUrl` und die tatsächliche ACA-Bindung müssen am Ende übereinstimmen.

### 2) ACS Domain-DNS / Verifikation / Linking
Wenn ACS Email genutzt wird:

1. Mit `acsDeployFoundation = true` deployen
2. Die angezeigten DNS-Records setzen
3. Warten, bis die Domain **verified** ist
4. Die verifizierte Domain mit dem Communication Service verknüpfen
5. SMTP-Username + RBAC für die Entra-App anlegen
6. `main.json` mit den finalen ACS-SMTP-Werten erneut deployen

### 3) Smoke-Tests
Vor Go-Live die Tests aus dem [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md) durchführen.

---

## Produktiv- / Go-Live-Checkliste

Vor dem Go-Live alle Punkte prüfen:

### App / URL
- [ ] Container App ist erreichbar
- [ ] `allowInsecureHttp = false`
- [ ] Finale Ziel-URL antwortet mit gültigem TLS-Zertifikat
- [ ] `domainUrl` entspricht der real gebundenen URL

### Mail
- [ ] Testmail aus Vaultwarden erfolgreich
- [ ] Absenderadresse korrekt
- [ ] SPF/DKIM/DMARC passend zum gewählten Mailpfad
- [ ] Keine Platzhalterwerte mehr in SMTP-Parametern
- [ ] Bei ACS: Domain ist verified und mit dem Communication Service verknüpft

### Sicherheit
- [ ] `ADMIN_TOKEN` nur aus Key Vault entnommen, nicht lokal gespeichert
- [ ] `adminPanelEnabled` nach erfolgreichem Bootstrap/Testing auf `false` gesetzt
- [ ] Kein persistierter `admin_token` in `/data/config.json`
- [ ] Unnötige Signups deaktiviert (`SIGNUPS_ALLOWED=false` ist der Default)
- [ ] SSO/Push nur aktiv, wenn getestet
- [ ] `SHOW_PASSWORD_HINT=false` (Default)
- [ ] `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=true` (Default, verhindert SSRF)

### Daten
- [ ] Login erfolgreich
- [ ] Neuer Tresoreintrag speicherbar
- [ ] Attachment hochladbar
- [ ] Attachment wieder abrufbar

### Backup / Recovery
- [ ] Mindestens ein Restore-Drill geplant oder bereits durchgeführt
- [ ] Bekannt, wie PostgreSQL + Azure Files gemeinsam wiederhergestellt werden
- [ ] PostgreSQL-PITR-Retention (`postgresBackupRetentionDays`) ist ausreichend
- [ ] Azure-Files-Backup ist aktiv und läuft

---

## Härtungsstufen (optional)

Dieses Repository deployt eine **Baseline-Architektur**, die für KMU-Produktiveinsatz geeignet ist. Für Umgebungen mit strengeren Sicherheitsanforderungen gibt es folgende abgestufte Härtungsstufen:

### Stufe 0: Baseline (Default)
**Was man out-of-the-box bekommt:**
- ACA Direct Ingress mit HTTPS
- PostgreSQL öffentlicher Zugriff mit `AllowAzureServices`-Firewall-Regel
- Key Vault mit RBAC und Purge Protection
- Azure-Files-Backup über Recovery Services Vault
- Diagnostic Settings für Key Vault und PostgreSQL
- Vaultwarden-Image gepinnt, Signups deaktiviert, Passwort-Hints aus

**Tradeoffs:**
- Keine feste Outbound-IP → PostgreSQL-Firewall verlässt sich auf `AllowAzureServices`
- Keine WAF → Rate Limiting ist nur Vaultwarden-intern
- Keine VNet-Isolation

**Kosten: ~30–50 €/Monat** (Consumption ACA + B1ms PostgreSQL + Standard_LRS Storage)

### Stufe 1: Fester Egress + PostgreSQL-Einschränkung
**Zusätzlich:**
- ACA-Environment mit VNet-Integration (Workload Profiles)
- NAT Gateway für feste Outbound-IP
- Spezifische PostgreSQL-Firewall-Regel anstelle von `AllowAzureServices`

**Vorteile:**
- PostgreSQL akzeptiert nur Verbindungen von der bekannten IP
- SMTP-Server von Drittanbietern können die IP allowlisten
- Outbound-Traffic ist nachvollziehbar

**Mehrkosten: +30–50 €/Monat** (NAT Gateway + Workload-Profiles-Overhead)

### Stufe 2: Enterprise-Härtung
**Zusätzlich:**
- Private Endpoint für PostgreSQL (kein öffentlicher Zugriff)
- Private Endpoint für Key Vault
- Private Endpoint für Storage Account
- Private DNS Zones für alle Endpoints
- Optional: Azure Front Door oder Application Gateway mit WAF

**Vorteile:**
- Keine öffentliche Data-Plane-Exposition für Backend-Dienste
- WAF-Schutz am Edge
- Netzwerk-Mikrosegmentierung

**Mehrkosten: +100–200 €/Monat** (Private Endpoints + DNS Zones + optionale WAF)

> **Hinweis:** Jede Stufe erhöht die betriebliche Komplexität. Abwägen, ob die zusätzliche Sicherheit die Kosten und den Verwaltungsaufwand für die eigene Organisation rechtfertigt.

---

## Bekannte Einschränkungen und offene Risiken

| Einschränkung | Auswirkung | Mitigation |
|---|---|---|
| ACA-Consumption-Plan hat keine feste Outbound-IP | PostgreSQL-Firewall nutzt `AllowAzureServices` (0.0.0.0-Regel) | Auf Stufe 1 upgraden für festen Egress |
| Vaultwarden `config.json` kann ENV-Variablen überlagern | Im Admin-UI gespeicherte Einstellungen persistieren über Redeployments | Admin-Panel nach Bootstrap deaktivieren; im Runbook dokumentieren |
| Azure Files ist kein transaktionaler Store | `/data`-Backup und PostgreSQL-Backup sind möglicherweise nicht perfekt synchronisiert | Restore-Ablauf dokumentieren; Restore-Drills durchführen |
| `allowInsecureHttp` ist standardmäßig `false`, kann aber auf `true` gesetzt werden | Exponiert Traffic im Klartext | In Produktion `false` erzwingen |
| Deployment-Script hängt von Azure-CLI-Container-Image-Version ab | Zukünftige AzureCLI-Image-Änderungen könnten Script-Verhalten beeinflussen | `azCliVersion` ist auf `2.81.0` gepinnt |
| PostgreSQL-Passwort wird auto-generiert wenn nicht angegeben | Beim Redeploy erhält der `dbPassword`-Parameter einen neuen `newGuid()`-Wert, aber PostgreSQL ignoriert ihn, weil der Server bereits existiert (incrementelles Deploy) | Das ist sicher für Redeployment; das Passwort wird nur bei Erstanlage gesetzt |

---

## Changelog gegenüber der ursprünglichen Baseline

- Storage-Account-Name sicher auf 24 Zeichen begrenzt
- PostgreSQL-Tier wird dynamisch aus dem SKU-Namenspräfix abgeleitet
- Container-Health-Probes nutzen Vaultwardens `/alive`-Endpoint (Startup + Liveness + Readiness)
- Deploy-Button-URL für aktuelles Repository aktualisiert
- Repo-Struktur-Dokumentation korrigiert (PowerShell-Script berücksichtigt)
- `main.bicep` als nicht gepflegt markiert
- `enabledForTemplateDeployment` am Key Vault deaktiviert
- Vaultwarden-ENV-Variablen sauber mit bedingter Einbindung modelliert
- `SMTP_AUTH_MECHANISM` wird an Vaultwarden durchgereicht
- Optionale ENV-Werte werden nicht mehr als Leerstrings gesetzt
- Deployment-Script aktualisiert Secrets bei Änderungen
- SMTP-Auth wird im Deployment-Script validiert
- `mailRootDomain` als explizite Mail-Basisdomain (keine heuristische Ableitung aus `domainUrl`)
- PostgreSQL-PITR-Retention parametrierbar
- ACS von „alles auf einmal" auf **Foundation automatisiert, Finalisierung manuell** umgestellt
- `deploymentScriptForceUpdateTag` für bewusste Bootstrap-Re-Runs
- Deployment-Script nutzt `az postgres flexible-server execute` (kein `psql`-, `pip`- oder `pg8000`-Pfad)

---

## Quellen (ACS, M365, Bitwarden/Vaultwarden)

Die verlinkten Aussagen in README und Playbook wurden zuletzt **am 2026-03-20 16:02 CET** gegengeprüft.

### Microsoft Learn / Microsoft 365
- Verifizierte E-Mail-Domain verbinden
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/connect-email-communication-resource
- SMTP-Authentifizierung für E-Mail-Versand einrichten
  https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email-smtp/smtp-authentication
- Benutzerdefinierte verifizierte E-Mail-Domains hinzufügen
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/add-custom-verified-domains
- Fehlerbehebung bei Domain-Konfigurationsproblemen
  https://learn.microsoft.com/en-gb/azure/communication-services/concepts/email/email-domain-configuration-troubleshooting
- DNS-Einträge hinzufügen (Microsoft-gehostetes DNS)
  https://learn.microsoft.com/en-us/office365/admin/setup/add-domain

### Bitwarden / Vaultwarden
- Bitwarden: Installation ID & Key anfordern
  https://bitwarden.com/host/
- Bitwarden Hosting-FAQ
  https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay
  https://bitwarden.com/help/configure-push-relay/
- Vaultwarden SSO via OpenID Connect (Wiki)
  https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect
- Vaultwarden Mobile Push (Wiki)
  https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification

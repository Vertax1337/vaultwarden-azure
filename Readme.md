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
| **Deployment Script** (AzureCLI) | Bootstrap: DB-App-User, Secret-Seeding, MX-Lookup |
| **Recovery Services Vault** | Azure-Files-Backup (standardmäßig aktiv) |
| **Log Analytics + Diagnostic Settings** | Observability für Key Vault und PostgreSQL |
| **ACS Foundation** (optional) | Email Service, Email Domain, Communication Service |

### Designphilosophie

Dieses Repository richtet sich an **KMUs**, die einen sicheren, produktionsreifen Passwortmanager brauchen – ohne Enterprise-Kosten oder -Komplexität. Die Architektur nutzt bewusst:

- **ACA Direct Ingress** (kein Application Gateway oder Front Door als Default)
- **Öffentlichen PostgreSQL-Zugriff mit Firewall-Regeln** (kein VNet/Private Endpoint als Default)
- **Consumption-Tier ACA** (keine Workload Profiles als Default)
- **Alles in einem einzigen ARM-Template** für maximale Einfachheit

Diese bewussten Tradeoffs sind im Abschnitt [Bekannte Tradeoffs und Härtungsstufen](#bekannte-tradeoffs-und-härtungsstufen) dokumentiert.

### Wann dieses Template **nicht** geeignet ist

| Anforderung | Warum nicht passend | Alternative |
|---|---|---|
| VNet-Isolation / Private Endpoints Pflicht | Baseline nutzt Consumption-Plan-ACA ohne VNet | Härtungsstufe 2 oder eigenes Template |
| WAF / DDoS-Schutz compliancepflichtig | Kein Application Gateway oder Front Door im Default | Eigenes Template mit Azure Front Door + WAF |
| HA / Multi-Region | Einzelnes Replikat in einer Region | Azure-native Multi-Region-Architektur |
| Feste Outbound-IP für SMTP-Drittanbieter | Dynamische Outbound-IPs im Consumption Plan | Härtungsstufe 1 mit NAT Gateway |
| Mehr als ~500 Nutzer | B1ms PostgreSQL + einzelnes Replikat sind KMU-dimensioniert | Größerer PostgreSQL-Tier + Workload Profiles |
| Strenge Compliance (SOC 2, ISO 27001) | Öffentlicher PostgreSQL-Zugriff genügt nicht | Enterprise-Architektur mit Private Endpoints und NSGs |

> **Kurzregel:** Wenn du „Application Gateway", „Private Endpoints" oder „Multi-Region" brauchst, ist dieses Template der falsche Startpunkt. Es ist bewusst für **einfache, kostengünstige KMU-Deployments** gebaut.

---

## Deploy

Es gibt jetzt bewusst **zwei** Deploy-Pfade:

1. **Basic Mode / Azure-only** über den bestehenden **Deploy-to-Azure-Button**
2. **Production Mode / Cloudflare-managed** über den neuen **Wizard `scripts/Invoke-CustomerDeployment.ps1`**

Der Basic Mode bleibt der einfache Azure-Pfad ohne Cloudflare-Automatisierung. Der Production Mode erzeugt unter `customers/<slug-aus-vaultwarden-domain>/...` eine Kundenkonfiguration, generiert daraus die Azure-Parameterdatei und schreibt zusätzlich eine **aktive Kopie** nach `current/`. Der Deploy-to-Azure-Button zeigt auf diese aktive Kopie.

[![Deploy to Azure (ARM JSON)](
https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true
)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmaster%2Fcurrent%2Fmain.deploytoazure.json
)
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmaster%2Fcurrent%2Fmain.deploytoazure.json)
> **Hinweis:** Wenn du dieses Repo forkst oder Owner/Branch änderst, muss die Raw-URL im Button oben angepasst werden.

Für ein lokales Deployment ohne GitHub-Hosting: Azure Portal → **Benutzerdefinierte Vorlage bereitstellen** → **Eigene Vorlage im Editor erstellen** und `main.json` einfügen.

**Basic Mode (Deploy-to-Azure-Button):**
- verwendet `current/main.deploytoazure.json` als aktive Portal-Eingabemaske
- nested deploy auf `main.json`
- Azure-only
- kein Cloudflare
- deutlich mehr einstellbare Basisparameter im Portal
- Custom Domain / TLS für ACA bleibt manuell

**Production Mode (Wizard / Wrapper):**
- `scripts/Invoke-CustomerDeployment.ps1`
- erzeugt `customers/<slug-aus-vaultwarden-domain>/deployment.config.json`
- generiert `customers/<slug-aus-vaultwarden-domain>/azure.parameters.json`
- Azure-Deploy + Cloudflare-DNS/SSL/WAF/Rate-Limits + optionaler Origin-Lockdown

**Bewusst manuell oder extern bleibende Themen:**
- ACS DNS-Verifikation der E-Mail-Domain
- ACS Domain-Linking + SMTP-Username
- echte produktive Secrets sollten nicht in Git eingecheckt werden

Diese Schritte und die neue Trennung zwischen Basic-/Production-Mode sind im [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md) dokumentiert.

---

## Architektur-Überblick

![Vaultwarden on Azure Container Apps – Baseline Architecture](./docs/diagrams/vaultwarden-aca-architecture.svg)

Detaillierte Beschreibung der Ressourcen, Datenflüsse und Designentscheidungen: [docs/architecture.md](./docs/architecture.md)

---

## Was `main.json` deployt

### Immer enthalten
- Container Apps Environment + Log Analytics
- Container App mit Startup-, Liveness- und Readiness-Probes
- Storage Account + Azure Files Share (`/data`)
- PostgreSQL Flexible Server + Datenbank
- User Assigned Managed Identities (App-Reader + Script-Writer)
- Key Vault (RBAC) mit Purge Protection
- Deployment Script (DB-User, `ADMIN_TOKEN`, `DATABASE_URL`, SMTP-/SSO-/Push-Secrets, MX-Lookup)
- Azure-Files-Backup über Recovery Services Vault (standardmäßig aktiv)
- Diagnostic Settings für Key Vault und PostgreSQL

### Optional: ACS Foundation
Wenn `acsDeployFoundation = true`:
- Email Service, Email Domain Resource, Communication Service

DNS-Verifikation, Domain-Linking und SMTP-Username bleiben manuelle Post-Deploy-Aufgaben (→ [Playbook §7](./docs/HowToInstall/Operation-Playbook.md#7-mail-konfiguration-und--betrieb)).

> **Hinweis:** Wenn `acsDeployFoundation = true`, aber weder `acsDomainName` noch `mailRootDomain` angegeben wird, werden die ACS-Ressourcen **nicht** deployt. Das Deployment gibt eine explizite **WARNING** aus.

### Bewusst **nicht** automatisiert
- ACA Custom Domain / Zertifikatsbindung
- ACS Domain-Verifikation, `linkedDomains`, `smtpUsernames`
- ACS-RBAC für die SMTP-Entra-App

---

## Wichtige Sicherheitshinweise

> **`/data/config.json` kann ENV-Variablen überlagern.** Vaultwarden speichert Admin-UI-Änderungen persistent in `/data/config.json` auf dem Azure-Files-Share. Diese Werte haben bei nachfolgenden Container-Starts **Vorrang vor ENV-Variablen**. Admin-Panel nach Bootstrap deaktivieren (`adminPanelEnabled=false`) und sicherstellen, dass kein persistierter `admin_token` zurückbleibt.

- **Admin-Panel-Lifecycle:** Erstdeployment mit `adminPanelEnabled=true`; nach Bootstrap/Tests Redeploy mit `adminPanelEnabled=false`. **Achtung:** Falls der `admin_token` bereits in `/data/config.json` persistiert wurde, muss er dort manuell entfernt werden (Azure Files Share → `vaultwarden/config.json` → Schlüssel `admin_token` löschen), sonst bleibt das Admin-Panel trotz `adminPanelEnabled=false` aktiv.
- **`signupsDomainsWhitelist`:** Dieser Parameter erlaubt Self-Registrierung für die angegebenen Domains **auch wenn `SIGNUPS_ALLOWED=false`** (hardcoded). Das ist gewolltes Vaultwarden-Verhalten, aber ein häufiger Irrtum. Nur setzen, wenn Self-Registrierung für bestimmte Domains bewusst gewünscht ist.
- **SSO:** `ssoOnly=true` erfordert `ssoEnabled=true` und deaktiviert den Master-Passwort-Login vollständig. SSO vorher gründlich testen.
- **Push:** Erfordert Bitwarden Installation ID + Key von https://bitwarden.com/host/. Ohne Push funktionieren Clients, aber ohne Echtzeit-Sync.
- **Gehärtete Defaults:** HTTP deaktiviert, Image gepinnt, Signups aus, Passwort-Hints aus, SSRF-Schutz aktiv, `IP_HEADER=X-Forwarded-For` gesetzt. Details in [HARDENING.md](./HARDENING.md).
- **Key Vault Purge Protection:** Der Key Vault wird mit Soft Delete (90 Tage) und Purge Protection deployt. Nach Löschung einer Resource Group bleibt der Key-Vault-Name 90 Tage reserviert. Vor einem erneuten Deployment in eine neue RG muss der gelöschte Key Vault manuell gepurgt werden (`az keyvault purge --name <kvName>`) oder ein anderer `appName`-Wert verwendet werden.

---

## Bekannte Tradeoffs und Härtungsstufen

### Bewusste Architekturentscheidungen

| Tradeoff | Auswirkung | Mitigation |
|---|---|---|
| Kein VNet / Keine Private Endpoints | Backend-Dienste nicht netzwerkisoliert | `AllowAzureServices`-Firewallregel; Härtungsstufe 2 |
| Keine feste Outbound-IP | PostgreSQL-Firewall kann ACA nicht spezifisch einschränken | M365 / ACS SMTP; Härtungsstufe 1 |
| Keine WAF | Kein Request-Filtering am Edge | ACA HTTPS-Ingress + Vaultwarden-internes Rate Limiting |
| Einzelnes Replikat, einzelne Region | Kein HA, kein Multi-Region-DR | Probes für Auto-Restart; Azure-Files-Backup + PostgreSQL-PITR |
| Admin-Panel überschreibt ENV | `/data/config.json` persistiert über Redeployments | Admin-Panel nach Bootstrap deaktivieren |
| Azure Files statt Managed Disk | Backup-Zeitpunkt kann von PostgreSQL abweichen | Restore-Drills durchführen |

### Härtungsstufen

| Stufe | Was kommt dazu | Mehrkosten |
|---|---|---|
| **0 – Baseline (Default)** | ACA Direct Ingress, öffentl. PostgreSQL mit `AllowAzureServices`, Key Vault RBAC, Backup, Diagnostics | ~30–50 €/Monat |
| **1 – Fester Egress** | VNet-Integration, NAT Gateway, spezifische PostgreSQL-Firewall | +30–50 €/Monat |
| **2 – Enterprise-Härtung** | Private Endpoints (PostgreSQL, Key Vault, Storage), Private DNS Zones, optionale WAF | +100–200 €/Monat |

> Jede Stufe erhöht die betriebliche Komplexität. Abwägen, ob die zusätzliche Sicherheit die Kosten für die eigene Organisation rechtfertigt.

---

## Go-Live-Checkliste

Vor dem produktiven Einsatz müssen folgende Punkte abgearbeitet sein:

### Pflicht (vor Go-Live)

- [ ] Deployment erfolgreich, Container App erreichbar über ACA-FQDN
- [ ] `domainUrl` zeigt auf die korrekte öffentliche URL (`https://...`)
- [ ] Custom Domain + TLS-Zertifikat an Container App gebunden (→ [Playbook §6](./docs/HowToInstall/Operation-Playbook.md))
- [ ] SMTP-Mailversand getestet (Einladungsmail oder Admin-Test-Mail)
- [ ] Ersten Admin-Benutzer über Einladung angelegt und angemeldet
- [ ] Admin-Panel deaktiviert: Redeploy mit `adminPanelEnabled=false`
- [ ] Prüfen, ob `/data/config.json` auf Azure Files einen persistierten `admin_token` enthält – falls ja, entfernen
- [ ] Backup verifiziert: Azure Files Backup-Job läuft, PostgreSQL PITR aktiv
- [ ] `signupsDomainsWhitelist` bewusst gesetzt oder leer (= keine Self-Registrierung)
- [ ] `orgCreationUsers` auf Admin-Benutzer eingeschränkt oder leer gelassen (= alle)
- [ ] DNS-Einträge für Mail (SPF, DKIM) korrekt gesetzt
- [ ] Key Vault Diagnostic Settings aktiv (Log Analytics)

### Empfohlen (zeitnah nach Go-Live)

- [ ] SSO konfiguriert und getestet (falls gewünscht)
- [ ] Push Notifications konfiguriert (falls gewünscht)
- [ ] Restore-Drill durchgeführt: Azure Files Restore + PostgreSQL PITR
- [ ] Monitoring/Alerting auf Container-Neustart und PostgreSQL-Metriken eingerichtet
- [ ] Vaultwarden-Image-Version-Strategie dokumentiert (wann/wie aktualisieren)

---

## Betriebs-Checkliste (laufender Betrieb)

| Intervall | Aufgabe |
|---|---|
| **Wöchentlich** | Azure Files Backup-Status prüfen |
| **Monatlich** | Vaultwarden-Releases auf neue Versionen prüfen; bei Sicherheits-Patches zeitnah aktualisieren |
| **Monatlich** | Key Vault Audit-Logs auf unerwartete Zugriffe prüfen |
| **Quartalsweise** | Restore-Drill: Azure Files + PostgreSQL PITR testen |
| **Quartalsweise** | SMTP-Funktion testen (Test-Einladung senden) |
| **Bei Bedarf** | TLS-Zertifikat erneuern (falls nicht automatisch über Cloudflare/Let's Encrypt) |
| **Bei Bedarf** | PostgreSQL-Administratorkennwort rotieren (betrifft nur Bootstrap, nicht den App-User) |

Detaillierte Anleitungen: [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md)

---

## Bekannte Einschränkungen und Caveats

| Einschränkung | Auswirkung | Mitigation |
|---|---|---|
| Key Vault Purge Protection (90 Tage) | Nach RG-Löschung ist der KV-Name 90 Tage reserviert; erneutes Deployment schlägt fehl | `az keyvault purge --name <kvName>` vor erneutem Deployment oder anderen `appName` verwenden |
| `dbPassword` regeneriert sich bei jedem Deployment | ARM-Funktion `newGuid()` erzeugt neuen Wert; wird nur bei Erstanlage des PostgreSQL-Servers verwendet | Sicher bei Redeployments – PostgreSQL ignoriert das Passwort bei bestehenden Servern |
| `signupsDomainsWhitelist` umgeht `SIGNUPS_ALLOWED=false` | Eingetragene Domains können sich selbst registrieren | Nur bewusst setzen; leer lassen wenn keine Self-Registrierung gewünscht |
| Azure Files ist kein transaktionaler Store | Backup-Zeitpunkt `/data` kann von PostgreSQL-PITR abweichen | Restore-Drills durchführen; Datenbank ist die autoritative Quelle |
| Einzelnes Replikat | Kurzer Ausfall bei Container-Restart oder Deployment | Probes sorgen für automatischen Restart; für KMU-Größe akzeptabel |

---

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [Operations Playbook / Runbook](./docs/HowToInstall/Operation-Playbook.md) | Go-Live, Mail (SMTP Auth / Direct Send / ACS), SSO, Push, Update/Upgrade, Observability, Backup/Recovery, Troubleshooting |
| [Architektur-Referenz](./docs/architecture.md) | Detaillierte Architektur, Tradeoffs, Härtungsstufen, Redeploy-Verhalten |
| [Parameter-Referenz](./docs/reference/parameters.md) | Vollständige Parameterliste mit ENV-Mapping |
| [Vaultwarden – How to Use (BSSE)](./docs/HowToUse/HowToUse.pdf) | Endbenutzer-Anleitung |
| [Changelog `main.json`](./docs/changes.md) | Revisioniertes Änderungsprotokoll |
| [Gehärtete Defaults](./HARDENING.md) | Produktionsgehärtete Standardwerte im Template |
| [Quellen](./docs/reference/sources.md) | Geprüfte Quellenlinks (ACS, M365, Bitwarden/Vaultwarden) |
| [Beispiel-Parameterdateien](./examples/parameters/) | Szenariospezifische Vorlagen (M365, SSO, Push, ACS) |

### Beispiel-Parameterdateien

Unter `./examples/parameters/` liegen einsatznahe Vorlagen:

| Datei | Szenario |
|---|---|
| `main.parameters.m365-smtp-auth.example.json` | M365-SMTP-Auth-Standardpfad |
| `main.parameters.m365-smtp-auth-sso.example.json` | M365 SMTP Auth + Entra-ID-SSO |
| `main.parameters.m365-smtp-auth-sso-push.example.json` | M365 SMTP Auth + SSO + Push |
| `main.parameters.m365-direct-send.example.json` | Direct Send (nur interne Szenarien) |
| `main.parameters.acs-foundation-m365-dns-hosted.example.json` | ACS Foundation mit M365-DNS |

Alle Dateien enthalten **nur Platzhalterwerte** und müssen vor dem produktiven Einsatz angepasst werden.

---

## Repo-Struktur

| Pfad | Beschreibung |
|---|---|
| `main.json` | Primäres ARM-Deployment-Template (alle Ressourcen) |
| `main.deploytoazure.json` | Deploy-to-Azure-Wrapper mit breiterem Parameterdialog für den Basic-Pfad |
| `customers/<slug-aus-vaultwarden-domain>/...` | Kundenbezogene Konfiguration, generierte Azure-Parameterdatei und Deploy-Artefakte für den Wizard-Pfad |
| `scripts/Invoke-CustomerDeployment.ps1` | Interaktiver Wizard / Wrapper für den produktiven Cloudflare-Pfad |
| `scripts/Set-CloudflareZoneConfig.ps1` | Cloudflare DNS / SSL / WAF / Rate-Limit API-Orchestrierung |
| `scripts/Bind-AcaCustomDomain.ps1` | Origin-Zertifikat erzeugen, hochladen und ACA-Hostname binden |
| `main.bicep` | ⚠️ Ältere Bicep-Referenz – **nicht gepflegt**, nicht für Deployments verwenden |
| `scripts/deploy.ps1` | Optionaler PowerShell-Wrapper für CLI-basiertes Deployment |
| `docs/architecture.md` | Detaillierte Architektur, Tradeoffs, Härtungsstufen |
| `docs/HowToInstall/Operation-Playbook.md` | Betriebshandbuch (24 Abschnitte) |
| `docs/HowToUse/` | Endbenutzer-Dokumentation (PDF + Markdown) |
| `docs/operations/` | Navigationsseiten zu Playbook-Abschnitten (Runbook, Troubleshooting, Upgrades, SMTP/ACS) |
| `docs/reference/` | Parameter-Referenz und Quellen |
| `docs/changes.md` | Changelog für `main.json` |
| `examples/parameters/` | Parameterdatei-Vorlagen für typische Szenarien |
| `HARDENING.md` | Gehärtete Defaults |

---

## Changelog

Das revisionierte Änderungsprotokoll aller Änderungen an `main.json` befindet sich in [docs/changes.md](./docs/changes.md).

---

## Quellen

Die verlinkten Aussagen in README und Playbook wurden zuletzt **am 2026-03-20 16:02 CET** gegengeprüft. Die vollständige Quellenliste steht in [docs/reference/sources.md](./docs/reference/sources.md) und im [Operations Playbook §24](./docs/HowToInstall/Operation-Playbook.md#24-quellen).

Wichtigste Referenzen:
- [Bitwarden: Installation ID & Key](https://bitwarden.com/host/)
- [Vaultwarden SSO via OpenID Connect (Wiki)](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect)
- [Vaultwarden Mobile Push (Wiki)](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification)
- [ACS SMTP-Authentifizierung](https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email-smtp/smtp-authentication)

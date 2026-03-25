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
- ACS Domain-Linking + SMTP-Username

Diese Schritte erfordern DNS-Propagation und externe Verifikation und können nicht zuverlässig in einem einzelnen Deployment automatisiert werden. Sie sind im [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md) dokumentiert.

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

- **Admin-Panel-Lifecycle:** Erstdeployment mit `adminPanelEnabled=true`; nach Bootstrap/Tests Redeploy mit `adminPanelEnabled=false`.
- **SSO:** `ssoOnly=true` erfordert `ssoEnabled=true` und deaktiviert den Master-Passwort-Login vollständig. SSO vorher gründlich testen.
- **Push:** Erfordert Bitwarden Installation ID + Key von https://bitwarden.com/host/. Ohne Push funktionieren Clients, aber ohne Echtzeit-Sync.
- **Gehärtete Defaults:** HTTP deaktiviert, Image gepinnt, Signups aus, Passwort-Hints aus, SSRF-Schutz aktiv. Details in [README.HARDENED.md](./README.HARDENED.md).

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

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [Operations Playbook / Runbook](./docs/HowToInstall/Operation-Playbook.md) | Go-Live, Mail (SMTP Auth / Direct Send / ACS), SSO, Push, Update/Upgrade, Observability, Backup/Recovery, Troubleshooting |
| [Architektur-Referenz](./docs/architecture.md) | Detaillierte Architektur, Tradeoffs, Härtungsstufen, Redeploy-Verhalten |
| [Parameter-Referenz](./docs/reference/parameters.md) | Vollständige Parameterliste mit ENV-Mapping |
| [Vaultwarden – How to Use (BSSE)](./docs/HowToUse/HowToUse.pdf) | Endbenutzer-Anleitung |
| [Changelog `main.json`](./docs/changes.md) | Revisioniertes Änderungsprotokoll |
| [Gehärtete Defaults](./README.HARDENED.md) | Produktionsgehärtete Standardwerte im Template |
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
| `main.bicep` | ⚠️ Ältere Bicep-Referenz – **nicht gepflegt**, nicht für Deployments verwenden |
| `scripts/deploy.ps1` | Optionaler PowerShell-Wrapper für CLI-basiertes Deployment |
| `docs/architecture.md` | Detaillierte Architektur, Tradeoffs, Härtungsstufen |
| `docs/HowToInstall/Operation-Playbook.md` | Betriebshandbuch (24 Abschnitte) |
| `docs/HowToUse/` | Endbenutzer-Dokumentation (PDF + Markdown) |
| `docs/operations/` | Navigationsseiten zu Playbook-Abschnitten (Runbook, Troubleshooting, Upgrades, SMTP/ACS) |
| `docs/reference/` | Parameter-Referenz und Quellen |
| `docs/changes.md` | Changelog für `main.json` |
| `examples/parameters/` | Parameterdatei-Vorlagen für typische Szenarien |
| `README.HARDENED.md` | Gehärtete Defaults |

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

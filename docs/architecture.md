# Architektur – Vaultwarden auf Azure Container Apps


## Architektur-Diagramm

![Vaultwarden on Azure Container Apps – Baseline Architecture](./diagrams/vaultwarden-aca-architecture.svg)

> **Quell-Datei zum Bearbeiten:** [`docs/diagrams/vaultwarden-aca-architecture.drawio`](./diagrams/vaultwarden-aca-architecture.drawio) – öffnen mit [app.diagrams.net](https://app.diagrams.net) oder der VS-Code-Extension *Draw.io Integration*.
> Nach dem Bearbeiten als SVG exportieren und unter `docs/diagrams/vaultwarden-aca-architecture.svg` speichern.

---
Dieses Dokument beschreibt die Architektur, bewusste Tradeoffs und optionale Härtungsstufen des Vaultwarden-ACA-Templates im Detail. Es ergänzt die kompakte Übersicht in der [Readme.md](../Readme.md).

---

## Komponentenübersicht

Das ARM-Template (`main.json`) deployt eine vollständige Vaultwarden-Umgebung als einzelnes Deployment:

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

---

## Designphilosophie

Dieses Repository richtet sich an **KMUs**, die einen sicheren, produktionsreifen Passwortmanager brauchen – ohne Enterprise-Kosten oder -Komplexität. Die Architektur nutzt bewusst:

- **ACA Direct Ingress** (kein Application Gateway oder Front Door als Default)
- **Öffentlichen PostgreSQL-Zugriff mit Firewall-Regeln** (kein VNet/Private Endpoint als Default)
- **Consumption-Tier ACA** (keine Workload Profiles als Default)
- **Alles in einem einzigen ARM-Template** für maximale Einfachheit

---

## ACA-Netzwerk-Tradeoffs

Azure Container Apps im Consumption Plan bietet **keine feste Outbound-IP**. Das hat folgende Konsequenzen:

| Einschränkung | Auswirkung | Mitigation |
|---|---|---|
| Dynamische Outbound-IPs | Keine spezifische PostgreSQL-Firewall-Regel für ACA möglich | `allowAzureServicesToPostgres=true` (0.0.0.0-Regel) erlaubt allen Azure-Diensten den Zugriff |
| Kein statischer Egress | SMTP-Server von Drittanbietern, die IP-Allowlisting erwarten, können Verbindungen ablehnen | Microsoft 365 SMTP oder ACS SMTP verwenden – dort ist kein Sender-IP-Allowlisting nötig |
| Keine eingebaute WAF | Kein Request-Filtering am Edge | ACA HTTPS-Ingress liefert TLS-Terminierung; Vaultwarden hat eigenes Rate Limiting; für WAF siehe Härtungsstufen |

Der Default `allowAzureServicesToPostgres=true` ist für Consumption-Plan-ACA erforderlich. Er öffnet PostgreSQL für alle Azure-Dienste (nicht das öffentliche Internet) – ein akzeptabler Tradeoff für KMU-Einsatz.

---

## Bewusste Tradeoffs

Diese Tradeoffs sind **bewusste Architekturentscheidungen** für den KMU-Fokus dieses Templates:

| Tradeoff | Entscheidung | Auswirkung | Mitigation |
|---|---|---|---|
| Kein VNet / Keine Private Endpoints | ACA Consumption Plan, öffentlicher PostgreSQL-Zugriff | Backend-Dienste sind nicht netzwerkisoliert | `AllowAzureServices`-Firewallregel; Härtungsstufe 2 für Private Endpoints |
| Keine feste Outbound-IP | ACA Consumption Plan hat dynamische Egress-IPs | PostgreSQL-Firewall kann ACA nicht spezifisch einschränken; SMTP-Drittanbieter ggf. nicht nutzbar | Microsoft 365 / ACS SMTP verwenden; Härtungsstufe 1 für NAT Gateway |
| Keine WAF | Kein Application Gateway oder Front Door | Kein Request-Filtering am Edge | ACA HTTPS-Ingress + Vaultwarden-internes Rate Limiting; Härtungsstufe 2 für WAF |
| Einzelnes Replikat | ACA läuft mit `maxReplicas: 1` | Kein HA, kurzer Ausfall bei ACA-Neustarts | Für KMU-Größe akzeptabel; `liveness`-/`readiness`-Probes sorgen für automatischen Restart |
| Einzelne Region | Kein Multi-Region-Setup | Kein Disaster Recovery in eine andere Region | Azure-Files-Backup + PostgreSQL-PITR für Restore-in-Place |
| Azure Files statt Managed Disk | Vaultwarden benötigt ein beschreibbares Volume | Azure Files ist kein transaktionaler Store; Backup-Zeitpunkt kann von PostgreSQL abweichen | Restore-Drills durchführen; Dokumentation im Operations Playbook |
| Admin-Panel überschreibt ENV | `/data/config.json` persistiert UI-Änderungen über Redeployments | Im Admin-UI gespeicherte Werte haben Vorrang vor Template-Parametern | Admin-Panel nach Bootstrap deaktivieren (`adminPanelEnabled=false`) |

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

## Härtungsstufen

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

## Deployment-Outputs

### Standard-Outputs

Das Deployment gibt die üblichen ARM-Deployment-Outputs zurück (Ressourcen-IDs, URLs).

### ACS-Foundation-Outputs

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

---

## Vaultwarden-spezifische Architekturhinweise

1. **`DATABASE_URL`** – Vaultwarden nutzt eine einzelne `DATABASE_URL` für PostgreSQL (keine getrennten DB-ENV-Variablen). Die URL wird vom Bootstrap-Script generiert und in Key Vault abgelegt.

2. **`/data/config.json`-Persistenz** – Vaultwarden speichert Admin-UI-Änderungen persistent in `/data/config.json` auf dem Azure-Files-Share. Diese Werte haben bei nachfolgenden Container-Starts **Vorrang vor ENV-Variablen**. Das ist bekanntes Vaultwarden-Verhalten und erfordert bewusstes Management.

3. **Mail-Service-Aktivierung** – Der Vaultwarden-Maildienst aktiviert sich, wenn `SMTP_FROM` und entweder `SMTP_HOST` oder `USE_SENDMAIL` gesetzt sind. `DOMAIN` muss korrekt sein, damit E-Mail-Links auf den richtigen Host zeigen.

4. **Direct Send: Auth-Variablen müssen fehlen** – Für Direct Send dürfen `SMTP_USERNAME`, `SMTP_PASSWORD` und `SMTP_AUTH_MECHANISM` in der App-Konfiguration nicht vorhanden sein. Das Template lässt diese korrekt weg, wenn `smtpUseAuth=false`.

5. **Bootstrap-Script** – Das Script hängt explizit von der optionalen PostgreSQL-Firewall-Regel `AllowAzure` ab, wenn `allowAzureServicesToPostgres=true`. Interne Warte-/Retry-Fenster sind auf 10 Minuten gesetzt, damit RBAC- und Firewall-Propagation nicht in Timing-Fehler laufen.


---

## Weiterführende Dokumentation

- [Readme.md](../Readme.md) – Einstiegsseite mit Deploy-Button und kompakter Übersicht
- [Operations Playbook](./HowToInstall/Operation-Playbook.md) – Betriebshandbuch für Go-Live, Betrieb und Recovery
- [Vaultwarden – How to Use](./HowToUse/HowToUse.pdf) – Endbenutzer-Anleitung
- [Parameter-Referenz](./reference/parameters.md) – Vollständige Parameterliste mit ENV-Mapping
- [Gehärtete Defaults](../README.HARDENED.md) – Produktionsgehärtete Standardwerte im Template


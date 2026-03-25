# Architektur – Vaultwarden auf Azure Container Apps

## Architektur-Diagramm

![Vaultwarden on Azure Container Apps – Baseline Architecture](./diagrams/vaultwarden-aca-architecture.svg)

> **Quell-Datei zum Bearbeiten:** [`docs/diagrams/vaultwarden-aca-architecture.drawio`](./diagrams/vaultwarden-aca-architecture.drawio) – öffnen mit [app.diagrams.net](https://app.diagrams.net) oder der VS-Code-Extension *Draw.io Integration*.
> Nach dem Bearbeiten als SVG exportieren und unter `docs/diagrams/vaultwarden-aca-architecture.svg` speichern.

---

## Baseline-Ressourcen (immer deployt)

| Ressource | Aufgabe |
|---|---|
| **Container Apps Environment** | Hosting-Umgebung für die Container App; gebunden an Log Analytics |
| **Azure Container App** | Vaultwarden-Docker-Image, HTTPS-Ingress, `/data`-Mount über Azure Files, Secrets via Key Vault |
| **Azure Files (Storage Account)** | Persistenter Datenspeicher für `/data` (File Share) |
| **Azure Database for PostgreSQL Flexible Server** | Relationale Datenhaltung; App-User + `DATABASE_URL` werden durch das Deployment Script erzeugt |
| **Azure Key Vault** | RBAC-basierter Secret Store für `DATABASE_URL`, SMTP-Credentials, SSO-Secrets und Push-Secrets |
| **User Assigned Managed Identities** | App-Identity (Key Vault Secrets User) und KV-Writer-Identity (Key Vault Secrets Officer) |
| **Deployment Script** | Bootstrap: legt DB-App-User an, schreibt Secrets in Key Vault (ADMIN_TOKEN, DATABASE_URL, SMTP, SSO, Push) |
| **Recovery Services Vault** | Backup der Azure Files (tägliche + wöchentliche Retention) |
| **Log Analytics Workspace** | Ziel für Container-App-Logs und Diagnostic Settings |
| **Diagnostic Settings** | Leiten Key-Vault- und PostgreSQL-Logs an Log Analytics weiter |

## Optionale Ressourcen

| Ressource | Bedingung | Aufgabe |
|---|---|---|
| **ACS Email Service** | `acsDeployFoundation = true` | Azure Communication Services – E-Mail-Dienst |
| **ACS Email Domain Resource** | `acsDeployFoundation = true` | Custom Domain für ACS E-Mail (DNS-Verifikation manuell) |
| **ACS Communication Service** | `acsDeployFoundation = true` | Kommunikationsdienst (Domain Linking + SMTP-Finalisierung manuell) |

Die ACS Foundation wird nur deployt, wenn `acsDeployFoundation = true` gesetzt ist. DNS-Verifikation, Domain Linking und SMTP-Username bleiben bewusst manuelle Post-Deploy-Schritte.

---

## Datenflüsse und Beziehungen

1. **End User → Internet → Container App** – Zugriff über HTTPS (Port 443) auf den Container App Ingress.
2. **Container App → Key Vault** – Die App liest Secrets über versionlose Key-Vault-Secret-URIs (secret refs im Container-App-Manifest).
3. **Container App → Azure Files** – `/data` wird als Volume-Mount über die Container Apps Environment Storage bereitgestellt.
4. **Container App → PostgreSQL** – Verbindung über `DATABASE_URL` (Secret aus Key Vault).
5. **Deployment Script → Key Vault** – Schreibt und aktualisiert Bootstrap-Secrets.
6. **Deployment Script → PostgreSQL** – Legt den App-User und die Datenbank an.
7. **Managed Identities → Key Vault** – RBAC-Zuweisungen: App-Identity als Secrets User, KV-Writer-Identity als Secrets Officer.
8. **Recovery Services Vault → Azure Files** – Backup-Policy mit konfigurierbarer Daily-/Weekly-Retention.
9. **Diagnostic Settings → Log Analytics** – Key-Vault- und PostgreSQL-Diagnose-Logs werden an den Log-Analytics-Workspace gesendet.

---

## Bewusste Designentscheidungen

- **Baseline mit öffentlichem PostgreSQL-Zugriff** – Firewallregeln + „Allow Azure Services"; für kleinere Umgebungen einfacher und günstiger.
- **Kein VNet / Private Endpoint im Baseline** – Gehärtete Varianten (ACA in VNet, Private Access für PostgreSQL, NAT Gateway) sind als Ausbaustufe dokumentiert, aber nicht im Core-Template.
- **Deployment Script statt Pipeline** – Bootstrap-Logik läuft als ARM Deployment Script; kein separater CI/CD-Pfad nötig.
- **Manuelle Post-Deploy-Schritte für Custom Domain und ACS** – DNS-Verifikation und Zertifikatsbindung erzeugen Henne/Ei-Themen und bleiben daher bewusst manuell.

Weitere Details zu Tradeoffs und Hardening stehen im [README](../Readme.md) und in der [README.HARDENED.md](../README.HARDENED.md).

---

## Weiterführende Dokumentation

- [README (Einstieg, Deploy, Parameter)](../Readme.md)
- [Operations Playbook / Runbook](./HowToInstall/Operation-Playbook.md)
- [Vaultwarden – How to Use](./HowToUse/HowToUse.pdf)

# Phase 0 – Zielarchitektur und Leitplanken

Status: `[ ]`

## Ist-Befund

- Produktiver Wizard-Einstieg ist `scripts/Invoke-CustomerDeployment.ps1`.
- Menü-/Flow-Logik liegt bereits modular in `scripts/lib/VaultwardenDeployment.*.ps1`.
- Persistente Kundenkonfiguration liegt in `customers/<slug>/deployment.config.json`.
- `azure.parameters.json` ist generiert und kann Secure-Werte enthalten; es ist kein persistenter Source-of-Truth.
- `current/` ist ein veränderlicher Deploy-to-Azure-Kompatibilitätspfad und nicht concurrency-sicher für mehrere Kunden.
- Operative Deployments verwenden aktuell `main.json`.
- `main.bicep` existiert bereits, ist aber derzeit aus `main.json` dekompiliert und damit nicht Source-of-Truth.
- GitHub-spezifische Kopplungen existieren in Workflow, Raw-URLs, Deploy-to-Azure-Wrappern und Template-Traceability.
- `Deploy-AzureStack.ps1` nutzt derzeit `cmd.exe /c az` und ist dadurch unnötig Windows-spezifisch.
- Cloudflare-DNS-/Ruleset-Operationen sind weitgehend convergent.
- Custom-Domain-/Origin-CA-Zertifikatsbindung erzeugt aktuell bei erneutem Lauf neue Zertifikate und ist damit kein sauberes Ensure-Verhalten.
- Repair und Update sind im UI getrennt, laufen technisch aber weitgehend durch denselben Deploymentpfad.

## Verbindliches Zielbild

### Sources of Truth

1. `main.bicep` = Azure-Infrastruktur.
2. `customers/<slug>/deployment.config.json` = persistente gewünschte Kundenkonfiguration.
3. Secrets = Runtime Secret Store / Azure DevOps / Key Vault; niemals Git.
4. Generated parameter files = vergängliche Laufzeitartefakte.
5. Pipeline-Artefakte = Logs, Deployment-Outputs und Diagnoseartefakte, sofern sie nicht explizit persistenter Reconciliation-State sein müssen.

### Bedienmodell

- Der Techniker arbeitet weiterhin über den lokalen PowerShell-CLI-Wizard.
- Azure DevOps ist Backend und soll im Normalbetrieb nicht manuell geöffnet werden müssen.
- Der Wizard speichert/validiert Konfiguration und stößt das Deployment eines exakten Git-Stands an.
- Die Pipeline führt Validate → Prepare → What-If → Deploy → PostDeploy → Verify aus.

### Authentifizierungsmodell

- Kein persönlicher `az login` als Pipeline-Credential.
- Kein weitergereichtes Benutzer-Access-Token.
- Kein dauerhafter PAT für den Deploymentpfad.
- Azure Pipeline authentifiziert sich über Azure Resource Manager Service Connection + Workload Identity Federation.
- Eine Deployment Identity wird pro sinnvoller Trust-/Privilege-Boundary wiederverwendet, typischerweise Kunde + Environment.
- Nicht eine Identity pro Workload/Repo und nicht eine globale Identity für alle Kunden.
- Der privilegierte Erst-Bootstrap ist vom normalen Workload-Deployment getrennt.

### PlatformBootstrap

- Bootstrap gehört konzeptionell in die zentrale DevOps-Plattform, nicht in Vaultwarden-spezifische Fachlogik.
- Workload-Wizards konsumieren nur `Ensure-CustomerDeploymentProfile`.
- Wenn Profil fehlt, startet Bootstrap automatisch ohne Rückfrage.
- Bootstrap muss idempotent prüfen/erstellen/reparieren:
  - Customer Tenant/Subscription Kontext
  - User Assigned Managed Identity oder äquivalente WIF-fähige Deployment Identity
  - benötigte RBAC-Zuweisungen
  - Federated Identity Credential
  - Azure DevOps Service Connection
  - Pipeline-Autorisierung
  - zentrale Customer Deployment Registry
  - End-to-End-Verbindungstest

## Architekturentscheidungen

### AD-001 – Bicep ist Source-of-Truth
Status: `[ ]`

`main.json` darf nach Cutover nicht mehr manuell gepflegte Infrastrukturquelle sein.

### AD-002 – Kunden-JSON bleibt bestehen
Status: `[ ]`

Die Migration ARM→Bicep betrifft die Infrastrukturdefinition, nicht die persistente Kundenkonfiguration.

### AD-003 – CLI bleibt Frontend
Status: `[ ]`

Kein Zwang für Techniker, Azure DevOps UI für Standarddeployments zu bedienen.

### AD-004 – PlatformBootstrap ist workload-unabhängig
Status: `[ ]`

Vaultwarden darf die zentrale Deployment Identity nicht als Vaultwarden-spezifische Ressource modellieren.

### AD-005 – Identity pro Privilege Boundary
Status: `[ ]`

Default: Kunde + Environment. Weitere Trennung nur bei abweichendem Sicherheits-/Berechtigungsbedarf.

### AD-006 – Deployment ist commitgebunden
Status: `[ ]`

Pipeline muss `customerCode`, `operation` und eindeutigen Commit/SHA erhalten bzw. selbst eindeutig auflösen.

### AD-007 – Kein `current/` im Zielbetrieb
Status: `[ ]`

Der mutable Deploy-to-Azure-Pointer wird nach erfolgreichem Pipeline-Cutover entfernt.

## Phase-0-Gate

Phase 0 darf erst `[x]` werden, wenn alle Architekturentscheidungen AD-001 bis AD-007 in Code-/Repo-Konventionen oder nachfolgenden Workchunks eindeutig verankert und ohne widersprüchliche Zielvorgaben dokumentiert sind.

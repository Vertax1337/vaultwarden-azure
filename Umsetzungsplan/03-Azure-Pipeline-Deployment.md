# Phase 3 – Azure Pipeline als Deployment-Backend

Status: `[ ]`

## Ziel

Das eigentliche Deployment wird aus der lokalen Benutzersession herausgelöst und reproduzierbar durch Azure Pipelines ausgeführt.

## WC-03.1 – Deployment-Pipeline anlegen
Status: `[ ]`

### Zielstruktur
`pipelines/deploy.yml`

### Eingaben
Mindestens:
- `customerCode`
- `operation`
- eindeutiger `commitSha` bzw. Pipeline-Commit

Erlaubte Operationen initial:
- `deploy`
- `repair`
- `update`
- optional `what-if`

### Akzeptanzkriterien
- Pipeline kann einen exakt definierten Kunden und Commit deterministisch laden.
- Keine Abhängigkeit von `current/`.

## WC-03.2 – Pipeline-Stages implementieren
Status: `[ ]`

### Pflicht-Stages
1. Validate
2. Prepare
3. What-If
4. Deploy
5. PostDeploy
6. Verify
7. Publish Artifacts

### Details

#### Validate
- Repo-/Config-Validierung
- PowerShell/Pester/Python/Bicep Checks

#### Prepare
- `customers/<slug>/deployment.config.json` laden
- Runtime Secrets beziehen
- Parameterdatei erzeugen
- Secure-Dateien nur temporär halten

#### What-If
- `az deployment group what-if`
- Ergebnis protokollieren
- gefährliche/unbeabsichtigte Änderungen sichtbar machen

#### Deploy
- `main.bicep`
- Kundenparameter
- Runtime Secrets

#### PostDeploy
- Basic- oder Cloudflare-managed Pfad
- DNS/WAF/Rate Limit
- Custom Domain/Zertifikat
- optionaler zweiter Reconcile für Origin Lockdown

#### Verify
- Container App Status
- Zielhostname
- TLS
- HTTPS-/Vaultwarden-Healthcheck

#### Publish Artifacts
- Deployment Outputs
- What-If-Ausgabe
- relevante Logs/Diagnosedaten

## WC-03.3 – Runtime-Secrets entkoppeln
Status: `[ ]`

### Regeln
- Keine Secrets in Git.
- Keine Pipeline-Logs mit Secretwerten.
- Ziel-Kunden-Key-Vault allein ist für First Deploy nicht ausreichend, wenn er erst durch den Stack entsteht.
- Bootstrap-/Deployment-Secrets müssen aus einem bereits existierenden zentralen Secret Store bzw. sicherer Pipeline-Integration kommen.

### Akzeptanzkriterien
- SMTP/SSO/Push/Cloudflare Credentials werden ausschließlich zur Laufzeit geladen.
- Temporäre Parameterdateien werden auch bei Fehlern entfernt.

## WC-03.4 – Pipeline-Artefakte statt Git-Runtime-State
Status: `[ ]`

### Prüfen/migrieren
- `artifacts/last-deploy-output.json`
- weitere generierte Diagnose-/Deployment-Ausgaben

### Regel
Nur State, der für echte Reconciliation dauerhaft benötigt wird, darf versioniert bleiben. Reine Laufzeit-Ausgaben gehören in Pipeline Artifacts.

## WC-03.5 – Commit-Traceability
Status: `[ ]`

### Aufgaben
- GitHub-`templateLinkUri`/`raw.githubusercontent.com`-Traceability aus Bicep entfernen.
- expliziten Build-/Commit-Ref aus Azure DevOps in Deployment-Metadaten/Outputs aufnehmen, z. B. `Build.SourceVersion`.

## Phase-3-Gate
Status: `[ ]`

Nur schließen, wenn ein nicht-interaktiver Pipeline-Lauf für einen Testkunden erfolgreich Validate → What-If → Deploy → PostDeploy → Verify durchläuft und eindeutig auf Customer Config + Commit zurückgeführt werden kann.

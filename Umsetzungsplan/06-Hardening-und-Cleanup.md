# Phase 6 – Hardening, Portabilität und Cleanup

Status: `[ ]`

## Ziel

Nach dem funktionalen Cutover werden Altpfade entfernt, Idempotenzlücken geschlossen und die Toolchain für den dauerhaften Betrieb gehärtet.

## WC-06.1 – `current/` entfernen
Status: `[ ]`

### Aufgaben
- Deploy-to-Azure-Abhängigkeit vollständig ablösen.
- `current/` erst löschen, wenn kein produktiver Pfad mehr darauf zeigt.
- Tests/Doku auf den Pipeline-basierten Kundenpfad umstellen.

### Akzeptanzkriterien
- Kein produktiver Code, Test oder README-Standardpfad benötigt `current/`.

## WC-06.2 – GitHub-spezifische Kopplungen entfernen
Status: `[ ]`

### Prüfen und entfernen/ersetzen
- `.github/workflows/arm-to-bicep-migration.yml`
- `.repo-sync`
- `raw.githubusercontent.com` URLs
- Deploy-to-Azure Wrapper-Abhängigkeiten
- GitHub-spezifische Template-Traceability in `main.bicep`

### Akzeptanzkriterien
- Zielbetrieb funktioniert vollständig ohne GitHub als Deployment-Host.

## WC-06.3 – PowerShell/CLI plattformneutral machen
Status: `[ ]`

### Hauptpunkt
`Deploy-AzureStack.ps1` darf Azure CLI nicht über `cmd.exe /c az` starten.

### Ziel
- direkte `az`-Ausführung aus PowerShell 7
- Windows/Linux kompatibel
- sauberer Exit-Code-/StdOut-/StdErr-Umgang

### Akzeptanzkriterien
- relevante Scripts laufen auf Microsoft-hosted `ubuntu-latest`.
- Windows-spezifische Logik existiert nur dort, wo sie fachlich notwendig ist.

## WC-06.4 – Custom Domain / Zertifikat zu Ensure-Verhalten umbauen
Status: `[ ]`

### Ist-Risiko
`Bind-AcaCustomDomain.ps1` erzeugt bei erneutem Lauf neue Private Keys/Origin-CA-Zertifikate und bindet erneut.

### Ziel
Konzeptionell `Ensure-AcaCustomDomain`:
- bestehendes gültiges Binding erkennen
- gültiges Zertifikat wiederverwenden
- nur bei fehlendem/ablaufendem Zertifikat oder expliziter Rotation neu ausstellen
- Rotation nachvollziehbar protokollieren

### Akzeptanzkriterien
- zweiter identischer Deploymentlauf erzeugt kein neues Zertifikat.
- definierter Rotationstest existiert.

## WC-06.5 – Cloudflare-Reconciliation absichern
Status: `[ ]`

### Aufgaben
- bestehende GET→PUT/POST DNS-Logik testen.
- BSSE-managed Rules eindeutig identifizieren.
- fremde/nicht verwaltete Regeln dürfen nicht gelöscht/überschrieben werden.
- zweiter identischer Lauf muss No-op bzw. semantisch unverändert sein.

## WC-06.6 – Desired State und Observed State prüfen
Status: `[ ]`

### Aktuell
`preservedInfraState.customDomains` liegt in `deployment.config.json`.

### Entscheidung
Nach erfolgreichem Cutover prüfen, ob:
- dieser technische beobachtete Zustand dort bewusst bleiben soll, oder
- Desired Config und Observed/Reconciliation State getrennt werden.

### Regel
Keine vorschnelle Migration dieses States vor funktionalem Cutover; Stabilität vor Schönheitsrefactoring.

## WC-06.7 – Generierte Parameter auf `.bicepparam` umstellen
Status: `[ ]`

### Voraussetzungen
- Bicep-Deployment stabil
- JSON-Parameterpfad bereits bewiesen

### Anforderungen
- `.bicepparam` wird aus Kundenconfig generiert.
- Datei bleibt gitignored/temporär.
- Secure-Werte werden nur zur Laufzeit eingebunden.

## WC-06.8 – Runtime-Artefakte aus Git entfernen
Status: `[ ]`

### Prüfen
- `artifacts/last-deploy-output.json`
- weitere generierte Outputs

### Ziel
Pipeline Artifacts/Logs statt Source Control, sofern Daten nicht für Reconciliation zwingend versioniert werden müssen.

## WC-06.9 – Dokumentation aktualisieren
Status: `[ ]`

### Mindestens
- `Readme.md`
- `docs/architecture.md`
- relevante Runbooks
- `docs/changes.md`

### Inhalte
- Azure Repos/Azure Pipelines statt GitHub Deploy-to-Azure
- Bicep als Source-of-Truth
- CLI-First Bedienmodell
- PlatformBootstrap/WIF
- Customer Deployment Profile
- Secret-Modell
- Repair/Update-Semantik

## Phase-6-Gate
Status: `[ ]`

Nur schließen, wenn:
- GitHub-/`current/`-/ARM-Source-of-Truth-Altpfade entfernt sind,
- Ubuntu-Agentpfad funktioniert,
- wiederholte Deployments keine unnötigen Zertifikats-/Cloudflare-/Identity-Neuanlagen verursachen,
- Runtime-Artefakte korrekt ausgelagert sind,
- Produkt-/Betriebsdokumentation den realen Zielzustand beschreibt.

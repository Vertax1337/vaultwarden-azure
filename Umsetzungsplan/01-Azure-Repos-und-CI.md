# Phase 1 – Azure Repos und CI-Baseline

Status: `[ ]`

## Ziel

Repository-Historie nach Azure Repos migrieren und zunächst **ohne funktionale Deploymentänderung** eine reproduzierbare CI-Baseline herstellen.

## WC-01.1 – Repository-Migration
Status: `[ ]`

### Aufgaben
- Repository vollständig nach Azure Repos importieren bzw. spiegeln.
- Historie und relevante Refs erhalten.
- `master` zunächst als Default Branch beibehalten; Branch-Rename nicht mit der Migration koppeln.
- Zielrepo auf leeren/definierten Zustand prüfen, bevor ein Mirror-Push verwendet wird.

### Akzeptanzkriterien
- Commit-Historie ist nachvollziehbar erhalten.
- Default Branch ist korrekt.
- Alle produktionsrelevanten Dateien sind im Azure-Repo vorhanden.
- Kein unbeabsichtigtes Löschen zusätzlicher Zielrefs.

### Nachweis
- Azure-Repos-Commit-SHA des importierten HEAD.
- Vergleich des Quell-/Ziel-HEAD und Stichprobe der Historie.

## WC-01.2 – Bestehende Tests unverändert lauffähig machen
Status: `[ ]`

### Aufgaben
- Pester-Tests aus `tests/Wizard.Tests.ps1` in Azure Pipelines ausführen.
- Python-Contract-Tests aus `tests/test_repo_contract.py` ausführen.
- PowerShell-Syntaxprüfung aufnehmen.
- Noch **keine** Tests entfernen, nur weil sie aktuelle ARM-/GitHub-Verträge beschreiben.

### Akzeptanzkriterien
- Baseline-Pipeline ist grün oder bekannte Baseline-Fehler sind explizit dokumentiert.
- Testresultate werden in Azure DevOps sichtbar veröffentlicht.

## WC-01.3 – Validation Pipeline
Status: `[ ]`

### Zielstruktur
`pipelines/validate.yml`

### Muss enthalten
- Checkout exakter Commit.
- PowerShell 7.
- Python.
- Azure CLI/Bicep CLI.
- Pester.
- Python Contract Tests.
- `az bicep build`/Lint, sobald Phase 2 vorbereitet ist.

### Agent-OS
Bevorzugt Microsoft-hosted `ubuntu-latest`, sofern alle Repo-Skripte dafür portabel gemacht bzw. Windows-Sonderfälle kontrolliert behandelt werden.

## WC-01.4 – Branch Policies
Status: `[ ]`

### Aufgaben
- Produktionsbranch durch Pull Requests schützen.
- Build Validation mit der Validation Pipeline erzwingen.
- Kommentarauflösung verlangen.
- Sinnvolle Reviewer-Mindestzahl konfigurieren.
- Direkte Änderungen am Produktionsbranch einschränken.

## Phase-1-Gate
Status: `[ ]`

Nur schließen, wenn:
- Repo in Azure Repos vollständig vorhanden ist,
- CI auf dem Zielrepo läuft,
- bestehende Tests nachvollziehbar ausgeführt werden,
- Branch Policy die Validierung erzwingt,
- noch keine funktionale Deploymentregression eingeführt wurde.

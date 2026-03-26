# Change Log

## Schritt 1 – Problem 1: PostgreSQL-Connectivity im Deployment Script

### Problem / Ursache
Das Azure Deployment Script `vault-ensure-kv-secrets` hat PostgreSQL bisher nur über wiederholte `az postgres flexible-server execute`-Aufrufe geprüft. In realen Deployments war der Server nach ARM-`dependsOn` oft noch nicht im Zustand `Ready`, obwohl Key Vault bereits erreichbar war. Dadurch lief der Connectivity-Check 600 Sekunden lang ins Leere und das Deployment brach ab.

### Betroffene Dateien
- `main.json`
- `scripts/lib/VaultwardenDeployment.Common.ps1`
- `scripts/Deploy-AzureStack.ps1`
- `scripts/deploy.ps1`
- `scripts/Invoke-CustomerDeployment.ps1`
- `tests/test_repo_contract.py`

### Umgesetzter Fix
- Shared Logic im zentralen Helper-Modul und in den zentralen Deploy-Pfaden mit dem vereinbarten Kommentarstandard gekennzeichnet.
- Deployment Script in `main.json` auf einen zweistufigen PostgreSQL-Wait umgebaut:
  1. Warten auf `provisioningState == Succeeded` via `az postgres flexible-server wait --created`
  2. Danach explizites Polling auf `state == Ready` via `az postgres flexible-server show --query state`
  3. Erst danach Connectivity-Check per `az postgres flexible-server execute`
- Deployment Script Timeout auf `PT1H` gesetzt, damit der längere Readiness-Pfad nicht selbst am Script-Timeout scheitert.
- Letzte Connectivity-Fehlermeldung sowie ein Server-`show` werden bei Abbruch mit ausgegeben, damit Problem 2 vorbereitet wird, ohne Problem 1 zu überspringen.

### Relevante Nebenwirkungen / Risiken
- Längere Deployment-Dauer im Fehlerfall, weil PostgreSQL jetzt bewusster auf Readiness geprüft wird.
- Shared Logic wurde nur markiert, nicht funktional umgebaut. Die Änderungen an den zentralen Skripten beschränken sich auf Kennzeichnung, um Seiteneffekte gering zu halten.

### Test / Validierung
- Repo-Testlauf lokal: bestehende Tests plus neue statische Tests für den Readiness-Pfad und den Shared-Logic-Kommentar.
- Validiert wird damit die Template-/Skriptlogik, nicht ein echter Live-Azure-Deploy.

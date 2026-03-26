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

## Schritt 2 – Problem 2: PostgreSQL-Fehlerursache im Deployment Script besser diagnostizieren

### Problem / Ursache
Nach Schritt 1 war der PostgreSQL-Readiness-Pfad robuster, aber ein Fehlschlag lieferte weiterhin zu wenig konkrete Diagnostik. Im realen Fehlerbild war nur sichtbar, dass PostgreSQL nach 600 Sekunden nicht erreichbar war. Für die Fehlersuche fehlten serverseitige Zustandsdaten, Firewall-Regeln, Datenbankliste sowie Exitcode/Stdout/Stderr des letzten `az postgres flexible-server execute`-Versuchs.

### Betroffene Dateien
- `main.json`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzter Fix
- Im Deployment Script in `main.json` neue Diagnose-Helfer ergänzt:
  - `print_pg_server_diagnostics`
  - `print_pg_firewall_diagnostics`
  - `print_pg_database_diagnostics`
  - `print_pg_connectivity_diagnostics`
- Bei PostgreSQL-Fehlschlägen werden jetzt zusätzlich ausgegeben:
  - Server-Details (`az postgres flexible-server show`)
  - Firewall-Regeln (`firewall-rule list`)
  - Datenbanken (`db list`)
  - letzter Execute-Exitcode
  - letzter Execute-Stdout
  - letzter Execute-Stderr
- Die bestehende Readiness-Logik aus Schritt 1 wurde nicht funktional verändert, nur die Diagnose im Fehlerfall erweitert.

### Relevante Nebenwirkungen / Risiken
- Etwas ausführlichere Deployment-Logs im Fehlerfall.
- Die Diagnose-Funktionen wurden lokal im Deployment Script ergänzt und nicht als neue Shared Logic in PowerShell-Skripte ausgelagert, um Seiteneffekte auf andere Pfade zu vermeiden.

### Test / Validierung
- Repo-Testlauf mit `pwsh`: alle Tests grün.
- Zusätzliche statische Tests prüfen, dass die PostgreSQL-Diagnose-Helfer und die erweiterten Diagnoseausgaben im Deployment Script vorhanden sind.

## Schritt 1b – Problem 1: DeploymentScript-Identität bekommt PostgreSQL-Leserechte

### Problem / Ursache
Nach dem ersten Fix für Problem 1 zeigte der reale Azure-Lauf, dass das Deployment Script `vault-ensure-kv-secrets` zwar Key Vault erreichen konnte, aber beim Warten auf PostgreSQL mit `AuthorizationFailed` auf `Microsoft.DBforPostgreSQL/flexibleServers/read` scheiterte. Ursache war, dass die `kv-writer-id`-Identity zwar Key Vault-Rollen hatte, aber keine Azure-RBAC-Leserechte auf dem PostgreSQL Flexible Server.

### Betroffene Dateien
- `main.json`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzter Fix
- Neue Variable `roleReader` für die Azure Built-in Role **Reader** ergänzt.
- Neue Role Assignment Resource auf Scope `Microsoft.DBforPostgreSQL/flexibleServers/{postgresServerName}` für die User Assigned Identity `{appName}-kv-writer-id` ergänzt.
- Das Deployment Script hängt jetzt zusätzlich von dieser PostgreSQL-Reader-Rollenzuweisung ab.
- Dadurch können die im Deployment Script verwendeten Leseoperationen (`wait`, `show`, `firewall-rule list`, `db list`) auf dem PostgreSQL-Server ausgeführt werden.

### Relevante Nebenwirkungen / Risiken
- Die Änderung betrifft die zentrale ARM-Hauptvorlage `main.json`, aber nur im PostgreSQL-/DeploymentScript-Pfad.
- Es wurde bewusst **kein** breiterer Scope wie Resource Group Reader vergeben, sondern minimal-invasiv Reader direkt auf dem PostgreSQL-Server.
- Andere Wizard-/Button-Pfade bleiben unverändert; sie profitieren nur von der zusätzlichen Berechtigung für denselben DeploymentScript-Pfad.

### Test / Validierung
- Vollständiger Repo-Testlauf mit `pwsh`: 51/51 Tests grün.
- Neuer statischer Test prüft:
  - `roleReader` ist vorhanden
  - genau eine PostgreSQL-Reader-Role-Assignment-Resource existiert
  - das Deployment Script davon abhängt

## Schritt 1c – Problem 1: `rdbms-connect`-Extension explizit bootstrappen und Execute-Exitcodes korrekt erfassen

### Problem / Ursache
Ein realer Deploy-Lauf zeigte, dass PostgreSQL bereits `Ready` war, der Connectivity-Check aber trotzdem wiederholt scheiterte. Die Diagnose machte sichtbar, dass `az postgres flexible-server execute` versucht hat, die Azure-CLI-Erweiterung `rdbms-connect` dynamisch zu installieren und dabei mit `Pip failed with status code 1` scheiterte. Zusätzlich wurde der Exitcode des Execute-Aufrufs im bisherigen Loop irreführend als `0` geloggt.

### Betroffene Dateien
- `main.json`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzter Fix
- Vor dem PostgreSQL-Connectivity- und SQL-Provisioning-Pfad wird die Azure-CLI-Erweiterung `rdbms-connect` jetzt explizit vorbereitet:
  - `extension.use_dynamic_install=yes_without_prompt`
  - `extension.dynamic_install_allow_preview=true`
  - explizites `az extension add --name rdbms-connect --allow-preview true --only-show-errors`
- Der Erweiterungspfad wird auf ein beschreibbares temporäres Verzeichnis (`AZURE_EXTENSION_DIR=/tmp/az-extensions`) gesetzt, um Seiteneffekte aus Benutzer-/Home-Verzeichnissen zu vermeiden.
- Wenn die Extension-Installation fehlschlägt, bricht das Deployment Script jetzt früh und mit konkreter Diagnose für die Extension-Installation ab, statt 600 Sekunden lang einen Connectivity-Fehler vorzutäuschen.
- Der PostgreSQL-Connectivity-Loop erfasst den echten Exitcode des `execute`-Aufrufs jetzt korrekt, statt ihn über den `if ...; then`-Pfad verfälscht zu loggen.
- Dasselbe gilt für die beiden SQL-Provisioning-Schritte (`bootstrap-admin.sql`, `bootstrap-db.sql`): deren Exitcodes werden jetzt korrekt erfasst und diagnostiziert.

### Relevante Nebenwirkungen / Risiken
- Die Änderung bleibt lokal im Deployment Script in `main.json` und greift nicht in zentrale PowerShell-Shared-Logic ein.
- Der Fix setzt weiter auf `az postgres flexible-server execute`; er ersetzt die Methode nicht, sondern macht deren Vorbereitung und Fehlerbilder robuster.

### Test / Validierung
- Vollständiger Repo-Testlauf mit `pwsh`.
- Zusätzliche statische Tests prüfen:
  - expliziten Bootstrap der `rdbms-connect`-Extension
  - Preview-/Dynamic-Install-Konfiguration
  - korrektes Erfassen der Execute-Exitcodes
  - korrekte Diagnosepfade für die SQL-Provisioning-Schritte

## Schritt 1d – Problem 1: `pip` im Deployment-Script-Container bootstrappen

### Problem / Ursache
Ein realer Deploy-Lauf schlug beim Installieren der `rdbms-connect`-Extension fehl, weil der AzureCLI-Deployment-Script-Container kein `pip` mitbringt. Die Extension-Installation (`az extension add --name rdbms-connect`) benötigt `pip` intern, um ihre Python-Abhängigkeiten (u.a. `psycopg[binary]`) zu installieren. Der Fehler war:
```
[vault-ensure-kv-secrets] Installing Python package psycopg[binary]...
[vault-ensure-kv-secrets] ERROR: Failed to install Python package psycopg[binary]
[vault-ensure-kv-secrets] python package install stderr: /usr/bin/python3: No module named pip
```

### Betroffene Dateien
- `main.json`
- `change.md`

### Umgesetzter Fix
- Neue Funktion `ensure_pip()` im Deployment Script ergänzt, die `pip` vor der Extension-Installation sicherstellt:
  1. Prüft ob `python3 -m pip` bereits verfügbar ist.
  2. Falls nicht: versucht `python3 -m ensurepip --default-pip` (Python-Standardbibliothek).
  3. Falls `ensurepip` fehlt: versucht den System-Paketmanager (`apk`, `tdnf` oder `apt-get`).
  4. Falls nichts funktioniert: gibt Warnung aus und fährt trotzdem fort (Extension-Installationsfehlschlag wird weiterhin über den bestehenden `ensure_rdbms_connect_extension()`-Pfad abgefangen).
- Die Funktion `configure_az_extension_installation()` ruft `ensure_pip || true` auf, bevor die Azure-CLI-Extension-Konfiguration gesetzt wird.

### Relevante Nebenwirkungen / Risiken
- Geringe zusätzliche Deployment-Dauer (wenige Sekunden) durch die pip-Bootstrapping-Logik.
- Die Änderung bleibt lokal im Deployment Script in `main.json` und greift nicht in zentrale PowerShell-Shared-Logic ein.
- Wenn `pip` weder über `ensurepip` noch über den Paketmanager installiert werden kann, wird eine Warnung ausgegeben. Die Extension-Installation schlägt dann über den bestehenden Fehler-/Diagnosepfad fehl.

### Test / Validierung
- Vollständiger Repo-Testlauf mit bestehenden Tests.
- Die `ensure_pip`-Funktion ist im Deployment Script statisch prüfbar.

## Schritt 2a – PostgreSQL-SQL-Pfad: `az postgres flexible-server execute` durch `psql` ersetzen

### Problem / Ursache
Die Schritte 1c und 1d versuchten, das Problem um `az postgres flexible-server execute` + `rdbms-connect`-Extension + `pip`-Installation robuster zu machen. In der Praxis bleibt dieser Pfad aber grundsätzlich unzuverlässig:
- Die `rdbms-connect`-Extension benötigt `pip` zur Installation ihrer Python-Abhängigkeit `psycopg[binary]`.
- Die AzureCLI-Deployment-Script-Container (CBL-Mariner/Azure-Linux) liefern weder `pip` noch `ensurepip` zuverlässig aus.
- Auch das nachträgliche Bootstrap über Paketmanager (`tdnf`, `apk`, `apt-get`) schlägt je nach Container-Image fehl.
- Reale Fehlerbilder:
  - `The command requires the extension rdbms-connect`
  - `Pip failed with status code 1`
  - `/usr/bin/python3: No module named pip`

### Betroffene Dateien
- `main.json`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzter Fix
- Die gesamte `rdbms-connect`-/`pip`-basierte Toolchain wurde aus dem Deployment Script entfernt:
  - `ensure_pip()` – entfernt
  - `configure_az_extension_installation()` – entfernt
  - `ensure_rdbms_connect_extension()` – entfernt
  - `PG_CLI_BASE` (Array mit `az postgres flexible-server execute ...`) – entfernt
  - Alle Aufrufe von `"${PG_CLI_BASE[@]}"` – ersetzt durch `run_psql`
- Ersetzt durch Standard-PostgreSQL-Tooling (`psql`):
  - Neue Funktion `ensure_psql()`: installiert `postgresql-client` über den im Container verfügbaren Paketmanager (`apk`, `tdnf` oder `apt-get`). Das ist ein einfaches Paket ohne Python-/pip-Abhängigkeit.
  - Neue Funktion `build_psql_env()`: setzt Standard-PostgreSQL-Umgebungsvariablen (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE`) aus den bereits vorhandenen ARM-Environment-Variablen.
  - Neue Funktion `run_psql()`: kapselt den `psql`-Aufruf mit `--no-password --set=ON_ERROR_STOP=1` für konsistente Fehlerbehandlung.
- Der Connectivity-Check (`SELECT 1`) nutzt jetzt `run_psql postgres -c "SELECT 1"` statt `az postgres flexible-server execute`.
- Die SQL-Provisioning-Schritte (`bootstrap-admin.sql`, `bootstrap-db.sql`) nutzen jetzt `run_psql` mit `-f`.
- Die Diagnose-Helfer (`print_pg_connectivity_diagnostics`) referenzieren jetzt `psql exit code` / `psql stdout` / `psql stderr` statt `execute exit code`.
- Die Azure-CLI-Leseoperationen (`az postgres flexible-server show/wait`, `firewall-rule list`, `db list`) bleiben unverändert – sie benötigen keine Extension.

### Relevante Nebenwirkungen / Risiken
- Die Änderung bleibt lokal im Deployment Script in `main.json` und greift nicht in zentrale PowerShell-Shared-Logic ein.
- `psql` ist ein stabiles, weit verbreitetes Standard-Tool. Die AzureCLI-Container basieren auf CBL-Mariner/Azure-Linux (`tdnf`) oder Alpine (`apk`) – beide bieten `postgresql-client` als Paket an.
- Kein Python-/pip-/`rdbms-connect`-Bootstrap mehr erforderlich – die gesamte Fehlerkategorie entfällt.
- Wizard-, Button-, GenerateOnly-, Redeploy-, Repair- und Update-Pfade bleiben funktional unverändert, da sie dasselbe ARM-Template und damit dasselbe Deployment Script nutzen.

### Test / Validierung
- Vollständiger Repo-Testlauf: 53/53 Tests grün.
- Zwei bestehende Tests aktualisiert:
  - `test_main_json_bootstraps_rdbms_connect_extension_explicitly` → `test_main_json_uses_psql_instead_of_rdbms_connect`: prüft, dass `ensure_psql`, `build_psql_env`, `run_psql` vorhanden sind und kein `rdbms-connect`-/`PG_CLI_BASE`-/`ensure_pip`-Pfad mehr existiert.
  - `test_main_json_connectivity_loop_captures_real_execute_exit_code` → `test_main_json_connectivity_loop_uses_psql`: prüft `run_psql`-basierte Aufrufe für Connectivity-Check und SQL-Provisioning mit Exitcode-Erfassung.
- Bestehender Diagnose-Test (`test_deployment_script_has_pg_diagnostic_helpers`) auf `psql exit code` aktualisiert.

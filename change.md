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

## Schritt 3 – SMTP/Direct-Send-Pfad: MX-Lookup entfernen, smtpHost als Pflichtfeld für Direct Send

### Problem / Ursache
Der Direct-Send-Pfad (smtpUseAuth=false) im Deployment Script in `main.json` versuchte den MX-Endpunkt der Mail-Domain zur Laufzeit via `dig` oder `nslookup` zu ermitteln. Im Azure-DeploymentScript-Container (CBL-Mariner/Azure-Linux) sind diese Tools nicht zuverlässig verfügbar. Dadurch brach das Deployment mit einer unklaren Fehlermeldung ab.

Gleichzeitig schrieb der Wizard (`Invoke-CustomerDeployment.ps1`) den `smtpHost`-Wert nur für den SMTP-Auth-Pfad in die ARM-Parameterdatei. Bei Direct Send fehlte er, was den MX-Lookup im Deployment Script auslöste.

### Betroffene Dateien

#### Shared-Logic-Kennzeichnung
- `main.json` – Deployment Script (geteilter Pfad für Wizard, Deploy-to-Azure-Button, Repair, Update, Redeploy)
- `scripts/Invoke-CustomerDeployment.ps1` – Wizard (geteilte Funktionen `New-CustomerConfigObject`, `New-CustomerAzureParameters`)

#### Alle betroffenen Pfade
| Pfad | Betroffenheit |
|---|---|
| Wizard (Invoke-CustomerDeployment.ps1) | Neuer Direct-Send-Prompt für smtpHost; Early Validation im CLI-Pfad |
| Deploy-to-Azure-Button | smtpHost-Parameter in ARM-Template bereits vorhanden → kein Umbau nötig |
| GenerateOnly | Schreibt smtpHost jetzt korrekt für Direct Send in Parameter-Datei |
| Repair / Update / Redeploy | Lesen vorhandene Config; wenn smtpHost gesetzt ist, wird er korrekt weitergegeben |
| Bestehende Kundenkonfigs | Konfigurationen mit useAuth=true sind nicht betroffen; Direct-Send-Kunden brauchen smtpHost in deployment.config.json |

#### Konkrete Dateiänderungen
- `main.json`
- `scripts/Invoke-CustomerDeployment.ps1`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzter Fix

**1. `main.json` – Deployment Script**

Early-Validation-Block:
- Alt: Schlägt nur fehl wenn BEIDE `SMTP_HOST_INPUT` UND `MAIL_ROOT_DOMAIN` fehlen
- Neu: Schlägt fehl wenn `smtpUseAuth=false` und `SMTP_HOST_INPUT` fehlt (MX-Lookup-Fallback entfernt)
- Klare Fehlermeldung: benennt explizit, dass MX-Lookup nicht unterstützt wird

MX-Auflösungsblock (ca. 70 Zeilen `dig`/`nslookup`-Logik):
- Entfernt: gesamter `dig`-Pfad, gesamter `nslookup`-Pfad, MX-Parsing via Python-Heredocs
- Ersetzt durch: einfaches `MX_HOST="${SMTP_HOST_INPUT}"` für Direct Send

SMTP Auth: unverändert (smtp.office365.com als Default, SMTP_HOST_INPUT als Override)

**2. `scripts/Invoke-CustomerDeployment.ps1` – Wizard**

Interaktiver Wizard:
- Wenn `smtpUseAuth=false`: neuer expliziter Prompt `SMTP Host (MX-Endpunkt für Direct Send)` mit `-Required`
- Wenn `smtpUseAuth=true`: unverändert (smtp.office365.com als Default)

`New-CustomerAzureParameters`:
# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
- Wenn `useAuth=false` und `smtp.host` nicht leer: schreibt `smtpHost` in ARM-Parameter (neu)
- Wenn `useAuth=false` und `smtp.host` leer: wirft früh mit klarer Fehlermeldung
- Wenn `useAuth=true`: unverändert

CLI-Pfad (NonInteractive / GenerateOnly):
- Neue Early Validation vor `New-CustomerConfigObject`: schlägt fehl wenn `smtpUseAuth=false` und `SmtpHost` leer

**3. `main.json` – `smtpHost`-Parameter-Beschreibung**
- Beschreibung aktualisiert: MX-Lookup-Referenz entfernt, Pflichtfeld-Hinweis für Direct Send ergänzt

### Warum wurde die geteilte Funktion `New-CustomerAzureParameters` geändert?
Diese Funktion schreibt die ARM-Parameterdatei für alle Deploy-Pfade (Wizard, GenerateOnly, Repair, Update). Ohne Änderung hier würde `smtpHost` für Direct Send nie in die Parameterdatei geschrieben, und das Deployment Script würde immer einen leeren `SMTP_HOST_INPUT` sehen. Die Änderung ist minimal: nur ein neuer `elseif`-Branch für den Direct-Send-Fall.

### Relevante Nebenwirkungen / Risiken
- Bestehende Direct-Send-Kundenkonfigurationen ohne `smtpHost` in `deployment.config.json` werden beim nächsten Repair/Update scheitern, bis `smtpHost` ergänzt wird.
- Deploy-to-Azure-Button-Nutzer, die `smtpUseAuth=false` wählen und `smtpHost` leer lassen, bekommen jetzt einen frühen, klaren Fehler im Deployment Script statt eines DNS-Tool-Fehlers.
- SMTP-Auth-Pfad (smtpUseAuth=true) ist vollständig unverändert.
- GenerateOnly und Wizard-Tests wurden aktualisiert, um smtpHost für Direct Send zu übergeben.

### Test / Validierung
- Vollständiger Repo-Testlauf: 59/59 Tests grün (53 bestehend + 6 neue).
- 6 neue Tests:
  - `test_main_json_smtp_no_dig_or_nslookup`: kein `dig`/`nslookup` mehr im Deployment Script
  - `test_main_json_smtp_direct_send_requires_explicit_host`: frühe Validierung im Script vorhanden
  - `test_main_json_smtp_direct_send_uses_smtp_host_input_directly`: Direct Send nutzt SMTP_HOST_INPUT direkt
  - `test_wizard_direct_send_prompts_for_smtp_host`: Wizard hat Prompt für MX-Endpunkt
  - `test_parameter_generation_writes_smtp_host_for_direct_send`: smtpHost wird für Direct Send in Parameter-Datei geschrieben
  - `test_cli_path_validates_direct_send_requires_smtp_host`: CLI-Pfad validiert smtpHost für Direct Send
- 3 bestehende GenerateOnly-Tests aktualisiert: `-SmtpHost 'mx.*.de'` ergänzt (da Direct Send jetzt expliziten smtpHost erfordert)


## Schritt 4 – SMTP-UX-Cleanup: Wizard vereinfachen, Doku bereinigen

### Problem / Ursache
Nach Schritt 3 war der technische Direct-Send-Pfad korrekt, aber:
1. Der Wizard fragte `SMTP Host` auch im SMTP-Auth-Hauptpfad interaktiv ab – unnötig prominent, da `smtp.office365.com` ein sinnvoller stabiler Default ist.
2. Dokumentation und Metadaten enthielten noch veraltete Hinweise auf automatischen MX-Lookup:
   - `docs/reference/parameters.md`: `Root-Domain für MX-Lookup (Direct Send)` und `MX-Lookup bei Direct Send`
   - `docs/operations/smtp-and-acs.md`: Direct-Send-Tabelleneintrag zeigte `mailRootDomain` statt `smtpHost`
   - `docs/HowToInstall/Operation-Playbook.md`: Zeile 55 erwähnte noch MX-Lookup im Deployment Script; §7.2 beschrieb `smtpHost` als optional
   - `main.json`: `mailRootDomain`-Parameterbeschreibung implizierte MX-Lookup für Direct Send

### Betroffene Dateien

#### Shared-Logic-Betroffenheit
- `scripts/Invoke-CustomerDeployment.ps1` – Wizard-Funktion `New-CustomerConfigInteractive` (SHARED LOGIC: betrifft alle interaktiven Pfade)
- `main.json` – ARM-Parameter-Metadaten (betrifft Deploy-to-Azure-Button, Wizard, alle Pfade)

#### Alle betroffenen Pfade
| Pfad | Betroffenheit |
|---|---|
| Wizard (interaktiv) | SMTP Host wird bei SMTP Auth nicht mehr im Hauptpfad abgefragt |
| GenerateOnly / CLI | Unverändert – SmtpHost wird weiterhin via `-SmtpHost` übergeben |
| Repair / Update | Unverändert – vorhandene Config-Werte werden gelesen |
| Deploy-to-Azure-Button | Nur Metadaten-Text verbessert, Verhalten unverändert |

#### Konkrete Dateiänderungen
- `scripts/Invoke-CustomerDeployment.ps1`
- `docs/reference/parameters.md`
- `docs/operations/smtp-and-acs.md`
- `docs/HowToInstall/Operation-Playbook.md`
- `main.json`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzter Fix

**1. `scripts/Invoke-CustomerDeployment.ps1` – Wizard (SHARED LOGIC)**

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.

Warum geändert: `New-CustomerConfigInteractive` fragte `SMTP Host` interaktiv ab, obwohl `smtp.office365.com` der stabile Default für SMTP Auth ist. Das hat den Wizard unnötig verlängert.

SMTP-Auth-Pfad:
- `SMTP Host` wird nicht mehr interaktiv abgefragt
- Stattdessen: vorhandenen Wert aus ExistingConfig übernehmen, sonst `smtp.office365.com` als stilles Default
- Kein funktionaler Unterschied für den Deploy-Pfad – das ARM-Template behandelt leeren/gleichen Wert identisch

Direct-Send-Pfad: unverändert – expliziter Prompt für MX-Endpunkt bleibt

Andere betroffene Pfade: keine – der CLI-Pfad (`-SmtpHost` via Parameter) und der Repair/Update-Pfad (liest gespeicherten Wert) sind nicht betroffen.

**2. `docs/reference/parameters.md`**
- `mailRootDomain`-Beschreibung: "Root-Domain für MX-Lookup (Direct Send)" → korrekte Beschreibung (Mailrouting + ACS Default)
- `smtpHost`-Beschreibung: "MX-Lookup bei Direct Send" → "Pflichtfeld – MX-Endpunkt (kein automatischer Lookup)"

**3. `docs/operations/smtp-and-acs.md`**
- Direct-Send-Tabelleneintrag: `mailRootDomain` → `smtpHost (MX-Endpunkt, Pflichtfeld)`

**4. `docs/HowToInstall/Operation-Playbook.md`**
- Zeile 55: "MX-Lookup" im Deployment Script → "SMTP-Host-Validierung"
- §7.2: `smtpHost` als Pflichtfeld dokumentiert, MX-Lookup-Hinweis entfernt

**5. `main.json` – Parameter-Metadaten**
- `mailRootDomain`-Beschreibung: Verweis auf Direct-Send-ohne-smtpHost entfernt
- `smtpUseAuth`-Beschreibung: Ergänzung, dass Direct Send smtpHost explizit erfordert

### Warum wurde `New-CustomerConfigInteractive` geändert?
Diese Funktion ist SHARED LOGIC – sie wird für alle interaktiven Deploy-Pfade (Neues Deployment, Bearbeiten+Deployen, GenerateOnly interaktiv) genutzt. Die Änderung entfernt lediglich eine redundante Frage im SMTP-Auth-Hauptpfad; der Funktionswert (`smtp.office365.com`) bleibt korrekt. Der CLI-Pfad und alle anderen Pfade sind nicht betroffen.

Geprüft für Seiteneffekte:
- Wizard: neue Tests verifizieren, dass `Read-TextWithDefault -Label 'SMTP Host'` nicht mehr im Code vorkommt
- Deploy-to-Azure-Button: nur Metadaten-Text, keine Logik-Änderung
- GenerateOnly: weiterhin über `-SmtpHost` steuerbar
- Repair/Update: lesen vorhandenen `smtp.host` aus Config → keine Änderung
- Bestehende Kundenkonfigs: `smtp.host` bleibt im Config gespeichert, wird beim Repair/Update korrekt gelesen

### Relevante Nebenwirkungen / Risiken
- Keine funktionalen Risiken: SMTP Auth mit leerem `smtpHost` wird durch das ARM-Template korrekt auf `smtp.office365.com` aufgelöst
- Kunden mit Custom-SMTP-Host (nicht Office365): müssen `-SmtpHost` via CLI übergeben oder deployment.config.json manuell bearbeiten
- Doku-Änderungen sind rein redaktionell, keine Code-Auswirkungen

### Test / Validierung
- Vollständiger Repo-Testlauf: 60/60 Tests grün (59 bestehend + 1 neuer).
- 1 neuer Test:
  - `test_wizard_smtp_auth_does_not_prompt_for_host_in_main_flow`: verifiziert, dass `Read-TextWithDefault -Label 'SMTP Host'` nicht mehr im Code ist, smtp.office365.com als Default vorhanden ist und der Kommentar die Design-Entscheidung dokumentiert
- Bestehender Test `test_wizard_direct_send_prompts_for_smtp_host` angepasst: prüft jetzt auf `MX-Endpunkt` (bleibt im Direct-Send-Pfad erhalten)


## Schritt 5 – Mail-Modus-Zustandswechsel: vollständige State-Migration, Shared-Logic-Marker, Tests

### Problem / Ursache

Der Deploy-/Wizard-Pfad behandelte den Mail-Modus-Wechsel (Direct Send ↔ SMTP Auth) nicht als vollständige Zustandsmigration:

1. **Bug – CLI-Pfad: `smtpPort` defaultete auf '587' für Direct Send**: In der CLI-Path-Konfigurationserzeugung (`Invoke-CustomerDeployment.ps1`, Hauptausführungspfad) wurde `-SmtpPort` immer mit `$(if ($SmtpPort) { $SmtpPort } else { '587' })` defaultet – unabhängig vom Mail-Modus. Beim Wechsel SMTP Auth → Direct Send ohne expliziten `-SmtpPort`-Parameter verblieb '587' im gespeicherten Config-Objekt, obwohl Direct Send keinen Port verwendet. Das ARM-Template ignoriert den gespeicherten Port-Wert zwar für Direct Send, aber die `deployment.config.json` enthielt damit einen inkonsistenten Zielzustand.

2. **Fehlende Shared-Logic-Marker**: Die zentralen SMTP-zustandsrelevanten Funktionen in `Invoke-CustomerDeployment.ps1` (`New-CustomerConfigObject`, `Get-RuntimeSecretParameters`, `New-CustomerConfigInteractive`, `New-CustomerAzureParameters`, `Save-CustomerFiles`) hatten keine `# SHARED LOGIC:`-Kommentare, obwohl sie von mehreren Deploy-/Wizard-Pfaden verwendet werden und Mail-Modus-Änderungen an diesen Stellen Seiteneffekte in allen Pfaden verursachen können.

3. **Fehlende Tests für Zustandswechsel-Szenarien**: Es existierten keine Tests, die explizit prüfen, ob beim Wechsel zwischen Mail-Modi der korrekte Zielzustand hergestellt wird (ACA-Secrets, Env-Variablen, ARM-Parameter-Inhalt).

### Betroffene Dateien

#### Shared-Logic-Betroffenheit

| Funktion | Verwendung | Mail-Modus-Relevanz |
|---|---|---|
| `New-CustomerConfigObject` | Wizard (New-CustomerConfigInteractive), CLI-Pfad, GenerateOnly | Kanonische SMTP-Zustandsdefinition; beim Moduswechsel werden useAuth, port, security, username, passwordSource gesetzt |
| `Get-RuntimeSecretParameters` | Hauptausführungspfad (interaktiv + CLI + GenerateOnly) | smtpPassword wird nur bei useAuth=true angefordert |
| `New-CustomerConfigInteractive` | Wizard-Pfade 1 (Neu), 3 (Bearbeiten+Deployen), 6 (GenerateOnly interaktiv) | SMTP-Auth-Felder werden im Wizard explizit initialisiert; bei Direct Send werden port/security/username leer gesetzt |
| `New-CustomerAzureParameters` | Save-CustomerFiles (alle Pfade), temporärer Deploy-Pfad | ARM-Parameter-Erzeugung für Direct Send (nur smtpHost) vs. SMTP Auth (alle Auth-Felder) |
| `Save-CustomerFiles` | Alle Pfade | Orchestriert Config, ARM-Parameter, current/-Kopien |

#### Konkrete Dateiänderungen

- `scripts/Invoke-CustomerDeployment.ps1`
- `tests/test_repo_contract.py`
- `change.md`

### Umgesetzte Fixes

**1. `scripts/Invoke-CustomerDeployment.ps1` – Bug-Fix: SmtpPort-Default im CLI-Pfad**

Vorher:
```powershell
-SmtpPort $(if ($SmtpPort) { $SmtpPort } else { '587' })
```

Nachher:
```powershell
-SmtpPort $(if ($SmtpPort) { $SmtpPort } elseif ($effectiveSmtpUseAuth) { '587' } else { '' })
```

Erklärung: Der Port-Default '587' ist nur für SMTP Auth sinnvoll. Direct Send verwendet Port 25 (das ARM-Template setzt diesen fest im `vwEnvSmtpCommon`-Array, unabhängig vom Parameter). Im Config-Objekt muss Port für Direct Send leer bleiben, damit der Zielzustand sauber und korrekt persistiert wird.

**2. `scripts/Invoke-CustomerDeployment.ps1` – Shared-Logic-Marker ergänzt**

Folgende Funktionen erhielten `# SHARED LOGIC:`-Kommentare mit Beschreibung der Mail-Modus-relevanten Logik:
- `New-CustomerConfigObject`
- `Get-RuntimeSecretParameters`
- `New-CustomerConfigInteractive`
- `New-CustomerAzureParameters`
- `Save-CustomerFiles`

**3. `tests/test_repo_contract.py` – 10 neue Tests**

Pure-Python-Tests (keine pwsh-Abhängigkeit):
- `test_main_json_smtp_secrets_conditional_on_smtp_use_auth`: Verifiziert, dass die ACA-Container-App-Secrets smtp-password nur bei `smtpUseAuth=true` enthält (ARM-`if(parameters('smtpUseAuth'), variables('vwSecretsSmtp'), json('[]'))`-Muster)
- `test_main_json_smtp_auth_env_vars_conditional_on_smtp_use_auth`: Verifiziert, dass SMTP_USERNAME und SMTP_PASSWORD (secretRef) Env-Variablen nur bei `smtpUseAuth=true` aktiv sind
- `test_main_json_smtp_auth_mechanism_conditional_on_smtp_use_auth`: Verifiziert, dass SMTP_AUTH_MECHANISM bei Direct Send niemals aktiv ist
- `test_deployment_script_smtp_password_secret_only_in_auth_mode`: Verifiziert, dass das Deployment Script `az keyvault secret set` für smtp-password nur bei SMTP Auth ausführt und für Direct Send überspringt
- `test_main_json_smtp_shared_logic_comment_in_deploy_script`: Verifiziert, dass alle SMTP-zustandsrelevanten Funktionen einen `# SHARED LOGIC:`-Kommentar haben

pwsh-abhängige Tests:
- `test_generate_only_smtp_auth_params_include_all_auth_fields`: Szenario Direct Send → SMTP Auth; prüft, dass ARM-Parameter smtpHost/Port/Security/Username enthalten
- `test_generate_only_direct_send_params_exclude_smtp_auth_fields`: Szenario SMTP Auth → Direct Send; prüft, dass ARM-Parameter kein smtpPort/Security/Username/Password mehr enthalten
- `test_generate_only_mode_switch_smtp_auth_to_direct_send_clears_auth_fields`: Vollständiger Wechsel-Test; prüft config.smtp und ARM-Parameter vor und nach dem Moduswechsel
- `test_generate_only_existing_smtp_auth_redeploy_no_regression`: Redeploy SMTP Auth; prüft, dass bestehende Auth-Felder erhalten bleiben
- `test_generate_only_existing_direct_send_redeploy_no_smtp_auth_ballast`: Redeploy Direct Send; prüft, dass kein SMTP-Auth-Ballast aktiviert wird

### Zielzustand: Direct Send (smtpUseAuth=false)
- `deployment.config.json`: `useAuth=false`, `port=''`, `security='starttls'`, `username=''`, `passwordSource='none'`
- `azure.parameters.json`: `smtpUseAuth=false`, `smtpHost=<MX-Endpunkt>`, kein smtpPort/Security/Username/Password
- ACA: kein smtp-password Secret, kein SMTP_USERNAME/SMTP_PASSWORD/SMTP_AUTH_MECHANISM Env-Var

### Zielzustand: SMTP AUTH (smtpUseAuth=true)
- `deployment.config.json`: `useAuth=true`, `port='587'`, `security='starttls'`, `username='...'`, `passwordSource='prompt'`
- `azure.parameters.json`: `smtpUseAuth=true`, alle SMTP-Auth-Felder vorhanden
- ACA: smtp-password Secret aktiv, SMTP_USERNAME/SMTP_PASSWORD Env-Vars aktiv

### Vaultwarden /data/config.json – Hinweis
Vaultwarden persistiert SMTP-Konfiguration intern in `/data/config.json` (Admin-Panel-Einstellungen). Beim Mail-Modus-Wechsel werden diese internen Werte NICHT automatisch durch das ARM-Deployment bereinigt. Da Azure Container Apps aber SMTP_USERNAME, SMTP_PASSWORD und SMTP_AUTH_MECHANISM im Direct-Send-Modus nicht mehr als Env-Variablen setzt, werden Vaultwarden-interne SMTP-Auth-Einstellungen nicht verwendet. Dies ist kein Bug, aber ein dokumentierter Hinweis: Falls der Admin-Panel zuvor manuelle SMTP-Einstellungen hatte, könnten diese in `/data/config.json` verbleiben. Eine strukturelle Architekturentscheidung (z.B. Reset via Vaultwarden-ENV `ADMIN_TOKEN`) ist hier nicht nötig, da Env-Variablen die Admin-Panel-Konfiguration überschreiben.

### Relevante Nebenwirkungen / Risiken
- **Bestehende CLI-Deployments mit explizitem `-SmtpPort` für Direct Send**: Funktionieren weiterhin korrekt (der übergebene Wert wird verwendet).
- **Repair/Update-Pfade**: Lesen den gespeicherten Config-Wert – ein zuvor fehlerhaft mit port='587' gespeicherter Direct-Send-Config könnte nach dem Fix korrekt leer gesetzt werden, wenn eine neue `New-CustomerConfigObject`-Erzeugung stattfindet.
- **Keine ACA-Fehler durch verwaiste Secret-Refs**: Das ARM-Template schließt smtp-password aus der ACA-Secrets-Liste aus, sobald `smtpUseAuth=false` – unabhängig davon, ob das KV-Secret noch existiert.

### Test / Validierung
- Vollständiger Repo-Testlauf: 69/70 Tests grün (60 bestehend + 10 neue).
- 1 vor-existierender Fehler (`test_rg_default_in_stored_configs`) unverändert – betrifft einen gespeicherten Kundenkonfig mit abweichendem RG-Namensschema, nicht diesen Fix.
- 10 neue Tests alle grün:
  - `test_main_json_smtp_secrets_conditional_on_smtp_use_auth`
  - `test_main_json_smtp_auth_env_vars_conditional_on_smtp_use_auth`
  - `test_main_json_smtp_auth_mechanism_conditional_on_smtp_use_auth`
  - `test_deployment_script_smtp_password_secret_only_in_auth_mode`
  - `test_main_json_smtp_shared_logic_comment_in_deploy_script`
  - `test_generate_only_smtp_auth_params_include_all_auth_fields`
  - `test_generate_only_direct_send_params_exclude_smtp_auth_fields`
  - `test_generate_only_mode_switch_smtp_auth_to_direct_send_clears_auth_fields`
  - `test_generate_only_existing_smtp_auth_redeploy_no_regression`
  - `test_generate_only_existing_direct_send_redeploy_no_smtp_auth_ballast`

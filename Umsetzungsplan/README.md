# Umsetzungsplan – Azure DevOps / Bicep / Platform Bootstrap

## Zweck

Dieser Ordner ist die ausführbare Migrationsplanung für einen KI-Agenten. Er ersetzt bewusst **keine** bestehende Produktdokumentation und ist **kein einzelnes monolithisches `Umsetzungsplan.md`**.

Der Plan zerlegt die Migration in voneinander prüfbare Phasen und Workchunks. Ein Workchunk darf erst als abgeschlossen markiert werden, wenn seine Akzeptanzkriterien erfüllt und die geforderten Nachweise vorhanden sind.

## Zielbild

> Der lokale CLI-Wizard beschreibt bzw. wählt den gewünschten Kundenzustand. Git versioniert diesen Zustand. Bicep beschreibt die Azure-Infrastruktur. Azure Pipelines reconciled beides mit Azure. Ein zentraler PlatformBootstrap stellt fehlende Kunden-Deployment-Profile automatisch her. Der Techniker bedient Azure DevOps nicht manuell.

## Statusnotation

- `[ ]` offen
- `[~]` in Arbeit
- `[x]` abgeschlossen und nachgewiesen
- `[!]` blockiert; Ursache muss direkt am Workchunk dokumentiert werden

**Verbot:** Ein Agent darf `[x]` nicht allein aufgrund einer Codeänderung setzen. Tests, Validierung und die im Workchunk geforderten Nachweise gehören zur Definition of Done.

## Phasen

1. [`00-Zielarchitektur-und-Leitplanken.md`](00-Zielarchitektur-und-Leitplanken.md) – verbindliche Architekturentscheidungen und Ist-Befund
2. [`01-Azure-Repos-und-CI.md`](01-Azure-Repos-und-CI.md) – Repository-Migration und belastbare CI-Baseline
3. [`02-Bicep-Source-of-Truth.md`](02-Bicep-Source-of-Truth.md) – Bicep wird alleinige Infrastrukturquelle
4. [`03-Azure-Pipeline-Deployment.md`](03-Azure-Pipeline-Deployment.md) – unattended Deployment-Backend
5. [`04-PlatformBootstrap-und-WIF.md`](04-PlatformBootstrap-und-WIF.md) – wiederverwendbares Customer-Onboarding und WIF
6. [`05-CLI-Integration-und-Cutover.md`](05-CLI-Integration-und-Cutover.md) – bestehender Wizard bleibt Bedienoberfläche
7. [`06-Hardening-und-Cleanup.md`](06-Hardening-und-Cleanup.md) – Idempotenz, Portabilität und Entfernung von Altpfaden
8. [`STATUS.md`](STATUS.md) – phasenübergreifender Fortschritt
9. [`99-Abschluss-Gate.md`](99-Abschluss-Gate.md) – harte Endabnahme

## Ausführungsregeln für KI-Agenten

1. Reihenfolge und Abhängigkeiten der Workchunks respektieren. Keine spätere Phase als abgeschlossen markieren, wenn ihr Eingangs-Gate nicht erfüllt ist.
2. Bestehendes Verhalten zuerst durch Tests festhalten, dann ändern.
3. Keine Secrets, Tokens, PATs, Kennwörter, PFX-Dateien oder temporären Secure-Parameterdateien committen.
4. `customers/<slug>/deployment.config.json` bleibt persistente, versionierte Kundenkonfiguration. Die JSON-Datei ist **kein ARM-Altbestand**, der wegen Bicep entfernt werden soll.
5. `main.bicep` wird Infrastruktur-Source-of-Truth. Generiertes ARM-JSON ist höchstens Build-/Kompatibilitätsartefakt.
6. Produktionsdeployments müssen auf einen eindeutigen Git-Stand zurückführbar sein.
7. Azure DevOps ist Execution Backend. Der Techniker soll weder Pipelines noch Service Connections manuell bedienen müssen.
8. Fehlendes Customer Deployment Profile wird automatisch über den zentralen PlatformBootstrap hergestellt; keine Ja/Nein-Rückfrage im Workload-Wizard.
9. Eine Workload Identity wird **nicht pro Deployment und nicht pro Repository** erzeugt. Sie wird pro sinnvoller Kunden-/Environment-/Privilege-Boundary wiederverwendet.
10. Eine einzige globale Deployment Identity über alle Kunden ist nicht das Ziel.
11. Änderungen müssen idempotent/reconciling sein: korrekt vorhandener Zustand bleibt unverändert, fehlender Zustand wird ergänzt, falscher verwalteter Zustand wird kontrolliert korrigiert.
12. Bei jeder Phase `STATUS.md` aktualisieren. Das Gesamtprojekt bleibt offen, bis `99-Abschluss-Gate.md` vollständig erfüllt ist.

## Harte Gate-Regel

**Die Migration ist nicht abgeschlossen, solange auch nur ein verpflichtender Workchunk oder ein Abschlusskriterium offen, blockiert oder ohne Nachweis ist.**

Das finale Gate darf nur `[x]` erhalten, wenn:

- alle Phasen-Gates `[x]` sind,
- alle Pflicht-Workchunks `[x]` sind,
- Tests/What-If/Deployment/Verifikation erfolgreich sind,
- keine produktive Abhängigkeit mehr von GitHub-raw/`current/`/ARM-JSON als Source-of-Truth besteht,
- PlatformBootstrap und unattended Pipeline-Authentifizierung praktisch getestet wurden,
- der Techniker den normalen Deploymentpfad vollständig aus dem CLI bedienen kann.

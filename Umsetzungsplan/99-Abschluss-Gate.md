# Phase 99 – Hartes Abschluss-Gate

Status: `[ ]`

## Zweck

Dieses Dokument ist die verbindliche Endabnahme. Die Migration darf **nicht** als abgeschlossen gelten, solange hier auch nur ein Pflichtpunkt offen oder blockiert ist.

## Gate A – Repository und CI

- [ ] Azure Repos enthält die vollständige relevante Historie.
- [ ] Produktionsbranch ist geschützt.
- [ ] Build Validation ist verpflichtend.
- [ ] Pester-, Python-, PowerShell- und Bicep-Validierung laufen im Zielrepo.

## Gate B – Bicep

- [ ] `main.bicep` ist alleinige gepflegte Infrastruktur-Source-of-Truth.
- [ ] `az bicep build` ist fehlerfrei.
- [ ] Parameter-/Ressourcen-/Output-Contract ist durch Tests abgesichert.
- [ ] Kein produktiver Pfad dekompiliert `main.json` nach Bicep.
- [ ] Kein produktiver Deploymentpfad verlangt handgepflegtes `main.json`.

## Gate C – Customer Config und Secrets

- [ ] `customers/<slug>/deployment.config.json` bleibt persistenter Desired Customer State.
- [ ] Keine Secrets werden in Customer Config, Repo oder Logs gespeichert.
- [ ] Runtime Secret Retrieval ist getestet.
- [ ] Temporäre Secure-Dateien werden auch im Fehlerfall entfernt.
- [ ] Generated Parameter Files sind kein zweiter Source-of-Truth.

## Gate D – Azure Pipeline

- [ ] Pipeline arbeitet commitgebunden.
- [ ] Validate erfolgreich.
- [ ] Prepare erfolgreich.
- [ ] What-If erfolgreich und nachvollziehbar.
- [ ] Deploy erfolgreich.
- [ ] PostDeploy erfolgreich.
- [ ] Verify erfolgreich.
- [ ] relevante Outputs/Logs werden als Pipeline Artifacts veröffentlicht.

## Gate E – PlatformBootstrap / Identity

- [ ] PlatformBootstrap ist workload-unabhängig.
- [ ] Workload ruft `Ensure-CustomerDeploymentProfile` bzw. äquivalente zentrale Schnittstelle auf.
- [ ] Fehlendes Deployment-Profil löst automatisch Bootstrap aus, ohne Ja/Nein-Rückfrage.
- [ ] Erst-Onboarding kann die erforderliche interaktive Kunden-Authentifizierung durchführen.
- [ ] Deployment Identity wird pro definierter Trust-/Privilege-Boundary wiederverwendet.
- [ ] Kein Identity-Neubau pro Deployment.
- [ ] Keine globale Deployment Identity über alle Kunden.
- [ ] WIF ist End-to-End getestet.
- [ ] Zweiter Ensure-Lauf ist idempotent und erzeugt keine neue Identity/Service Connection.
- [ ] RBAC ist minimal sinnvoll scoped und für notwendige Role Assignments ausreichend.
- [ ] Bootstrap- und dauerhafte Runtime-Privilegien sind getrennt bzw. nachvollziehbar minimiert.
- [ ] Standardbetrieb benötigt keinen langfristigen PAT.

## Gate F – Techniker-UX

- [ ] Standarddeployment kann vollständig aus dem bestehenden CLI gestartet werden.
- [ ] Techniker muss Azure DevOps nicht manuell öffnen.
- [ ] Bereits onboardeter Kunde benötigt keinen interaktiven Kundentenant-Login für normales Deployment.
- [ ] Nicht onboardeter Kunde wird automatisch gebootstrapped und der ursprüngliche Vorgang danach fortgesetzt.
- [ ] CLI zeigt mindestens Profilstatus, Pipeline-Start, Deploymentstatus und aussagekräftigen Fehler/Run-Referenz.
- [ ] Config wird vor Deployment deterministisch committed/gepusht bzw. anderweitig exakt commitgebunden bereitgestellt.

## Gate G – Idempotenz / Reconciliation

- [ ] Zweites identisches Infrastructure Deployment erzeugt keine unnötigen Ressourcen.
- [ ] Zweites identisches PlatformBootstrap erzeugt keine neue Deployment Identity.
- [ ] Zweites identisches Custom-Domain-Ensure erzeugt kein neues Zertifikat.
- [ ] Cloudflare-DNS-/Ruleset-Reconciliation bewahrt nicht verwaltete Regeln.
- [ ] Preserved/Observed State ist bewusst modelliert und dokumentiert.
- [ ] Repair und Update besitzen definierte, getestete Semantik oder wurden sinnvoll konsolidiert.

## Gate H – Altpfade entfernt

- [ ] `current/` ist nicht mehr Teil des produktiven Deploymentmodells.
- [ ] Deploy-to-Azure Raw-GitHub-Pfad ist nicht mehr produktiv erforderlich.
- [ ] `raw.githubusercontent.com` ist aus produktiven Deploymentabhängigkeiten entfernt.
- [ ] `.github/workflows/arm-to-bicep-migration.yml` ist entfernt/obsolet.
- [ ] `.repo-sync` ist entfernt/obsolet, sofern keine andere nachgewiesene Funktion besteht.
- [ ] GitHub-spezifische Template-Traceability wurde durch Azure-DevOps-Commit-Traceability ersetzt.

## Gate I – Plattform und Betrieb

- [ ] Deploymentskripte funktionieren auf PowerShell 7 ohne `cmd.exe /c az`-Abhängigkeit.
- [ ] Microsoft-hosted `ubuntu-latest` ist erfolgreich praktisch getestet oder eine begründete dokumentierte Alternative wurde gewählt.
- [ ] Runtime-Artefakte liegen nicht unnötig im Git-Repository.
- [ ] Produktdokumentation und Architekturdiagramme entsprechen dem real implementierten Zielzustand.
- [ ] `docs/changes.md` enthält die abgeschlossene Migration.

## Pflicht-End-to-End-Tests

Mindestens folgende reale Testfälle müssen mit Nachweis in `STATUS.md` dokumentiert werden:

### E2E-01 – bereits onboardeter Kunde
- [ ] CLI auswählen
- [ ] Profil wird erkannt
- [ ] kein interaktiver Kundentenant-Login
- [ ] Pipeline startet
- [ ] What-If/Deploy/PostDeploy/Verify erfolgreich

### E2E-02 – neuer Kunde
- [ ] CLI auswählen/anlegen
- [ ] fehlendes Profil wird automatisch erkannt
- [ ] PlatformBootstrap startet ohne Rückfrage
- [ ] erforderlicher Microsoft-Kundenlogin funktioniert
- [ ] Identity/RBAC/WIF/Service Connection/Registry werden eingerichtet
- [ ] ursprüngliches Workload-Deployment wird automatisch fortgesetzt
- [ ] Deployment erfolgreich

### E2E-03 – Idempotenz neuer Kunde
- [ ] E2E-02 unmittelbar erneut ausführen
- [ ] keine neue Deployment Identity
- [ ] keine neue Service Connection
- [ ] keine unnötige Zertifikatsrotation
- [ ] keine unerwarteten Cloudflare-Änderungen
- [ ] Deployment erfolgreich

### E2E-04 – Repair/Drift
- [ ] einen sicher reproduzierbaren verwalteten Zustand entfernen/verändern
- [ ] Repair/Ensure erkennt Drift
- [ ] Zustand wird kontrolliert wiederhergestellt
- [ ] nicht verwalteter Zustand bleibt erhalten

## Finale Abschlussbedingung

Erst wenn **alle** Checkboxen dieses Dokuments `[x]` sind und zu den E2E-Tests belastbare Nachweise in `STATUS.md` hinterlegt wurden, darf:

`Gesamtstatus: [x]`

gesetzt werden.

Ein KI-Agent darf keine offenen Punkte stillschweigend als "später", "optional" oder "außerhalb Scope" deklarieren. Wenn ein Punkt fachlich entfallen soll, muss die Architekturentscheidung explizit geändert, begründet und der Gate-Punkt nachvollziehbar angepasst werden.

# Phase 5 – CLI-Integration und Cutover

Status: `[ ]`

## Ziel

Der bestehende PowerShell-Wizard bleibt die einzige notwendige Techniker-Oberfläche. Er steuert Konfiguration, Bootstrap-Prüfung und Pipeline-Start, ohne dass Azure DevOps manuell bedient werden muss.

## WC-05.1 – Bestehenden Wizard als Frontend erhalten
Status: `[ ]`

### Anforderungen
- Bestehende Kundenwahl und Konfigurationsflows bleiben erhalten.
- Menü-/Flow-Libraries bleiben von Deployment-Backend-Details möglichst getrennt.
- Kein Rückfall auf direkte Azure-Deploymentlogik im UI-Layer.

### Akzeptanzkriterien
- `DeployExisting`, `EditConfig`, `CreateOnly`, `Repair` und `Update` besitzen weiterhin definierte Bedienpfade.
- Bestehende Wizard-Tests bleiben erhalten bzw. werden zielgerichtet erweitert.

## WC-05.2 – Automatisches Deployment-Profile Ensure
Status: `[ ]`

Vor jedem Vorgang, der Azure Deployment benötigt:

1. Customer/Environment bestimmen.
2. `Ensure-CustomerDeploymentProfile` aufrufen.
3. Bei vorhandenem Profil ohne Benutzerinteraktion fortfahren.
4. Bei fehlendem Profil PlatformBootstrap **automatisch** ausführen.
5. Nur wenn Microsoft für das erstmalige Kunden-Onboarding interaktive Authentifizierung benötigt, diesen Login anzeigen.
6. Nach erfolgreichem Bootstrap den ursprünglich gewählten Vorgang automatisch fortsetzen.

### Verbot
Keine Frage wie:

`Soll PlatformBootstrap gestartet werden? [J/N]`

Fehlender verwalteter Zustand wird automatisch hergestellt.

## WC-05.3 – Pipeline-Queue aus CLI
Status: `[ ]`

### Pipeline-Aufruf muss mindestens übergeben
- `customerCode`
- `operation`
- exakten Git-Commit/SHA

### Anforderungen
- Kein PAT als reguläre Benutzereingabe.
- Techniker muss keine Azure-DevOps-Webseite öffnen.
- Pipeline-ID/-Name wird aus zentraler Konfiguration/Registry bezogen und nicht frei aus Kunden-JSON übernommen.

## WC-05.4 – Git-Stand deterministisch machen
Status: `[ ]`

### Anforderungen
- Geänderte Kundenkonfiguration muss vor Deployment in dem Git-Stand enthalten sein, den die Pipeline auscheckt.
- Pipeline darf nicht versehentlich einen älteren Branch-HEAD deployen.
- Uncommitted/unpushed Config muss erkannt und kontrolliert behandelt werden.

### Zielvarianten
Bevorzugt:
- Config ändern → validieren → commit/push → Pipeline exakt auf Commit starten.

Für produktive Änderungen kann später optional PR/Approval vorgeschaltet werden; das darf den CLI-First-Grundsatz nicht aufheben.

## WC-05.5 – Fortschritt im CLI anzeigen
Status: `[ ]`

Der Techniker soll mindestens erkennen können:
- Deployment-Profil geprüft/erstellt
- Config validiert
- Pipeline gestartet
- What-If
- Deploy
- PostDeploy
- Verify
- Erfolg/Fehler mit aussagekräftiger Referenz

### Regel
Azure DevOps darf Backend bleiben, aber Fehler dürfen nicht hinter einer simplen Meldung `Pipeline failed` versteckt werden. Der CLI-Flow muss relevante Ursache/Run-ID ausgeben.

## WC-05.6 – Semantik Repair vs Update festlegen
Status: `[ ]`

Aktuell sind Repair und Update im UI getrennt, technisch aber weitgehend gleich.

Vor finalem Cutover muss entschieden und implementiert werden:
- `repair` = gewünschten Zustand erneut reconciliieren / Drift beheben, keine absichtliche Versionsänderung
- `update` = explizite Komponenten-/Versionsänderung oder definierter Upgradepfad

Wenn keine fachlich sinnvolle Trennung implementiert wird, dürfen zwei nur scheinbar unterschiedliche Aktionen nicht bestehen bleiben.

## WC-05.7 – DeleteConfig klar von Infrastructure Delete trennen
Status: `[ ]`

### Anforderungen
- `DeleteConfig` darf nicht implizit Azure-Ressourcen löschen.
- UI und Doku müssen klar benennen, ob nur lokale/versionierte Config entfernt wird.
- Destruktive Azure-Deprovisionierung, falls später gewünscht, erhält separaten, stark abgesicherten Workflow mit eigenem Gate.

## Phase-5-Gate
Status: `[ ]`

Nur schließen, wenn ein Techniker den vollständigen Standardablauf für einen bereits onboardeten und einen noch nicht onboardeten Testkunden ausschließlich aus dem CLI durchführen kann, inklusive automatischem Bootstrap, Pipeline-Start und sichtbarem Endergebnis, ohne manuelle Azure-DevOps-Konfiguration.

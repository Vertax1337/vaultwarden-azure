# Phase 2 – Bicep wird Source-of-Truth

Status: `[ ]`

## Ziel

Die bestehende Richtung `main.json -> main.bicep` wird umgedreht. `main.bicep` ist die einzige gepflegte Infrastrukturquelle.

## WC-02.1 – Bicep-Parität herstellen
Status: `[ ]`

### Aufgaben
- Bestehendes `main.bicep` gegen aktuelles `main.json` prüfen.
- Parameter-, Ressourcen- und Output-Vertrag vollständig vergleichen.
- Bekannte Decompiler-Artefakte bereinigen.
- Bicep-Lint-/Build-Fehler beheben.

### Akzeptanzkriterien
- `az bicep build --file main.bicep` ist erfolgreich.
- Kompiliertes ARM-JSON besitzt denselben erforderlichen Parameter-/Ressourcen-/Output-Vertrag wie die aktuelle produktive Vorlage.

## WC-02.2 – Contract Tests auf kompiliertes Bicep umstellen
Status: `[ ]`

### Prinzip
Bestehende ARM-Contract-Tests werden nicht unnötig verworfen.

Pipeline/Tests erzeugen temporär:

`main.bicep -> az bicep build -> main.compiled.json`

und führen bestehende Ressourcen-/Parameter-/Output-Assertions gegen `main.compiled.json` aus.

### Akzeptanzkriterien
- Tests prüfen weiterhin den realen ARM-Vertrag.
- Kein Test hängt für den Zielbetrieb zwingend an handgepflegtem `main.json`.

## WC-02.3 – Deploymentpfade auf `main.bicep` umstellen
Status: `[ ]`

### Betroffene Stellen mindestens
- `scripts/Invoke-CustomerDeployment.ps1`
- `scripts/deploy.ps1`
- `scripts/Set-AcaIngressRestrictions.ps1`
- weitere Template-Pfadreferenzen

### Vorgehen
Zunächst **JSON-Parameterdateien beibehalten**. Azure CLI kann Bicep-Template + JSON-Parameterdatei deployen. Damit werden Template- und Parameter-Migration nicht unnötig gekoppelt.

### Akzeptanzkriterien
- Lokaler Deploymentpfad kann `main.bicep` verwenden.
- Kein produktiver Skriptpfad verlangt `main.json` als Source-of-Truth.

## WC-02.4 – GitHub Decompile Workflow entfernen/ersetzen
Status: `[ ]`

### Aufgaben
- `.github/workflows/arm-to-bicep-migration.yml` nach erfolgreichem Ersatz entfernen.
- `.repo-sync` entfernen, sofern keine andere aktive Funktion nachgewiesen wird.
- Dauerhafte CI darf Bicep **builden**, aber nicht aus ARM dekompilieren.

## WC-02.5 – Native `.bicepparam` vorbereiten
Status: `[ ]`

### Regel
Nicht zwingend gleichzeitig mit dem Template-Cutover.

### Ziel
- Generierte Kundenparameter langfristig als `.bicepparam` erzeugen.
- Datei bleibt generiert/vergänglich und wird nicht zweiter Source-of-Truth.
- Secrets weiterhin ausschließlich zur Laufzeit injizieren.

## Phase-2-Gate
Status: `[ ]`

Nur schließen, wenn:
- `main.bicep` erfolgreich baut,
- Contract Tests gegen kompiliertes Bicep laufen,
- produktive Template-Referenzen auf Bicep zeigen,
- JSON->Bicep-Decompile nicht mehr Teil des Zielworkflows ist,
- `main.json` nicht mehr manuell gepflegte Infrastrukturquelle ist.

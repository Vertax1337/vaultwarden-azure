## Deployment Scripts nach erfolgreichem Deployment bereinigen

### Hintergrund
Nach einem erfolgreichen Deployment werden die Azure `deploymentScripts`-Ressourcen nicht mehr für den laufenden Betrieb benötigt. Sie dienen nur zur Ausführung während des Deployments sowie kurzzeitig für Status, Logs und Outputs.

### Ziel
Die Resource Group soll nach erfolgreichen Deployments sauber bleiben und keine unnötigen Deployment-Artefakte dauerhaft enthalten.

### Vorschlag
Für `deploymentScripts` konsequent Cleanup und kurze Aufbewahrung konfigurieren:

- `cleanupPreference: OnSuccess`
- `retentionInterval: PT1H`

### Erwartetes Verhalten
- Bei erfolgreichem Deployment werden Script-Hilfsressourcen automatisch bereinigt.
- Logs/Outputs bleiben noch kurz für Prüfzwecke verfügbar.
- Keine dauerhafte Vermüllung der Resource Group durch Deployment-Artefakte.

### Hinweis
Die `deploymentScripts`-Ressource ist keine Laufzeitkomponente der Anwendung und wird nach erfolgreichem Deployment für den Betrieb nicht mehr benötigt.

### ToDo
- [ ] Vorhandene `deploymentScripts` im Template prüfen
- [ ] `cleanupPreference` auf `OnSuccess` setzen
- [ ] `retentionInterval` sinnvoll kurz setzen (z. B. `PT1H`)
- [ ] Verhalten nach Success/Failure testen und dokumentieren

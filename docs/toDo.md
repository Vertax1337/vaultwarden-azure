# ToDo


#       ________                __     _____       __      __  _                
#      / ____/ /___  __  ______/ /    / ___/____  / /_  __/ /_(_)___  ____      
#     / /   / / __ \/ / / / __  /_____\__ \/ __ \/ / / / / __/ / __ \/ __ \     
#    / /___/ / /_/ / /_/ / /_/ /_____/__/ / /_/ / / /_/ / /_/ / /_/ / / / /     
#    \____/_/\____/\__,_/\__,_/  __ /____/\____/_/\__,_/\__/_/\____/_/ /_/      
#              / __ \___  ____  / /___  __  _____  _____                        
#             / / / / _ \/ __ \/ / __ \/ / / / _ \/ ___/                        
#            / /_/ /  __/ /_/ / / /_/ / /_/ /  __/ /                            
#           /_____/\___/ .___/_/\____/\__, /\___/_/                             
#                     /_/            /____/                   


## Offene Punkte

- [ ] SMTP-Secret-Abfrage im Deploy-Flow klarer beschriften
- [ ] Deployment-Scripts nach erfolgreichem Deployment automatisch bereinigen

---

## 1. SMTP-Secret-Abfrage im Deploy-Flow klarer beschriften

### Problem
Beim Deployen einer bestehenden Kundenkonfiguration wird das SMTP-Secret korrekt erst zur Laufzeit abgefragt, damit kein Secret in Dateien oder Konfigurationen gespeichert werden muss.

Die aktuelle Eingabeaufforderung ist jedoch zu generisch (`SMTP Password`) und zeigt nicht, für **welchen Benutzer**, **welchen Host** oder **welchen Mail-Modus** das Secret gerade abgefragt wird.

### Ziel
Die Secret-Abfrage soll für den Operator eindeutig und nachvollziehbar sein, ohne das Secret selbst offenzulegen oder zu speichern.

### Anforderungen
Die Eingabeaufforderung soll mindestens folgende Informationen anzeigen:

- Kundenkontext bzw. Zielkonfiguration
- Mail-Modus (`smtp_auth`, `acs_smtp`, etc.)
- SMTP-Benutzer
- SMTP-Host

### Beispiel
Aktuell:

`SMTP Password`

Gewünscht z. B.:

`SMTP-Secret für noreply@example.de auf smtp.office365.com eingeben (Mail-Modus: smtp_auth)`

### Akzeptanzkriterien
- [ ] Die Passwortabfrage bleibt interaktiv und sicher.
- [ ] Es wird kein Secret in Config-Dateien, Logs oder Parameterdateien geschrieben.
- [ ] Der Prompt ist eindeutig genug, damit der Operator sofort erkennt, für welchen SMTP-Kontext die Eingabe gilt.
- [ ] Die Formulierung funktioniert auch für unterschiedliche Mail-Modi und ist nicht nur auf klassisches SMTP-Auth beschränkt.

---

## 2. Deployment-Scripts nach erfolgreichem Deployment bereinigen

### Hintergrund
Nach einem erfolgreichen Deployment werden die Azure-`deploymentScripts`-Ressourcen nicht mehr für den laufenden Betrieb benötigt. Sie dienen nur zur Ausführung während des Deployments sowie kurzzeitig für Status, Logs und Outputs.

### Ziel
Die Resource Group soll nach erfolgreichen Deployments sauber bleiben und keine unnötigen Deployment-Artefakte dauerhaft enthalten.

### Umsetzungsvorschlag
Für `deploymentScripts` konsequent Cleanup und kurze Aufbewahrung konfigurieren:

- `cleanupPreference: OnSuccess`
- `retentionInterval: PT1H`

### Erwartetes Verhalten
- Bei erfolgreichem Deployment werden Script-Hilfsressourcen automatisch bereinigt.
- Logs und Outputs bleiben noch kurz für Prüfzwecke verfügbar.
- Die Resource Group wird nicht dauerhaft mit Deployment-Artefakten belastet.

### Hinweis
Die `deploymentScripts`-Ressource ist keine Laufzeitkomponente der Anwendung und wird nach erfolgreichem Deployment für den Betrieb nicht mehr benötigt.

### Akzeptanzkriterien
- [ ] Vorhandene `deploymentScripts` im Template wurden geprüft.
- [ ] `cleanupPreference` ist auf `OnSuccess` gesetzt.
- [ ] `retentionInterval` ist sinnvoll kurz gesetzt (z. B. `PT1H`).
- [ ] Das Verhalten bei Success und Failure wurde getestet.
- [ ] Das Ergebnis wurde kurz dokumentiert.

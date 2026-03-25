# Operations Playbook – Vaultwarden auf Azure Container Apps

Dieses Dokument ist das operative Runbook für Deployment, Go-Live, Betrieb und Recovery.

## 1. Zielbild

Die Lösung besteht aus fünf betrieblich relevanten Ebenen:

1. **Azure Container App**
   - eigentliche Vaultwarden-Laufzeit
2. **Azure Files**
   - `/data`
   - Attachments, Icons, weitere persistente Dateiinhalte
3. **PostgreSQL Flexible Server**
   - relationale Anwendungsdaten
4. **Key Vault**
   - `ADMIN_TOKEN`, `DATABASE_URL`, SMTP-/SSO-/Push-Secrets (bei Push = Installation ID + Key)
5. **Optional: ACS Foundation**
   - Email Service
   - Email Domain Resource
   - Communication Service

Wichtig:
Ein vollständiger Service-Restore ist immer **App + Daten + Secrets + Smoke-Test**.

---

## 2. Standard-Betriebsweg

### Ohne ACS
1. `main.json` deployen (`adminPanelEnabled=true`, Default)
2. `domainUrl` prüfen
3. SMTP testen
4. ACA-Custom-Domain + TLS binden
5. Smoke-Test inkl. Admin-/DB-Diagnose
6. `main.json` erneut mit `adminPanelEnabled=false` deployen
7. produktiv schalten

### Mit ACS Foundation
1. `main.json` mit `acsDeployFoundation=true` deployen (`adminPanelEnabled=true`, Default)
2. Deployment-Outputs für ACS notieren
3. DNS für ACS setzen (auch bei Microsoft-365-gehosteter Zone im M365 Admin Center)
4. ACS Domain verifizieren
5. Domain mit dem Communication Service verknüpfen
6. SMTP-Username + RBAC für die Entra-App anlegen
7. `main.json` erneut mit ACS-SMTP-Werten deployen
8. Mail-Smoketest und Admin-/DB-Diagnose abschließen
9. `main.json` erneut mit `adminPanelEnabled=false` deployen
10. produktiv schalten

---

## 3. Go-Live-Checkliste

Vor dem Go-Live müssen alle Punkte erfüllt sein:

### App / URL
- Container App ist erreichbar
- `allowInsecureHttp = false`
- finale Ziel-URL antwortet mit gültigem TLS-Zertifikat
- `domainUrl` entspricht der real gebundenen URL

### Mail
- Testmail aus Vaultwarden erfolgreich
- Absenderadresse korrekt
- SPF/DKIM/DMARC passend zum gewählten Mailpfad
- keine Platzhalterwerte mehr in SMTP-Parametern
- bei ACS: Domain ist verified und wirklich mit dem Communication Service verknüpft

### Daten
- Login erfolgreich
- neuer Tresoreintrag speicherbar
- Attachment hochladbar
- Attachment wieder abrufbar

### Sicherheit
- `ADMIN_TOKEN` nur aus Key Vault entnommen, nicht lokal herumliegen lassen
- `adminPanelEnabled` nach erfolgreichem Bootstrap/Testing auf `false` zurückgestellt
- falls im Adminbereich gespeichert wurde: kein persistierter `admin_token` in `/data/config.json` verbleibt
- unnötige Signups deaktiviert
- SSO/Push nur aktiv, wenn getestet

### Recovery
- mindestens ein Restore-Drill geplant oder bereits durchgeführt
- bekannt, wie PostgreSQL + Azure Files gemeinsam zurückgeführt werden

---

## 4. Smoke-Tests nach Deployment

## 4.1 Basis-Smoketest
1. Vaultwarden-Weboberfläche öffnen
2. Login durchführen
3. neuen Login-Eintrag anlegen
4. Eintrag bearbeiten
5. Eintrag wieder lesen

## 4.2 Mail-Smoketest
1. Testeinladung oder Mailfunktion auslösen
2. prüfen, ob Mail ankommt
3. Link in der Mail testen
4. Header prüfen:
   - Absender
   - Reply-To / From konsistent
   - TLS / Zustellung plausibel

## 4.3 Attachment-Smoketest
1. neuen Eintrag mit Attachment erstellen
2. Attachment herunterladen
3. prüfen, ob Datei nach Neustart der App noch vorhanden ist

## 4.4 Restart-Smoketest
1. neue Revision ausrollen oder App neu starten
2. Login erneut testen
3. bestehende Daten prüfen
4. Attachment erneut prüfen

## 4.5 Admin-Panel-Lifecycle-Test
1. Erstdeployment / Bootstrap bewusst mit `adminPanelEnabled = true` fahren
2. Admin-Diagnose abschließen (z. B. Mail-Settings, Datenbankpfad, allgemeine Settings prüfen)
3. Wenn im Adminbereich gespeichert wurde: kontrollieren, dass kein ungewollter persistierter `admin_token` in `/data/config.json` stehen bleibt
4. `main.json` erneut mit `adminPanelEnabled = false` deployen
5. prüfen, dass das Admin-Panel danach nicht mehr aktiv ist

---

## 5. Mail-Betrieb

## 5.1 SMTP Auth
Empfohlener Default.

Prüfen:
- `smtpUseAuth = true`
- `smtpHost` korrekt (`smtp.office365.com` wenn leerer Default genutzt wird, oder Provider-spezifischer Host)
- `smtpPort = 587`
- `smtpSecurity = starttls`
- `smtpUsername` gesetzt
- `smtpPassword` gesetzt
- optional `smtpAuthMechanism` passend zum Provider
- `smtpFrom` produktiv bewusst gesetzt

## 5.2 Direct Send
Nur nutzen, wenn bewusst gewollt.

Prüfen:
- `smtpUseAuth = false`
- `smtpHost` entweder explizit gesetzt oder leer nur zusammen mit gesetztem `mailRootDomain`
- `mailRootDomain` sauber und bewusst gesetzt; es gibt keine automatische Root-Domain-Ableitung mehr aus `domainUrl`
- aktueller Template-Pfad setzt für Vaultwarden in diesem Modus `SMTP_PORT=25` und `SMTP_SECURITY=starttls`
- `SMTP_USERNAME` **darf in der App nicht vorhanden sein**
- `SMTP_PASSWORD` **darf in der App nicht vorhanden sein**
- `SMTP_AUTH_MECHANISM` **darf in der App nicht vorhanden sein**
- Ziel- und Empfängerszenario passt zu Direct Send

Vaultwarden-spezifisch:
- laut offizieller `.env.template` ist `SMTP_PASSWORD` verpflichtend, sobald `SMTP_USERNAME` gesetzt ist
- `SMTP_AUTH_MECHANISM`, `HELO_NAME`, `SMTP_EMBED_IMAGES`, `SMTP_DEBUG`, `SMTP_ACCEPT_INVALID_CERTS` und `SMTP_ACCEPT_INVALID_HOSTNAMES` sind optionale Zusatzparameter
- Admin-UI-Werte können in `/data/config.json` persistiert sein und den Moduswechsel überlagern; beim Wechsel von SMTP Auth auf Direct Send daher im Vaultwarden-Adminbereich prüfen, dass alte SMTP-Auth-Werte nicht mehr aktiv sind.

## 5.3 ACS Foundation + ACS SMTP
Wenn ACS vorbereitet wurde, reicht **nicht** nur der Foundation-Deploy. Für echten Mail-Betrieb sind nach dem ARM-Deploy noch manuelle Portal- und DNS-Schritte erforderlich.

### 5.3.1 Was nach dem Foundation-Deploy bereits da ist
Bei `acsDeployFoundation = true` erstellt `main.json` bereits:
- **Email Service**
- **Email Domain Resource**
- **Communication Service**

Notiere direkt nach dem Deploy mindestens:
- `acsEmailServiceName`
- `acsCommunicationServiceName`
- `acsEmailDomain`
- `acsEmailDomainResourceId`

### 5.3.2 DNS-Records der ACS-Domain setzen
**Repo-Entscheidung:** Dieses Repo nutzt bewusst nur noch den öffentlich dokumentierten ACS-Custom-Domain-Pfad `CustomerManaged`. `CustomerManagedInExchangeOnline` wurde entfernt, weil Microsoft dafür keinen gleichwertig dokumentierten Workflow bereitstellt.

1. Öffne im Azure-Portal den **Email Service**.
2. Gehe zu **Provision domains** und öffne die vorbereitete Domain.
3. Übernimm **genau** die von ACS geforderten DNS-Einträge im maßgeblichen DNS-System. Wenn Microsoft 365 deine Zone hostet, setzt du diese Records **im M365 Admin Center** und nicht beim Registrar. Typischerweise geht es um:
   - **Ownership-/Domain-Verification-TXT**
   - **SPF-TXT**
   - **DKIM-CNAME**
   - **DKIM2-CNAME**
4. Achte darauf, die Zielwerte unverändert zu übernehmen. DKIM-/DKIM2-CNAMEs dürfen nicht umgeschrieben oder durch Proxies verfälscht werden.
5. Warte nach dem DNS-Update auf die Propagation. Microsoft nennt für die Verifikation typischerweise **15 bis 30 Minuten**, real kann es je nach DNS-Provider länger dauern.

### 5.3.3 Domain-Verifikation in ACS abschließen
1. Bleibe im **Email Service** unter **Provision domains**.
2. Prüfe die Statusfelder der Domain. Für den produktiven Versand sollten **alle** relevanten Stati erfolgreich sein:
   - **Domain status = Verified**
   - **SPF = Verified**
   - **DKIM = Verified**
   - **DKIM2 = Verified**
3. Falls einer dieser Stati fehlt, **nicht** mit dem SMTP-Setup weitermachen. Erst die DNS- bzw. Verifikationsfehler beheben.
4. Wenn SPF trotz sichtbarem TXT nicht validiert, prüfe insbesondere den exakten ACS-Wert und laut Microsoft-Troubleshooting auch die SPF-Endung (`-all` statt `~all`, falls ACS genau diesen Nachweis verlangt).

### 5.3.4 Domain mit dem Communication Service verknüpfen
1. Öffne den **Azure Communication Service** (nicht nur den Email Service).
2. Navigiere zu **Email** → **Domains**.
3. Klicke **Connect domain**.
4. Wähle:
   - Subscription
   - Resource Group
   - den passenden **Email Service**
   - die **verifizierte Domain**
5. Bestätige mit **Connect**.

Wichtig:
- Laut Microsoft kann nur eine **verifizierte** Domain verknüpft werden.
- Domain und Communication Service müssen in derselben **Geography / Data location** liegen. Wenn `acsDataLocation` bzw. die Datenlokation nicht zusammenpassen, schlägt das Linking fehl.

### 5.3.5 Entra-Anwendung vorbereiten
1. Verwende eine vorhandene oder neue **Microsoft Entra App Registration** für SMTP AUTH.
2. Erzeuge ein **Client Secret** für diese Anwendung.
3. Notiere:
   - **Application (client) ID**
   - **Client Secret**

Das **Client Secret** ist später das Passwort, das im Template als `smtpPassword` hinterlegt wird.

### 5.3.6 RBAC auf dem Communication Service setzen
1. Öffne den **Azure Communication Service**.
2. Gehe zu **Access control (IAM)**.
3. Lege eine Rollenzuweisung für die verwendete Entra-Anwendung an.
4. Nutze die eingebaute Rolle **Communication and Email Service Owner**.
5. Warte kurz, bis die RBAC-Zuweisung wirksam ist.

Ohne diese Zuweisung taucht die Entra-Anwendung im SMTP-Username-Dialog typischerweise nicht sinnvoll auf bzw. kann später nicht wie erwartet für SMTP AUTH genutzt werden.

### 5.3.7 SMTP-Username im Communication Service anlegen
1. Bleibe im **Azure Communication Service**.
2. Öffne **SMTP Usernames**.
3. Klicke **+ Add SMTP Username**.
4. Wähle die vorbereitete **Entra-Anwendung** aus.
5. Vergib den SMTP-Username. Das kann je nach gewünschtem Modell ein freier Text oder eine Mailadresse unter der verifizierten Domain sein.
6. Prüfe den Status. Erst wenn der Username **Ready to use** ist, solltest du den finalen App-Deploy durchführen.

### 5.3.8 Finalen Vaultwarden-Deploy mit ACS-SMTP fahren
Danach `main.json` erneut mit dem finalen ACS-SMTP-Pfad deployen:
- `smtpUseAuth = true`
- `smtpHost = smtp.azurecomm.net`
- `smtpPort = 587`
- `smtpSecurity = starttls`
- `smtpUsername = <ACS SMTP Username>`
- `smtpPassword = <Client Secret der Entra App>`
- optional `smtpAuthMechanism = Xoauth2`, falls dein Provider-/ACS-Pfad das explizit verlangt

### 5.3.9 Technische Mindestprüfungen nach dem ACS-Cutover
Nach dem finalen Deploy prüfen:
1. Vaultwarden-Testmail senden
2. Mail kommt an
3. Absender liegt unter der verifizierten und verknüpften Domain
4. `smtp.azurecomm.net` auf **Port 587** erreichbar
5. TLS / StartTLS aktiv
6. SMTP-Username im ACS-Portal weiterhin **Ready to use**

### 5.3.10 Häufige Fehlerbilder
- **Domain verified, aber nicht connectbar**  
  Meist ist die Domain noch nicht vollständig verifiziert oder die **Data location / Geography** passt nicht zwischen Email Service und Communication Service.

- **SMTP-Username bleibt nicht nutzbar**  
  RBAC auf dem Communication Service fehlt, die falsche Entra-App wurde gewählt oder die Domain ist noch nicht sauber verknüpft.

- **DNS scheinbar korrekt, Portal zeigt trotzdem unverified**  
  Propagation ist noch nicht vollständig durch oder einzelne Records wurden verändert/proxied übernommen.

- **Mail aus Vaultwarden schlägt trotz fertigem ACS fehl**  
  Häufig sind `smtpUsername`, `smtpPassword`, `smtpFrom`, Domain-Linking oder persistierte alte SMTP-Werte in Vaultwarden (`/data/config.json`) die Ursache.

---

## 5.4 Vaultwarden SSO / OIDC

Die SSO-Parameter in `main.json` bilden **Vaultwarden OIDC / SSO** ab, nicht Azure App Proxy oder Entra Seamless SSO.

### 5.4.1 Wofür die Parameter stehen
- `ssoEnabled` → aktiviert `SSO_ENABLED`
- `ssoOnly` → aktiviert `SSO_ONLY` und unterbindet klassischen Mail/Passwort-Login
- `ssoAuthority` → `SSO_AUTHORITY`
- `ssoClientId` → `SSO_CLIENT_ID`
- `ssoClientSecret` → `SSO_CLIENT_SECRET`
- `ssoScopes` → `SSO_SCOPES`

### 5.4.2 Empfohlener Entra-ID-Pfad
1. In **Microsoft Entra ID** eine **App Registration** anlegen.
2. **Web Redirect URI** für Vaultwarden hinterlegen. Laut aktueller Vaultwarden-OIDC-Doku wird der Callback aus `DOMAIN` gebildet; bei `https://vaultwarden.example.tld` lautet er `https://vaultwarden.example.tld/identity/connect/oidc-signin`.
3. `Application (client) ID` als `ssoClientId` übernehmen.
4. `Directory (tenant) ID` in `ssoAuthority` einbauen: `https://login.microsoftonline.com/<TENANT_ID>/v2.0`
5. In **Certificates & secrets** ein Client Secret erzeugen und dessen **Secret Value** als `ssoClientSecret` verwenden.
6. Die in der Vaultwarden-Doku empfohlenen Scopes verwenden. Für Entra ID ist der Repo-Default `openid profile email offline_access User.Read` bewusst passend gewählt.
7. `main.json` mit den finalen Werten deployen.
8. Danach zuerst **zusätzlich** zum klassischen Login testen (`ssoOnly=false`). Erst wenn der Login zuverlässig klappt, optional auf `ssoOnly=true` umstellen.

### 5.4.3 Weiterführende Links
- Vaultwarden SSO (Wiki): https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect
- Release-Hinweis zu SSO in Vaultwarden 1.35.0: https://github.com/dani-garcia/vaultwarden/releases/tag/1.35.0

## 5.5 Vaultwarden Mobile Push

### 5.5.1 Wofür die Parameter stehen
- `pushEnabled` → `PUSH_ENABLED`
- `pushInstallationId` → `PUSH_INSTALLATION_ID`
- `pushInstallationKey` → `PUSH_INSTALLATION_KEY`
- `pushUseEuServers` → setzt im Repo die passenden `.com`- bzw. `.eu`-URIs fuer `PUSH_RELAY_URI` und `PUSH_IDENTITY_URI`

### 5.5.2 Bereitstellung von Installation ID / Key
1. Öffne **https://bitwarden.com/host/**.
2. Fordere dort **eine eindeutige Installation ID und einen Installation Key pro Vaultwarden-/Bitwarden-Instanz** an.
3. Wähle die Region passend zu deinem Bitwarden-Cloud-/Lizenz-Kontext:
   - `vault.bitwarden.com` → US
   - `vault.bitwarden.eu` → EU
4. Übernimm die Werte in `pushInstallationId` und `pushInstallationKey`.
5. Setze `pushUseEuServers=true` **nur dann**, wenn die Installation ID / der Key für die **EU-Region** angefordert wurden.
6. Deploye `main.json` erneut mit `pushEnabled=true`.

### 5.5.3 Wichtige Betriebsnotizen
- Bitwarden behandelt **Installation ID und Key als Geheimnisse**. Das Repo legt deshalb jetzt **beide** Werte in Key Vault ab.
- Ohne Push funktionieren die Clients weiter, aber automatische Mobile-Syncs und bestimmte Logout-/Status-Signale laufen eingeschränkt.
- Nach Aktivierung von Push den Flow mit einem echten Mobilclient testen.

### 5.5.4 Weiterführende Links
- Installation ID / Key anfordern: https://bitwarden.com/host/
- Bitwarden Hosting-FAQ: https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay: https://bitwarden.com/help/configure-push-relay/
- Vaultwarden Mobile Push (Wiki): https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification

## 5.6 Parameter-Referenz (Azure vs. Vaultwarden)

### Azure-/Deploy-Parameter
#### Core
- `location`, `environment`, `bsseRef`, `appName`
- `vaultwardenImage`, `cpuCores`, `memorySize`
- `allowInsecureHttp`, `diagnosticsEnabled`, `deploymentScriptForceUpdateTag`

#### Azure Files / Backup
- `storageAccountSku`
- `azureFilesBackupEnabled`
- `azureFilesBackupScheduleRunTime`
- `azureFilesBackupTimeZone`
- `azureFilesBackupDailyRetentionDays`
- `azureFilesBackupWeeklyDaysOfWeek`
- `azureFilesBackupWeeklyRetentionWeeks`

#### PostgreSQL / Bootstrap-only
- `postgresSkuName`
- `postgresStorageGB`
- `postgresBackupRetentionDays`
- `allowAzureServicesToPostgres`
- `dbAdminUser`
- `dbPassword`

`dbAdminUser` und `dbPassword` werden weiterhin benötigt, weil damit der PostgreSQL Flexible Server erstellt und das initiale Bootstrap-Script ausgeführt wird. Diese Werte sind **keine** Vaultwarden-App-Credentials und werden nicht als Vaultwarden-Login genutzt.

#### ACS Foundation
- `acsDeployFoundation`
- `acsDataLocation`
- `acsDomainName`

### Vaultwarden-Parameter / ENV-Mapping
#### Core / Admin
- `domainUrl` → `DOMAIN`
- `adminPanelEnabled` → steuert `ADMIN_TOKEN`

#### Organisation / Signup
- `invitationOrgName` → `INVITATION_ORG_NAME`
- `signupsDomainsWhitelist` → `SIGNUPS_DOMAINS_WHITELIST`
- `orgCreationUsers` → `ORG_CREATION_USERS`

#### Mail
- `mailRootDomain`
- `smtpUseAuth`, `smtpFrom`, `smtpFromName`, `heloName`, `smtpHost`, `smtpPort`, `smtpSecurity`, `smtpUsername`, `smtpPassword`, `smtpAuthMechanism`

#### SSO
- `ssoEnabled`, `ssoOnly`, `ssoAuthority`, `ssoClientId`, `ssoClientSecret`, `ssoScopes`

#### Push
- `pushEnabled`, `pushInstallationId`, `pushInstallationKey`, `pushUseEuServers`

## 6. Regelbetrieb / tägliche Checks

### Täglich / regelmäßig
- Container App fehlerfrei erreichbar
- keine auffälligen Restarts
- Mailversand funktioniert
- PostgreSQL erreichbar
- letzter Azure Files Backup Job erfolgreich
- bei ACS: Domain-Verknüpfung und Zustellpfad unverändert intakt

### Nach Redeploys
- ein Redeploy mit unverändertem `deploymentScript` führt das Bootstrap-Script nicht automatisch erneut aus
- wenn DB-/Secret-Reconciliation bewusst erneut laufen soll, `deploymentScriptForceUpdateTag` ändern
- nach jedem bewussten Bootstrap-Re-Run Basis- und Mail-Smoketest fahren

### Nach Änderungen an Secrets
- bei versionlosen Key-Vault-URIs kann ACA neue Secret-Versionen nachziehen, ohne dass die Secret-URI geändert wird
- für planbare Sofortwirkung trotzdem bewussten Restart / neue Revision oder inhaltlichen Redeploy einplanen
- Mail/SSO/Push sofort testen

### Nach Änderungen an DNS / Domains
- finale URL testen
- Zertifikat prüfen
- Mailzustellung erneut testen

---

## 7. Änderungen / Wartung

## 7.1 Vaultwarden-Image aktualisieren
1. neues Image-Tag in `main.json` setzen
2. Deploy ausführen
3. Basis- und Mail-Smoketest fahren
4. Änderungen dokumentieren

## 7.2 SMTP-Credentials rotieren
1. neues Secret / neues Passwort erzeugen
2. `main.json` mit neuem `smtpPassword` erneut deployen
3. falls das Bootstrap-Script sicher erneut laufen soll: `deploymentScriptForceUpdateTag` mitändern
4. Mail-Smoketest durchführen

## 7.3 SSO-Secret rotieren
1. neues Entra-App-Secret erzeugen
2. `main.json` mit neuem `ssoClientSecret` erneut deployen
3. falls das Bootstrap-Script sicher erneut laufen soll: `deploymentScriptForceUpdateTag` mitändern
4. SSO-Login testen

## 7.4 Push-Credentials rotieren
1. bei Bedarf **neue** Installation ID / Key über https://bitwarden.com/host/ beschaffen
2. `main.json` mit neuem `pushInstallationId` und/oder `pushInstallationKey` erneut deployen
3. falls das Bootstrap-Script sicher erneut laufen soll: `deploymentScriptForceUpdateTag` mitändern
4. Push-Funktion mit echtem Mobilclient testen

## 7.5 Admin-Panel nach Bootstrap deaktivieren
1. sicherstellen, dass Bootstrap / Tests / Admin-Diagnose abgeschlossen sind
2. wenn im Vaultwarden-Adminbereich gespeichert wurde: prüfen, dass kein persistierter `admin_token` in `/data/config.json` zurückbleibt
3. `main.json` mit `adminPanelEnabled = false` erneut deployen
4. prüfen, dass das Admin-Panel danach nicht mehr aktiv ist
5. Änderung dokumentieren

## 7.6 ACS-Finalisierung nachholen
1. prüfen, ob ACS Foundation bereits deployed ist
2. die detaillierten Schritte aus **Abschnitt 5.3** abarbeiten
3. insbesondere DNS-Status, Domain Linking, RBAC und SMTP-Username-Status **Ready to use** prüfen
4. `main.json` mit finalem ACS-SMTP-Pfad erneut deployen
5. Mail-Smoketest dokumentieren

---

## 8. Backup- und Recovery-Modell

## 8.1 Was gesichert wird
### PostgreSQL
- Flexible Server Backups / PITR
- Retention über `postgresBackupRetentionDays`

### Azure Files
- Recovery Services Vault Backup, wenn `azureFilesBackupEnabled=true`

### Nicht als „klassisches Backup“ zu verstehen
- Container App selbst
- Revisionen
- Ingress-Bindungen
- ACS DNS / Verifikationszustand

Diese Dinge werden notfalls durch Redeploy / Konfigurationswiederherstellung rekonstruiert.

---

## 9. Incident-Klassen

### A) Nur App / Revision kaputt
Symptome:
- Container startet nicht
- neue Revision fehlerhaft
- Daten aber noch intakt

Vorgehen:
1. letzte funktionierende Konfiguration identifizieren
2. Redeploy / Fix ausrollen
3. Basis-Smoketest durchführen

### B) Mail kaputt
Symptome:
- keine Einladungs-/Testmails
- SMTP-Fehler

Vorgehen:
1. Key Vault Secret prüfen
2. SMTP-Parameter prüfen
3. Mail-Smoketest wiederholen
4. bei ACS: Domain-, Communication-Service-, Linking-, SMTP-Username- und RBAC-Status prüfen
5. bei Direct Send: MX / Root-Domain / Empfängerszenario prüfen

### C) PostgreSQL beschädigt / falscher Datenstand
Symptome:
- Daten fehlen oder sind inkonsistent
- App-Fehler wegen DB

Vorgehen:
1. Schreibzugriffe stoppen
2. PITR-Zeitpunkt bestimmen
3. neuen PostgreSQL-Server per Restore erzeugen
4. `DATABASE_URL` umstellen
5. neue Revision / Redeploy
6. Smoke-Test

### D) Dateiebene `/data` beschädigt
Symptome:
- Attachments fehlen
- Dateifehler

Vorgehen:
1. Schreibzugriffe stoppen
2. Azure Files Recovery Point auswählen
3. bevorzugt in Alternate Location restoren
4. testen
5. dann gezielt umschalten oder Original ersetzen

### E) Vollständiger Service-Recovery
Symptome:
- DB + `/data` müssen zusammen wiederhergestellt werden

Vorgehen:
1. App schreibseitig anhalten
2. Wiederherstellungszeitpunkt festlegen
3. PostgreSQL restoren
4. Azure Files restoren
5. `DATABASE_URL` und ggf. Share-Bindung anpassen
6. neue Revision starten
7. vollständigen Smoke-Test fahren

---

## 10. PostgreSQL Restore

## 10.1 Zielbild
Restore erfolgt typischerweise in **einen neuen Server**.
Danach muss Vaultwarden auf diesen neuen DB-Endpunkt zeigen.

## 10.2 Schritte
1. Restore-Zeitpunkt bestimmen
2. PITR auf neuen Server ausführen
3. Connection String für Vaultwarden aktualisieren
4. Key Vault Secret `vw-database-url` aktualisieren
5. App neu ausrollen
6. Login + Datenprüfung

## 10.3 Nachkontrolle
- Login funktioniert
- alte Einträge vorhanden
- neue Einträge speicherbar
- Mailversand weiterhin intakt

---

## 11. Azure Files Restore

## 11.1 Empfehlung
Für Tests immer zuerst **Alternate Location Restore**.

## 11.2 Schritte
1. Recovery Point auswählen
2. Restore in Alternate Location
3. Inhalt prüfen
4. dann entscheiden:
   - Original überschreiben
   - oder manuellen Sonderpfad für Restore-Umschaltung gehen

> Hinweis: Das Core-Template enthält aktuell keinen einfachen Parameter, um die Container App direkt auf ein alternatives Restore-Share umzuschalten. Dieser Pfad ist derzeit bewusst ein manueller Betriebsfall außerhalb des Standard-Deploys.

## 11.3 Nachkontrolle
- Attachments vorhanden
- Dateien lesbar
- nach Restart weiterhin sichtbar

---

## 12. Vollständiger Recovery-Drill

Empfohlen mindestens einmal nach dem initialen Go-Live.

### Drill-Ablauf
1. Testfenster planen
2. PostgreSQL in neuen Server restoren
3. Azure Files in Alternate Location restoren
4. manuellen Restore-Testpfad auf restored Ressourcen aufbauen
5. Login testen
6. Attachment testen
7. Mail testen
8. Ergebnis dokumentieren

### Ziel
Nicht nur „Backup existiert“, sondern nachweisen:
- Restore ist praktisch durchführbar
- die Kombination aus DB + Files funktioniert
- das Team kennt den Ablauf

---

## 13. Typische Fehlerbilder

### Fehler: `domainUrl` zeigt auf Ziel-Domain, aber ACA ist dort noch nicht gebunden
Auswirkung:
- Links in Mails zeigen auf eine URL, die technisch noch nicht aktiv ist

Lösung:
- Go-Live erst nach finaler Domain-/TLS-Bindung
- alternativ zuerst mit funktionierender Zwischen-URL arbeiten und später umstellen

### Fehler: ACS Foundation ist deployed, aber Domain noch nicht linked
Auswirkung:
- ACS SMTP meldet sinngemäß, dass die Domain noch nicht verknüpft ist

Lösung:
- erst DNS-Verifikation sauber abschließen
- dann Domain mit dem Communication Service verknüpfen
- erst danach SMTP Username und produktiven ACS SMTP Pfad aktivieren

### Fehler: SMTP geändert, aber nicht getestet
Auswirkung:
- produktiver Mailpfad kaputt

Lösung:
- jede Änderung an SMTP sofort mit Testmail validieren

### Fehler: nur DB restore, aber `/data` nicht passend
Auswirkung:
- Attachments oder Dateiinhalte passen nicht zum Datenstand

Lösung:
- Restore immer als Gesamtbild betrachten

---

## 14. Empfohlene Minimal-Dokumentation pro Kunde / Instanz

Für jede produktive Instanz festhalten:
- Resource Group
- Container App Name
- finale URL
- Storage Account + File Share
- PostgreSQL Servername
- Key Vault Name
- Recovery Services Vault Name
- gewählter SMTP-Modus
- ACS Foundation ja/nein
- ACS Email Service Name
- ACS Communication Service Name
- letzter erfolgreicher Smoke-Test
- letzter erfolgreicher Recovery-Drill

---

## 15. Kurzfassung für den Notfall

### App down, Daten okay
- Redeploy / Revision fixen

### Mail down
- SMTP Secret + SMTP Settings prüfen
- Testmail senden
- bei ACS zusätzlich Domain Linking / SMTP Username / RBAC prüfen

### DB kaputt
- PostgreSQL PITR
- `DATABASE_URL` umstellen
- neu deployen

### `/data` kaputt
- Azure Files Restore
- Attachments testen
- Restore-Umschaltung aktuell als manueller Sonderpfad behandeln

### Alles kaputt
- DB + Files wiederherstellen
- App auf Restore-Zustand umschalten
- Smoke-Test
---

## 16. Quellen / Stand (ACS, M365, Bitwarden/Vaultwarden)

Die verlinkten Aussagen in diesem Playbook wurden zuletzt **am 2026-03-20 16:02 CET** gegengeprüft.

### Microsoft Learn / Microsoft 365
- Connect a verified email domain to send email  
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/connect-email-communication-resource
- Set up SMTP authentication for sending emails  
  https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email-smtp/smtp-authentication
- Add custom verified email domains  
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/add-custom-verified-domains
- Troubleshooting domain configuration issues  
  https://learn.microsoft.com/en-gb/azure/communication-services/concepts/email/email-domain-configuration-troubleshooting
- Add DNS records if Microsoft hosts your DNS  
  https://learn.microsoft.com/en-us/office365/admin/setup/add-domain

### Bitwarden / Vaultwarden
- Installation ID / Key anfordern  
  https://bitwarden.com/host/
- Bitwarden Hosting-FAQ  
  https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay  
  https://bitwarden.com/help/configure-push-relay/
- Vaultwarden SSO via OpenID Connect (Wiki)  
  https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect
- Vaultwarden Mobile Push (Wiki)  
  https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification

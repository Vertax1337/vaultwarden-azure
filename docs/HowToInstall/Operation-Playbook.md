# Betriebshandbuch – Vaultwarden auf Azure Container Apps

Dieses Dokument ist das operative Betriebshandbuch (Runbook) für Deployment, Go-Live, laufenden Betrieb, Wartung, Observability und Recovery einer Vaultwarden-Instanz auf Azure Container Apps.

**Zielgruppe:** Administratoren, IT-Dienstleister und KMU-Verantwortliche, die eine Vaultwarden-Instanz auf Azure betreiben oder betreuen.

**Bezug:** Dieses Playbook ergänzt die [Readme.md](../../Readme.md) und den [Changelog](../changes.md). Detaillierte Architektur- und Tradeoff-Dokumentation befindet sich in [docs/architecture.md](../architecture.md), die vollständige Parameterliste mit ENV-Mapping in [docs/reference/parameters.md](../reference/parameters.md). Hier liegt der Fokus auf dem operativen Ablauf.

---

## Inhaltsverzeichnis

1. [Zielbild und Komponentenübersicht](#1-zielbild-und-komponentenübersicht)
2. [Voraussetzungen](#2-voraussetzungen)
3. [Deployment-Ablauf](#3-deployment-ablauf)
4. [Manuelle Nacharbeiten vor Go-Live](#4-manuelle-nacharbeiten-vor-go-live)
5. [Go-Live-Checkliste](#5-go-live-checkliste)
6. [Smoke-Tests](#6-smoke-tests)
7. [Mail-Konfiguration und -Betrieb](#7-mail-konfiguration-und--betrieb)
8. [SSO / OIDC](#8-sso--oidc)
9. [Mobile Push](#9-mobile-push)
10. [Vaultwarden-Update und Upgrade](#10-vaultwarden-update-und-upgrade)
11. [Wartung und Secret-Rotation](#11-wartung-und-secret-rotation)
12. [Regelbetrieb und Prüfroutine](#12-regelbetrieb-und-prüfroutine)
13. [Observability und Troubleshooting](#13-observability-und-troubleshooting)
14. [Backup- und Recovery-Modell](#14-backup--und-recovery-modell)
15. [Incident-Klassen und Wiederherstellung](#15-incident-klassen-und-wiederherstellung)
16. [PostgreSQL-Restore](#16-postgresql-restore)
17. [Azure-Files-Restore](#17-azure-files-restore)
18. [Vollständiger Recovery-Drill](#18-vollständiger-recovery-drill)
19. [Typische Fehlerbilder](#19-typische-fehlerbilder)
20. [Instanz-Dokumentation (pro Kunde / Umgebung)](#20-instanz-dokumentation-pro-kunde--umgebung)
21. [Kurzreferenz für den Notfall](#21-kurzreferenz-für-den-notfall)
22. [Wann dieses Setup nicht geeignet ist](#22-wann-dieses-setup-nicht-geeignet-ist)
23. [Parameter-Referenz](#23-parameter-referenz)
24. [Quellen](#24-quellen)

---

## 1. Zielbild und Komponentenübersicht

Die Lösung besteht aus fünf betrieblich relevanten Ebenen:

| Komponente | Zweck |
|---|---|
| **Azure Container App** | Vaultwarden-Laufzeit (einzelnes Replikat, gepinntes Image) |
| **Azure Files** | Persistentes `/data`-Volume (Attachments, Icons, `config.json`) |
| **PostgreSQL Flexible Server** | Relationale Anwendungsdaten |
| **Azure Key Vault** | `ADMIN_TOKEN`, `DATABASE_URL`, SMTP-/SSO-/Push-Secrets |
| **ACS Foundation** (optional) | Email Service, Email Domain Resource, Communication Service |

Ergänzend deployt das Template:

- **User Assigned Managed Identities** (App liest Secrets; Bootstrap-Script schreibt Secrets)
- **Deployment Script** (Bootstrap: DB-App-User, Secret-Seeding, MX-Lookup)
- **Recovery Services Vault** (Azure-Files-Backup, standardmäßig aktiv)
- **Log Analytics + Diagnostic Settings** (Observability für Key Vault und PostgreSQL)

> **Wichtig:** Ein vollständiger Service-Restore erfordert immer **App + Daten + Secrets + Smoke-Test**.

---

## 2. Voraussetzungen

Vor dem ersten Deployment müssen folgende Voraussetzungen erfüllt sein:

- **Azure-Subscription** mit ausreichenden Berechtigungen (Contributor auf Resource-Group-Ebene)
- **Resource Group** in der gewünschten Azure-Region
- **Parameterdatei** vorbereitet (siehe Beispieldateien unter `examples/parameters/`)
- **DNS-Zugriff** auf die Zieldomain (für Custom Domain und ggf. ACS)
- **SMTP-Zugangsdaten** bereit (M365, ACS oder Drittanbieter)
- Falls SSO gewünscht: **Entra-ID-App-Registration** vorbereitet
- Falls Push gewünscht: **Bitwarden Installation ID und Key** von https://bitwarden.com/host/

> **Hinweis:** `main.bicep` ist veraltet und entspricht **nicht** dem aktuellen `main.json`. Ausschließlich `main.json` für Deployments verwenden.

---

## 3. Deployment-Ablauf

### 3.1 Standard-Ablauf (ohne ACS)

1. `main.json` deployen (`adminPanelEnabled=true`, Default)
2. `domainUrl` prüfen
3. SMTP testen
4. ACA-Custom-Domain + TLS binden (manuell, siehe [Abschnitt 4](#4-manuelle-nacharbeiten-vor-go-live))
5. Smoke-Test inkl. Admin-/DB-Diagnose durchführen
6. `main.json` erneut mit `adminPanelEnabled=false` deployen
7. Produktiv schalten

### 3.2 Ablauf mit ACS Foundation

1. `main.json` mit `acsDeployFoundation=true` deployen (`adminPanelEnabled=true`, Default)
2. Deployment-Outputs für ACS notieren
3. DNS für ACS setzen (auch bei Microsoft-365-gehosteter Zone im M365 Admin Center)
4. ACS-Domain verifizieren
5. Domain mit dem Communication Service verknüpfen
6. SMTP-Username + RBAC für die Entra-App anlegen
7. `main.json` erneut mit ACS-SMTP-Werten deployen
8. Mail-Smoke-Test und Admin-/DB-Diagnose abschließen
9. `main.json` erneut mit `adminPanelEnabled=false` deployen
10. Produktiv schalten

<!-- Screenshot-Vorschlag: Azure-Portal – Deployment-Übersicht nach erfolgreichem Deploy -->

---

## 4. Manuelle Nacharbeiten vor Go-Live

Die folgenden Schritte erfordern DNS-Propagation und externe Verifikation und können nicht in einem einzelnen ARM-Deployment automatisiert werden.

### 4.1 Custom Domain + TLS für die Container App

1. Im Azure-Portal die Container App öffnen
2. Unter **Custom domains** die Zieldomain hinzufügen
3. DNS-Einträge beim Domain-Provider setzen (CNAME oder A-Record + TXT-Validierung)
4. TLS-Zertifikat binden (Azure Managed Certificate oder eigenes Zertifikat)
5. Warten, bis das Zertifikat ausgestellt und aktiv ist

<!-- Screenshot-Vorschlag: Azure-Portal – Container App → Custom domains -->

### 4.2 ACS-Nacharbeiten (nur bei ACS Foundation)

Die vollständige ACS-Finalisierung ist in [Abschnitt 7.3](#73-acs-foundation--acs-smtp) beschrieben.

---

## 5. Go-Live-Checkliste

Vor dem Go-Live müssen alle Punkte erfüllt sein:

### App / URL

- [ ] Container App ist erreichbar
- [ ] `allowInsecureHttp = false`
- [ ] Finale Ziel-URL antwortet mit gültigem TLS-Zertifikat
- [ ] `domainUrl` entspricht der real gebundenen URL

### Mail

- [ ] Testmail aus Vaultwarden erfolgreich
- [ ] Absenderadresse korrekt
- [ ] SPF/DKIM/DMARC passend zum gewählten Mailpfad
- [ ] Keine Platzhalterwerte mehr in SMTP-Parametern
- [ ] Bei ACS: Domain ist verifiziert und mit dem Communication Service verknüpft

### Sicherheit

- [ ] `ADMIN_TOKEN` nur aus Key Vault entnommen, nicht lokal gespeichert
- [ ] `adminPanelEnabled` nach erfolgreichem Bootstrap/Testing auf `false` gesetzt
- [ ] Kein persistierter `admin_token` in `/data/config.json`
- [ ] Unnötige Signups deaktiviert (`SIGNUPS_ALLOWED=false` ist der Default)
- [ ] SSO/Push nur aktiv, wenn getestet
- [ ] `SHOW_PASSWORD_HINT=false` (Default)
- [ ] `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=true` (Default, SSRF-Schutz)

### Daten

- [ ] Login erfolgreich
- [ ] Neuer Tresoreintrag speicherbar
- [ ] Attachment hochladbar
- [ ] Attachment wieder abrufbar

### Backup / Recovery

- [ ] Mindestens ein Restore-Drill geplant oder bereits durchgeführt
- [ ] Bekannt, wie PostgreSQL + Azure Files gemeinsam wiederhergestellt werden
- [ ] PostgreSQL-PITR-Retention (`postgresBackupRetentionDays`) ist ausreichend
- [ ] Azure-Files-Backup ist aktiv und läuft

---

## 6. Smoke-Tests

### 6.1 Basis-Smoke-Test

1. Vaultwarden-Weboberfläche öffnen
2. Login durchführen
3. Neuen Login-Eintrag anlegen
4. Eintrag bearbeiten
5. Eintrag wieder lesen

### 6.2 Mail-Smoke-Test

1. Testeinladung oder Mailfunktion auslösen
2. Prüfen, ob die Mail ankommt
3. Link in der Mail testen
4. Header prüfen:
   - Absender korrekt
   - Reply-To / From konsistent
   - TLS-Zustellung plausibel

### 6.3 Attachment-Smoke-Test

1. Neuen Eintrag mit Attachment erstellen
2. Attachment herunterladen
3. Prüfen, ob die Datei nach Neustart der App noch vorhanden ist

### 6.4 Neustart-Smoke-Test

1. Neue Revision ausrollen oder App neu starten
2. Login erneut testen
3. Bestehende Daten prüfen
4. Attachment erneut prüfen

### 6.5 Admin-Panel-Lifecycle-Test

1. Erstdeployment / Bootstrap bewusst mit `adminPanelEnabled = true` fahren
2. Admin-Diagnose abschließen (z. B. Mail-Einstellungen, Datenbankpfad, allgemeine Konfiguration prüfen)
3. Falls im Adminbereich gespeichert wurde: kontrollieren, dass kein ungewollter persistierter `admin_token` in `/data/config.json` stehen bleibt
4. `main.json` erneut mit `adminPanelEnabled = false` deployen
5. Prüfen, dass das Admin-Panel danach nicht mehr aktiv ist

> **Warnung:** Vaultwarden speichert Admin-UI-Änderungen in `/data/config.json` auf dem Azure-Files-Share. Dort persistierte Werte haben Vorrang vor ENV-Variablen aus dem Template. Nach dem Bootstrap sicherstellen, dass keine veralteten Werte zurückbleiben.

---

## 7. Mail-Konfiguration und -Betrieb

### 7.1 SMTP Auth (Produktiv-Default)

Empfohlener Standard für produktive Umgebungen.

**Prüfpunkte:**

- `smtpUseAuth = true`
- `smtpHost` korrekt (`smtp.office365.com` bei leerem Default, oder providerspezifischer Host)
- `smtpPort = 587`
- `smtpSecurity = starttls`
- `smtpUsername` gesetzt
- `smtpPassword` gesetzt
- Optional: `smtpAuthMechanism` passend zum Provider
- `smtpFrom` produktiv bewusst gesetzt

### 7.2 Direct Send

Nur nutzen, wenn bewusst gewollt.

**Prüfpunkte:**

- `smtpUseAuth = false`
- `smtpHost` entweder explizit gesetzt oder leer zusammen mit gesetztem `mailRootDomain`
- `mailRootDomain` sauber und bewusst gesetzt (keine automatische Ableitung aus `domainUrl`)
- Template setzt für Vaultwarden in diesem Modus `SMTP_PORT=25` und `SMTP_SECURITY=starttls`
- `SMTP_USERNAME` **darf in der App nicht vorhanden sein**
- `SMTP_PASSWORD` **darf in der App nicht vorhanden sein**
- `SMTP_AUTH_MECHANISM` **darf in der App nicht vorhanden sein**
- Ziel- und Empfängerszenario passt zu Direct Send

**Vaultwarden-spezifisches Verhalten:**

- Laut offizieller `.env.template` ist `SMTP_PASSWORD` verpflichtend, sobald `SMTP_USERNAME` gesetzt ist
- `SMTP_AUTH_MECHANISM`, `HELO_NAME`, `SMTP_EMBED_IMAGES`, `SMTP_DEBUG`, `SMTP_ACCEPT_INVALID_CERTS` und `SMTP_ACCEPT_INVALID_HOSTNAMES` sind optionale Zusatzparameter
- Admin-UI-Werte können in `/data/config.json` persistiert sein und den Moduswechsel überlagern. Beim Wechsel von SMTP Auth auf Direct Send daher im Vaultwarden-Adminbereich prüfen, dass alte SMTP-Auth-Werte nicht mehr aktiv sind.

### 7.3 ACS Foundation + ACS SMTP

Wenn ACS vorbereitet wurde, reicht **nicht** nur der Foundation-Deploy. Für echten Mail-Betrieb sind nach dem ARM-Deploy noch manuelle Portal- und DNS-Schritte erforderlich.

#### 7.3.1 Was nach dem Foundation-Deploy bereits vorhanden ist

Bei `acsDeployFoundation = true` erstellt `main.json` bereits:

- **Email Service**
- **Email Domain Resource**
- **Communication Service**

Direkt nach dem Deploy mindestens notieren:

- `acsEmailServiceName`
- `acsCommunicationServiceName`
- `acsEmailDomain`
- `acsEmailDomainResourceId`

#### 7.3.2 DNS-Records der ACS-Domain setzen

**Repo-Entscheidung:** Dieses Repository nutzt bewusst nur den öffentlich dokumentierten ACS-Custom-Domain-Pfad `CustomerManaged`. `CustomerManagedInExchangeOnline` wurde entfernt, weil Microsoft dafür keinen gleichwertig dokumentierten Workflow bereitstellt.

1. Im Azure-Portal den **Email Service** öffnen
2. Unter **Provision domains** die vorbereitete Domain öffnen
3. Die von ACS geforderten DNS-Einträge **exakt** im maßgeblichen DNS-System übernehmen. Bei Microsoft-365-gehosteter Zone die Records **im M365 Admin Center** setzen, nicht beim Registrar. Typische Einträge:
   - **Ownership-/Domain-Verification-TXT**
   - **SPF-TXT**
   - **DKIM-CNAME**
   - **DKIM2-CNAME**
4. DKIM-/DKIM2-CNAMEs unverändert übernehmen – nicht umschreiben oder durch Proxies verfälschen
5. Nach dem DNS-Update auf Propagation warten. Microsoft nennt typischerweise **15 bis 30 Minuten**; real kann es je nach DNS-Provider länger dauern

<!-- Screenshot-Vorschlag: Azure-Portal – Email Service → Provision domains → DNS-Einträge -->

#### 7.3.3 Domain-Verifikation in ACS abschließen

1. Im **Email Service** unter **Provision domains** bleiben
2. Statusfelder der Domain prüfen. Für den produktiven Versand müssen **alle** relevanten Stati erfolgreich sein:
   - **Domain status = Verified**
   - **SPF = Verified**
   - **DKIM = Verified**
   - **DKIM2 = Verified**
3. Falls einer dieser Stati fehlt: **nicht** mit dem SMTP-Setup weitermachen. Erst DNS- bzw. Verifikationsfehler beheben.
4. Falls SPF trotz sichtbarem TXT nicht validiert: den exakten ACS-Wert prüfen, insbesondere SPF-Endung (`-all` statt `~all`, falls ACS diesen Nachweis verlangt)

#### 7.3.4 Domain mit dem Communication Service verknüpfen

1. Den **Azure Communication Service** öffnen (nicht nur den Email Service)
2. Zu **Email** → **Domains** navigieren
3. **Connect domain** klicken
4. Auswählen:
   - Subscription
   - Resource Group
   - Den passenden **Email Service**
   - Die **verifizierte Domain**
5. Mit **Connect** bestätigen

> **Wichtig:** Nur eine **verifizierte** Domain kann verknüpft werden. Domain und Communication Service müssen in derselben **Geography / Data location** liegen. Bei Abweichung schlägt das Linking fehl.

<!-- Screenshot-Vorschlag: Azure-Portal – Communication Service → Email → Domains → Connect domain -->

#### 7.3.5 Entra-Anwendung vorbereiten

1. Eine vorhandene oder neue **Microsoft Entra App Registration** für SMTP AUTH verwenden
2. Ein **Client Secret** für diese Anwendung erzeugen
3. Notieren:
   - **Application (client) ID**
   - **Client Secret** (wird als `smtpPassword` im Template hinterlegt)

#### 7.3.6 RBAC auf dem Communication Service setzen

1. Den **Azure Communication Service** öffnen
2. Unter **Access control (IAM)** eine Rollenzuweisung für die Entra-Anwendung anlegen
3. Die Rolle **Communication and Email Service Owner** verwenden
4. Kurz warten, bis die RBAC-Zuweisung wirksam ist

Ohne diese Zuweisung kann die Entra-Anwendung nicht für SMTP AUTH genutzt werden.

#### 7.3.7 SMTP-Username im Communication Service anlegen

1. Im **Azure Communication Service** zu **SMTP Usernames** navigieren
2. **+ Add SMTP Username** klicken
3. Die vorbereitete **Entra-Anwendung** auswählen
4. SMTP-Username vergeben (freier Text oder Mailadresse unter der verifizierten Domain)
5. Status prüfen: Erst wenn der Username den Status **„Bereit zur Verwendung"** hat, den finalen Deploy durchführen

<!-- Screenshot-Vorschlag: Azure-Portal – Communication Service → SMTP Usernames → Status -->

#### 7.3.8 Finalen Vaultwarden-Deploy mit ACS-SMTP fahren

`main.json` erneut mit dem finalen ACS-SMTP-Pfad deployen:

- `smtpUseAuth = true`
- `smtpHost = smtp.azurecomm.net`
- `smtpPort = 587`
- `smtpSecurity = starttls`
- `smtpUsername = <ACS SMTP Username>`
- `smtpPassword = <Client Secret der Entra App>`
- Optional: `smtpAuthMechanism = Xoauth2`, falls der ACS-Pfad das explizit verlangt

#### 7.3.9 Technische Mindestprüfungen nach dem ACS-Cutover

Nach dem finalen Deploy prüfen:

1. Vaultwarden-Testmail senden
2. Mail kommt an
3. Absender liegt unter der verifizierten und verknüpften Domain
4. `smtp.azurecomm.net` auf **Port 587** erreichbar
5. TLS / StartTLS aktiv
6. SMTP-Username im ACS-Portal weiterhin im Status **„Bereit zur Verwendung"**

#### 7.3.10 Häufige ACS-Fehlerbilder

| Fehlerbild | Typische Ursache |
|---|---|
| Domain verifiziert, aber nicht verknüpfbar | Domain noch nicht vollständig verifiziert oder **Data location / Geography** passt nicht zwischen Email Service und Communication Service |
| SMTP-Username nicht nutzbar | RBAC auf dem Communication Service fehlt, falsche Entra-App gewählt oder Domain noch nicht sauber verknüpft |
| DNS korrekt, Portal zeigt dennoch „nicht verifiziert" | Propagation noch nicht abgeschlossen oder einzelne Records verändert/proxied übernommen |
| Mail aus Vaultwarden schlägt trotz fertigem ACS fehl | Häufig: `smtpUsername`, `smtpPassword`, `smtpFrom`, Domain-Linking oder persistierte alte SMTP-Werte in `/data/config.json` |

---

## 8. SSO / OIDC

Die SSO-Parameter in `main.json` bilden **Vaultwarden OIDC / SSO** ab – nicht Azure App Proxy oder Entra Seamless SSO.

### 8.1 Parameter-Zuordnung

| Template-Parameter | Vaultwarden-ENV |
|---|---|
| `ssoEnabled` | `SSO_ENABLED` |
| `ssoOnly` | `SSO_ONLY` (unterbindet klassischen Mail-/Passwort-Login) |
| `ssoAuthority` | `SSO_AUTHORITY` |
| `ssoClientId` | `SSO_CLIENT_ID` |
| `ssoClientSecret` | `SSO_CLIENT_SECRET` |
| `ssoScopes` | `SSO_SCOPES` |

### 8.2 Empfohlener Entra-ID-Einrichtungspfad

1. In **Microsoft Entra ID** eine **App Registration** anlegen
2. **Web Redirect URI** hinterlegen. Vaultwarden bildet den Callback aus `DOMAIN`:  
   `https://vaultwarden.example.tld/identity/connect/oidc-signin`
3. `Application (client) ID` als `ssoClientId` übernehmen
4. `Directory (tenant) ID` in `ssoAuthority` einbauen:  
   `https://login.microsoftonline.com/<TENANT_ID>/v2.0`
5. Unter **Certificates & secrets** ein Client Secret erzeugen und dessen **Secret Value** als `ssoClientSecret` verwenden
6. Scopes verwenden: Der Repo-Default `openid profile email offline_access User.Read` ist für Entra ID bewusst passend gewählt
7. `main.json` mit den finalen Werten deployen
8. Zuerst **zusätzlich** zum klassischen Login testen (`ssoOnly=false`). Erst wenn der Login zuverlässig funktioniert, optional auf `ssoOnly=true` umstellen

> **Warnung:** `ssoOnly=true` deaktiviert den Master-Passwort-Login vollständig. SSO vorher gründlich testen. Das Deployment bricht mit einer Fehlermeldung ab, wenn `ssoOnly=true` ohne `ssoEnabled=true` gesetzt wird.

### 8.3 Weiterführende Links

- Vaultwarden SSO (Wiki): https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect
- Release-Hinweis zu SSO in Vaultwarden 1.35.0: https://github.com/dani-garcia/vaultwarden/releases/tag/1.35.0

---

## 9. Mobile Push

### 9.1 Parameter-Zuordnung

| Template-Parameter | Vaultwarden-ENV |
|---|---|
| `pushEnabled` | `PUSH_ENABLED` |
| `pushInstallationId` | `PUSH_INSTALLATION_ID` |
| `pushInstallationKey` | `PUSH_INSTALLATION_KEY` |
| `pushUseEuServers` | Setzt die passenden `.com`- bzw. `.eu`-URIs für `PUSH_RELAY_URI` und `PUSH_IDENTITY_URI` |

### 9.2 Installation ID und Key beschaffen

1. https://bitwarden.com/host/ öffnen
2. **Eine eindeutige Installation ID und einen Installation Key pro Vaultwarden-Instanz** anfordern
3. Region passend zum Bitwarden-Cloud-/Lizenz-Kontext wählen:
   - `vault.bitwarden.com` → US
   - `vault.bitwarden.eu` → EU
4. Werte in `pushInstallationId` und `pushInstallationKey` übernehmen
5. `pushUseEuServers=true` **nur dann** setzen, wenn die Werte für die **EU-Region** angefordert wurden
6. `main.json` mit `pushEnabled=true` deployen

### 9.3 Wichtige Betriebshinweise

- Bitwarden behandelt **Installation ID und Key als Geheimnisse**. Das Repository legt deshalb beide Werte in Key Vault ab.
- Ohne Push funktionieren die Clients weiter, aber automatische Mobile-Syncs und bestimmte Logout-/Status-Signale sind eingeschränkt.
- Nach Aktivierung von Push den Flow mit einem echten Mobilclient testen.

### 9.4 Weiterführende Links

- Installation ID / Key anfordern: https://bitwarden.com/host/
- Bitwarden Hosting-FAQ: https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay: https://bitwarden.com/help/configure-push-relay/
- Vaultwarden Mobile Push (Wiki): https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification

---

## 10. Vaultwarden-Update und Upgrade

### 10.1 Image-Tag-Strategie

Der Parameter `vaultwardenImage` (Default: `vaultwarden/server:1.35.3-alpine`) bestimmt das Container-Image.

| Ansatz | Beispiel | Empfehlung |
|---|---|---|
| Gepinnter Tag | `vaultwarden/server:1.35.3-alpine` | **Produktiv-Default** – reproduzierbar, kein unerwartetes Update |
| Minor-Floating | `vaultwarden/server:1-alpine` | Nur für Test-/Dev-Umgebungen |
| `latest` | `vaultwarden/server:latest` | **Nicht empfohlen** – unkontrolliertes Versionsupdate |

### 10.2 Update-Ablauf

1. **Vorbereiten**
   - Release-Notes auf https://github.com/dani-garcia/vaultwarden/releases prüfen (Breaking Changes, DB-Migrationen)
   - Aktuellen `vaultwardenImage`-Wert aus dem letzten Deployment notieren
2. **Backup erstellen**
   - PostgreSQL-PITR-Zeitpunkt notieren
   - Azure-Files-Backup prüfen / manuellen Snapshot erstellen
3. **Image-Tag aktualisieren**
   - In der Parameterdatei `vaultwardenImage` auf den neuen Tag setzen (z. B. `vaultwarden/server:1.36.0-alpine`)
4. **Redeploy ausführen**
   ```bash
   az deployment group create \
     -g <resource-group> \
     -f main.json \
     -p @params.json
   ```
5. **Validieren**
   - Container-Log-Stream auf Startfehler prüfen
   - Login testen, Tresoreintrag erstellen/lesen
   - Mail-Versand testen (falls SMTP aktiv)

### 10.3 Downtime-Verhalten

- Das Template nutzt `activeRevisionsMode: Single` mit `minReplicas: 1` / `maxReplicas: 1`
- Bei einem Redeploy erstellt ACA eine **neue Revision** und deaktiviert die alte
- Während des Übergangs gibt es eine **kurze Downtime** (typisch 10–30 Sekunden), bis die neue Revision die Startup-Probe besteht
- Es gibt kein Blue/Green-Deployment im Single-Revision-Modus
- Für geplante Updates: Wartungsfenster kommunizieren; für KMU-Größe ist die kurze Unterbrechung in der Regel akzeptabel

### 10.4 Rollback

Falls das neue Image Probleme verursacht:

1. `vaultwardenImage` auf den vorherigen Tag zurücksetzen
2. Erneut deployen
3. Falls DB-Migrationen nicht rückwärtskompatibel: PostgreSQL via PITR auf den Backup-Zeitpunkt wiederherstellen

> **Warnung:** Vaultwarden führt DB-Schema-Migrationen automatisch beim Start durch. Ein Downgrade auf eine ältere Version kann fehlschlagen, wenn die neue Version das Schema geändert hat. Im Zweifel immer den PITR-Pfad nutzen.

---

## 11. Wartung und Secret-Rotation

### 11.1 SMTP-Credentials rotieren

1. Neues Secret / neues Passwort erzeugen
2. `main.json` mit neuem `smtpPassword` erneut deployen
3. Falls das Bootstrap-Script erneut laufen soll: `deploymentScriptForceUpdateTag` mitändern
4. Mail-Smoke-Test durchführen

### 11.2 SSO-Secret rotieren

1. Neues Entra-App-Secret erzeugen
2. `main.json` mit neuem `ssoClientSecret` erneut deployen
3. Falls das Bootstrap-Script erneut laufen soll: `deploymentScriptForceUpdateTag` mitändern
4. SSO-Login testen

### 11.3 Push-Credentials rotieren

1. Bei Bedarf **neue** Installation ID / Key über https://bitwarden.com/host/ beschaffen
2. `main.json` mit neuen Werten erneut deployen
3. Falls das Bootstrap-Script erneut laufen soll: `deploymentScriptForceUpdateTag` mitändern
4. Push-Funktion mit echtem Mobilclient testen

### 11.4 Admin-Panel nach Bootstrap deaktivieren

1. Sicherstellen, dass Bootstrap / Tests / Admin-Diagnose abgeschlossen sind
2. Falls im Vaultwarden-Adminbereich gespeichert wurde: prüfen, dass kein persistierter `admin_token` in `/data/config.json` zurückbleibt
3. `main.json` mit `adminPanelEnabled = false` erneut deployen
4. Prüfen, dass das Admin-Panel danach nicht mehr aktiv ist

### 11.5 ACS-Finalisierung nachholen

1. Prüfen, ob ACS Foundation bereits deployt ist
2. Die detaillierten Schritte aus [Abschnitt 7.3](#73-acs-foundation--acs-smtp) abarbeiten
3. Insbesondere DNS-Status, Domain-Linking, RBAC und SMTP-Username-Status prüfen
4. `main.json` mit finalem ACS-SMTP-Pfad erneut deployen
5. Mail-Smoke-Test durchführen und dokumentieren

---

## 12. Regelbetrieb und Prüfroutine

### 12.1 Regelmäßige Prüfungen

| Prüfpunkt | Häufigkeit |
|---|---|
| Container App fehlerfrei erreichbar | Täglich / automatisiert |
| Keine auffälligen Container-Neustarts | Täglich |
| Mailversand funktioniert (Testmail) | Wöchentlich |
| PostgreSQL erreichbar | Täglich / automatisiert |
| Letzter Azure-Files-Backup-Job erfolgreich | Wöchentlich |
| Log Analytics auf Fehler prüfen | Wöchentlich |
| Bei ACS: Domain-Verknüpfung und Zustellpfad intakt | Monatlich |
| Vaultwarden-Release-Notes auf neue Versionen prüfen | Monatlich |

### 12.2 Nach Redeploys

- Ein Redeploy mit unverändertem `deploymentScript` führt das Bootstrap-Script **nicht** automatisch erneut aus
- Wenn DB-/Secret-Reconciliation bewusst erneut laufen soll: `deploymentScriptForceUpdateTag` ändern
- Nach jedem bewussten Bootstrap-Re-Run Basis- und Mail-Smoke-Test fahren

### 12.3 Nach Änderungen an Secrets

- Bei versionlosen Key-Vault-URIs kann ACA neue Secret-Versionen nachziehen, ohne dass die Secret-URI geändert wird
- Für planbare Sofortwirkung trotzdem bewussten Restart / neue Revision oder inhaltlichen Redeploy einplanen
- Mail/SSO/Push sofort testen

### 12.4 Nach Änderungen an DNS / Domains

- Finale URL testen
- Zertifikat prüfen
- Mailzustellung erneut testen

---

## 13. Observability und Troubleshooting

### 13.1 Log-Quellen

| Quelle | Ort | Inhalt |
|---|---|---|
| Vaultwarden-Containerlog | Azure Portal → Container App → **Log stream** oder Log Analytics: `ContainerAppConsoleLogs_CL` | App-Startfehler, SMTP-Fehler, SSO-Fehler, DB-Verbindungsfehler |
| ACA-Systemlogs | Log Analytics: `ContainerAppSystemLogs_CL` | Probe-Ausfälle, Revisions-Neustarts, Image-Pull-Fehler |
| Key-Vault-Audit | Log Analytics: `AzureDiagnostics` (Kategorie `AuditEvent`) | Secret-Zugriffe, Berechtigungsfehler (erfordert `diagnosticsEnabled=true`) |
| PostgreSQL-Logs | Log Analytics: `AzureDiagnostics` (Kategorie `PostgreSQLLogs`) | Verbindungsfehler, langsame Abfragen, Auth-Fehler (erfordert `diagnosticsEnabled=true`) |
| Deployment-Script | Azure Portal → Resource Group → Deployments → Script-Ressource → **Logs** | Bootstrap-Fehler, Eingabevalidierung, Secret-Provisionierung |

<!-- Screenshot-Vorschlag: Azure-Portal – Container App → Log stream -->

### 13.2 Erster Fehler-Check (Quick Triage)

| Symptom | Erster Check |
|---|---|
| **Container startet nicht** | Log-Stream prüfen → häufigste Ursache: `DATABASE_URL` ungültig, Volume-Mount-Fehler oder Image-Pull-Fehler. `ContainerAppSystemLogs_CL` auf Liveness-/Readiness-Probe-Ausfälle prüfen |
| **502 / Seite nicht erreichbar** | Custom Domain + TLS-Zertifikat korrekt gebunden? `domainUrl` stimmt mit der tatsächlichen URL überein? `allowInsecureHttp=false` ohne TLS-Zertifikat? |
| **Mail kommt nicht an** | Containerlog nach `SMTP`-Fehlern durchsuchen. Bei Direct Send: MX-Auflösung im Deployment-Script-Log prüfen. SPF/DKIM/DMARC-Records validieren |
| **SSO-Login schlägt fehl** | Containerlog nach `OIDC`-/`SSO`-Fehlern durchsuchen. Redirect-URI in der App Registration korrekt? `ssoAuthority`-URL erreichbar? |
| **Deployment-Script schlägt fehl** | Script-Log im Portal prüfen → klare `ERROR:`-Meldungen für fehlende Parameter. Timeout-Fehler deuten auf Netzwerk-/RBAC-Probleme hin |

### 13.3 Nützliche Log-Analytics-Abfragen (KQL)

```kusto
// Vaultwarden-Containerlogs der letzten 30 Minuten
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where ContainerAppName_s contains "vault"
| project TimeGenerated, Log_s
| order by TimeGenerated desc

// Probe-Ausfälle (Liveness/Readiness)
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(1h)
| where Reason_s in ("Unhealthy", "BackOff")
| project TimeGenerated, Reason_s, Log_s

// Key-Vault-Zugriffsfehler
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where ResultSignature != "OK"
| project TimeGenerated, OperationName, ResultSignature, CallerIPAddress
```

<!-- Screenshot-Vorschlag: Azure-Portal – Log Analytics → Abfrage-Editor mit KQL-Abfrage -->

---

## 14. Backup- und Recovery-Modell

### 14.1 Was gesichert wird

| Datenquelle | Backup-Methode | Konfiguration |
|---|---|---|
| **PostgreSQL** | Flexible-Server-Backups / PITR | Retention über `postgresBackupRetentionDays` (Default: 14 Tage) |
| **Azure Files** | Recovery Services Vault Backup | Aktiv wenn `azureFilesBackupEnabled=true` (Default) |

### 14.2 Nicht als „klassisches Backup" zu verstehen

Folgende Elemente werden bei Bedarf durch Redeploy / Konfigurationswiederherstellung rekonstruiert:

- Container App (Revisionen, Ingress-Bindungen)
- ACS DNS- / Verifikationszustand
- Key-Vault-Secrets (werden vom Bootstrap-Script geschrieben)

---

## 15. Incident-Klassen und Wiederherstellung

### 15.1 Nur App / Revision fehlerhaft

**Symptome:** Container startet nicht, neue Revision fehlerhaft, Daten intakt

**Vorgehen:**

1. Letzte funktionierende Konfiguration identifizieren
2. Redeploy / Fix ausrollen
3. Basis-Smoke-Test durchführen

### 15.2 Mail fehlerhaft

**Symptome:** Keine Einladungs-/Testmails, SMTP-Fehler

**Vorgehen:**

1. Key-Vault-Secret prüfen
2. SMTP-Parameter prüfen
3. Mail-Smoke-Test wiederholen
4. Bei ACS: Domain-, Communication-Service-, Linking-, SMTP-Username- und RBAC-Status prüfen
5. Bei Direct Send: MX / Root-Domain / Empfängerszenario prüfen

### 15.3 PostgreSQL beschädigt / falscher Datenstand

**Symptome:** Daten fehlen oder sind inkonsistent, App-Fehler wegen DB

**Vorgehen:**

1. Schreibzugriffe stoppen
2. PITR-Zeitpunkt bestimmen
3. Neuen PostgreSQL-Server per Restore erzeugen
4. `DATABASE_URL` umstellen (Key-Vault-Secret `vw-database-url` aktualisieren)
5. Neue Revision / Redeploy
6. Smoke-Test

### 15.4 Dateiebene `/data` beschädigt

**Symptome:** Attachments fehlen, Dateifehler

**Vorgehen:**

1. Schreibzugriffe stoppen
2. Azure-Files-Recovery-Point auswählen
3. Bevorzugt in alternativen Speicherort wiederherstellen
4. Inhalt testen
5. Gezielt umschalten oder Original ersetzen

### 15.5 Vollständiger Service-Recovery

**Symptome:** DB + `/data` müssen zusammen wiederhergestellt werden

**Vorgehen:**

1. App schreibseitig anhalten
2. Wiederherstellungszeitpunkt festlegen
3. PostgreSQL wiederherstellen
4. Azure Files wiederherstellen
5. `DATABASE_URL` und ggf. Share-Bindung anpassen
6. Neue Revision starten
7. Vollständigen Smoke-Test fahren

---

## 16. PostgreSQL-Restore

### 16.1 Zielbild

Der Restore erfolgt typischerweise in **einen neuen Server**. Danach muss Vaultwarden auf diesen neuen DB-Endpunkt zeigen.

### 16.2 Schritte

1. Restore-Zeitpunkt bestimmen
2. PITR auf neuen Server ausführen
3. Connection-String für Vaultwarden aktualisieren
4. Key-Vault-Secret `vw-database-url` aktualisieren
5. App neu ausrollen
6. Login + Datenprüfung

### 16.3 Nachkontrolle

- [ ] Login funktioniert
- [ ] Alte Einträge vorhanden
- [ ] Neue Einträge speicherbar
- [ ] Mailversand weiterhin intakt

---

## 17. Azure-Files-Restore

### 17.1 Empfehlung

Für Tests immer zuerst einen **Restore in alternativen Speicherort** durchführen.

### 17.2 Schritte

1. Recovery-Point auswählen
2. Restore in alternativen Speicherort
3. Inhalt prüfen
4. Entscheiden:
   - Original überschreiben
   - Oder manuellen Sonderpfad für Restore-Umschaltung verwenden

> **Hinweis:** Das Core-Template enthält aktuell keinen Parameter, um die Container App direkt auf ein alternatives Restore-Share umzuschalten. Dieser Pfad ist derzeit bewusst ein manueller Betriebsfall außerhalb des Standard-Deploys.

### 17.3 Nachkontrolle

- [ ] Attachments vorhanden
- [ ] Dateien lesbar
- [ ] Nach Neustart weiterhin sichtbar

---

## 18. Vollständiger Recovery-Drill

Empfohlen mindestens einmal nach dem initialen Go-Live.

### 18.1 Ablauf

1. Testfenster planen
2. PostgreSQL in neuen Server wiederherstellen
3. Azure Files in alternativen Speicherort wiederherstellen
4. Manuellen Restore-Testpfad auf wiederhergestellte Ressourcen aufbauen
5. Login testen
6. Attachment testen
7. Mail testen
8. Ergebnis dokumentieren

### 18.2 Ziel

Nicht nur „Backup existiert" nachweisen, sondern:

- [ ] Restore ist praktisch durchführbar
- [ ] Die Kombination aus DB + Files funktioniert
- [ ] Das Team kennt den Ablauf

---

## 19. Typische Fehlerbilder

| Fehlerbild | Auswirkung | Lösung |
|---|---|---|
| `domainUrl` zeigt auf Ziel-Domain, aber ACA ist dort noch nicht gebunden | Links in Mails führen auf eine noch nicht aktive URL | Go-Live erst nach finaler Domain-/TLS-Bindung; alternativ zuerst mit funktionierender Zwischen-URL arbeiten |
| ACS Foundation deployt, aber Domain noch nicht verknüpft | ACS SMTP meldet, dass die Domain nicht verknüpft ist | DNS-Verifikation abschließen → Domain mit Communication Service verknüpfen → erst dann SMTP-Username aktivieren |
| SMTP geändert, aber nicht getestet | Produktiver Mailpfad kaputt | Jede Änderung an SMTP sofort mit Testmail validieren |
| Nur DB-Restore, aber `/data` nicht passend | Attachments oder Dateiinhalte passen nicht zum Datenstand | Restore immer als Gesamtbild betrachten (DB + Files) |
| Admin-UI-Werte überlagern Template-Parameter | Unerwartetes Verhalten nach Redeploy | `/data/config.json` prüfen; Admin-Panel nach Bootstrap deaktivieren |

---

## 20. Instanz-Dokumentation (pro Kunde / Umgebung)

Für jede produktive Instanz festhalten:

| Information | Wert |
|---|---|
| Resource Group | |
| Container App Name | |
| Finale URL | |
| Storage Account + File Share | |
| PostgreSQL Servername | |
| Key Vault Name | |
| Recovery Services Vault Name | |
| Gewählter SMTP-Modus | |
| ACS Foundation ja/nein | |
| ACS Email Service Name | |
| ACS Communication Service Name | |
| Aktuelles Vaultwarden-Image-Tag | |
| Letzter erfolgreicher Smoke-Test | |
| Letzter erfolgreicher Recovery-Drill | |

---

## 21. Kurzreferenz für den Notfall

### App nicht erreichbar, Daten intakt

→ Redeploy / Revision fixen → Basis-Smoke-Test

### Mail nicht zustellbar

→ SMTP-Secret + SMTP-Einstellungen prüfen → Testmail senden → bei ACS zusätzlich Domain-Linking / SMTP-Username / RBAC prüfen

### Datenbank beschädigt

→ PostgreSQL PITR → `DATABASE_URL` umstellen → neu deployen → Smoke-Test

### `/data` beschädigt

→ Azure Files Restore → Attachments testen → Restore-Umschaltung aktuell als manueller Sonderpfad

### Alles beschädigt

→ DB + Files wiederherstellen → App auf Restore-Zustand umschalten → vollständiger Smoke-Test

---

## 22. Wann dieses Setup nicht geeignet ist

| Anforderung | Warum nicht passend | Alternative |
|---|---|---|
| VNet-Isolation ist Pflicht | Baseline nutzt Consumption-Plan-ACA ohne VNet | Härtungsstufe 2 oder eigenes Template |
| WAF / DDoS-Schutz ist compliancepflichtig | Kein Application Gateway oder Front Door im Default | Eigenes Template mit Azure Front Door + WAF |
| Hochverfügbarkeit / Multi-Region | Einzelnes Replikat in einer Region | Multi-Region-Architektur mit Traffic Manager |
| Feste Outbound-IP für SMTP-Drittanbieter | Consumption-Plan hat dynamische Outbound-IPs | Härtungsstufe 1 mit NAT Gateway |
| Mehr als ~500 Nutzer | Burstable B1ms und einzelnes Replikat sind für KMU dimensioniert | Größerer PostgreSQL-Tier und ACA Workload Profiles |
| Strenge Compliance (SOC 2, ISO 27001) mit Netzwerkisolation | Öffentlicher PostgreSQL-Zugriff genügt nicht | Enterprise-Architektur mit Private Endpoints |

> **Kurzregel:** Wenn „Application Gateway", „Private Endpoints" oder „Multi-Region" benötigt werden, ist dieses Template der falsche Startpunkt. Es ist bewusst für einfache, kostengünstige KMU-Deployments gebaut. Siehe [Härtungsstufen](../../Readme.md#härtungsstufen) in der Readme für Erweiterungsoptionen.

---

## 23. Parameter-Referenz

### Azure-/Deploy-Parameter

#### Core / Deploy

- `location`, `environment`, `bsseRef`, `appName`
- `vaultwardenImage`, `cpuCores`, `memorySize`
- `allowInsecureHttp`, `diagnosticsEnabled`, `deploymentScriptForceUpdateTag`

#### Azure Files / Backup

- `storageAccountSku`
- `azureFilesBackupEnabled`, `azureFilesBackupScheduleRunTime`, `azureFilesBackupTimeZone`
- `azureFilesBackupDailyRetentionDays`, `azureFilesBackupWeeklyDaysOfWeek`, `azureFilesBackupWeeklyRetentionWeeks`

#### PostgreSQL / Bootstrap

- `postgresSkuName`, `postgresStorageGB`, `postgresBackupRetentionDays`
- `allowAzureServicesToPostgres`
- `dbAdminUser`, `dbPassword`

> **Hinweis:** `dbAdminUser` und `dbPassword` werden für die PostgreSQL-Servererstellung und das initiale Bootstrap-Script benötigt. Diese Werte sind **keine** Vaultwarden-App-Credentials.

#### ACS Foundation

- `acsDeployFoundation`, `acsDataLocation`, `acsDomainName`

### Vaultwarden-Parameter / ENV-Zuordnung

#### Core / Admin

- `domainUrl` → `DOMAIN`
- `adminPanelEnabled` → steuert `ADMIN_TOKEN`

#### Organisation / Registrierung

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

---

## 24. Quellen

Die verlinkten Aussagen in diesem Playbook wurden zuletzt **am 2026-03-20 16:02 CET** gegengeprüft.

### Microsoft Learn / Microsoft 365

- Verifizierte E-Mail-Domain verbinden  
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/connect-email-communication-resource
- SMTP-Authentifizierung für E-Mail-Versand einrichten  
  https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email-smtp/smtp-authentication
- Benutzerdefinierte verifizierte E-Mail-Domains hinzufügen  
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/add-custom-verified-domains
- Fehlerbehebung bei Domain-Konfigurationsproblemen  
  https://learn.microsoft.com/en-gb/azure/communication-services/concepts/email/email-domain-configuration-troubleshooting
- DNS-Einträge hinzufügen (Microsoft-gehostetes DNS)  
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

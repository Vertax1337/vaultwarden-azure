# Phase 4 – PlatformBootstrap und Workload Identity Federation

Status: `[ ]`

## Ziel

Customer-Onboarding wird aus Vaultwarden entkoppelt und als zentrale, wiederverwendbare Plattformfunktion umgesetzt. Workload-Repositories konsumieren nur ein vorhandenes oder automatisch hergestelltes Deployment-Profil.

## Grundregel

**Nicht:** Identity pro Deployment.

**Nicht:** Identity pro Repository/Workload.

**Nicht:** eine globale Identity für alle Kunden.

**Sondern:** eine wiederverwendbare Deployment Identity pro sinnvoller Trust-/Privilege-Boundary, standardmäßig Kunde + Environment.

Beispiel:
- `id-bsse-iac-1309-prod`
- `sc-azure-1309-prod`

## WC-04.1 – Zentrale PlatformBootstrap-Schnittstelle definieren
Status: `[ ]`

### Kernfunktion
Konzeptionell:

`Ensure-CustomerDeploymentProfile -CustomerId <id> -Environment <env>`

### Rückgabe mindestens
- Customer ID
- Tenant ID
- Subscription ID
- Environment
- Deployment Profile ID/Name
- Service Connection Referenz
- Scope/Privilege Boundary
- Validierungsstatus

### Akzeptanzkriterien
- Funktion enthält keine Vaultwarden-spezifische Fachlogik.
- Kann später von AVD und weiterem IaC wiederverwendet werden.

## WC-04.2 – Customer Deployment Registry
Status: `[ ]`

### Ziel
Eine zentrale Zuordnung für Kunde/Environment, ohne Secrets.

Beispielinhalt:
- Customer ID
- Tenant ID
- Subscription ID
- Environment
- Connection Profile
- Service Connection Mapping
- Identity Resource ID
- Scope

### Regel
Workload-Konfigurationen sollen möglichst nur ein logisches Profil wie `1309-prod` referenzieren und keine beliebige Service Connection frei aus Git auswählen können.

## WC-04.3 – Erst-Onboarding implementieren
Status: `[ ]`

### Verhalten
Wenn noch kein Deployment-Profil existiert:
1. interaktive Microsoft-Anmeldung am Kundentenant, sofern noch kein delegierter Bootstrapzugang besteht,
2. Tenant/Subscription prüfen,
3. Deployment Identity erstellen,
4. RBAC vergeben,
5. Federated Identity Credential konfigurieren,
6. Azure DevOps Service Connection erstellen/konfigurieren,
7. nur benötigte Pipelines autorisieren,
8. Registry aktualisieren,
9. WIF End-to-End testen,
10. ursprünglichen Workload-Vorgang fortsetzen.

### Wichtig
Der Techniker soll Azure DevOps dafür nicht manuell öffnen müssen.

## WC-04.4 – Reconcile-/Repair-Verhalten
Status: `[ ]`

`Ensure-CustomerDeploymentProfile` muss bei jedem Aufruf prüfen:
- Identity vorhanden und korrekt?
- RBAC vorhanden und korrekt?
- WIF Credential vorhanden und korrekt?
- Service Connection vorhanden und funktionsfähig?
- Pipeline-Autorisierung vorhanden?
- Registry konsistent?

Zustände:
- korrekt → No-op
- fehlt → erstellen
- verwalteter Zustand falsch → kontrolliert korrigieren
- nicht sicher automatisch reparierbar → klar blockieren und Ursache dokumentieren

## WC-04.5 – Privilege Boundaries
Status: `[ ]`

### Default
Kunde + Environment.

### Zusätzliche Trennung nur wenn nötig
Beispiele:
- besonders privilegiertes Netzwerk-IaC
- separate Prod/Test Subscriptions
- stark unterschiedliche RBAC-Anforderungen

### Prinzip
Eine Identity pro Sicherheitsgrenze, nicht pro Repo.

## WC-04.6 – Bootstrap-Rechte von Runtime-Rechten trennen
Status: `[ ]`

### Ziel
Der einmalige/interaktive Bootstrap darf privilegierter sein als die dauerhafte Pipeline Identity.

### Akzeptanzkriterien
- Normale Deployment Identity erhält nur die Rechte, die ihre IaC-Workloads tatsächlich benötigen.
- Hohe Bootstrap-Rechte bleiben nicht unnötig als dauerhafte technische Identität bestehen.
- Role Assignments aus Bicep werden berücksichtigt: Contributor allein reicht dafür nicht; benötigte RBAC-Administrationsrechte müssen minimal scoped werden.

## WC-04.7 – Keine PAT-basierte Standardlösung
Status: `[ ]`

### Regeln
- Kein langfristiger PAT im Technikerprofil oder Repo.
- Azure DevOps-Automatisierung bevorzugt Entra-/WIF-fähige Authentisierung.
- Kunden- und BSSE-Authentifizierungskontext sauber trennen, damit ein Tenantwechsel nicht versehentlich den DevOps-Kontext zerstört.

## Phase-4-Gate
Status: `[ ]`

Nur schließen, wenn ein bisher nicht onboardeter Testkunde aus einem Workload-Flow heraus automatisch bis zu einem funktionierenden WIF-Deployment-Profil eingerichtet wurde, ohne dass der Techniker Azure DevOps manuell konfigurieren musste, und ein zweiter Lauf nachweislich idempotent ohne Neuanlage der Identity funktioniert.

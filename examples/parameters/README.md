# Beispiel-Parameterdateien

Diese Dateien sind absichtlich **M365-lastig** und decken die typischen Zielpfade des Repos ab.

## Enthaltene Vorlagen

- `main.parameters.m365-smtp-auth.example.json`
  - Standardpfad für Microsoft 365 SMTP Submission (`smtp.office365.com:587`, `starttls`)
- `main.parameters.m365-smtp-auth-sso.example.json`
  - wie oben, zusätzlich mit Entra-ID-/OIDC-Parametern für Vaultwarden-SSO
- `main.parameters.m365-smtp-auth-sso-push.example.json`
  - wie oben, zusätzlich mit Bitwarden-Push-Parametern (`pushInstallationId`, `pushInstallationKey`)
- `main.parameters.m365-direct-send.example.json`
  - Direct Send ohne SMTP-Auth; `smtpHost` ist hier bewusst **explizit** gesetzt, damit das Deployment nicht vom MX-Lookup im Script abhängt
- `main.parameters.acs-foundation-m365-dns-hosted.example.json`
  - ACS-Foundation für eine kundeneigene Domäne, deren DNS zwar in Microsoft 365 gehostet wird, die in ACS aber trotzdem über den **öffentlich dokumentierten** `CustomerManaged`-Pfad vorbereitet wird

## Vor Einsatz ersetzen

- `vault.example.de`
- `example.de`
- `vaultwarden@example.de`
- `example-de.mail.protection.outlook.com`
- alle Werte `REPLACE_WITH_REAL_SECRET`
- Tenant-/App-IDs in den SSO-Vorlagen

## Hinweis

Die Dateien sind **Beispiele** und enthalten absichtlich nur die Parameter, die für den jeweiligen Pfad nötig bzw. sinnvoll sind. Repo-Defaults aus `main.json` bleiben weiterhin aktiv.

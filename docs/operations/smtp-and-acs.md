# SMTP und ACS – Vaultwarden auf Azure Container Apps

Die vollständige Dokumentation zu SMTP Auth, Direct Send und ACS SMTP (Foundation, DNS-Verifikation, Domain-Linking, SMTP-Username) befindet sich im **Operations Playbook**:

→ **[Operations Playbook – Mail-Konfiguration und -Betrieb](../HowToInstall/Operation-Playbook.md#7-mail-konfiguration-und--betrieb)**

---

## Relevante Abschnitte im Playbook

| Thema | Abschnitt |
|---|---|
| SMTP Auth (Produktiv-Default) | [§7.1](../HowToInstall/Operation-Playbook.md#71-smtp-auth-produktiv-default) |
| Direct Send | [§7.2](../HowToInstall/Operation-Playbook.md#72-direct-send) |
| ACS Foundation + ACS SMTP | [§7.3](../HowToInstall/Operation-Playbook.md#73-acs-foundation--acs-smtp) |
| DNS-Records setzen | [§7.3.2](../HowToInstall/Operation-Playbook.md#732-dns-records-der-acs-domain-setzen) |
| Domain-Verifikation | [§7.3.3](../HowToInstall/Operation-Playbook.md#733-domain-verifikation-in-acs-abschließen) |
| Domain-Linking | [§7.3.4](../HowToInstall/Operation-Playbook.md#734-domain-mit-dem-communication-service-verknüpfen) |
| SMTP-Username anlegen | [§7.3.7](../HowToInstall/Operation-Playbook.md#737-smtp-username-im-communication-service-anlegen) |
| Häufige ACS-Fehlerbilder | [§7.3.10](../HowToInstall/Operation-Playbook.md#7310-häufige-acs-fehlerbilder) |

---

## Kurzübersicht der SMTP-Modi

| Modus | Wann nutzen | Schlüsselparameter |
|---|---|---|
| **SMTP Auth** (Default) | Produktiv: M365, eigener Relay, ACS nach Finalisierung | `smtpUseAuth=true`, `smtpHost`, `smtpUsername`, `smtpPassword` |
| **Direct Send** | Nur interne Szenarien in kontrollierten M365-Umgebungen | `smtpUseAuth=false`, `mailRootDomain` |
| **ACS SMTP** | Kundeneigene Domain mit Azure Communication Services | `acsDeployFoundation=true` + manuelle ACS-Finalisierung + finaler Redeploy mit `smtpHost=smtp.azurecomm.net` |

Details zu jedem Modus stehen im Playbook.

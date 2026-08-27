# vault-thermosun-de

- Kunden-Nr.: 13363
- Vaultwarden-Domäne: vault.thermosun.de
- Resource Group: rg-thermosun-vault01-prod-gwc
- Location: germanywestcentral
- URL: https://vault.thermosun.de
- Edge-Modus: basic
- WAF: True
- Rate Limit: True
- Origin Lockdown: False

> `deployment.config.json` ist die persistente Kundenkonfiguration.
> `azure.parameters.json` wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per `.gitignore` ausgeschlossen.
> Erweiterte ARM-Parameter stehen unter `azure.advancedArmParameters` in der Kundenkonfiguration.
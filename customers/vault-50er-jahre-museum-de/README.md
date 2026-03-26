# vault-50er-jahre-museum-de

- Kunden-Nr.: 1309
- Vaultwarden-Domäne: vault.50er-jahre-museum.de
- Resource Group: rg-museum-vault-prod-gwc
- Location: germanywestcentral
- URL: https://vault.50er-jahre-museum.de
- Edge-Modus: basic
- WAF: True
- Rate Limit: True
- Origin Lockdown: False

> `deployment.config.json` ist die persistente Kundenkonfiguration.
> `azure.parameters.json` wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per `.gitignore` ausgeschlossen.
> Erweiterte ARM-Parameter stehen unter `azure.advancedArmParameters` in der Kundenkonfiguration.
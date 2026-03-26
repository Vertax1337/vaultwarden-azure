# vault-petri-network-de

- Kunden-Nr.: 1309
- Vaultwarden-Domäne: vault.petri-network.de
- Resource Group: rg-petri-network-vault-prod-gwc
- Location: germanywestcentral
- URL: https://vault.petri-network.de
- Edge-Modus: cloudflare-managed
- WAF: False
- Rate Limit: False
- Origin Lockdown: True

> `deployment.config.json` ist die persistente Kundenkonfiguration.
> `azure.parameters.json` wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per `.gitignore` ausgeschlossen.
> Erweiterte ARM-Parameter stehen unter `azure.advancedArmParameters` in der Kundenkonfiguration.
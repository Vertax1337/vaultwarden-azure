# vault-thermosun-de

- Kunden-Nr.: $(System.Collections.Hashtable.customerNumber)
- Vaultwarden-Domäne: $(System.Collections.Hashtable.domain.hostname)
- Resource Group: $(System.Collections.Hashtable.azure.resourceGroupName)
- Location: $(System.Collections.Hashtable.azure.location)
- URL: $(System.Collections.Hashtable.domain.url)
- Edge-Modus: $(System.Collections.Hashtable.edge.mode)
- WAF: $(System.Collections.Hashtable.edge.enableWaf)
- Rate Limit: $(System.Collections.Hashtable.edge.enableRateLimit)
- Origin Lockdown: $(System.Collections.Hashtable.edge.lockOriginToCloudflare)

> deployment.config.json ist die persistente Kundenkonfiguration.
> zure.parameters.json wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per .gitignore ausgeschlossen.
> Erweiterte ARM-Parameter stehen unter zure.advancedArmParameters in der Kundenkonfiguration.
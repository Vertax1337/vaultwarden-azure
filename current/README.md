# current

Diese Dateien sind die **aktive Deploy-to-Azure-Kopie** für $(System.Collections.Hashtable.domain.hostname).

- Quelle: customers/vault-thermosun-de/...
- Aktive Vaultwarden-Domäne: $(System.Collections.Hashtable.domain.hostname)
- Resource Group Default: $(System.Collections.Hashtable.azure.resourceGroupName)

Verwendung:
- Der Deploy-to-Azure-Button zeigt auf current/main.deploytoazure.json.
- current/azure.parameters.json ist die dazugehörige aktive Parameterkopie.

Achtung:
- current/azure.parameters.json kann sensible Klartextwerte enthalten, wenn sie bei der Generierung übergeben wurden.
- Vor einem Push ins Git bitte prüfen, ob Secrets enthalten sind.
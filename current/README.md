# current

Diese Dateien sind die **aktive Deploy-to-Azure-Kopie** für vault.mytest.de.

- Quelle: `customers/vault-mytest-de/...`
- Aktive Vaultwarden-Domäne: vault.mytest.de
- Resource Group Default: rg-mytest-vault-prod-gwc

Verwendung:
- Der Deploy-to-Azure-Button zeigt auf `current/main.deploytoazure.json`.
- `current/azure.parameters.json` ist die dazugehörige aktive Parameterkopie.

Achtung:
- `current/azure.parameters.json` kann sensible Klartextwerte enthalten, wenn sie bei der Generierung übergeben wurden.
- Vor einem Push ins Git bitte prüfen, ob Secrets enthalten sind.
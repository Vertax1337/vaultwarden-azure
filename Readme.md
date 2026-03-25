# Vaultwarden on Azure Container Apps (ACA)

Production-oriented ARM template for **Vaultwarden on Azure Container Apps**, designed for SMEs/KMUs.

## Architecture

This template deploys a complete Vaultwarden environment as a single ARM deployment:

| Component | Purpose |
|---|---|
| **Azure Container Apps** (consumption plan) | Vaultwarden runtime (single replica, pinned image) |
| **Azure Files** | Persistent `/data` volume (attachments, icons, config) |
| **PostgreSQL Flexible Server** (Burstable B1ms) | Relational data |
| **Azure Key Vault** (RBAC) | Secrets (`ADMIN_TOKEN`, `DATABASE_URL`, SMTP/SSO/Push credentials) |
| **User Assigned Managed Identities** | App reads secrets; bootstrap script writes secrets |
| **Deployment Script** (AzureCLI) | Bootstrap: DB app-user provisioning, secret seeding, MX lookup |
| **Recovery Services Vault** | Azure Files backup (enabled by default) |
| **Log Analytics + Diagnostic Settings** | Observability for Key Vault and PostgreSQL |
| **ACS Foundation** (optional) | Email Service, Email Domain, Communication Service |

### Design Philosophy

This repository targets **SMEs/KMUs** that need a secure, production-ready password manager without enterprise-scale cost or complexity. The architecture intentionally:

- Uses **ACA direct ingress** (no Application Gateway or Front Door by default)
- Uses **public PostgreSQL with firewall rules** (no VNet/Private Endpoint by default)
- Runs on **consumption-tier ACA** (no Workload Profiles by default)
- Keeps the entire deployment in **a single ARM template** for simplicity

These are deliberate tradeoffs documented in the [Hardening Tiers](#hardening-tiers-optional) section below.

### ACA Networking Tradeoffs

Azure Container Apps on the consumption plan does **not** provide a fixed outbound IP. This has specific consequences:

| Constraint | Impact | Mitigation |
|---|---|---|
| Dynamic outbound IPs | Cannot create a specific PostgreSQL firewall rule for ACA | `allowAzureServicesToPostgres=true` (0.0.0.0 rule) allows any Azure service to connect |
| No static egress | Third-party SMTP servers expecting IP allowlisting may reject connections | Use Microsoft 365 SMTP or ACS SMTP which do not require sender IP allowlisting |
| No built-in WAF | No request filtering at the edge | ACA HTTPS ingress provides TLS termination; Vaultwarden itself has rate limiting; for WAF, see hardening tiers |

The `allowAzureServicesToPostgres=true` default is required for consumption-plan ACA. It opens PostgreSQL to any Azure service (not the public internet), which is an acceptable tradeoff for SME use. To restrict this further, see the [Hardening Tiers](#hardening-tiers-optional) section.

## Deploy

There is intentionally **only one** deploy path. Everything that can be cleanly automated is in `main.json`.

[![Deploy to Azure (ARM JSON)](
https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true
)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmain%2Fmain.json
)

> **Note:** If you fork this repo or change the owner/branch, you must update the raw URL in the button above.

For local deployment without GitHub hosting, use the Azure Portal path **Deploy a custom template** → **Build your own template in the editor** and paste `main.json`.

**Intentionally manual post-deploy steps:**
- ACA Custom Domain + TLS certificate binding
- ACS DNS verification of the email domain
- ACS Domain linking to the Communication Service
- ACS SMTP username + final SMTP activation

These steps involve DNS propagation and external verification that cannot be reliably automated in a single deployment. They are documented in the [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md).

---

## Documentation

- [How to Use Vaultwarden (BSSE)](./docs/HowToUse/HowToUse.pdf)
- [Operations Playbook / Runbook](./docs/HowToInstall/Operation-Playbook.md)

A PowerShell helper script is available at `scripts/deploy.ps1` for local CLI-based deployments with interactive parameter prompts. The primary supported deployment path remains the ARM template via Azure Portal or `az deployment group create`.

---

## Example Parameter Files

Under `./examples/parameters/` are deployment-ready templates for common scenarios:

- **`main.parameters.m365-smtp-auth.example.json`**
  M365 SMTP Auth standard path (`smtp.office365.com`, Port 587, `starttls`).

- **`main.parameters.m365-smtp-auth-sso.example.json`**
  M365 SMTP Auth + Entra ID / OIDC parameters for SSO.

- **`main.parameters.m365-direct-send.example.json`**
  Direct Send without SMTP Auth. Only for specific internal scenarios.

- **`main.parameters.m365-smtp-auth-sso-push.example.json`**
  M365 SMTP Auth + Entra ID SSO + Bitwarden Push parameters.

- **`main.parameters.acs-foundation-m365-dns-hosted.example.json`**
  ACS Foundation deploy for a custom domain with M365-hosted DNS.

All files contain **placeholder values** and must be customized before production use.

---

## Repository Structure

- **`main.json`** → Primary ARM deployment template (all resources)
- **`main.bicep`** → ⚠️ Older Bicep reference – **not maintained**, does not match `main.json`; do not use for deployment
- **`scripts/deploy.ps1`** → Optional PowerShell wrapper for CLI-based deployment
- **`docs/HowToInstall/Operation-Playbook.md`** → Go-Live, operations, ACS, backup/recovery, smoke tests
- **`examples/parameters/`** → Scenario-specific parameter file templates

---

## What `main.json` Deploys

### Always Included
- Azure Container Apps Environment + Log Analytics
- Azure Container App for Vaultwarden (with startup, liveness, and readiness probes)
- Azure Storage Account + Azure Files Share (`/data`)
- Azure Database for PostgreSQL Flexible Server + database
- User Assigned Managed Identities (app reader + script writer)
- Azure Key Vault (RBAC)
- Deployment Script for:
  - `ADMIN_TOKEN` generation
  - DB app-user + `DATABASE_URL` provisioning
  - SMTP secret (when SMTP Auth enabled)
  - SSO secret (optional)
  - Push secrets (optional; Installation ID + Key)
  - MX lookup for Direct Send (when `smtpUseAuth=false`)
  - Controllable re-run via `deploymentScriptForceUpdateTag`
- Azure Files Backup (enabled by default via Recovery Services Vault)
- Diagnostic Settings for Key Vault and PostgreSQL (enabled by default)

The bootstrap script explicitly depends on the optional PostgreSQL firewall rule `AllowAzure` when `allowAzureServicesToPostgres=true`. Internal wait/retry windows are set to 10 minutes to allow RBAC and firewall propagation.

### Optional: ACS Foundation
When `acsDeployFoundation = true`, `main.json` additionally deploys:
- **Azure Communication Services Email Service**
- **ACS Email Domain Resource**
- **ACS Communication Service**

This provides the foundation infrastructure. **Not** automated are DNS verification, domain linking, and SMTP username creation.

### Intentionally **Not** Automated
- ACA Custom Domain / certificate binding
- ACS Domain verification
- ACS `linkedDomains`
- ACS `smtpUsernames`
- ACS RBAC for the SMTP Entra app

These steps remain **manual post-deploy** tasks. This keeps the core deploy at one button click, while domain/mail activation follows the documented procedures in the Operations Playbook.

---

## SMTP Modes

### A) SMTP Auth (**Production Default**)
Recommended standard path.

- `smtpUseAuth = true` (default)
- Empty `smtpHost` → `smtp.office365.com`
- `smtpPort = 587`
- `smtpSecurity = starttls`
- `smtpUsername` + `smtpPassword` required
- Optional `smtpAuthMechanism` (e.g. `Login`, `Plain`, `Xoauth2`)

#### Suitable for
- Microsoft 365 SMTP Submission
- Custom SMTP relay / mail gateway
- ACS SMTP **after** ACS finalization

---

### B) Direct Send
Only for clearly bounded internal scenarios.

- `smtpUseAuth = false`
- Empty `smtpHost` → MX lookup via `mailRootDomain`
- Template sets `SMTP_PORT=25` and `SMTP_SECURITY=starttls` for this mode
- **`SMTP_USERNAME` must not be set**
- **`SMTP_PASSWORD` must not be set**
- **`SMTP_AUTH_MECHANISM` must not be set**

#### Vaultwarden-Specific Behavior
Vaultwarden treats SMTP auth based on whether settings are actually present, not just their values. Per the official `.env.template`: when `SMTP_USERNAME` is set, `SMTP_PASSWORD` is mandatory. For Direct Send, the template correctly omits all auth env vars when `smtpUseAuth=false`.

#### Admin UI / `config.json` Override Warning
Vaultwarden persists Admin UI changes to `/data/config.json`. These can override ENV values for `SMTP_HOST`, `SMTP_SECURITY`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_USERNAME`, `SMTP_PASSWORD`, etc. **When switching from SMTP Auth to Direct Send**, you must also clear any persisted SMTP auth values from the Vaultwarden admin panel.

#### Suitable for
- Internal mail delivery in controlled Microsoft 365 scenarios

#### Operational Note
When `smtpHost` is empty, `mailRootDomain` must be set for the bootstrap script to resolve the MX record. The script does not install additional OS packages. If the runtime has neither `dig` nor `nslookup`, set `smtpHost` explicitly for Direct Send.

#### Not Recommended as Default
For production use where email is critical, SMTP Auth or ACS SMTP is more robust and predictable.

---

### C) ACS SMTP
ACS can now be **partially** prepared via `main.json`.

#### Step 1 – Foundation with `main.json`
Set during deployment:
- `acsDeployFoundation = true`
- `acsDataLocation` matching your desired geography
- `acsDomainName` optionally explicit, otherwise `mailRootDomain` is used
- The repo uses only the publicly documented ACS custom domain path `CustomerManaged`

This creates:
- Email Service
- Email Domain Resource
- Communication Service

#### Step 2 – Manual ACS Finalization
The complete manual steps are in the [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md) under **"ACS Foundation + ACS SMTP"**. Summary:
1. Set DNS records for the ACS domain in the authoritative DNS system
2. Wait until **Domain Status**, **SPF**, **DKIM**, and **DKIM2** are fully verified
3. Link the verified domain to the Communication Service
4. Assign the Entra application the **Communication and Email Service Owner** role
5. Create an SMTP username and wait for **Ready to use** status
6. Redeploy `main.json` with final values:
   - `smtpUseAuth = true`
   - `smtpHost = smtp.azurecomm.net`
   - `smtpPort = 587`
   - `smtpSecurity = starttls`
   - `smtpUsername = <ACS SMTP Username>`
   - `smtpPassword = <Client Secret of the Entra App>`
   - Optional `smtpAuthMechanism = Xoauth2`


---

## Vaultwarden-Specific Caveats

1. **Mail service activation**
   The Vaultwarden mail service activates when `SMTP_FROM` and either `SMTP_HOST` or `USE_SENDMAIL` are set. `DOMAIN` must be correct so that email links point to the right host. For production, set `smtpFrom` explicitly rather than relying on the implicit default.

2. **Direct Send: auth variables must be omitted**
   For Direct Send, `SMTP_USERNAME`, `SMTP_PASSWORD`, and `SMTP_AUTH_MECHANISM` must not be present in the app configuration. The template correctly omits these when `smtpUseAuth=false`.

3. **Admin UI can override template values**
   Vaultwarden persists Admin UI changes to `/data/config.json`. If SMTP values or `admin_token` are persisted there, they will override ENV values. When switching modes or disabling the admin panel, always verify the Vaultwarden admin diagnostics view.

   The intended workflow is: initial deployment with `adminPanelEnabled=true` for bootstrap/testing/admin diagnostics; then redeploy with `adminPanelEnabled=false` to stop passing `ADMIN_TOKEN` to the app. **Important:** If settings were saved in the admin UI, a persisted `admin_token` in `/data/config.json` must also be removed, or the admin panel will remain active despite the removed ENV var.

5. **Optional SMTP fine-tuning parameters**
   `SMTP_AUTH_MECHANISM`, `HELO_NAME`, `SMTP_EMBED_IMAGES`, `SMTP_DEBUG`, `SMTP_ACCEPT_INVALID_CERTS`, and `SMTP_ACCEPT_INVALID_HOSTNAMES` are real Vaultwarden parameters. The template currently passes through only `SMTP_AUTH_MECHANISM` and `HELO_NAME`. The remaining options are intentionally not automated and belong to troubleshooting/special cases.

6. **`/data/config.json` persistence risk**
   Any setting changed in the Vaultwarden admin UI is persisted to `/data/config.json` on the Azure Files share. These values take precedence over ENV vars on subsequent container starts. This is a known Vaultwarden behavior. The safe approach is:
   - Use the admin panel only during bootstrap
   - Do not save SMTP settings from the admin UI (they come from ENV)
   - After bootstrap, disable the admin panel and verify no stale values persist

7. **SSO / OIDC caveats**
   - `SSO_ONLY=true` disables master-password login entirely. Test SSO thoroughly before enabling this.
   - The OIDC callback URL is derived from `DOMAIN`: `https://<domain>/identity/connect/oidc-signin`
   - If using Entra ID, ensure the redirect URI is registered in the App Registration.

8. **Push notifications external dependency**
   - Push notifications require a valid Bitwarden Installation ID and Key from https://bitwarden.com/host/
   - Both values are treated as secrets and stored in Key Vault
   - Without push, mobile clients still work but lack real-time sync signals

---

## Key Parameters in `main.json`

Parameters are organized in two dimensions:
- **Azure/Deploy parameters** = control resources, sizing, bootstrap, and Azure services
- **Vaultwarden parameters** = map to Vaultwarden ENV vars or control Vaultwarden-adjacent behavior

### Azure/Deploy Parameters

#### Core / Deploy
- `location`
- `environment`
- `bsseRef`
- `appName` (keep short; storage account names are derived from it and limited to 24 chars)
- `deploymentScriptForceUpdateTag` (only change intentionally when the bootstrap script should re-run)
- `diagnosticsEnabled`
- `allowInsecureHttp`
- `vaultwardenImage` (pinned by default; update intentionally during maintenance windows)
- `cpuCores`
- `memorySize`

#### Azure Files / Backup
- `storageAccountSku`
- `azureFilesBackupEnabled`
- `azureFilesBackupScheduleRunTime`
- `azureFilesBackupTimeZone`
- `azureFilesBackupDailyRetentionDays`
- `azureFilesBackupWeeklyDaysOfWeek`
- `azureFilesBackupWeeklyRetentionWeeks`

#### PostgreSQL / Bootstrap-only
- `postgresSkuName` (tier is automatically derived: `Standard_B*` = Burstable, `Standard_D*` = GeneralPurpose, `Standard_E*` = MemoryOptimized)
- `postgresStorageGB`
- `postgresBackupRetentionDays`
- `allowAzureServicesToPostgres`
- `dbAdminUser`
- `dbPassword`

`dbAdminUser` and `dbPassword` remain in the template because they are needed for PostgreSQL server creation and the bootstrap script. They are **not** productive Vaultwarden app credentials; the app uses a separate least-privilege user via `DATABASE_URL` from Key Vault.

#### ACS Foundation
- `acsDeployFoundation`
- `acsDataLocation`
- `acsDomainName`

### Vaultwarden Parameters / ENV Mapping

#### Core / Instance Behavior
- `domainUrl` → `DOMAIN`
- `adminPanelEnabled` → controls whether `ADMIN_TOKEN` is passed to the app

#### Organization / Signup / Policies
- `invitationOrgName` → `INVITATION_ORG_NAME`
- `signupsDomainsWhitelist` → `SIGNUPS_DOMAINS_WHITELIST`
- `orgCreationUsers` → `ORG_CREATION_USERS`

**Important:** `SIGNUPS_DOMAINS_WHITELIST` has specific Vaultwarden behavior. When set, test the self-service signup process carefully; domain whitelist and invitation/org flows behave differently than with open registration.

#### Mail / SMTP
- `mailRootDomain`
- `smtpUseAuth`
- `smtpFrom` → `SMTP_FROM`
- `smtpFromName` → `SMTP_FROM_NAME`
- `heloName` → `HELO_NAME` (empty = host from `DOMAIN`)
- `smtpHost` → `SMTP_HOST`
- `smtpPort` → `SMTP_PORT`
- `smtpSecurity` → `SMTP_SECURITY`
- `smtpUsername` → `SMTP_USERNAME`
- `smtpPassword` → `SMTP_PASSWORD`
- `smtpAuthMechanism` → `SMTP_AUTH_MECHANISM`

#### SSO / OIDC
- `ssoEnabled` → `SSO_ENABLED`
- `ssoOnly` → `SSO_ONLY`
- `ssoAuthority` → `SSO_AUTHORITY`
- `ssoClientId` → `SSO_CLIENT_ID`
- `ssoClientSecret` → `SSO_CLIENT_SECRET`
- `ssoScopes` → `SSO_SCOPES`

#### Mobile Push
- `pushEnabled` → `PUSH_ENABLED`
- `pushInstallationId` → `PUSH_INSTALLATION_ID`
- `pushInstallationKey` → `PUSH_INSTALLATION_KEY`
- `pushUseEuServers` → sets `PUSH_RELAY_URI` / `PUSH_IDENTITY_URI` for `.com` vs `.eu`

Both `pushInstallationId` and `pushInstallationKey` are stored as secrets in Key Vault.

### Further Documentation
- Operations Playbook: [docs/HowToInstall/Operation-Playbook.md](./docs/HowToInstall/Operation-Playbook.md)
- Bitwarden Installation ID / Key: https://bitwarden.com/host/
- Bitwarden Hosting FAQ: https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay: https://bitwarden.com/help/configure-push-relay/
- Vaultwarden SSO (Wiki): https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect

## Outputs

When `acsDeployFoundation = true`, the deployment additionally outputs:
- `acsFoundationEnabled`
- `acsEmailServiceName`
- `acsCommunicationServiceName`
- `acsEmailDomain`
- `acsEmailDomainResourceId`
- `acsNextSteps`

These outputs serve as an operational bridge between core deploy and manual ACS finalization.

---

## Redeploy and Secret Behavior

### Redeploying the Same Template to the Same Resource Group
- ARM works in **incremental** mode by default
- Existing PostgreSQL / Azure Files / Vaultwarden data is preserved
- The bootstrap `deploymentScript` does **not** automatically re-run if nothing changed in its resource definition
- Use `deploymentScriptForceUpdateTag` for intentional re-runs

### When to Use `deploymentScriptForceUpdateTag`
Use this parameter intentionally, for example when:
- DB app-user / `DATABASE_URL` should be reconciled again
- SMTP/SSO/Push secrets should be re-written despite otherwise identical template values
- A no-op redeploy is not sufficient and the bootstrap script must run again

### Key Vault Secrets in ACA
The Container App uses versionless Key Vault secret URIs. New secret versions can be picked up without changing the secret URI in the template.

For **predictable immediate effect**, it is still advisable to:
- Perform a targeted redeploy with a content change
- Or restart / create a new revision after sensitive secret changes

### Disabling the Admin Panel After Bootstrap
Recommended operational workflow:
1. Initial deployment with `adminPanelEnabled = true` (default)
2. Complete bootstrap / tests / admin diagnostics
3. If settings were saved in the Vaultwarden admin UI: verify no persisted `admin_token` remains in `/data/config.json`
4. Redeploy `main.json` with `adminPanelEnabled = false`
5. Verify the admin panel is no longer accessible

For later maintenance, the admin panel can be temporarily re-enabled by setting `adminPanelEnabled = true` and then disabling it again after completing the work.

---

## Manual Steps Before Go-Live

These steps are **intentionally** not fully automated.

### 1) Custom Domain + TLS for ACA
If you do not want to stay on the default `*.azurecontainerapps.io` URL:

1. Add a custom domain to the Container App ingress
2. Set DNS records
3. Bind a certificate (Managed Certificate or your own)
4. Test under the final target URL

> `domainUrl` and the actual ACA binding must match at the end.

### 2) ACS Domain DNS / Verification / Linking
If using ACS Email:

1. Deploy with `acsDeployFoundation = true`
2. Set the displayed DNS records
3. Wait until the domain is **verified**
4. Link the verified domain to the Communication Service
5. Create SMTP username + RBAC for the Entra app
6. Redeploy `main.json` with the final ACS SMTP values

### 3) Smoke Tests
Before go-live, run the tests from the [Operations Playbook](./docs/HowToInstall/Operation-Playbook.md).

---

## Production / Go-Live Checklist

Before going live, verify all items:

### App / URL
- [ ] Container App is reachable
- [ ] `allowInsecureHttp = false`
- [ ] Final target URL responds with a valid TLS certificate
- [ ] `domainUrl` matches the actually bound URL

### Mail
- [ ] Test email from Vaultwarden successful
- [ ] Sender address correct
- [ ] SPF/DKIM/DMARC appropriate for chosen mail path
- [ ] No placeholder values remaining in SMTP parameters
- [ ] For ACS: domain is verified and linked to the Communication Service

### Security
- [ ] `ADMIN_TOKEN` retrieved only from Key Vault, not stored locally
- [ ] `adminPanelEnabled` set to `false` after successful bootstrap/testing
- [ ] No persisted `admin_token` in `/data/config.json`
- [ ] Unnecessary signups disabled (`SIGNUPS_ALLOWED=false` is the default)
- [ ] SSO/Push only active if tested
- [ ] `SHOW_PASSWORD_HINT=false` (default)
- [ ] `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=true` (default, prevents SSRF)

### Data
- [ ] Login successful
- [ ] New vault entry can be saved
- [ ] Attachment can be uploaded
- [ ] Attachment can be retrieved

### Backup / Recovery
- [ ] At least one restore drill planned or already performed
- [ ] Known how to restore PostgreSQL + Azure Files together
- [ ] Verified that PostgreSQL PITR retention (`postgresBackupRetentionDays`) is sufficient
- [ ] Verified that Azure Files backup is enabled and running

---

## Hardening Tiers (Optional)

This repository deploys a **baseline architecture** suitable for SME/KMU production use. For environments with stricter security requirements, consider the following graduated hardening tiers:

### Tier 0: Baseline (Default)
**What you get out of the box:**
- ACA direct ingress with HTTPS
- PostgreSQL public access with `AllowAzureServices` firewall rule
- Key Vault with RBAC and purge protection
- Azure Files backup via Recovery Services Vault
- Diagnostic settings for Key Vault and PostgreSQL
- Vaultwarden image pinned, signups disabled, password hints off

**Tradeoffs:**
- No fixed outbound IP → PostgreSQL firewall relies on `AllowAzureServices`
- No WAF → rate limiting is Vaultwarden-internal only
- No VNet isolation

**Cost: ~€30-50/month** (consumption ACA + B1ms PostgreSQL + Standard_LRS storage)

### Tier 1: Fixed Egress + PostgreSQL Restriction
**Add:**
- ACA Environment with VNet integration (Workload Profiles)
- NAT Gateway for fixed outbound IP
- Specific PostgreSQL firewall rule replacing `AllowAzureServices`

**Benefits:**
- PostgreSQL only accepts connections from your known IP
- Third-party SMTP servers can allowlist your IP
- Outbound traffic is traceable

**Cost impact: +€30-50/month** (NAT Gateway + Workload Profiles overhead)

### Tier 2: Enterprise Hardening
**Add:**
- Private Endpoint for PostgreSQL (no public access)
- Private Endpoint for Key Vault
- Private Endpoint for Storage Account
- Private DNS Zones for all endpoints
- Optional: Azure Front Door or Application Gateway with WAF

**Benefits:**
- No public data-plane exposure for backend services
- WAF-level protection at the edge
- Network microsegmentation

**Cost impact: +€100-200/month** (private endpoints + DNS zones + optional WAF)

> **Note:** Each tier adds operational complexity. Evaluate whether the additional security posture justifies the cost and management burden for your organization.

---

## Known Constraints and Open Risks

| Constraint | Impact | Mitigation |
|---|---|---|
| ACA consumption plan has no fixed outbound IP | PostgreSQL firewall uses `AllowAzureServices` (0.0.0.0 rule) | Upgrade to Tier 1 for fixed egress |
| Vaultwarden `config.json` can override ENV vars | Settings saved in admin UI persist across redeployments | Disable admin panel after bootstrap; document in runbook |
| Azure Files is not a transactional store | `/data` backup and PostgreSQL backup may not be perfectly synchronized | Document restore procedure; perform restore drills |
| `allowInsecureHttp` defaults to `false` but can be set to `true` | Exposes traffic in plaintext | Enforce `false` in production |
| Deployment script depends on Azure CLI container image version | Future AzureCLI image changes could affect script behavior | `azCliVersion` is pinned to `2.81.0` |
| PostgreSQL password is auto-generated if not provided | On redeploy, the `dbPassword` parameter gets a new `newGuid()` value, but PostgreSQL ignores it because the server already exists (incremental deploy) | This is safe for redeployment; the password is set only on initial creation |

---

## Changelog from Original Baseline

- Storage account name safely truncated to 24 characters
- PostgreSQL tier dynamically derived from SKU name prefix
- Container health probes use Vaultwarden `/alive` endpoint (startup + liveness + readiness)
- Deploy button URL updated for current repository
- Repository structure documentation corrected (PowerShell script acknowledged)
- `main.bicep` marked as unmaintained
- `enabledForTemplateDeployment` disabled on Key Vault
- Vaultwarden ENV vars cleanly modeled with conditional inclusion
- `SMTP_AUTH_MECHANISM` passed through to Vaultwarden
- Optional ENV values not set to empty strings
- Deployment script updates secrets on changes
- SMTP auth validated in deployment script
- `mailRootDomain` as explicit mail base domain (no heuristic derivation from `domainUrl`)
- PostgreSQL PITR retention parameterized
- ACS changed from "all at once" to **foundation automated, finalization manual**
- `deploymentScriptForceUpdateTag` for intentional bootstrap re-runs
- Deployment script uses `az postgres flexible-server execute` (no `psql`, `pip`, or `pg8000` dependency)

---

## References (ACS, M365, Bitwarden/Vaultwarden)

The linked statements in README and Playbook were last verified **on 2026-03-20 16:02 CET**.

### Microsoft Learn / Microsoft 365
- Connect a verified email domain to send email
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/connect-email-communication-resource
- Set up SMTP authentication for sending emails
  https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email-smtp/smtp-authentication
- Add custom verified email domains
  https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/add-custom-verified-domains
- Troubleshooting domain configuration issues
  https://learn.microsoft.com/en-gb/azure/communication-services/concepts/email/email-domain-configuration-troubleshooting
- Add DNS records if Microsoft hosts your DNS
  https://learn.microsoft.com/en-us/office365/admin/setup/add-domain

### Bitwarden / Vaultwarden
- Bitwarden: Request Hosting Installation ID & Key
  https://bitwarden.com/host/
- Bitwarden Hosting FAQs
  https://bitwarden.com/help/hosting-faqs/
- Bitwarden Push Relay
  https://bitwarden.com/help/configure-push-relay/
- Vaultwarden SSO via OpenID Connect (Wiki)
  https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect
- Vaultwarden Mobile Push (Wiki)
  https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification

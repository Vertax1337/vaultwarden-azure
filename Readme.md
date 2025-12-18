# Creates a Vaultwarden Container App with Azure File & PostgreSQL Storage

[![Deploy to Azure (ARM JSON)](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmaster%2Fmain.json
)

[![Deploy to Azure (Bicep)](https://aka.ms/deploytoazurebutton)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmaster%2Fmain.bicep
)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](
http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmaster%2Fmain.json
)

---

## Overview

This template deploys **Vaultwarden** as an **Azure Container App (Consumption)** with:

- Persistent **Azure File Share** storage (`/data`)
- **PostgreSQL Flexible Server** backend
- Built-in **SMTP support** (Microsoft 365 compatible)
- Designed for **KMU / small enterprise production usage**
- Cost-efficient (no App Service Plan, no Front Door / WAF required)

The deployment supports **backup & restore** scenarios and **safe container updates** without data loss.

---

## Deployment

### 1. Click **Deploy to Azure**
You can choose between:
- **ARM JSON** (portal-friendly, classic)
- **Bicep** (recommended for technical users & CI/CD)

### 2. Fill in the parameters

- **Resource Group**  
  All resources will be created inside this group.

- **Storage Account Type**  
  Default: `Standard_LRS`  
  For higher resilience you may choose `Standard_GRS`, `ZRS`, etc.

- **Admin API Key**
  - Generated automatically if not provided
  - Used to access the `/admin` interface
  - **Minimum length: 20 characters**

- **CPU / Memory sizing**  
  Recommended starting point:
  - `0.25 CPU`
  - `0.5 GiB RAM`

  Valid combinations:

  | CPU  | Memory |
  |-----:|-------:|
  | 0.25 | 0.5 Gi |
  | 0.5  | 1.0 Gi |
  | 0.75 | 1.5 Gi |
  | 1.0  | 2.0 Gi |
  | 1.25 | 2.5 Gi |
  | 1.5  | 3.0 Gi |
  | 1.75 | 3.5 Gi |
  | 2.0  | 4.0 Gi |

- **Database admin password**

  ⚠️ **IMPORTANT – Password restrictions**

  The PostgreSQL password is embedded into a connection URL (`DATABASE_URL`).  
  To avoid URL parsing issues, **use only the following characters**:

  ```
  a–z A–Z 0–9
  ```

  ❌ Avoid characters like:
  ```
  @ : / ? # % & +
  ```

---

### 3. Deploy

Click **Deploy**.

> ⚠️ **Known Azure timing issue**  
> In rare cases the Container App may fail on first deployment because the Azure File share is not yet linked.
>
> **Fix:** Click **Redeploy** and reuse the same parameters.  
> No data will be lost.

---

## Post-Deployment Steps (Required for Production)

1. **Configure Custom Domain**
   - Add the required CNAME / TXT records shown in the Azure Portal

2. **Enable Managed Certificate**
   - Azure issues the TLS certificate after DNS verification

3. **Disable HTTP**
   - Set parameter `allowInsecureHttp = false`
   - Enforces HTTPS-only access

---

## Updating Vaultwarden

By default the container image uses `:latest`, allowing easy updates.

1. Azure Portal → Resource Group → **vaultwarden**
2. **Revisions**
3. **Create revision**
4. Keep image set to `latest`
5. Create revision

✔ No downtime  
✔ Persistent data remains intact  
✔ Database migrations are handled automatically

> If required, you can pin a specific image version via the `vaultwardenImage` parameter.

---

## Get Admin Token

1. Azure Portal → Resource Group → **vaultwarden**
2. Container App → **Configuration**
3. Environment Variables
4. Copy the value of `ADMIN_TOKEN`

Admin UI:
```
https://<your-domain>/admin
```

---

## Notes

- SMTP is **mandatory** for:
  - Password reset
  - Signup verification
  - Security notifications
- Microsoft 365 SMTP (`smtp.office365.com`) is fully supported
- Secrets are stored as **Container App Secrets**
- Azure Container Apps (Consumption) keeps costs low while remaining production-ready

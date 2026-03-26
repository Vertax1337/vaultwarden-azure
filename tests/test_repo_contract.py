import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PWSH = next((p for p in [pathlib.Path('/mnt/data/pwsh76/pwsh'), pathlib.Path('/mnt/data/work/pwsh/pwsh')] if p.exists()), pathlib.Path('pwsh'))


def run_ps(command: str, env: dict | None = None) -> subprocess.CompletedProcess:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run([str(PWSH), '-NoProfile', '-Command', command], check=True, capture_output=True, text=True, env=merged_env)


class RepoContractTests(unittest.TestCase):
    def test_main_json_has_dual_mode_parameters(self):
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        self.assertIn('edgeMode', data['parameters'])
        self.assertIn('enableIngressIpRestrictions', data['parameters'])
        self.assertIn('ingressAllowedCidrs', data['parameters'])
        outputs = data['outputs']
        self.assertIn('containerAppEnvironmentName', outputs)
        self.assertIn('containerAppName', outputs)

    def test_deploy_to_azure_wrapper_exists_and_exposes_many_parameters(self):
        data = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        params = data['parameters']
        self.assertGreaterEqual(len(params), 57)
        for key in ['appName', 'domainUrl', 'mailRootDomain', 'smtpUseAuth', 'storageAccountSku', 'postgresSkuName', 'dbPassword', 'azureFilesBackupEnabled', 'smtpAuthMechanism', 'customHostname', 'edgeMode', 'enableIngressIpRestrictions', 'ingressAllowedCidrs']:
            self.assertIn(key, params)
        self.assertIn('main.json', data['parameters']['mainTemplateUri']['defaultValue'])
        self.assertEqual(data['parameters']['dbPassword']['defaultValue'], '[concat(toUpper(newGuid()), newGuid())]')

    def test_powershell_scripts_parse(self):
        scripts = [
            'scripts/Invoke-CustomerDeployment.ps1',
            'scripts/Deploy-AzureStack.ps1',
            'scripts/Set-CloudflareZoneConfig.ps1',
            'scripts/Bind-AcaCustomDomain.ps1',
            'scripts/Set-AcaIngressRestrictions.ps1',
            'scripts/lib/VaultwardenDeployment.Common.ps1',
            'scripts/cloudflare/Get-CloudflareIpRanges.ps1',
            'scripts/deploy.ps1',
        ]
        for rel in scripts:
            parser_command = (
                "$errors=$null; $tokens=$null; "
                f"[System.Management.Automation.Language.Parser]::ParseFile('{str(REPO_ROOT / rel).replace("'", "''")}',[ref]$tokens,[ref]$errors) | Out-Null; "
                "if($errors){ $errors | ForEach-Object { $_.Message }; exit 1 }"
            )
            run_ps(parser_command)

    def test_generate_only_cloudflare_customer_files_with_domain_defaults(self):
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-'))
        current_root = REPO_ROOT / 'current'
        try:
            if current_root.exists():
                shutil.rmtree(current_root, ignore_errors=True)
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '4711' -VaultwardenDomain 'vault.kunde.de' -CloudflareZone 'kunde.de'"
            command += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'cloudflare-managed'"
            command += f" -CustomersRoot '{str(customers_root).replace("'", "''")}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain 'kunde.de' -SmtpUseAuth -SmtpFrom 'vaultwarden@kunde.de' -SmtpHost 'smtp.office365.com' -SmtpPort '587' -SmtpSecurity 'starttls' -SmtpUsername 'vaultwarden@kunde.de'"
            command += " -SmtpPassword (ConvertTo-SecureString 'secret' -AsPlainText -Force)"
            command += " -SsoEnabled -SsoAuthority 'https://login.microsoftonline.com/tenant/v2.0' -SsoClientId 'client-id' -SsoClientSecret (ConvertTo-SecureString 'ssosecret' -AsPlainText -Force)"
            command += " -PushEnabled -PushInstallationId 'push-id' -PushInstallationKey (ConvertTo-SecureString 'pushsecret' -AsPlainText -Force)"
            command += " -StorageAccountSku 'Standard_LRS' -PostgresSkuName 'Standard_B1ms' -PostgresStorageGB 64"
            run_ps(command)
            config_path = customers_root / 'vault-kunde-de' / 'deployment.config.json'
            params_path = customers_root / 'vault-kunde-de' / 'azure.parameters.json'
            current_config_path = current_root / 'deployment.config.json'
            current_params_path = current_root / 'azure.parameters.json'
            current_wrapper_path = current_root / 'main.deploytoazure.json'
            self.assertTrue(config_path.exists())
            self.assertTrue(params_path.exists())
            self.assertTrue(current_config_path.exists())
            self.assertTrue(current_params_path.exists())
            self.assertTrue(current_wrapper_path.exists())
            config_text = config_path.read_text(encoding='utf-8')
            config = json.loads(config_text)
            params = json.loads(params_path.read_text(encoding='utf-8'))
            current_wrapper = json.loads(current_wrapper_path.read_text(encoding='utf-8'))
            self.assertEqual(config['customerNumber'], '4711')
            self.assertNotIn('\"password\":', config_text)
            self.assertNotIn('dbPassword', config_text)
            self.assertEqual(config['customerCode'], 'vault-kunde-de')
            self.assertEqual(config['domain']['hostname'], 'vault.kunde.de')
            self.assertEqual(config['edge']['mode'], 'cloudflare-managed')
            self.assertEqual(config['azure']['resourceGroupName'], 'rg-kunde-vault-prod-gwc')
            self.assertEqual(params['parameters']['edgeMode']['value'], 'cloudflare-managed')
            self.assertEqual(params['parameters']['customHostname']['value'], 'vault.kunde.de')
            self.assertEqual(config['azure']['advancedArmParameters']['invitationOrgName'], 'kunde.de')
            self.assertEqual(config['azure']['advancedArmParameters']['signupsDomainsWhitelist'], 'kunde.de')
            self.assertTrue(config['azure']['advancedArmParameters']['ssoEnabled'])
            self.assertTrue(config['azure']['advancedArmParameters']['pushEnabled'])
            self.assertFalse(config['azure']['advancedArmParameters']['acsDeployFoundation'])
            self.assertFalse(params['parameters']['enableIngressIpRestrictions']['value'])
            self.assertTrue(params['parameters']['ssoEnabled']['value'])
            self.assertEqual(params['parameters']['ssoClientId']['value'], 'client-id')
            self.assertTrue(params['parameters']['pushEnabled']['value'])
            self.assertEqual(params['parameters']['postgresStorageGB']['value'], 64)
            self.assertNotIn('smtpPassword', params['parameters'])
            self.assertNotIn('ssoClientSecret', params['parameters'])
            self.assertNotIn('pushInstallationKey', params['parameters'])
            self.assertEqual(current_wrapper['parameters']['appName']['defaultValue'], 'vaultkunde')
            self.assertEqual(current_wrapper['parameters']['domainUrl']['defaultValue'], 'https://vault.kunde.de')
            self.assertEqual(current_wrapper['parameters']['mailRootDomain']['defaultValue'], 'kunde.de')
            self.assertEqual(current_wrapper['parameters']['ssoEnabled']['defaultValue'], True)
            self.assertEqual(current_wrapper['parameters']['pushEnabled']['defaultValue'], True)
            self.assertEqual(current_wrapper['parameters']['smtpPassword']['defaultValue'], '')
            self.assertEqual(current_wrapper['parameters']['ssoClientSecret']['defaultValue'], '')
            self.assertEqual(current_wrapper['parameters']['pushInstallationKey']['defaultValue'], '')
            self.assertEqual(current_wrapper['parameters']['dbPassword']['defaultValue'], '[concat(toUpper(newGuid()), newGuid())]')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    def test_generate_only_basic_customer_files(self):
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-basic-'))
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '0815' -VaultwardenDomain 'vault.basic.de' -CloudflareZone 'basic.de'"
            command += " -Environment 'test' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace("'", "''")}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain 'basic.de' -SmtpFrom 'vaultwarden@basic.de'"
            run_ps(command)
            config = json.loads((customers_root / 'vault-basic-de' / 'deployment.config.json').read_text(encoding='utf-8'))
            self.assertEqual(config['edge']['mode'], 'basic')
            self.assertFalse(config['edge']['lockOriginToCloudflare'])
            self.assertEqual(config['customerNumber'], '0815')
            self.assertEqual(config['azure']['resourceGroupName'], 'rg-basic-vault-test-gwc')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)

    def test_lockdown_script_keeps_cidrs_in_config_and_rules_in_param_file(self):
        customer_code = 'locktest'
        customer_root = REPO_ROOT / 'customers' / customer_code
        try:
            (customer_root / 'artifacts').mkdir(parents=True, exist_ok=True)
            config = {
                'customerCode': customer_code,
                'customerNumber': '9999',
                'metadata': {'createdAt': '2026-03-25T00:00:00Z', 'updatedAt': '2026-03-25T00:00:00Z', 'version': 3},
                'azure': {
                    'resourceGroupName': 'rg-vault-prod-gwc',
                    'location': 'germanywestcentral',
                    'environment': 'prod',
                    'appName': 'locktest',
                    'edgeMode': 'cloudflare-managed',
                    'enableIngressIpRestrictions': False,
                    'ingressAllowedCidrs': [],
                    'advancedArmParameters': {}
                },
                'domain': {'hostname': 'vault.lock.example.com', 'zoneName': 'example.com', 'url': 'https://vault.lock.example.com'},
                'edge': {'mode': 'cloudflare-managed', 'enableWaf': True, 'enableRateLimit': True, 'lockOriginToCloudflare': True},
                'smtp': {'useAuth': False, 'mailRootDomain': 'example.com', 'from': 'vaultwarden@example.com', 'fromName': 'Vaultwarden', 'host': '', 'port': '', 'security': 'starttls', 'username': '', 'passwordSource': 'none'},
                'secrets': {'smtpPasswordSource': 'none', 'cloudflareApiTokenSource': 'prompt-or-env', 'ssoClientSecretSource': 'none', 'pushInstallationKeySource': 'none'}
            }
            params = {
                '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#',
                'contentVersion': '1.0.0.0',
                'parameters': {
                    'location': {'value': 'germanywestcentral'},
                    'environment': {'value': 'prod'},
                    'appName': {'value': 'locktest'},
                    'domainUrl': {'value': 'https://vault.lock.example.com'},
                    'customHostname': {'value': 'vault.lock.example.com'},
                    'mailRootDomain': {'value': 'example.com'},
                    'smtpUseAuth': {'value': False},
                    'smtpFrom': {'value': 'vaultwarden@example.com'},
                    'smtpFromName': {'value': 'Vaultwarden'},
                    'edgeMode': {'value': 'cloudflare-managed'},
                    'enableIngressIpRestrictions': {'value': False},
                    'ingressAllowedCidrs': {'value': []}
                }
            }
            (customer_root / 'deployment.config.json').write_text(json.dumps(config), encoding='utf-8')
            (customer_root / 'azure.parameters.json').write_text(json.dumps(params), encoding='utf-8')
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Set-AcaIngressRestrictions.ps1')
            command += f" -CustomerConfigPath '{str(customer_root / 'deployment.config.json').replace("'", "''")}'"
            run_ps(command, env={'CLOUDFLARE_IP_RANGES_JSON': '["173.245.48.0/20","103.21.244.0/22"]'})
            updated_config = json.loads((customer_root / 'deployment.config.json').read_text(encoding='utf-8'))
            updated_params = json.loads((customer_root / 'azure.parameters.json').read_text(encoding='utf-8'))
            self.assertTrue(updated_config['azure']['enableIngressIpRestrictions'])
            self.assertIsInstance(updated_config['azure']['ingressAllowedCidrs'][0], str)
            self.assertEqual(updated_params['parameters']['ingressAllowedCidrs']['value'][0]['action'], 'Allow')
        finally:
            shutil.rmtree(customer_root, ignore_errors=True)

    def test_region_helper_uses_caf_like_default_rg_name(self):
        command = (
            ". '{}' ; "
            "Get-DefaultResourceGroupName -Environment 'prod' -Location 'germanywestcentral' -VaultwardenDomain 'vault.thermosun.de'"
        ).format(REPO_ROOT / 'scripts/lib/VaultwardenDeployment.Common.ps1')
        result = run_ps(command)
        self.assertEqual(result.stdout.strip(), 'rg-thermosun-vault-prod-gwc')

    def test_readme_button_points_to_current_wrapper(self):
        readme = (REPO_ROOT / 'Readme.md').read_text(encoding='utf-8')
        self.assertIn('current%2Fmain.deploytoazure.json', readme)



if __name__ == '__main__':
    unittest.main()

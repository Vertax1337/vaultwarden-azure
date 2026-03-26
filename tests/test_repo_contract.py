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
    def setUp(self):
        # Restore current/ directory if it was removed by a previous test
        current_wrapper = REPO_ROOT / 'current' / 'main.deploytoazure.json'
        if not current_wrapper.exists():
            subprocess.run(['git', 'checkout', 'HEAD', '--', 'current/'], cwd=REPO_ROOT, check=True)

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

    def test_readme_button_uses_master_branch(self):
        readme = (REPO_ROOT / 'Readme.md').read_text(encoding='utf-8')
        # All Deploy-to-Azure portal links must reference the master branch
        import re
        portal_links = re.findall(r'https://portal\.azure\.com/[^\s\)]+', readme)
        self.assertGreater(len(portal_links), 0, 'No Deploy-to-Azure portal links found')
        for link in portal_links:
            self.assertIn('master', link, f'Portal link does not reference master branch: {link}')
            self.assertNotIn('%2Fmain%2F', link, f'Portal link references main branch instead of master: {link}')

    def test_current_wrapper_parameter_coverage(self):
        """current/main.deploytoazure.json must have all params from root wrapper."""
        root = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        current = json.loads((REPO_ROOT / 'current' / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        root_params = set(root['parameters'].keys())
        current_params = set(current['parameters'].keys())
        missing = root_params - current_params
        self.assertEqual(missing, set(), f'current/main.deploytoazure.json is missing parameters: {sorted(missing)}')

    def test_current_wrapper_dbpassword_auto_generation(self):
        """current/main.deploytoazure.json must auto-generate dbPassword."""
        current = json.loads((REPO_ROOT / 'current' / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        self.assertIn('dbPassword', current['parameters'])
        self.assertEqual(
            current['parameters']['dbPassword']['defaultValue'],
            '[concat(toUpper(newGuid()), newGuid())]',
            'dbPassword must auto-generate via ARM template function'
        )

    def test_current_wrapper_resources_is_array(self):
        """ARM template resources must be a JSON array, not a dict."""
        current = json.loads((REPO_ROOT / 'current' / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        self.assertIsInstance(current['resources'], list, 'resources must be an array for valid ARM template')
        self.assertGreater(len(current['resources']), 0)

    def test_current_wrapper_maintemplate_uri_uses_master(self):
        """current wrapper must reference master branch for nested template."""
        current = json.loads((REPO_ROOT / 'current' / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        uri = current['parameters']['mainTemplateUri']['defaultValue']
        self.assertIn('/master/', uri, f'mainTemplateUri must reference master branch: {uri}')
        self.assertNotIn('/main/', uri, f'mainTemplateUri must NOT reference main branch: {uri}')

    def test_current_wrapper_no_secrets_as_defaults(self):
        """Secure parameters in current wrapper must not contain real secret values."""
        current = json.loads((REPO_ROOT / 'current' / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        for name, defn in current['parameters'].items():
            ptype = defn.get('type', '').lower()
            if ptype == 'securestring' and name != 'dbPassword':
                default = defn.get('defaultValue', '')
                self.assertEqual(default, '', f'Secure param {name} must have empty default, got: {default}')

    def test_current_wrapper_forwards_all_params(self):
        """current wrapper must forward all defined params to nested main.json."""
        current = json.loads((REPO_ROOT / 'current' / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        resources = current['resources']
        self.assertIsInstance(resources, list)
        deployment = next(r for r in resources if r.get('type') == 'Microsoft.Resources/deployments')
        forwarded = set(deployment['properties']['parameters'].keys())
        defined = set(current['parameters'].keys()) - {'mainTemplateUri'}
        not_forwarded = defined - forwarded
        self.assertEqual(not_forwarded, set(), f'Parameters defined but not forwarded: {sorted(not_forwarded)}')

    def test_customer_config_no_secrets(self):
        """Customer deployment.config.json must not contain real secrets."""
        for config_path in (REPO_ROOT / 'customers').rglob('deployment.config.json'):
            text = config_path.read_text(encoding='utf-8')
            self.assertNotIn('"password":', text.lower(), f'Secret found in {config_path}')
            self.assertNotIn('dbPassword', text, f'dbPassword reference in {config_path}')

    def test_generate_only_preserves_resources_array(self):
        """GenerateOnly must produce wrapper with resources as JSON array."""
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-arr-'))
        current_root = REPO_ROOT / 'current'
        try:
            if current_root.exists():
                shutil.rmtree(current_root, ignore_errors=True)
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '9999' -VaultwardenDomain 'vault.arrtest.de' -CloudflareZone 'arrtest.de'"
            command += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain 'arrtest.de' -SmtpFrom 'vw@arrtest.de'"
            run_ps(command)
            current_wrapper = json.loads((current_root / 'main.deploytoazure.json').read_text(encoding='utf-8'))
            self.assertIsInstance(current_wrapper['resources'], list, 'resources must be array after GenerateOnly')
            self.assertEqual(
                current_wrapper['parameters']['dbPassword']['defaultValue'],
                '[concat(toUpper(newGuid()), newGuid())]'
            )
            # Verify parameter coverage
            root_wrapper = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
            root_params = set(root_wrapper['parameters'].keys())
            current_params = set(current_wrapper['parameters'].keys())
            self.assertEqual(root_params, current_params, 'GenerateOnly wrapper must have all root wrapper params')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    def test_rg_default_in_stored_configs(self):
        """Stored configs must use the full CAF-like RG name pattern."""
        for config_path in list((REPO_ROOT / 'customers').rglob('deployment.config.json')) + [REPO_ROOT / 'current' / 'deployment.config.json']:
            if not config_path.exists():
                continue
            config = json.loads(config_path.read_text(encoding='utf-8'))
            rg = config['azure']['resourceGroupName']
            hostname = config['domain']['hostname']
            env = config['azure']['environment']
            # RG should contain a customer slug derived from hostname
            self.assertRegex(rg, r'^rg-.+-vault-.+-.+$', f'RG name {rg} in {config_path} does not match pattern')



if __name__ == '__main__':
    unittest.main()

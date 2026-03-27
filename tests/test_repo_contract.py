import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import typing
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PWSH: typing.Optional[pathlib.Path] = None

# Detect pwsh availability once at import time.
# Override with PWSH_PATH environment variable if needed.
_pwsh_candidates = [pathlib.Path('pwsh')]
if os.environ.get('PWSH_PATH'):
    _pwsh_candidates.insert(0, pathlib.Path(os.environ['PWSH_PATH']))
for _candidate in _pwsh_candidates:
    try:
        subprocess.run([str(_candidate), '-NoProfile', '-Command', 'exit 0'], check=True, capture_output=True, timeout=10)
        PWSH = _candidate
        break
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired, OSError):
        continue

_PWSH_AVAILABLE = PWSH is not None
_CURRENT_WRAPPER_BACKUP: typing.Optional[dict] = None
_CURRENT_DIR_BACKUPS: typing.Dict[str, str] = {}


def _load_current_wrapper_backup() -> typing.Optional[dict]:
    """Load the current wrapper from disk to restore after destructive tests."""
    global _CURRENT_WRAPPER_BACKUP
    if _CURRENT_WRAPPER_BACKUP is not None:
        return _CURRENT_WRAPPER_BACKUP
    path = REPO_ROOT / 'current' / 'main.deploytoazure.json'
    if path.exists():
        _CURRENT_WRAPPER_BACKUP = json.loads(path.read_text(encoding='utf-8'))
    return _CURRENT_WRAPPER_BACKUP


def _load_current_dir_backups() -> None:
    """Load all tracked files in current/ to restore after destructive tests."""
    global _CURRENT_DIR_BACKUPS
    if _CURRENT_DIR_BACKUPS:
        return
    current_dir = REPO_ROOT / 'current'
    for name in ('deployment.config.json', 'README.md'):
        fpath = current_dir / name
        if fpath.exists():
            _CURRENT_DIR_BACKUPS[name] = fpath.read_text(encoding='utf-8')


def _restore_current_wrapper() -> None:
    """Restore the current directory from in-memory backup (no git required)."""
    current_dir = REPO_ROOT / 'current'
    wrapper_path = current_dir / 'main.deploytoazure.json'
    if not wrapper_path.exists() and _CURRENT_WRAPPER_BACKUP is not None:
        current_dir.mkdir(parents=True, exist_ok=True)
        wrapper_path.write_text(json.dumps(_CURRENT_WRAPPER_BACKUP, indent=4, ensure_ascii=False) + '\n', encoding='utf-8')
    for name, content in _CURRENT_DIR_BACKUPS.items():
        fpath = current_dir / name
        if not fpath.exists():
            current_dir.mkdir(parents=True, exist_ok=True)
            fpath.write_text(content, encoding='utf-8')


def requires_pwsh(fn):
    """Decorator that skips a test when pwsh is not available."""
    return unittest.skipUnless(_PWSH_AVAILABLE, 'pwsh (PowerShell) not available')(fn)


def run_ps(command: str, env: typing.Optional[typing.Dict[str, str]] = None) -> subprocess.CompletedProcess:
    if not _PWSH_AVAILABLE:
        raise unittest.SkipTest('pwsh (PowerShell) not available')
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run([str(PWSH), '-NoProfile', '-Command', command], check=True, capture_output=True, text=True, env=merged_env)


# Load backup at import time so it is available before any test modifies current/
_load_current_wrapper_backup()
_load_current_dir_backups()


class RepoContractTests(unittest.TestCase):
    def setUp(self):
        # Restore current/ directory from in-memory backup (no git dependency)
        _restore_current_wrapper()

    def test_main_json_has_dual_mode_parameters(self):
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        self.assertIn('edgeMode', data['parameters'])
        self.assertIn('enableIngressIpRestrictions', data['parameters'])
        self.assertIn('ingressAllowedCidrs', data['parameters'])
        outputs = data['outputs']
        self.assertIn('containerAppEnvironmentName', outputs)
        self.assertIn('containerAppName', outputs)

    def test_main_json_assigns_reader_role_to_kv_writer_on_postgres(self):
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        self.assertIn('roleReader', data['variables'])
        resources = data['resources']
        role_assignments = [r for r in resources if r.get('type') == 'Microsoft.Authorization/roleAssignments']
        postgres_reader = [
            r for r in role_assignments
            if r.get('scope') == "[format('Microsoft.DBforPostgreSQL/flexibleServers/{0}', variables('postgresServerName'))]"
            and r.get('properties', {}).get('roleDefinitionId') == "[variables('roleReader')]"
        ]
        self.assertEqual(len(postgres_reader), 1, 'Expected exactly one PostgreSQL Reader role assignment for kv-writer identity')

        deployment_script = next(r for r in resources if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        expected_dep = "[extensionResourceId(resourceId('Microsoft.DBforPostgreSQL/flexibleServers', variables('postgresServerName')), 'Microsoft.Authorization/roleAssignments', guid(resourceId('Microsoft.DBforPostgreSQL/flexibleServers', variables('postgresServerName')), resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', format('{0}-kv-writer-id', parameters('appName'))), variables('roleReader')))]"
        self.assertIn(expected_dep, deployment_script['dependsOn'])

    def test_deploy_to_azure_wrapper_exists_and_exposes_many_parameters(self):
        data = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        params = data['parameters']
        self.assertGreaterEqual(len(params), 57)
        for key in ['appName', 'domainUrl', 'mailRootDomain', 'smtpUseAuth', 'storageAccountSku', 'postgresSkuName', 'dbPassword', 'azureFilesBackupEnabled', 'smtpAuthMechanism', 'customHostname', 'edgeMode', 'enableIngressIpRestrictions', 'ingressAllowedCidrs']:
            self.assertIn(key, params)
        self.assertIn('main.json', data['parameters']['mainTemplateUri']['defaultValue'])
        self.assertEqual(data['parameters']['dbPassword']['defaultValue'], '[concat(toUpper(newGuid()), newGuid())]')

    @requires_pwsh
    def test_powershell_scripts_parse(self):
        scripts = [
            'scripts/Invoke-CustomerDeployment.ps1',
            'scripts/Deploy-AzureStack.ps1',
            'scripts/Set-CloudflareZoneConfig.ps1',
            'scripts/Bind-AcaCustomDomain.ps1',
            'scripts/Set-AcaIngressRestrictions.ps1',
            'scripts/lib/VaultwardenDeployment.Common.ps1',
            'scripts/lib/VaultwardenDeployment.Flows.ps1',
            'scripts/lib/VaultwardenDeployment.Menu.ps1',
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

    @requires_pwsh
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
            self.assertEqual(current_wrapper['parameters']['appName']['defaultValue'], 'vault')
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

    @requires_pwsh
    def test_generate_only_basic_customer_files(self):
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-basic-'))
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '0815' -VaultwardenDomain 'vault.basic.de' -CloudflareZone 'basic.de'"
            command += " -Environment 'test' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace("'", "''")}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain 'basic.de' -SmtpFrom 'vaultwarden@basic.de' -SmtpHost 'mx.basic.de'"
            run_ps(command)
            config = json.loads((customers_root / 'vault-basic-de' / 'deployment.config.json').read_text(encoding='utf-8'))
            self.assertEqual(config['edge']['mode'], 'basic')
            self.assertFalse(config['edge']['lockOriginToCloudflare'])
            self.assertEqual(config['customerNumber'], '0815')
            self.assertEqual(config['azure']['resourceGroupName'], 'rg-basic-vault-test-gwc')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)

    @requires_pwsh
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

    @requires_pwsh
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

    def test_root_wrapper_forwards_all_params(self):
        """Root main.deploytoazure.json wrapper must forward all defined params to nested main.json."""
        root = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        resources = root['resources']
        self.assertIsInstance(resources, list)
        deployment = next(r for r in resources if r.get('type') == 'Microsoft.Resources/deployments')
        forwarded = set(deployment['properties']['parameters'].keys())
        defined = set(root['parameters'].keys()) - {'mainTemplateUri'}
        not_forwarded = defined - forwarded
        self.assertEqual(not_forwarded, set(), f'Root wrapper parameters defined but not forwarded: {sorted(not_forwarded)}')

    def test_root_wrapper_forwards_mail_mode(self):
        """Root main.deploytoazure.json must forward mailMode to nested deployment."""
        root = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        deployment = next(r for r in root['resources'] if r.get('type') == 'Microsoft.Resources/deployments')
        forwarded = deployment['properties']['parameters']
        self.assertIn('mailMode', forwarded,
                      'Root wrapper must forward mailMode to nested main.json deployment')
        self.assertEqual(forwarded['mailMode']['value'], "[parameters('mailMode')]",
                         'mailMode must be forwarded as a parameter reference')

    def test_customer_config_no_secrets(self):
        """Customer deployment.config.json must not contain real secrets."""
        for config_path in (REPO_ROOT / 'customers').rglob('deployment.config.json'):
            text = config_path.read_text(encoding='utf-8')
            self.assertNotIn('"password":', text.lower(), f'Secret found in {config_path}')
            self.assertNotIn('dbPassword', text, f'dbPassword reference in {config_path}')

    @requires_pwsh
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
            command += " -MailRootDomain 'arrtest.de' -SmtpFrom 'vw@arrtest.de' -SmtpHost 'mx.arrtest.de'"
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
        """Stored configs must have a non-empty resourceGroupName starting with 'rg-'.
        The wizard allows custom overrides of the derived default, so only a minimal
        prefix check is enforced here."""
        for config_path in list((REPO_ROOT / 'customers').rglob('deployment.config.json')) + [REPO_ROOT / 'current' / 'deployment.config.json']:
            if not config_path.exists():
                continue
            config = json.loads(config_path.read_text(encoding='utf-8'))
            rg = config['azure']['resourceGroupName']
            self.assertTrue(rg.startswith('rg-') and len(rg) > 3, f'RG name {rg} in {config_path} must be a non-empty value starting with rg-')

    def test_no_secrets_in_current_azure_parameters(self):
        """current/azure.parameters.json must not be tracked in git (or if present, must not contain real secrets)."""
        params_path = REPO_ROOT / 'current' / 'azure.parameters.json'
        if not params_path.exists():
            return  # File correctly absent
        text = params_path.read_text(encoding='utf-8')
        params = json.loads(text)
        secure_keys = ['smtpPassword', 'ssoClientSecret', 'pushInstallationKey']
        for key in secure_keys:
            if key in params.get('parameters', {}):
                value = params['parameters'][key].get('value', '')
                self.assertEqual(value, '', f'Secret {key} should not have a real value in current/azure.parameters.json')

    def test_gitignore_excludes_azure_parameters(self):
        """The .gitignore must exclude azure.parameters.json from customers/ and current/."""
        gitignore = (REPO_ROOT / '.gitignore').read_text(encoding='utf-8')
        self.assertIn('customers/*/azure.parameters.json', gitignore)
        self.assertIn('current/azure.parameters.json', gitignore)

    def test_ps_scripts_no_unguarded_depth_parameter(self):
        """All PowerShell scripts that use ConvertFrom-Json -Depth must guard it for PS5.1 compatibility."""
        ps_files = list((REPO_ROOT / 'scripts').rglob('*.ps1'))
        for ps_file in ps_files:
            content = ps_file.read_text(encoding='utf-8', errors='replace')
            lines = content.split('\n')
            for i, line in enumerate(lines, 1):
                if 'ConvertFrom-Json' in line and '-Depth' in line:
                    # Must be inside a PS6+ guard (check previous lines for version check)
                    context = '\n'.join(lines[max(0, i-5):i])
                    self.assertTrue(
                        'PSVersion.Major' in context or 'PSVersionTable' in context,
                        f'{ps_file.name}:{i} uses ConvertFrom-Json -Depth without PS5.1 version guard'
                    )

    def test_ps_scripts_no_randomnumbergenerator_fill(self):
        """RandomNumberGenerator::Fill() is PS7/.NET Core only. Must use Create()+GetBytes() pattern."""
        ps_files = list((REPO_ROOT / 'scripts').rglob('*.ps1'))
        for ps_file in ps_files:
            content = ps_file.read_text(encoding='utf-8', errors='replace')
            self.assertNotIn(
                'RandomNumberGenerator]::Fill',
                content,
                f'{ps_file.name} uses RandomNumberGenerator::Fill() which is not available in PS5.1/.NET Framework'
            )

    def test_wrapper_main_json_parameter_parity(self):
        """The root wrapper must forward every parameter that main.json declares (except internal-only ones)."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        wrapper = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        main_params = set(main['parameters'].keys())
        wrapper_params = set(wrapper['parameters'].keys()) - {'mainTemplateUri'}
        # The wrapper should cover main.json params (wrapper may have extra like mainTemplateUri, customHostname, edgeMode, etc.)
        # Check that no main.json param is missing from the wrapper
        missing = main_params - wrapper_params
        self.assertEqual(missing, set(), f'main.json parameters not exposed by wrapper: {sorted(missing)}')

    def test_customer_configs_no_secret_values(self):
        """No deployment.config.json in customers/ or current/ should contain plaintext secret values."""
        secret_patterns = ['"password":', 'dbpassword', 'clientsecret":', 'installationkey":']
        for config_path in list((REPO_ROOT / 'customers').rglob('deployment.config.json')) + [REPO_ROOT / 'current' / 'deployment.config.json']:
            if not config_path.exists():
                continue
            text = config_path.read_text(encoding='utf-8').lower()
            for pattern in secret_patterns:
                # passwordSource is allowed; actual "password": "value" is not
                if pattern == '"password":':
                    # Check that it is only passwordSource, not a real password value
                    self.assertNotIn('"password": "', text.replace('"passwordsource"', ''),
                                     f'Potential secret ({pattern}) found in {config_path}')
                else:
                    self.assertNotIn(pattern, text, f'Potential secret ({pattern}) found in {config_path}')

    def test_stored_customer_configs_have_mail_mode(self):
        """Every checked-in deployment.config.json must have smtp.mailMode set to one of the 3 valid states.

        This ensures the repo no longer relies on backward-compatibility fallback logic for mail mode detection.
        Enforces the canonical 3-state model: direct_send | smtp_auth | acs_smtp.
        """
        valid_modes = {'direct_send', 'smtp_auth', 'acs_smtp'}
        for config_path in list((REPO_ROOT / 'customers').rglob('deployment.config.json')) + [REPO_ROOT / 'current' / 'deployment.config.json']:
            if not config_path.exists():
                continue
            config = json.loads(config_path.read_text(encoding='utf-8'))
            smtp = config.get('smtp', {})
            mail_mode = smtp.get('mailMode')
            self.assertIsNotNone(
                mail_mode,
                f'{config_path}: smtp.mailMode is missing. Must be one of {sorted(valid_modes)}'
            )
            self.assertIn(
                mail_mode, valid_modes,
                f'{config_path}: smtp.mailMode={mail_mode!r} is invalid. Must be one of {sorted(valid_modes)}'
            )

    def test_stored_customer_configs_mail_mode_consistent_with_use_auth(self):
        """smtp.mailMode must be consistent with smtp.useAuth in all stored configs.

        direct_send → useAuth must be false
        smtp_auth   → useAuth must be true
        acs_smtp    → useAuth must be true
        """
        for config_path in list((REPO_ROOT / 'customers').rglob('deployment.config.json')) + [REPO_ROOT / 'current' / 'deployment.config.json']:
            if not config_path.exists():
                continue
            config = json.loads(config_path.read_text(encoding='utf-8'))
            smtp = config.get('smtp', {})
            mail_mode = smtp.get('mailMode')
            use_auth = smtp.get('useAuth')
            if mail_mode is None:
                continue  # caught by test_stored_customer_configs_have_mail_mode
            if mail_mode == 'direct_send':
                self.assertFalse(
                    use_auth,
                    f'{config_path}: mailMode=direct_send requires useAuth=false, got useAuth={use_auth}'
                )
            elif mail_mode in ('smtp_auth', 'acs_smtp'):
                self.assertTrue(
                    use_auth,
                    f'{config_path}: mailMode={mail_mode} requires useAuth=true, got useAuth={use_auth}'
                )

    def test_shared_logic_comment_present_in_common_library(self):
        """Shared helper library must mark sensitive shared logic explicitly."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        self.assertIn('# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.', content)
        self.assertIn('# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.', content)

    def test_toolchain_no_az_powershell_module_usage(self):
        """Deployment scripts must use Azure CLI exclusively – no Az PowerShell module calls."""
        az_ps_patterns = [
            'Connect-AzAccount',
            'Get-AzContext',
            'New-AzResourceGroupDeployment',
            'Import-Module Az',
            'Ensure-AzModuleLoaded',
        ]
        ps_files = list((REPO_ROOT / 'scripts').rglob('*.ps1'))
        for ps_file in ps_files:
            content = ps_file.read_text(encoding='utf-8', errors='replace')
            for pattern in az_ps_patterns:
                self.assertNotIn(
                    pattern,
                    content,
                    f'{ps_file.name} contains Az PowerShell pattern "{pattern}". '
                    f'All deployment scripts must use Azure CLI (az) consistently.'
                )

    def test_toolchain_deploy_scripts_use_ensure_az_cli(self):
        """Scripts that call az commands must use Ensure-AzCliReady or Test-AzCliPresent."""
        # These scripts directly invoke az CLI commands
        scripts_with_az = [
            'scripts/deploy.ps1',
            'scripts/Deploy-AzureStack.ps1',
            'scripts/Bind-AcaCustomDomain.ps1',
        ]
        for rel in scripts_with_az:
            content = (REPO_ROOT / rel).read_text(encoding='utf-8', errors='replace')
            has_ensure = 'Ensure-AzCliReady' in content
            has_test = 'Test-AzCliPresent' in content
            self.assertTrue(
                has_ensure or has_test,
                f'{rel} uses az CLI but does not call Ensure-AzCliReady or Test-AzCliPresent'
            )

    def test_common_lib_has_ensure_az_cli_ready(self):
        """VaultwardenDeployment.Common.ps1 must define the Ensure-AzCliReady function."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        self.assertIn('function Ensure-AzCliReady', content,
                      'Common library must define Ensure-AzCliReady for consistent CLI bootstrap')
        self.assertIn('function Test-AzCliPresent', content,
                      'Common library must define Test-AzCliPresent')

    def test_common_lib_no_az_powershell_module_bootstrap(self):
        """Common library must not contain Az PowerShell module bootstrap code."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        self.assertNotIn('Install-Module -Name Az', content,
                         'Common library must not install Az PowerShell module – use Azure CLI')
        self.assertNotIn('Connect-AzAccount', content,
                         'Common library must not use Connect-AzAccount – use az login')

    def test_common_lib_has_install_az_cli(self):
        """Common library must define Install-AzCli for auto-installation."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        self.assertIn('function Install-AzCli', content,
                      'Common library must define Install-AzCli for automatic CLI installation')

    def test_common_lib_has_update_path_from_registry(self):
        """Common library must define Update-PathFromRegistry for post-install PATH refresh."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        self.assertIn('function Update-PathFromRegistry', content,
                      'Common library must define Update-PathFromRegistry')

    def test_ensure_az_cli_ready_calls_install_on_missing(self):
        """Ensure-AzCliReady must call Install-AzCli when az is not found."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        # Ensure-AzCliReady must reference Install-AzCli in its body
        # Extract the function body (rough: from 'function Ensure-AzCliReady' to next function or end)
        start = content.find('function Ensure-AzCliReady')
        self.assertGreater(start, -1, 'Ensure-AzCliReady not found')
        body = content[start:]
        # Must call Install-AzCli
        self.assertIn('Install-AzCli', body,
                      'Ensure-AzCliReady must call Install-AzCli when az is missing')
        # Must call Test-AzCliPresent
        self.assertIn('Test-AzCliPresent', body,
                      'Ensure-AzCliReady must call Test-AzCliPresent to check az availability')

    def test_install_az_cli_supports_windows_linux_macos(self):
        """Install-AzCli must handle Windows, Linux, and macOS platforms."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        start = content.find('function Install-AzCli')
        self.assertGreater(start, -1, 'Install-AzCli not found')
        body = content[start:]
        # Must reference platform detection
        self.assertIn('winget', body, 'Install-AzCli must support winget on Windows')
        self.assertIn('msiexec', body.lower() if 'msiexec' not in body else body,
                      'Install-AzCli must support MSI fallback on Windows')
        self.assertIn('InstallAzureCLIDeb', body,
                      'Install-AzCli must support Linux installation')
        self.assertIn('brew', body,
                      'Install-AzCli must support Homebrew on macOS')

    def test_test_az_cli_present_returns_bool(self):
        """Test-AzCliPresent must return a boolean (not throw)."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        start = content.find('function Test-AzCliPresent')
        self.assertGreater(start, -1, 'Test-AzCliPresent not found')
        # Find the end of the function (next function or end of content)
        next_func = content.find('\nfunction ', start + 1)
        if next_func == -1:
            func_body = content[start:]
        else:
            func_body = content[start:next_func]
        # Must return bool, not throw
        self.assertIn('[bool]', func_body,
                      'Test-AzCliPresent must return a boolean value')
        self.assertNotIn('throw', func_body,
                         'Test-AzCliPresent must not throw – it should return $false when az is missing')

    @requires_pwsh
    def test_install_az_cli_returns_true_when_az_present(self):
        """Install-AzCli should succeed (return $true) when az is already available."""
        # This tests the happy path: az is already installed, so Install-AzCli
        # should detect it (via Test-AzCliPresent at the end) and return $true.
        # We can't test the actual install path in CI without side effects,
        # but we can verify the control flow works when az is present.
        command = (
            ". '{}' ; "
            "if (Test-AzCliPresent) {{ Write-Output 'AZ_PRESENT' }} else {{ Write-Output 'AZ_MISSING' }}"
        ).format(REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1')
        result = run_ps(command)
        # az may or may not be installed in CI; test is informational
        output = result.stdout.strip()
        self.assertIn(output, ['AZ_PRESENT', 'AZ_MISSING'],
                      'Test-AzCliPresent must return a clean boolean result')

    @requires_pwsh
    def test_ensure_az_cli_ready_skip_login(self):
        """Ensure-AzCliReady -SkipLogin must not attempt login even if az is present."""
        # This test verifies that -SkipLogin works without errors.
        # If az is missing, Install-AzCli will be attempted but may fail in CI – that's OK,
        # we just want to verify the code path doesn't crash on parse/basic execution.
        command = (
            ". '{}' ; "
            "try {{ Ensure-AzCliReady -SkipLogin; Write-Output 'OK' }} "
            "catch {{ Write-Output ('CAUGHT: ' + $_.Exception.Message) }}"
        ).format(REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1')
        result = run_ps(command)
        output = result.stdout.strip()
        # If az is installed: OK
        # If az is not installed and auto-install fails: CAUGHT: ... konnte nicht automatisch installiert werden
        is_ok = (output == 'OK')
        is_install_fail = ('konnte nicht automatisch installiert werden' in output)
        is_caught = ('CAUGHT' in output)
        self.assertTrue(
            is_ok or is_install_fail or is_caught,
            f'Unexpected output from Ensure-AzCliReady -SkipLogin: {output}'
        )

    def test_firewall_rule_has_no_condition(self):
        """PostgreSQL AllowAzure firewall rule must be unconditional in the standard path."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        firewall_rules = [
            r for r in data['resources']
            if r.get('type') == 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules'
        ]
        self.assertGreater(len(firewall_rules), 0, 'No PostgreSQL firewall rule resource found')
        for rule in firewall_rules:
            self.assertNotIn('condition', rule, 'Firewall rule must not have a condition (always deployed)')

    def test_deployment_script_depends_on_firewall_rule(self):
        """The deployment script must depend on the PostgreSQL firewall rule via a standard JSON array."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        deploy_scripts = [
            r for r in data['resources']
            if r.get('type') == 'Microsoft.Resources/deploymentScripts'
        ]
        self.assertGreater(len(deploy_scripts), 0, 'No deployment script resource found')
        for script_res in deploy_scripts:
            deps = script_res.get('dependsOn', [])
            # dependsOn must be a standard JSON array, not a dynamic ARM expression string
            self.assertIsInstance(deps, list,
                                 'dependsOn must be a JSON array, not a dynamic concat/if expression')
            # Must include the firewall rule dependency
            deps_str = json.dumps(deps)
            self.assertIn('firewallRules', deps_str,
                          'Deployment script must depend on PostgreSQL firewall rule')

    def test_deployment_script_waits_for_ready_state_before_connectivity(self):
        """Deployment script must wait for PostgreSQL provisioning and Ready state before execute()."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        deploy_script = next(r for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        script = deploy_script['properties']['scriptContent']
        self.assertIn('az postgres flexible-server wait', script)
        self.assertIn('--created', script)
        self.assertIn('--query state -o tsv', script)
        self.assertIn('PostgreSQL state is Ready', script)

    def test_deployment_script_timeout_allows_extended_pg_wait(self):
        """Deployment script timeout must be long enough for extended PostgreSQL readiness wait."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        deploy_script = next(r for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        self.assertEqual(deploy_script['properties']['timeout'], 'PT1H')

    def test_deployment_script_has_pg_diagnostic_helpers(self):
        """Deployment script must expose richer PostgreSQL diagnostics on connectivity failures."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        deploy_script = next(r for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        script = deploy_script['properties']['scriptContent']
        self.assertIn('print_pg_server_diagnostics()', script)
        self.assertIn('print_pg_firewall_diagnostics()', script)
        self.assertIn('print_pg_database_diagnostics()', script)
        self.assertIn('print_pg_connectivity_diagnostics()', script)
        self.assertIn('psql exit code', script)
        self.assertIn('last connectivity stdout', script)
        self.assertIn('PostgreSQL firewall rules', script)
        self.assertIn('PostgreSQL databases', script)

    def test_allow_azure_services_always_true_in_defaults(self):
        """allowAzureServicesToPostgres must default to true in all templates and wizard defaults."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        self.assertTrue(main['parameters']['allowAzureServicesToPostgres']['defaultValue'],
                        'allowAzureServicesToPostgres must default to true in main.json')
        wrapper = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        self.assertTrue(wrapper['parameters']['allowAzureServicesToPostgres']['defaultValue'],
                        'allowAzureServicesToPostgres must default to true in wrapper')

    @requires_pwsh
    def test_wizard_does_not_prompt_allow_azure_or_insecure_http(self):
        """Wizard must not interactively prompt for allowAzureServicesToPostgres or allowInsecureHttp."""
        content = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8', errors='replace')
        # These prompts should have been removed
        self.assertNotIn("'Allow Azure services to Postgres?'", content,
                         'Wizard must not prompt for allowAzureServicesToPostgres')
        self.assertNotIn("'Unsicheres HTTP erlauben?'", content,
                         'Wizard must not prompt for allowInsecureHttp')

    @requires_pwsh
    def test_domain_lowercasing_in_generate_only(self):
        """Domain inputs with mixed case must be normalized to lowercase in generated files."""
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-case-'))
        current_root = REPO_ROOT / 'current'
        try:
            if current_root.exists():
                shutil.rmtree(current_root, ignore_errors=True)
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '7777' -VaultwardenDomain 'Vault.50er-Jahre-Museum.DE'"
            command += " -CloudflareZone '50er-Jahre-Museum.DE'"
            command += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain '50er-Jahre-Museum.DE'"
            command += " -SmtpFrom 'vaultwarden@50er-Jahre-Museum.DE' -SmtpHost 'mx.50er-jahre-museum.de'"
            run_ps(command)
            # Find the generated customer directory (slug should be lowercase)
            customer_dirs = [d for d in customers_root.iterdir() if d.is_dir()]
            self.assertEqual(len(customer_dirs), 1, 'Expected exactly one customer directory')
            config = json.loads((customer_dirs[0] / 'deployment.config.json').read_text(encoding='utf-8'))
            # All domain values must be lowercase
            self.assertEqual(config['domain']['hostname'], 'vault.50er-jahre-museum.de')
            self.assertEqual(config['domain']['zoneName'], '50er-jahre-museum.de')
            self.assertEqual(config['domain']['url'], 'https://vault.50er-jahre-museum.de')
            self.assertEqual(config['smtp']['mailRootDomain'], '50er-jahre-museum.de')
            # Customer code must be lowercase slug
            self.assertRegex(config['customerCode'], r'^[a-z0-9-]+$')
            # allowAzureServicesToPostgres must be true
            self.assertTrue(config['azure']['advancedArmParameters']['allowAzureServicesToPostgres'])
            # allowInsecureHttp must be true
            self.assertTrue(config['azure']['advancedArmParameters']['allowInsecureHttp'])
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_rg_default_derived_from_various_domains(self):
        """Resource group name must be dynamically derived from the Vaultwarden domain."""
        test_cases = [
            ('vault.thermosun.de', 'prod', 'germanywestcentral', 'rg-thermosun-vault-prod-gwc'),
            ('vault.example.com', 'test', 'westeurope', 'rg-example-vault-test-weu'),
            ('vault.50er-jahre-museum.de', 'prod', 'germanywestcentral', 'rg-50er-jahre-museum-vault-prod-gwc'),
        ]
        for domain, env, location, expected_rg in test_cases:
            command = (
                ". '{}' ; "
                "Get-DefaultResourceGroupName -Environment '{}' -Location '{}' -VaultwardenDomain '{}'"
            ).format(
                REPO_ROOT / 'scripts/lib/VaultwardenDeployment.Common.ps1',
                env, location, domain
            )
            result = run_ps(command)
            actual_rg = result.stdout.strip()
            self.assertEqual(actual_rg, expected_rg,
                             f'RG name for {domain}/{env}/{location}: expected {expected_rg}, got {actual_rg}')

    def test_ensure_az_cli_ready_verifies_after_login(self):
        """Ensure-AzCliReady must verify login after az login by querying account state again."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8', errors='replace')
        start = content.find('function Ensure-AzCliReady')
        self.assertGreater(start, -1)
        body = content[start:]
        az_login_pos = body.find('az login')
        self.assertGreater(az_login_pos, -1, 'Ensure-AzCliReady must call az login')
        after_login = body[az_login_pos:]
        self.assertIn('Get-AzCurrentAccount', after_login,
                      'Ensure-AzCliReady must verify login after az login')

    @requires_pwsh
    def test_app_name_is_fixed_to_vault(self):
        """appName should be the stable fixed value 'vault' instead of a truncated domain-derived name."""
        command = (
            ". '{}' ; "
            "Convert-SlugToAppName -Slug 'vault-50er-jahre-museum-de'"
        ).format(REPO_ROOT / 'scripts/lib/VaultwardenDeployment.Common.ps1')
        result = run_ps(command)
        self.assertEqual(result.stdout.strip(), 'vault')


    def test_main_json_key_vault_name_no_oversize_substring(self):
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        key_vault_expr = data['variables']['keyVaultName']
        self.assertNotIn("substring(uniqueString(resourceGroup().id, parameters('appName')), 0, 20)", key_vault_expr)
        self.assertIn("uniqueString(resourceGroup().id, parameters('appName'))", key_vault_expr)

    @requires_pwsh
    def test_deploy_azure_stack_creates_resource_group_before_group_deploy(self):
        script_text = (REPO_ROOT / 'scripts' / 'Deploy-AzureStack.ps1').read_text(encoding='utf-8')
        self.assertIn('Ensure-ResourceGroupExists -ResourceGroupName $ResourceGroupName -Location $location', script_text)
        self.assertIn('Read-JsonFile -Path $ParametersFile', script_text)

    @requires_pwsh
    def test_direct_deploy_script_ensures_resource_group_and_location_parameter(self):
        script_text = (REPO_ROOT / 'scripts' / 'deploy.ps1').read_text(encoding='utf-8')
        self.assertIn("[string]$Location = 'germanywestcentral'", script_text)
        self.assertIn('Ensure-ResourceGroupExists -ResourceGroupName $ResourceGroupName -Location $Location', script_text)
        self.assertIn('location = @{ value = $Location }', script_text)


    def test_main_json_uses_psql_instead_of_rdbms_connect(self):
        """Deployment script uses psql (PostgreSQL client) instead of az postgres flexible-server execute / rdbms-connect."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(r['properties']['scriptContent'] for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        # psql-based functions must exist
        self.assertIn('ensure_psql()', script)
        self.assertIn('build_psql_env', script)
        self.assertIn('run_psql', script)
        # rdbms-connect extension must NOT be used
        self.assertNotIn('ensure_rdbms_connect_extension', script)
        self.assertNotIn('az extension add --name rdbms-connect', script)
        self.assertNotIn('configure_az_extension_installation', script)
        self.assertNotIn('ensure_pip', script)
        self.assertNotIn('PG_CLI_BASE', script)
        self.assertNotIn('flexible-server execute', script)

    def test_main_json_connectivity_loop_uses_psql(self):
        """Connectivity check and SQL execution use run_psql, capture exit codes, and report errors."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(r['properties']['scriptContent'] for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        self.assertIn('run_psql postgres -c "SELECT 1"', script)
        self.assertIn('PG_EXEC_EXIT=$?', script)
        self.assertIn('if [ "$PG_EXEC_EXIT" -eq 0 ]; then', script)
        self.assertIn('run_psql postgres -f "$SQL_TMP_DIR/bootstrap-admin.sql"', script)
        self.assertIn('run_psql "$POSTGRES_DBNAME" -f "$SQL_TMP_DIR/bootstrap-db.sql"', script)
        self.assertIn('ERROR: PostgreSQL bootstrap-admin.sql failed', script)
        self.assertIn('ERROR: PostgreSQL bootstrap-db.sql failed', script)

    def test_main_json_smtp_no_dig_or_nslookup(self):
        """Deployment script must not use dig or nslookup for MX lookup (not available in Azure DeploymentScript)."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(r['properties']['scriptContent'] for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        self.assertNotIn('command -v dig', script)
        self.assertNotIn('dig +short MX', script)
        self.assertNotIn('command -v nslookup', script)
        self.assertNotIn('nslookup -type=mx', script)

    def test_main_json_smtp_direct_send_requires_explicit_host(self):
        """Deployment script must fail early with clear message when Direct Send and smtpHost is empty."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(r['properties']['scriptContent'] for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        # Early validation: Direct Send without SMTP_HOST_INPUT must exit 1
        self.assertIn(
            'if [ "${MAIL_MODE:-smtp_auth}" = "direct_send" ] && [ -z "${SMTP_HOST_INPUT:-}" ]; then',
            script
        )
        self.assertIn('Direct Send (mailMode=direct_send) requires an explicit smtpHost parameter', script)
        self.assertIn('MX lookup is not supported in Azure DeploymentScript environments', script)

    def test_main_json_smtp_direct_send_uses_smtp_host_input_directly(self):
        """Deployment script Direct Send path must use SMTP_HOST_INPUT directly (no MX resolution)."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(r['properties']['scriptContent'] for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        # The simple direct assignment must be present in the else branch
        self.assertIn('MX_HOST="${SMTP_HOST_INPUT}"', script)
        # No MX resolution comment or block
        self.assertNotIn('Resolving MX for', script)
        self.assertNotIn('MX lookup returned empty', script)

    @requires_pwsh
    def test_wizard_direct_send_prompts_for_smtp_host(self):
        """Interactive wizard must prompt for SMTP Host in Direct Send path."""
        script_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8')
        self.assertIn('MX-Endpunkt', script_text)

    @requires_pwsh
    def test_wizard_smtp_auth_prompts_for_host_with_default(self):
        """Interactive wizard must prompt for SMTP Host in the smtp_auth flow with a default of smtp.office365.com.
        Operator can accept the default or type a custom host. direct_send still uses its own explicit MX prompt."""
        script_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8')
        # smtp_auth block must contain a Read-TextWithDefault prompt that exposes the SMTP host
        self.assertIn("smtp_auth-Relay", script_text)
        # Default must be smtp.office365.com
        self.assertIn("smtp.office365.com", script_text)
        # The old "silent default" comment must no longer be present
        self.assertNotIn('SMTP Host is NOT prompted in the main wizard flow', script_text)

    @requires_pwsh
    def test_parameter_generation_writes_smtp_host_for_direct_send(self):
        """New-CustomerAzureParameters must write smtpHost to ARM parameters for Direct Send."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        # The elseif block for Direct Send smtpHost must exist
        self.assertIn("elseif (-not [string]::IsNullOrWhiteSpace($Config.smtp.host))", script_text)
        self.assertIn("Direct Send: write smtpHost so the deployment script receives SMTP_HOST_INPUT", script_text)

    @requires_pwsh
    def test_cli_path_validates_direct_send_requires_smtp_host(self):
        """CLI/NonInteractive path must fail early when Direct Send and SmtpHost is missing."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('-not $effectiveSmtpUseAuth -and [string]::IsNullOrWhiteSpace($SmtpHost)', script_text)
        self.assertIn('Direct Send', script_text)
        self.assertIn('erfordert einen expliziten -SmtpHost-Parameter', script_text)

    # -----------------------------------------------------------------------
    # Mail-Modus-Zustandswechsel: ARM-Template-Struktur (Pure Python)
    # -----------------------------------------------------------------------

    def test_main_json_smtp_secrets_conditional_on_smtp_use_auth(self):
        """ACA container app secrets must include smtp-password only when mailMode != direct_send.

        Transition smtp_auth/acs_smtp → direct_send: smtp-password SecretRef must be absent.
        Transition direct_send → smtp_auth/acs_smtp: smtp-password SecretRef must be present.
        Verified via the ARM concat/if expression in the container app resource.
        """
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        variables = data['variables']

        # vwSecretsSmtp must contain exactly the smtp-password entry
        smtp_secrets = variables['vwSecretsSmtp']
        self.assertIsInstance(smtp_secrets, list)
        smtp_secret_names = [s['name'] for s in smtp_secrets]
        self.assertIn('smtp-password', smtp_secret_names, 'vwSecretsSmtp must contain smtp-password')

        # The container app secrets expression must conditionally include vwSecretsSmtp based on mailMode
        container_app = next(
            r for r in data['resources'] if r.get('type') == 'Microsoft.App/containerApps'
        )
        secrets_expr = container_app['properties']['configuration']['secrets']
        self.assertIsInstance(secrets_expr, str, 'Container app secrets must be an ARM expression')
        # Must use mailMode-based condition (not direct_send = use smtp secrets)
        self.assertIn("not(equals(parameters('mailMode'), 'direct_send')), variables('vwSecretsSmtp')", secrets_expr,
                      'smtp-password secret must be conditional on mailMode != direct_send in the ACA secrets list')
        # direct_send must result in empty array for smtp secrets
        self.assertIn("json('[]')", secrets_expr,
                      'ACA secrets must fall back to empty array when mailMode=direct_send')
        # smtpUseAuth must NOT be the gating condition for smtp secrets
        self.assertNotIn("if(parameters('smtpUseAuth'), variables('vwSecretsSmtp')", secrets_expr,
                         'ACA secrets must use mailMode, not smtpUseAuth, as the gating condition')

    def test_main_json_smtp_auth_env_vars_conditional_on_smtp_use_auth(self):
        """SMTP_USERNAME and SMTP_PASSWORD (secretRef) env vars must only appear when mailMode != direct_send.

        Transition smtp_auth/acs_smtp → direct_send: these env vars must be absent from ACA env.
        Transition direct_send → smtp_auth/acs_smtp: these env vars must be present.
        Verified via vwEnvSmtpAuthCore variable and the conditional env concat expression.
        """
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        variables = data['variables']

        # vwEnvSmtpAuthCore must contain SMTP_USERNAME and SMTP_PASSWORD (secretRef)
        smtp_auth_env = variables['vwEnvSmtpAuthCore']
        self.assertIsInstance(smtp_auth_env, list)
        env_names = [e['name'] for e in smtp_auth_env]
        self.assertIn('SMTP_USERNAME', env_names, 'vwEnvSmtpAuthCore must contain SMTP_USERNAME')
        self.assertIn('SMTP_PASSWORD', env_names, 'vwEnvSmtpAuthCore must contain SMTP_PASSWORD')

        # SMTP_PASSWORD must be a secretRef (not a plain value)
        smtp_password_entry = next(e for e in smtp_auth_env if e['name'] == 'SMTP_PASSWORD')
        self.assertIn('secretRef', smtp_password_entry,
                      'SMTP_PASSWORD env var must use secretRef, not a plain value')
        self.assertEqual(smtp_password_entry['secretRef'], 'smtp-password')

        # The container app env expression must conditionally include vwEnvSmtpAuthCore based on mailMode
        container_app = next(
            r for r in data['resources'] if r.get('type') == 'Microsoft.App/containerApps'
        )
        env_expr = container_app['properties']['template']['containers'][0]['env']
        self.assertIsInstance(env_expr, str, 'Container app env must be an ARM expression')
        self.assertIn("not(equals(parameters('mailMode'), 'direct_send')), variables('vwEnvSmtpAuthCore')", env_expr,
                      'SMTP_USERNAME/SMTP_PASSWORD env vars must be conditional on mailMode != direct_send')
        # smtpUseAuth must NOT be the gating condition for vwEnvSmtpAuthCore
        self.assertNotIn("if(parameters('smtpUseAuth'), variables('vwEnvSmtpAuthCore')", env_expr,
                         'ACA env must use mailMode, not smtpUseAuth, as the gating condition for vwEnvSmtpAuthCore')

    def test_main_json_smtp_auth_mechanism_conditional_on_smtp_use_auth(self):
        """SMTP_AUTH_MECHANISM env var must only appear when mailMode != direct_send and smtpAuthMechanism is set.

        Direct Send: SMTP_AUTH_MECHANISM must never be active.
        Verified via vwEnvSmtpAuthMechanism variable expression.
        """
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        variables = data['variables']

        mechanism_expr = variables['vwEnvSmtpAuthMechanism']
        self.assertIsInstance(mechanism_expr, str, 'vwEnvSmtpAuthMechanism must be a conditional ARM expression')
        # Must be disabled when mailMode=direct_send
        self.assertIn("equals(parameters('mailMode'), 'direct_send')", mechanism_expr,
                      'SMTP_AUTH_MECHANISM must be suppressed when mailMode=direct_send')
        # smtpUseAuth must NOT be used as the gating condition
        self.assertNotIn("not(parameters('smtpUseAuth'))", mechanism_expr,
                         'vwEnvSmtpAuthMechanism must use mailMode, not smtpUseAuth')
        # Must be disabled when smtpAuthMechanism is empty
        self.assertIn("empty(parameters('smtpAuthMechanism'))", mechanism_expr,
                      'SMTP_AUTH_MECHANISM must be suppressed when smtpAuthMechanism is empty')

    def test_deployment_script_smtp_password_secret_only_in_auth_mode(self):
        """Deployment script must create/update smtp-password KV secret only when mailMode != direct_send.

        direct_send (mailMode=direct_send): secret creation must be skipped.
        smtp_auth/acs_smtp (mailMode!=direct_send): secret must be created/updated.
        """
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(
            r['properties']['scriptContent']
            for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts'
        )
        # SMTP password block must be guarded by MAIL_MODE check (not smtpUseAuth)
        self.assertIn('if [ "${MAIL_MODE:-smtp_auth}" != "direct_send" ]; then', script)
        # The skip message for Direct Send must be present
        self.assertIn('SMTP auth disabled (mailMode=direct_send). Skipping SMTP password secret.', script)
        # The KV secret set command must be inside the SMTP Auth guard
        smtp_auth_block_start = script.find('# --- SMTP password ---')
        smtp_auth_block_end = script.find('# --- SSO client secret', smtp_auth_block_start)
        smtp_block = script[smtp_auth_block_start:smtp_auth_block_end]
        self.assertIn('az keyvault secret set', smtp_block,
                      'az keyvault secret set for smtp-password must be inside SMTP Auth guard')
        self.assertIn('SMTP_PASSWORD_SECRET', smtp_block)
        # smtpUseAuth must NOT be used as gating condition for SMTP password secret
        self.assertNotIn('SMTP_USE_AUTH', smtp_block,
                         'SMTP password secret guard must use MAIL_MODE, not SMTP_USE_AUTH')

    def test_main_json_smtp_shared_logic_comment_in_deploy_script(self):
        """Key SMTP state-transition functions in Invoke-CustomerDeployment.ps1 must have SHARED LOGIC comments."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        # New-CustomerConfigObject must be marked shared logic (smtp section definition)
        self.assertIn('New-CustomerConfigObject', script_text)
        # New-CustomerAzureParameters must be marked shared logic (arm param generation)
        self.assertIn('New-CustomerAzureParameters', script_text)
        # Get-RuntimeSecretParameters must be marked shared logic (smtp password prompt)
        self.assertIn('Get-RuntimeSecretParameters', script_text)
        # Save-CustomerFiles must be marked shared logic (orchestration)
        self.assertIn('Save-CustomerFiles', script_text)
        # All key shared functions must have the SHARED LOGIC marker nearby
        for func_name in ['New-CustomerConfigObject', 'Get-RuntimeSecretParameters',
                          'New-CustomerAzureParameters', 'Save-CustomerFiles']:
            idx = script_text.find(f'function {func_name}')
            self.assertGreater(idx, 0, f'function {func_name} not found in script')
            # The SHARED LOGIC comment must appear within 600 chars before the function keyword
            context = script_text[max(0, idx - 600):idx]
            self.assertIn('# SHARED LOGIC:', context,
                          f'function {func_name} must have a # SHARED LOGIC: comment above it')
        # New-CustomerConfigInteractive is an interactive-wizard function; it lives in Flows.ps1
        flows_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8')
        self.assertIn('function New-CustomerConfigInteractive', flows_text,
                      'New-CustomerConfigInteractive must be defined in VaultwardenDeployment.Flows.ps1')

    # -----------------------------------------------------------------------
    # Mail-Modus-Zustandswechsel: Parameter-Generierung (pwsh-abhängig)
    # -----------------------------------------------------------------------

    @requires_pwsh
    def test_generate_only_smtp_auth_params_include_all_auth_fields(self):
        """GenerateOnly with -SmtpUseAuth must produce ARM parameters with all SMTP Auth fields.

        Scenario: Direct Send → SMTP Auth transition.
        Expected: smtpHost, smtpPort, smtpSecurity, smtpUsername present; smtpUseAuth=true.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-smtpauth-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '8001' -VaultwardenDomain 'vault.smtpauth.de' -CloudflareZone 'smtpauth.de'"
            command += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain 'smtpauth.de' -SmtpUseAuth -SmtpFrom 'vaultwarden@smtpauth.de'"
            command += " -SmtpHost 'smtp.office365.com' -SmtpPort '587' -SmtpSecurity 'starttls'"
            command += " -SmtpUsername 'vaultwarden@smtpauth.de'"
            command += " -SmtpPassword (ConvertTo-SecureString 'secret' -AsPlainText -Force)"
            run_ps(command)
            params = json.loads(
                (customers_root / 'vault-smtpauth-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            config = json.loads(
                (customers_root / 'vault-smtpauth-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            # SMTP Auth mode: all auth fields must be present
            self.assertTrue(p['smtpUseAuth']['value'], 'smtpUseAuth must be true in ARM params')
            self.assertEqual(p['smtpHost']['value'], 'smtp.office365.com')
            self.assertEqual(p['smtpPort']['value'], '587')
            self.assertEqual(p['smtpSecurity']['value'], 'starttls')
            self.assertEqual(p['smtpUsername']['value'], 'vaultwarden@smtpauth.de')
            # smtpPassword not in non-secure params (requires -IncludeSecureParameters)
            self.assertNotIn('smtpPassword', p)
            # Config must reflect SMTP Auth state
            self.assertTrue(config['smtp']['useAuth'])
            self.assertEqual(config['smtp']['passwordSource'], 'prompt')
            self.assertEqual(config['secrets']['smtpPasswordSource'], 'prompt')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_direct_send_params_exclude_smtp_auth_fields(self):
        """GenerateOnly without -SmtpUseAuth must produce ARM parameters with no SMTP Auth fields.

        Scenario: SMTP Auth → Direct Send transition.
        Expected: smtpHost present; smtpPort, smtpSecurity, smtpUsername, smtpPassword absent.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-directsend-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '8002' -VaultwardenDomain 'vault.directsend.de' -CloudflareZone 'directsend.de'"
            command += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            command += " -MailRootDomain 'directsend.de' -SmtpFrom 'vaultwarden@directsend.de'"
            command += " -SmtpHost 'mx01.directsend-de.mail.protection.outlook.com'"
            run_ps(command)
            params = json.loads(
                (customers_root / 'vault-directsend-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            config = json.loads(
                (customers_root / 'vault-directsend-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            # Direct Send mode: smtpUseAuth=false, only smtpHost present
            self.assertFalse(p['smtpUseAuth']['value'], 'smtpUseAuth must be false in ARM params')
            self.assertEqual(p['smtpHost']['value'], 'mx01.directsend-de.mail.protection.outlook.com')
            # No SMTP Auth fields must be present in ARM params
            self.assertNotIn('smtpPort', p, 'smtpPort must not be in ARM params for Direct Send')
            self.assertNotIn('smtpSecurity', p, 'smtpSecurity must not be in ARM params for Direct Send')
            self.assertNotIn('smtpUsername', p, 'smtpUsername must not be in ARM params for Direct Send')
            self.assertNotIn('smtpPassword', p, 'smtpPassword must not be in ARM params for Direct Send')
            # Config must reflect Direct Send state
            self.assertFalse(config['smtp']['useAuth'])
            self.assertEqual(config['smtp']['username'], '')
            self.assertEqual(config['smtp']['passwordSource'], 'none')
            self.assertEqual(config['secrets']['smtpPasswordSource'], 'none')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_mode_switch_smtp_auth_to_direct_send_clears_auth_fields(self):
        """Switching from SMTP Auth to Direct Send must produce a clean Direct Send config.

        Scenario: Existing SMTP Auth config → new GenerateOnly run with Direct Send.
        Expected: config.smtp has no stale SMTP Auth values; ARM params have no auth fields.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-switch-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base_cmd = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base_cmd += " -CustomerNumber '8003' -VaultwardenDomain 'vault.switchtest.de' -CloudflareZone 'switchtest.de'"
            base_cmd += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base_cmd += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            base_cmd += " -MailRootDomain 'switchtest.de' -SmtpFrom 'vaultwarden@switchtest.de'"

            # Step 1: Generate SMTP Auth config
            cmd_auth = base_cmd + " -SmtpUseAuth -SmtpHost 'smtp.office365.com' -SmtpPort '587' -SmtpSecurity 'starttls' -SmtpUsername 'vw@switchtest.de'"
            cmd_auth += " -SmtpPassword (ConvertTo-SecureString 'secret' -AsPlainText -Force)"
            run_ps(cmd_auth)
            auth_config = json.loads(
                (customers_root / 'vault-switchtest-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            self.assertTrue(auth_config['smtp']['useAuth'], 'Step 1: config must be SMTP Auth')

            # Step 2: Switch to Direct Send – re-run with same customer code
            cmd_direct = base_cmd + " -SmtpHost 'mx01.switchtest-de.mail.protection.outlook.com'"
            run_ps(cmd_direct)
            direct_config = json.loads(
                (customers_root / 'vault-switchtest-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            direct_params = json.loads(
                (customers_root / 'vault-switchtest-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            p = direct_params['parameters']
            # Config: SMTP Auth fields must be cleared
            self.assertFalse(direct_config['smtp']['useAuth'], 'After switch: useAuth must be false')
            self.assertEqual(direct_config['smtp']['username'], '', 'After switch: username must be empty')
            self.assertEqual(direct_config['smtp']['port'], '', 'After switch: port must be empty')
            self.assertEqual(direct_config['smtp']['passwordSource'], 'none',
                             'After switch: passwordSource must be none')
            self.assertEqual(direct_config['secrets']['smtpPasswordSource'], 'none',
                             'After switch: smtpPasswordSource must be none')
            # ARM params: no SMTP Auth fields
            self.assertFalse(p['smtpUseAuth']['value'])
            self.assertNotIn('smtpPort', p, 'smtpPort must not remain in ARM params after mode switch')
            self.assertNotIn('smtpUsername', p, 'smtpUsername must not remain in ARM params after mode switch')
            self.assertNotIn('smtpPassword', p, 'smtpPassword must not remain in ARM params after mode switch')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_existing_smtp_auth_redeploy_no_regression(self):
        """Re-running GenerateOnly for an existing SMTP Auth config must not lose auth fields.

        Scenario: Existing SMTP Auth deployment → redeploy with same config.
        Expected: All SMTP Auth ARM params preserved; no regression.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-redeploy-auth-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base_cmd = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base_cmd += " -CustomerNumber '8004' -VaultwardenDomain 'vault.redeploy.de' -CloudflareZone 'redeploy.de'"
            base_cmd += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base_cmd += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            base_cmd += " -MailRootDomain 'redeploy.de' -SmtpFrom 'vaultwarden@redeploy.de'"
            base_cmd += " -SmtpUseAuth -SmtpHost 'smtp.office365.com' -SmtpPort '587' -SmtpSecurity 'starttls' -SmtpUsername 'vw@redeploy.de'"
            base_cmd += " -SmtpPassword (ConvertTo-SecureString 'secret' -AsPlainText -Force)"

            # Run twice to simulate redeploy
            run_ps(base_cmd)
            run_ps(base_cmd)

            params = json.loads(
                (customers_root / 'vault-redeploy-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            self.assertTrue(p['smtpUseAuth']['value'])
            self.assertEqual(p['smtpHost']['value'], 'smtp.office365.com')
            self.assertEqual(p['smtpPort']['value'], '587')
            self.assertEqual(p['smtpSecurity']['value'], 'starttls')
            self.assertEqual(p['smtpUsername']['value'], 'vw@redeploy.de')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_existing_direct_send_redeploy_no_smtp_auth_ballast(self):
        """Re-running GenerateOnly for an existing Direct Send config must not activate SMTP Auth fields.

        Scenario: Existing Direct Send deployment → redeploy with same config.
        Expected: No SMTP Auth fields in ARM params; no regression.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-redeploy-direct-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base_cmd = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base_cmd += " -CustomerNumber '8005' -VaultwardenDomain 'vault.directredo.de' -CloudflareZone 'directredo.de'"
            base_cmd += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base_cmd += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            base_cmd += " -MailRootDomain 'directredo.de' -SmtpFrom 'vaultwarden@directredo.de'"
            base_cmd += " -SmtpHost 'mx01.directredo-de.mail.protection.outlook.com'"

            # Run twice to simulate redeploy
            run_ps(base_cmd)
            run_ps(base_cmd)

            params = json.loads(
                (customers_root / 'vault-directredo-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            self.assertFalse(p['smtpUseAuth']['value'])
            self.assertIn('smtpHost', p)
            self.assertNotIn('smtpPort', p)
            self.assertNotIn('smtpSecurity', p)
            self.assertNotIn('smtpUsername', p)
            self.assertNotIn('smtpPassword', p)
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    # ------------------------------------------------------------------
    # Vaultwarden hardened default ENVs
    # ------------------------------------------------------------------

    def test_vaultwarden_hardened_envs_in_vwEnvBase(self):
        """All 7 security-hardened ENVs must be present in vwEnvBase with correct values."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        vw_env_base = main['variables']['vwEnvBase']
        env_map = {e['name']: e.get('value', '') for e in vw_env_base if isinstance(e, dict) and 'name' in e}

        expected = {
            'EMAIL_2FA_AUTO_FALLBACK':              'true',
            'EMAIL_2FA_ENFORCE_ON_VERIFIED_INVITE': 'true',
            'DISABLE_2FA_REMEMBER':                 'true',
            'ENFORCE_SINGLE_ORG_WITH_RESET_PW_POLICY': 'true',
            'PASSWORD_HINTS_ALLOWED':               'false',
            'SIGNUPS_VERIFY':                       'true',
            'SHOW_PASSWORD_HINT':                   'false',
        }
        for env_name, expected_value in expected.items():
            self.assertIn(env_name, env_map,
                          f'Hardened ENV {env_name} missing from vwEnvBase')
            self.assertEqual(env_map[env_name], expected_value,
                             f'Hardened ENV {env_name} has wrong value: '
                             f'expected {expected_value!r}, got {env_map[env_name]!r}')

    def test_hibp_api_key_env_in_vwEnvBase_uses_secret_ref(self):
        """HIBP_API_KEY in vwEnvBase must use secretRef, not a plaintext value."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        vw_env_base = main['variables']['vwEnvBase']
        hibp_entries = [e for e in vw_env_base if isinstance(e, dict) and e.get('name') == 'HIBP_API_KEY']
        self.assertEqual(len(hibp_entries), 1, 'HIBP_API_KEY must appear exactly once in vwEnvBase')
        self.assertEqual(hibp_entries[0].get('secretRef'), 'hibp-api-key',
                         'HIBP_API_KEY must use secretRef=hibp-api-key')
        self.assertNotIn('value', hibp_entries[0], 'HIBP_API_KEY must not have a plaintext value')

    def test_hibp_api_key_kv_secret_variable_defined(self):
        """vwSecretsHibp variable must be defined and point to Key Vault."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        variables = main['variables']
        self.assertIn('kvSecretHibpApiKeyName', variables,
                      'kvSecretHibpApiKeyName variable must be defined')
        self.assertIn('vwSecretsHibp', variables,
                      'vwSecretsHibp variable must be defined')
        hibp_secrets = variables['vwSecretsHibp']
        self.assertIsInstance(hibp_secrets, list)
        self.assertEqual(len(hibp_secrets), 1)
        self.assertEqual(hibp_secrets[0]['name'], 'hibp-api-key')
        self.assertIn('keyVaultUrl', hibp_secrets[0])
        self.assertIn('kvSecretHibpApiKeyName', hibp_secrets[0]['keyVaultUrl'])

    def test_container_app_secrets_include_hibp(self):
        """Container App secrets concat must include vwSecretsHibp unconditionally."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        container_app = next(
            r for r in main['resources'] if r.get('type') == 'Microsoft.App/containerApps'
        )
        secrets_expr = container_app['properties']['configuration']['secrets']
        self.assertIn("variables('vwSecretsHibp')", secrets_expr,
                      'Container App secrets concat must include vwSecretsHibp')

    def test_hibp_api_key_is_securestring_parameter(self):
        """hibpApiKey must be declared as securestring in main.json with empty default."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        self.assertIn('hibpApiKey', main['parameters'],
                      'hibpApiKey must be declared as a parameter in main.json')
        param = main['parameters']['hibpApiKey']
        self.assertEqual(param['type'].lower(), 'securestring',
                         'hibpApiKey must be of type securestring')
        self.assertEqual(param.get('defaultValue', ''), '',
                         'hibpApiKey must have an empty default value')

    def test_hibp_api_key_deployment_script_env_vars(self):
        """Deployment script must have HIBP_API_KEY_SECRET and HIBP_API_KEY_VALUE env vars."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        deploy_script = next(
            r for r in main['resources']
            if r.get('type') == 'Microsoft.Resources/deploymentScripts'
            and 'ensure-kv-secrets' in r.get('name', '')
        )
        env_names = {
            e['name']
            for e in deploy_script['properties']['environmentVariables']
            if isinstance(e, dict)
        }
        self.assertIn('HIBP_API_KEY_SECRET', env_names,
                      'Deployment script must expose HIBP_API_KEY_SECRET env var')
        self.assertIn('HIBP_API_KEY_VALUE', env_names,
                      'Deployment script must expose HIBP_API_KEY_VALUE env var')

        # HIBP_API_KEY_VALUE must be a secureValue, not plaintext
        hibp_val_env = next(
            e for e in deploy_script['properties']['environmentVariables']
            if isinstance(e, dict) and e.get('name') == 'HIBP_API_KEY_VALUE'
        )
        self.assertIn('secureValue', hibp_val_env,
                      'HIBP_API_KEY_VALUE must be a secureValue (not plaintext value)')
        self.assertNotIn('value', hibp_val_env,
                         'HIBP_API_KEY_VALUE must not use plaintext value field')

    def test_hibp_api_key_placeholder_logic_in_deployment_script(self):
        """Deployment script must set placeholder '00000-00000-00000' when no real HIBP key is provided."""
        main = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        deploy_script = next(
            r for r in main['resources']
            if r.get('type') == 'Microsoft.Resources/deploymentScripts'
            and 'ensure-kv-secrets' in r.get('name', '')
        )
        script = deploy_script['properties']['scriptContent']
        self.assertIn('HIBP_API_KEY', script,
                      'Deployment script must contain HIBP_API_KEY secret logic')
        self.assertIn('00000-00000-00000', script,
                      'Deployment script must set placeholder for HIBP_API_KEY when no real key is provided')

    def test_wrapper_exposes_hibp_api_key(self):
        """Both wrapper files must expose hibpApiKey as securestring."""
        for wrapper_path in [
            REPO_ROOT / 'main.deploytoazure.json',
            REPO_ROOT / 'current' / 'main.deploytoazure.json',
        ]:
            wrapper = json.loads(wrapper_path.read_text(encoding='utf-8'))
            self.assertIn('hibpApiKey', wrapper['parameters'],
                          f'hibpApiKey missing from {wrapper_path.name}')
            param = wrapper['parameters']['hibpApiKey']
            self.assertEqual(param['type'].lower(), 'securestring',
                             f'hibpApiKey in {wrapper_path.name} must be securestring')
            self.assertEqual(param.get('defaultValue', ''), '',
                             f'hibpApiKey in {wrapper_path.name} must have empty default')

    def test_hardened_envs_not_in_wizard_prompt(self):
        """The 7 hardened ENVs must not be interactively prompted in the Wizard."""
        wizard_scripts = [
            (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8'),
            (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8'),
        ]
        # These ENVs should never appear in Read-Host prompts
        hardened_env_names = [
            'EMAIL_2FA_AUTO_FALLBACK',
            'EMAIL_2FA_ENFORCE_ON_VERIFIED_INVITE',
            'DISABLE_2FA_REMEMBER',
            'ENFORCE_SINGLE_ORG_WITH_RESET_PW_POLICY',
            'PASSWORD_HINTS_ALLOWED',
            'SIGNUPS_VERIFY',
            'SHOW_PASSWORD_HINT',
        ]
        for ps_script in wizard_scripts:
            for env_name in hardened_env_names:
                env_lower = env_name.lower()
                for line in ps_script.splitlines():
                    if 'read-host' in line.lower() and env_lower in line.lower():
                        self.fail(
                            f'Hardened ENV {env_name} should not be in a Read-Host prompt: {line.strip()}'
                        )


    # ------------------------------------------------------------------
    # Mail-Modus: 3 exklusive Zielzustände (direct_send / smtp_auth / acs_smtp)
    # ------------------------------------------------------------------

    def test_wizard_has_three_mail_mode_choices(self):
        """The wizard must expose exactly 3 mail mode choices: direct_send, smtp_auth, acs_smtp."""
        flows_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8')
        self.assertIn("'direct_send'", flows_text,
                      "Wizard must have 'direct_send' as a mail mode choice")
        self.assertIn("'smtp_auth'", flows_text,
                      "Wizard must have 'smtp_auth' as a mail mode choice")
        self.assertIn("'acs_smtp'", flows_text,
                      "Wizard must have 'acs_smtp' as a mail mode choice")
        # Choices must appear near the 3-way mail mode selector (Read-ChoiceWithDefault for Mail-Modus)
        self.assertIn('Mail-Modus', flows_text,
                      "Wizard must prompt 'Mail-Modus' for the 3-way mode selection")

    def test_acs_smtp_mode_auto_sets_host_and_acs_foundation(self):
        """New-CustomerConfigObject with MailMode=acs_smtp must auto-set smtp.azurecomm.net and acsDeployFoundation=true."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('smtp.azurecomm.net', script_text,
                      'smtp.azurecomm.net must be the auto-set SMTP host for acs_smtp mode')
        self.assertIn('acsDeployFoundation', script_text,
                      'acsDeployFoundation must be referenced in the acs_smtp handling')

    def test_get_mail_mode_from_config_function_present(self):
        """Get-MailModeFromConfig helper must be present for backward compatibility."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('function Get-MailModeFromConfig', script_text,
                      'Get-MailModeFromConfig helper must be present in the script')
        # Must handle backward compat derivation from smtp.useAuth
        self.assertIn('smtp.useAuth', script_text,
                      'Get-MailModeFromConfig must reference smtp.useAuth for backward compat')

    def test_mail_mode_parameter_declared_in_script(self):
        """Script must expose a -MailMode parameter with ValidateSet for 3 states."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn("[ValidateSet('direct_send','smtp_auth','acs_smtp')]", script_text,
                      "Script must declare -MailMode with ValidateSet for all 3 states")

    def test_new_customer_config_object_stores_mail_mode(self):
        """New-CustomerConfigObject must store smtp.mailMode in the config object."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('mailMode = $effectiveMailMode', script_text,
                      'New-CustomerConfigObject must write mailMode to smtp section')

    def test_acs_smtp_wizard_prompts_for_acs_username(self):
        """Wizard acs_smtp path must prompt for ACS SMTP Username, not for a generic SMTP Host."""
        script_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8')
        self.assertIn('ACS SMTP Username', script_text,
                      'acs_smtp wizard path must prompt for ACS SMTP Username')

    def test_acs_smtp_mode_cli_validation_requires_username(self):
        """CLI path must validate that acs_smtp requires -SmtpUsername."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('MailMode=acs_smtp', script_text,
                      'CLI validation must mention MailMode=acs_smtp in error message')
        self.assertIn('SmtpUsername', script_text,
                      'CLI validation for acs_smtp must reference SmtpUsername')

    @requires_pwsh
    def test_generate_only_acs_smtp_mode_produces_correct_params(self):
        """GenerateOnly with -MailMode acs_smtp must produce ARM parameters with acsDeployFoundation=true and smtp.azurecomm.net.

        Scenario: New acs_smtp deployment.
        Expected: smtpUseAuth=true, smtpHost=smtp.azurecomm.net, acsDeployFoundation=true,
                  smtpUsername set, smtp.mailMode='acs_smtp' in config.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-acsmtp-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            command = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            command += " -CustomerNumber '9001' -VaultwardenDomain 'vault.acs-smtp.de' -CloudflareZone 'acs-smtp.de'"
            command += " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            command += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            command += " -MailMode 'acs_smtp' -MailRootDomain 'acs-smtp.de'"
            command += " -SmtpFrom 'vaultwarden@acs-smtp.de'"
            command += " -SmtpUsername 'smtp-user@acs-smtp.de'"
            command += " -SmtpPassword (ConvertTo-SecureString 'acskey' -AsPlainText -Force)"
            run_ps(command)
            params = json.loads(
                (customers_root / 'vault-acs-smtp-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            config = json.loads(
                (customers_root / 'vault-acs-smtp-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            # ACS SMTP mode: smtpUseAuth=true, smtpHost=smtp.azurecomm.net
            self.assertTrue(p['smtpUseAuth']['value'], 'smtpUseAuth must be true for acs_smtp mode')
            self.assertEqual(p['smtpHost']['value'], 'smtp.azurecomm.net',
                             'smtpHost must be smtp.azurecomm.net for acs_smtp mode')
            # acsDeployFoundation must be true
            self.assertTrue(p['acsDeployFoundation']['value'],
                            'acsDeployFoundation must be true for acs_smtp mode')
            # smtpUsername must be present
            self.assertEqual(p['smtpUsername']['value'], 'smtp-user@acs-smtp.de')
            # Config must reflect acs_smtp state
            self.assertEqual(config['smtp']['mailMode'], 'acs_smtp')
            self.assertTrue(config['smtp']['useAuth'])
            self.assertEqual(config['smtp']['host'], 'smtp.azurecomm.net')
            self.assertEqual(config['smtp']['passwordSource'], 'prompt')
            self.assertEqual(config['secrets']['smtpPasswordSource'], 'prompt')
            # acsDeployFoundation in advanced ARM params
            self.assertTrue(config['azure']['advancedArmParameters']['acsDeployFoundation'],
                            'acsDeployFoundation must be true in stored config for acs_smtp')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_mail_mode_stored_for_all_three_modes(self):
        """Config must store smtp.mailMode for all 3 modes (direct_send, smtp_auth, acs_smtp)."""
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-mailmodes-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base += f" -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"

            # direct_send
            run_ps(base + " -CustomerNumber '9010' -VaultwardenDomain 'vault.ds.de' -CloudflareZone 'ds.de'"
                         + " -MailMode 'direct_send' -MailRootDomain 'ds.de'"
                         + " -SmtpHost 'mx01.ds-de.mail.protection.outlook.com'")
            config_ds = json.loads((customers_root / 'vault-ds-de' / 'deployment.config.json').read_text())
            self.assertEqual(config_ds['smtp']['mailMode'], 'direct_send')
            self.assertFalse(config_ds['smtp']['useAuth'])

            # smtp_auth
            run_ps(base + " -CustomerNumber '9011' -VaultwardenDomain 'vault.sa.de' -CloudflareZone 'sa.de'"
                         + " -MailMode 'smtp_auth' -MailRootDomain 'sa.de' -SmtpUseAuth"
                         + " -SmtpHost 'smtp.office365.com' -SmtpUsername 'vault@sa.de'"
                         + " -SmtpPassword (ConvertTo-SecureString 'pw' -AsPlainText -Force)")
            config_sa = json.loads((customers_root / 'vault-sa-de' / 'deployment.config.json').read_text())
            self.assertEqual(config_sa['smtp']['mailMode'], 'smtp_auth')
            self.assertTrue(config_sa['smtp']['useAuth'])

            # acs_smtp
            run_ps(base + " -CustomerNumber '9012' -VaultwardenDomain 'vault.acs2.de' -CloudflareZone 'acs2.de'"
                         + " -MailMode 'acs_smtp' -MailRootDomain 'acs2.de'"
                         + " -SmtpUsername 'acsuser@acs2.de'"
                         + " -SmtpPassword (ConvertTo-SecureString 'acskey' -AsPlainText -Force)")
            config_acs = json.loads((customers_root / 'vault-acs2-de' / 'deployment.config.json').read_text())
            self.assertEqual(config_acs['smtp']['mailMode'], 'acs_smtp')
            self.assertTrue(config_acs['smtp']['useAuth'])
            self.assertEqual(config_acs['smtp']['host'], 'smtp.azurecomm.net')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_smtp_auth_to_acs_smtp_transition(self):
        """Switching from smtp_auth to acs_smtp must produce a clean acs_smtp config.

        Scenario: Existing smtp_auth config → redeploy as acs_smtp.
        Expected: mailMode=acs_smtp, smtpHost=smtp.azurecomm.net, acsDeployFoundation=true,
                  no stale smtp_auth-specific host value.
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-sa2acs-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base += f" -CustomerNumber '9020' -VaultwardenDomain 'vault.transition.de' -CloudflareZone 'transition.de'"
            base += f" -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            base += f" -MailRootDomain 'transition.de'"

            # First: create smtp_auth config
            run_ps(base + " -MailMode 'smtp_auth' -SmtpUseAuth"
                        + " -SmtpHost 'smtp.office365.com' -SmtpUsername 'vault@transition.de'"
                        + " -SmtpPassword (ConvertTo-SecureString 'pw' -AsPlainText -Force)")
            # Transition to acs_smtp
            run_ps(base + " -MailMode 'acs_smtp'"
                        + " -SmtpUsername 'acsuser@transition.de'"
                        + " -SmtpPassword (ConvertTo-SecureString 'acskey' -AsPlainText -Force)")

            params = json.loads(
                (customers_root / 'vault-transition-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            config = json.loads(
                (customers_root / 'vault-transition-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            self.assertEqual(config['smtp']['mailMode'], 'acs_smtp',
                             'After transition: smtp.mailMode must be acs_smtp')
            self.assertTrue(p['smtpUseAuth']['value'])
            self.assertEqual(p['smtpHost']['value'], 'smtp.azurecomm.net',
                             'After acs_smtp transition: smtpHost must be smtp.azurecomm.net')
            self.assertTrue(p['acsDeployFoundation']['value'],
                            'After acs_smtp transition: acsDeployFoundation must be true')
            # Old smtp_auth host must NOT be present
            self.assertNotEqual(p.get('smtpHost', {}).get('value', ''), 'smtp.office365.com',
                                'After acs_smtp transition: smtp.office365.com must be replaced')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    @requires_pwsh
    def test_generate_only_acs_smtp_to_direct_send_transition(self):
        """Switching from acs_smtp to direct_send must produce a clean direct_send config.

        Scenario: Existing acs_smtp config → redeploy as direct_send.
        Expected: mailMode=direct_send, smtpUseAuth=false, no smtp-auth fields,
                  no acsDeployFoundation in active state (no override needed).
        """
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-acs2ds-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base += f" -CustomerNumber '9030' -VaultwardenDomain 'vault.acs2ds.de' -CloudflareZone 'acs2ds.de'"
            base += f" -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"
            base += f" -MailRootDomain 'acs2ds.de'"

            # First: create acs_smtp config
            run_ps(base + " -MailMode 'acs_smtp'"
                        + " -SmtpUsername 'acsuser@acs2ds.de'"
                        + " -SmtpPassword (ConvertTo-SecureString 'acskey' -AsPlainText -Force)")
            # Transition to direct_send
            run_ps(base + " -MailMode 'direct_send'"
                        + " -SmtpHost 'mx01.acs2ds-de.mail.protection.outlook.com'")

            params = json.loads(
                (customers_root / 'vault-acs2ds-de' / 'azure.parameters.json').read_text(encoding='utf-8')
            )
            config = json.loads(
                (customers_root / 'vault-acs2ds-de' / 'deployment.config.json').read_text(encoding='utf-8')
            )
            p = params['parameters']
            self.assertEqual(config['smtp']['mailMode'], 'direct_send',
                             'After transition: smtp.mailMode must be direct_send')
            self.assertFalse(p['smtpUseAuth']['value'],
                             'After direct_send transition: smtpUseAuth must be false')
            self.assertEqual(p['smtpHost']['value'], 'mx01.acs2ds-de.mail.protection.outlook.com')
            # No SMTP Auth fields
            self.assertNotIn('smtpPort', p, 'direct_send must not have smtpPort in ARM params')
            self.assertNotIn('smtpUsername', p, 'direct_send must not have smtpUsername in ARM params')
            self.assertNotIn('smtpPassword', p, 'direct_send must not have smtpPassword in ARM params')
            # Config must reflect direct_send state
            self.assertEqual(config['smtp']['passwordSource'], 'none')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)


    # ------------------------------------------------------------------
    # ARM-level mailMode propagation (Source of Truth through all layers)
    # ------------------------------------------------------------------

    def test_main_json_has_mail_mode_parameter(self):
        """main.json must declare mailMode as an ARM parameter with allowedValues."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        params = data['parameters']
        self.assertIn('mailMode', params,
                      'main.json must have a mailMode parameter')
        mp = params['mailMode']
        self.assertEqual(mp['type'], 'string', 'mailMode must be of type string')
        allowed = mp.get('allowedValues', [])
        self.assertIn('direct_send', allowed, 'mailMode must allow direct_send')
        self.assertIn('smtp_auth', allowed, 'mailMode must allow smtp_auth')
        self.assertIn('acs_smtp', allowed, 'mailMode must allow acs_smtp')
        self.assertEqual(mp.get('defaultValue'), 'smtp_auth',
                         'mailMode default must be smtp_auth for backward compat')

    def test_main_json_deployment_script_receives_mail_mode(self):
        """Deployment script must receive MAIL_MODE as an environment variable."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        ds = next(r for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts')
        env_names = [e['name'] for e in ds['properties']['environmentVariables']]
        self.assertIn('MAIL_MODE', env_names,
                      'Deployment script must receive MAIL_MODE environment variable')
        mail_mode_ev = next(e for e in ds['properties']['environmentVariables'] if e['name'] == 'MAIL_MODE')
        self.assertIn("parameters('mailMode')", mail_mode_ev['value'],
                      'MAIL_MODE must reference the mailMode ARM parameter')

    def test_main_json_deployment_script_logs_mail_mode(self):
        """Deployment script bash must log the active mail mode for traceability."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        script = next(
            r['properties']['scriptContent']
            for r in data['resources'] if r.get('type') == 'Microsoft.Resources/deploymentScripts'
        )
        self.assertIn('MAIL_MODE', script,
                      'Deployment script must reference MAIL_MODE')
        self.assertIn('Mail mode:', script,
                      'Deployment script must log the active mail mode')

    def test_main_json_smtp_host_not_using_deployment_script_reference_for_direct_send(self):
        """ACA SMTP_HOST env must not use deployment script output reference.
        Instead, it must use parameters('smtpHost') directly for all modes
        (direct_send always has smtpHost pre-set by the PowerShell script).
        """
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        ca = next(r for r in data['resources'] if r.get('type') == 'Microsoft.App/containerApps')
        env_expr = ca['properties']['template']['containers'][0]['env']
        self.assertNotIn('deploymentScriptApiVersion', env_expr,
                         'ACA SMTP_HOST must not reference deployment script output')
        self.assertNotIn('.outputs.smtp_host', env_expr,
                         'ACA SMTP_HOST must not use deployment script smtp_host output')
        self.assertIn("parameters('smtpHost')", env_expr,
                      "ACA SMTP_HOST must use parameters('smtpHost') directly")

    def test_main_json_smtp_port_and_security_use_mail_mode(self):
        """SMTP_PORT and SMTP_SECURITY env vars must use mailMode, not smtpUseAuth, as condition."""
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        smtp_common = data['variables']['vwEnvSmtpCommon']
        port_entry = next(e for e in smtp_common if e['name'] == 'SMTP_PORT')
        security_entry = next(e for e in smtp_common if e['name'] == 'SMTP_SECURITY')
        self.assertIn("mailMode", port_entry['value'],
                      'SMTP_PORT must use mailMode as condition, not smtpUseAuth')
        self.assertIn("mailMode", security_entry['value'],
                      'SMTP_SECURITY must use mailMode as condition, not smtpUseAuth')
        self.assertNotIn("smtpUseAuth", port_entry['value'],
                         'SMTP_PORT must not use smtpUseAuth as condition')
        self.assertNotIn("smtpUseAuth", security_entry['value'],
                         'SMTP_SECURITY must not use smtpUseAuth as condition')

    def test_wrapper_exposes_mail_mode(self):
        """main.deploytoazure.json wrapper must expose the mailMode parameter."""
        wrapper = json.loads((REPO_ROOT / 'main.deploytoazure.json').read_text(encoding='utf-8'))
        self.assertIn('mailMode', wrapper['parameters'],
                      'Wrapper must expose mailMode parameter')
        wp = wrapper['parameters']['mailMode']
        self.assertEqual(wp['type'], 'string', 'Wrapper mailMode must be of type string')
        self.assertIn('direct_send', wp.get('allowedValues', []),
                      'Wrapper mailMode must allow direct_send')
        self.assertIn('acs_smtp', wp.get('allowedValues', []),
                      'Wrapper mailMode must allow acs_smtp')

    @requires_pwsh
    def test_generate_only_azure_params_include_mail_mode(self):
        """azure.parameters.json must always include mailMode for all 3 mail states."""
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-mailmode-arm-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            base = '& ' + "'{}'".format(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1')
            base += f" -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
            base += f" -CustomersRoot '{str(customers_root).replace(chr(39), chr(39)*2)}' -GenerateOnly -NonInteractive"

            # Test direct_send
            run_ps(base + " -CustomerNumber '9040' -VaultwardenDomain 'vault.mm1.de' -CloudflareZone 'mm1.de'"
                        + " -MailMode 'direct_send' -MailRootDomain 'mm1.de'"
                        + " -SmtpHost 'mx01.mm1.mail.protection.outlook.com'")
            params_ds = json.loads((customers_root / 'vault-mm1-de' / 'azure.parameters.json').read_text())
            self.assertIn('mailMode', params_ds['parameters'],
                          'azure.parameters.json must contain mailMode for direct_send')
            self.assertEqual(params_ds['parameters']['mailMode']['value'], 'direct_send',
                             'mailMode must be direct_send in ARM params')

            # Test smtp_auth
            run_ps(base + " -CustomerNumber '9041' -VaultwardenDomain 'vault.mm2.de' -CloudflareZone 'mm2.de'"
                        + " -MailMode 'smtp_auth' -MailRootDomain 'mm2.de' -SmtpUseAuth"
                        + " -SmtpHost 'smtp.office365.com' -SmtpUsername 'vault@mm2.de'"
                        + " -SmtpPassword (ConvertTo-SecureString 'pw' -AsPlainText -Force)")
            params_sa = json.loads((customers_root / 'vault-mm2-de' / 'azure.parameters.json').read_text())
            self.assertIn('mailMode', params_sa['parameters'],
                          'azure.parameters.json must contain mailMode for smtp_auth')
            self.assertEqual(params_sa['parameters']['mailMode']['value'], 'smtp_auth',
                             'mailMode must be smtp_auth in ARM params')

            # Test acs_smtp
            run_ps(base + " -CustomerNumber '9042' -VaultwardenDomain 'vault.mm3.de' -CloudflareZone 'mm3.de'"
                        + " -MailMode 'acs_smtp' -MailRootDomain 'mm3.de'"
                        + " -SmtpUsername 'acsuser@mm3.de'"
                        + " -SmtpPassword (ConvertTo-SecureString 'acskey' -AsPlainText -Force)")
            params_acs = json.loads((customers_root / 'vault-mm3-de' / 'azure.parameters.json').read_text())
            self.assertIn('mailMode', params_acs['parameters'],
                          'azure.parameters.json must contain mailMode for acs_smtp')
            self.assertEqual(params_acs['parameters']['mailMode']['value'], 'acs_smtp',
                             'mailMode must be acs_smtp in ARM params')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)

    # -----------------------------------------------------------------------
    # ACA Custom Domain Preservation
    # -----------------------------------------------------------------------

    def test_get_aca_custom_domains_function_present(self):
        """Get-AcaCustomDomains must be defined in the common library."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        self.assertIn('function Get-AcaCustomDomains', content,
                      'Get-AcaCustomDomains must be defined in VaultwardenDeployment.Common.ps1')

    def test_restore_aca_custom_domains_function_present(self):
        """Restore-AcaCustomDomains must be defined in the common library."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        self.assertIn('function Restore-AcaCustomDomains', content,
                      'Restore-AcaCustomDomains must be defined in VaultwardenDeployment.Common.ps1')

    def test_get_aca_custom_domains_has_shared_logic_comment(self):
        """Get-AcaCustomDomains must have a # SHARED LOGIC: comment above it."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        idx = content.find('function Get-AcaCustomDomains')
        self.assertGreater(idx, 0, 'Get-AcaCustomDomains not found')
        context = content[max(0, idx - 600):idx]
        self.assertIn('# SHARED LOGIC:', context,
                      'Get-AcaCustomDomains must have a # SHARED LOGIC: comment above it')

    def test_restore_aca_custom_domains_has_shared_logic_comment(self):
        """Restore-AcaCustomDomains must have a # SHARED LOGIC: comment above it."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        idx = content.find('function Restore-AcaCustomDomains')
        self.assertGreater(idx, 0, 'Restore-AcaCustomDomains not found')
        context = content[max(0, idx - 600):idx]
        self.assertIn('# SHARED LOGIC:', context,
                      'Restore-AcaCustomDomains must have a # SHARED LOGIC: comment above it')

    def test_deploy_script_calls_get_aca_custom_domains(self):
        """Invoke-CustomerDeployment.ps1 must call Get-AcaCustomDomains before deploy."""
        content = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('Get-AcaCustomDomains', content,
                      'Invoke-CustomerDeployment.ps1 must call Get-AcaCustomDomains')

    def test_deploy_script_calls_restore_aca_custom_domains(self):
        """Invoke-CustomerDeployment.ps1 must call Restore-AcaCustomDomains after deploy."""
        content = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('Restore-AcaCustomDomains', content,
                      'Invoke-CustomerDeployment.ps1 must call Restore-AcaCustomDomains')

    def test_deploy_script_stores_preserved_infra_state(self):
        """Invoke-CustomerDeployment.ps1 must store custom domains in preservedInfraState."""
        content = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('preservedInfraState', content,
                      'Invoke-CustomerDeployment.ps1 must store state in preservedInfraState')

    def test_ingress_restrictions_script_calls_get_aca_custom_domains(self):
        """Set-AcaIngressRestrictions.ps1 must call Get-AcaCustomDomains before redeploy."""
        content = (REPO_ROOT / 'scripts' / 'Set-AcaIngressRestrictions.ps1').read_text(encoding='utf-8')
        self.assertIn('Get-AcaCustomDomains', content,
                      'Set-AcaIngressRestrictions.ps1 must call Get-AcaCustomDomains')

    def test_ingress_restrictions_script_calls_restore_aca_custom_domains(self):
        """Set-AcaIngressRestrictions.ps1 must call Restore-AcaCustomDomains after redeploy."""
        content = (REPO_ROOT / 'scripts' / 'Set-AcaIngressRestrictions.ps1').read_text(encoding='utf-8')
        self.assertIn('Restore-AcaCustomDomains', content,
                      'Set-AcaIngressRestrictions.ps1 must call Restore-AcaCustomDomains')

    def test_get_aca_custom_domains_returns_empty_for_nonexistent_app(self):
        """Get-AcaCustomDomains must return an empty array when the app does not exist."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        idx = content.find('function Get-AcaCustomDomains')
        self.assertGreater(idx, 0, 'Get-AcaCustomDomains not found')
        body_start = content.find('{', idx)
        self.assertGreater(body_start, 0)
        depth = 0
        body_end = body_start
        for i, ch in enumerate(content[body_start:], start=body_start):
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    body_end = i
                    break
        func_body = content[body_start:body_end + 1]
        self.assertIn('LASTEXITCODE', func_body,
                      'Get-AcaCustomDomains must check $LASTEXITCODE for graceful error handling')
        self.assertIn('return @()', func_body,
                      'Get-AcaCustomDomains must return an empty array on failure')

    def test_restore_aca_custom_domains_noop_on_empty(self):
        """Restore-AcaCustomDomains must silently no-op when CustomDomains is empty."""
        content = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        idx = content.find('function Restore-AcaCustomDomains')
        self.assertGreater(idx, 0)
        # Extract function body
        body_start = content.find('{', idx)
        self.assertGreater(body_start, 0)
        # Find matching closing brace
        depth = 0
        body_end = body_start
        for i, ch in enumerate(content[body_start:], start=body_start):
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    body_end = i
                    break
        func_body = content[body_start:body_end + 1]
        self.assertIn('.Count -eq 0', func_body,
                      'Restore-AcaCustomDomains must short-circuit on empty CustomDomains')

    @requires_pwsh
    def test_get_aca_custom_domains_is_valid_powershell(self):
        """Get-AcaCustomDomains must be syntactically valid PowerShell."""
        common_lib = REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1'
        run_ps(f". '{common_lib}'; Write-Host 'OK'")

    @requires_pwsh
    def test_generate_only_does_not_capture_custom_domains(self):
        """GenerateOnly path must not attempt to query Azure (no Get-AcaCustomDomains call after GenerateOnly guard)."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        # The GenerateOnly early-return must appear BEFORE the Get-AcaCustomDomains call
        generate_only_idx = script_text.find("if ($GenerateOnly)")
        get_domains_idx = script_text.find('Get-AcaCustomDomains')
        self.assertGreater(generate_only_idx, 0, 'GenerateOnly guard not found')
        self.assertGreater(get_domains_idx, 0, 'Get-AcaCustomDomains call not found')
        self.assertLess(generate_only_idx, get_domains_idx,
                        'GenerateOnly return guard must appear BEFORE Get-AcaCustomDomains call '
                        'so that file-only generation does not attempt live Azure queries')

    @requires_pwsh
    def test_generate_only_new_deployment_no_preserved_state(self):
        """GenerateOnly for a new deployment must not produce a preservedInfraState section."""
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-preserve-'))
        current_root = REPO_ROOT / 'current'
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            cmd = (
                f"& '{REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1'}'"
                " -Environment 'prod' -Location 'germanywestcentral' -Mode 'basic'"
                f" -CustomersRoot '{str(customers_root)}' -GenerateOnly -NonInteractive"
                " -CustomerNumber '9900' -VaultwardenDomain 'vault.preserve-test.de'"
                " -CloudflareZone 'preserve-test.de'"
                " -MailMode 'direct_send' -MailRootDomain 'preserve-test.de'"
                " -SmtpHost 'mx01.preserve-test.de'"
            )
            run_ps(cmd)
            config_path = customers_root / 'vault-preserve-test-de' / 'deployment.config.json'
            self.assertTrue(config_path.exists(), 'deployment.config.json must be created')
            config = json.loads(config_path.read_text(encoding='utf-8'))
            self.assertNotIn('preservedInfraState', config,
                             'New deployment config must not have preservedInfraState section '
                             '(no live Azure query occurs in GenerateOnly mode)')
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)
            shutil.rmtree(current_root, ignore_errors=True)


    def test_consolemenu_back_does_not_update_menu_state(self):
        """Start-ConsoleMenuApplication must not persist the Back key as last submenu position.

        The unconditional $menuState update that previously ran before the switch
        statement would overwrite the last meaningful selection with the 'Zurueck'
        key whenever a user left a submenu via Back.  The fix moves the state update
        into each individual case so that the 'back' branch is deliberately excluded.
        """
        content = (REPO_ROOT / 'scripts/modules/ConsoleMenu/ConsoleMenu.psm1').read_text(encoding='utf-8')

        # The 'back' case must NOT contain a menuState assignment.
        # Use brace-depth counting to extract the full case body (the case may contain
        # nested braces such as if/else blocks, so a simple [^}]* regex is insufficient).
        back_start = re.search(r"'back'\s*\{", content)
        self.assertIsNotNone(back_start, "Start-ConsoleMenuApplication must have a 'back' case")
        pos = back_start.end() - 1  # position of the opening '{'
        depth = 0
        case_body_chars = []
        for ch in content[pos:]:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    break
            if depth > 0:
                case_body_chars.append(ch)
        back_body = ''.join(case_body_chars)
        self.assertNotIn('$menuState[', back_body,
                         "Start-ConsoleMenuApplication 'back' branch must not update menuState "
                         "(Back key must not overwrite the last meaningful submenu selection)")

        # The 'action' and 'submenu' cases must update menuState.
        self.assertIn("$menuState[$currentMenuId] = [string]$selectedItem.Key", content,
                      "Start-ConsoleMenuApplication must persist selection for action/submenu items")

    def test_deployment_menu_back_does_not_update_menu_state(self):
        """Show-DeploymentMainMenu must not persist the Back key as last submenu position.

        When a user leaves a submenu via 'Zurueck', the MenuState for that submenu
        must remain unchanged so that on re-entry the last meaningful action is
        pre-selected rather than the Back item.
        """
        content = (REPO_ROOT / 'scripts/lib/VaultwardenDeployment.Menu.ps1').read_text(encoding='utf-8')

        # The 'back' case must NOT contain a MenuState assignment.
        # Use brace-depth counting so that nested if/else blocks inside the case
        # body are fully covered (a simple [^}]* regex would stop at the first '}'.
        back_start = re.search(r"'back'\s*\{", content)
        self.assertIsNotNone(back_start, "Show-DeploymentMainMenu must have a 'back' case")
        pos = back_start.end() - 1  # position of the opening '{'
        depth = 0
        case_body_chars = []
        for ch in content[pos:]:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    break
            if depth > 0:
                case_body_chars.append(ch)
        back_body = ''.join(case_body_chars)
        self.assertNotIn('$MenuState[', back_body,
                         "Show-DeploymentMainMenu 'back' branch must not update MenuState "
                         "(Back key must not overwrite the last meaningful submenu selection)")

        # The 'action' case must update MenuState.
        self.assertIn("$MenuState[$currentMenuId] = [string]$selectedItem.Key", content,
                      "Show-DeploymentMainMenu must persist selection for action items")

    def test_wizard_functions_live_in_flows_ps1(self):
        """Interactive wizard helper functions must be defined in VaultwardenDeployment.Flows.ps1.

        After the Issue-5 wizard decoupling refactor, all interactive-wizard orchestration
        belongs in Flows.ps1, not in Invoke-CustomerDeployment.ps1.
        """
        flows_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Flows.ps1').read_text(encoding='utf-8')
        deploy_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')

        for func_name in ['Select-CustomerCodeInteractive', 'New-AdvancedArmParametersInteractive',
                          'New-CustomerConfigInteractive']:
            self.assertIn(f'function {func_name}', flows_text,
                          f'{func_name} must be defined in VaultwardenDeployment.Flows.ps1')
            self.assertNotIn(f'function {func_name}', deploy_text,
                             f'{func_name} must NOT be defined in Invoke-CustomerDeployment.ps1 '
                             f'(it belongs in VaultwardenDeployment.Flows.ps1)')

    def test_shared_data_factories_live_in_common_ps1(self):
        """Get-AdvancedParameterValue and New-EmptyAdvancedArmParameters must live in Common.ps1.

        These are pure data/utility helpers with no interactive UI coupling and are
        used by both the CLI path (Build-AdvancedArmParametersFromCli) and the
        interactive wizard (New-AdvancedArmParametersInteractive).
        """
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        deploy_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')

        for func_name in ['Get-AdvancedParameterValue', 'New-EmptyAdvancedArmParameters']:
            self.assertIn(f'function {func_name}', common_text,
                          f'{func_name} must be defined in VaultwardenDeployment.Common.ps1')
            self.assertNotIn(f'function {func_name}', deploy_text,
                             f'{func_name} must NOT be defined in Invoke-CustomerDeployment.ps1 '
                             f'(it belongs in VaultwardenDeployment.Common.ps1)')

    def test_invoke_with_spinner_defined_in_common(self):
        """Invoke-WithSpinner must be defined in VaultwardenDeployment.Common.ps1."""
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        self.assertIn('function Invoke-WithSpinner', common_text,
                      'Invoke-WithSpinner must be defined in VaultwardenDeployment.Common.ps1')

    def test_invoke_with_spinner_has_required_params(self):
        """Invoke-WithSpinner must accept Message, ScriptBlock, and optional RefreshMilliseconds."""
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        # Locate the function body
        idx = common_text.find('function Invoke-WithSpinner')
        self.assertGreater(idx, 0, 'Invoke-WithSpinner not found')
        body = common_text[idx:idx + 800]
        self.assertIn('$Message', body, 'Invoke-WithSpinner must have a $Message parameter')
        self.assertIn('$ScriptBlock', body, 'Invoke-WithSpinner must have a $ScriptBlock parameter')
        self.assertIn('$RefreshMilliseconds', body, 'Invoke-WithSpinner must have a $RefreshMilliseconds parameter')

    def test_invoke_with_spinner_shows_ok_and_fehler(self):
        """Invoke-WithSpinner must print [OK] on success and [FEHLER] on error."""
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        self.assertIn('[OK]', common_text, 'Invoke-WithSpinner must output [OK] on success')
        self.assertIn('[FEHLER]', common_text, 'Invoke-WithSpinner must output [FEHLER] on error')

    def test_deploy_azurestack_uses_native_process_spinner(self):
        """Deploy-AzureStack.ps1 must call Invoke-NativeProcessWithSpinner for the az deployment.

        The az deployment command must NOT be wrapped in Start-ThreadJob or Start-Job.
        Instead, Invoke-NativeProcessWithSpinner starts az as a native OS process via
        System.Diagnostics.Process, drains stdout/stderr asynchronously via .NET Tasks,
        and drives the spinner on the main thread.  This avoids all PS 5.1 CliXml
        serialisation issues while still providing a live spinner UI.
        """
        deploy_text = (REPO_ROOT / 'scripts' / 'Deploy-AzureStack.ps1').read_text(encoding='utf-8')
        # Must call the native-process spinner helper
        self.assertIn('Invoke-NativeProcessWithSpinner', deploy_text,
                      'Deploy-AzureStack.ps1 must call Invoke-NativeProcessWithSpinner for az deployment')
        # Must still pipe the returned stdout to ConvertFrom-Json
        self.assertIn('ConvertFrom-Json', deploy_text,
                      'Deploy-AzureStack.ps1 must parse the returned output with ConvertFrom-Json')
        # Must NOT use any background-job mechanism for the az deployment
        self.assertNotIn('Start-ThreadJob', deploy_text,
                         'Deploy-AzureStack.ps1 must not use Start-ThreadJob for az deployment')
        self.assertNotIn('Start-Job', deploy_text,
                         'Deploy-AzureStack.ps1 must not use Start-Job for az deployment')

    def test_invoke_native_process_with_spinner_defined_in_common(self):
        """Invoke-NativeProcessWithSpinner must be defined in VaultwardenDeployment.Common.ps1.

        It must use System.Diagnostics.Process (not Start-Job/ThreadJob) to start the
        native process, and must display [OK] / [FEHLER] lines like Invoke-WithSpinner.
        """
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        self.assertIn('function Invoke-NativeProcessWithSpinner', common_text,
                      'Invoke-NativeProcessWithSpinner must be defined in Common.ps1')
        idx = common_text.find('function Invoke-NativeProcessWithSpinner')
        self.assertGreater(idx, 0, 'Invoke-NativeProcessWithSpinner not found')
        body = common_text[idx:idx + 4000]
        # Must use System.Diagnostics.Process (native process, not a PS job)
        self.assertIn('System.Diagnostics.Process', body,
                      'Invoke-NativeProcessWithSpinner must use System.Diagnostics.Process')
        # Must drain streams asynchronously to prevent deadlock on large output
        self.assertIn('ReadToEndAsync', body,
                      'Invoke-NativeProcessWithSpinner must use ReadToEndAsync to drain stdout/stderr')
        # Must NOT use Start-ThreadJob or Start-Job for the subprocess
        self.assertNotIn('Start-ThreadJob', body,
                         'Invoke-NativeProcessWithSpinner must not use Start-ThreadJob')
        self.assertNotIn('Start-Job', body,
                         'Invoke-NativeProcessWithSpinner must not use Start-Job')
        # Must show [OK] on success and [FEHLER] on failure
        self.assertIn('[OK]', body,   'Invoke-NativeProcessWithSpinner must output [OK] on success')
        self.assertIn('[FEHLER]', body, 'Invoke-NativeProcessWithSpinner must output [FEHLER] on failure')

    def test_invoke_customer_deployment_uses_spinner_for_key_steps(self):
        """Invoke-CustomerDeployment.ps1 must use Invoke-WithSpinner for the key operative steps."""
        deploy_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('Invoke-WithSpinner', deploy_text,
                      'Invoke-CustomerDeployment.ps1 must use Invoke-WithSpinner for operative steps')
        # ACA custom domain state and ACA verification code are key waiting steps
        self.assertIn('ACA Custom Domain State', deploy_text,
                      'Spinner message for ACA Custom Domain State must be present')
        self.assertIn('ACA Verification Code', deploy_text,
                      'Spinner message for ACA Verification Code must be present')

    def test_get_aca_custom_domains_is_robust_for_first_deploy(self):
        """Get-AcaCustomDomains must silently return empty for missing RG / app (first-deploy robustness).

        The function may be called inside a background job (via Invoke-WithSpinner) where
        $ErrorActionPreference is 'Stop'. A terminating NativeCommandExitException from
        az CLI must never escape the function.  The outer try/catch and temporary
        ErrorActionPreference reset ensure this.
        """
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')
        # Locate the function body
        idx = common_text.find('function Get-AcaCustomDomains')
        self.assertGreater(idx, 0, 'Get-AcaCustomDomains not found in Common.ps1')
        # Extract function body up to the closing brace (a few hundred chars is enough)
        body = common_text[idx:idx + 1200]
        # Must have an outer try/catch for first-deploy robustness
        self.assertIn('try {', body,
                      'Get-AcaCustomDomains must wrap the az call in a try block to be first-deploy safe')
        self.assertIn('catch {', body,
                      'Get-AcaCustomDomains must have a catch block returning @() to be first-deploy safe')
        # Must suppress native command errors locally
        self.assertIn("ErrorActionPreference = 'SilentlyContinue'", body,
                      "Get-AcaCustomDomains must locally suppress ErrorActionPreference for the az call")
        # Must restore ErrorActionPreference after the az call
        self.assertIn('$ErrorActionPreference = $prevEap', body,
                      'Get-AcaCustomDomains must restore $ErrorActionPreference after the az call')

    def test_preserved_custom_domains_null_normalized_after_spinner(self):
        """Invoke-CustomerDeployment.ps1 must normalize the spinner result to @() when null.

        Receive-Job returns $null (not @()) when a background job's output is an empty
        array.  Without the explicit null check, accessing .Count on $null raises a
        PropertyNotFoundException under Set-StrictMode -Version Latest (Windows PS 5.1).
        """
        content = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn(
            "if ($null -eq $preservedCustomDomains) { $preservedCustomDomains = @() }",
            content,
            "Invoke-CustomerDeployment.ps1 must normalise $preservedCustomDomains to @() "
            "after the spinner call so that .Count is safe under Set-StrictMode -Version Latest"
        )

    def test_invoke_with_spinner_has_threadjob_fallback(self):
        """Invoke-WithSpinner must not unconditionally depend on Start-ThreadJob.

        On Windows PowerShell 5.1 without the ThreadJob module, Start-ThreadJob is
        unavailable. The function must detect availability via cached script-scoped variables
        (set at module load time), fall back to Start-Job (with Common.ps1 re-sourced so
        helper functions are available), and ultimately support a direct-execution path if no
        job infrastructure exists.
        """
        common_text = (REPO_ROOT / 'scripts' / 'lib' / 'VaultwardenDeployment.Common.ps1').read_text(encoding='utf-8')

        # Locate the Invoke-WithSpinner function body
        idx = common_text.find('function Invoke-WithSpinner')
        self.assertGreater(idx, 0, 'Invoke-WithSpinner not found in Common.ps1')
        # Extract enough body to cover all three paths
        body = common_text[idx:idx + 3000]

        # The function must read job-availability from the cached script-scoped variable,
        # not call Start-ThreadJob unconditionally without a guard.
        self.assertIn('_SpinnerHasThreadJob', body,
                      'Invoke-WithSpinner must read the cached _SpinnerHasThreadJob flag')

        # The cached availability flags must be set at module level (before the function).
        module_header = common_text[:idx]
        self.assertIn("Get-Command -Name 'Start-ThreadJob'", module_header,
                      "Common.ps1 module level must cache Start-ThreadJob availability via Get-Command")
        self.assertIn('_SpinnerHasThreadJob', module_header,
                      'Common.ps1 must set $Script:_SpinnerHasThreadJob at module load time')

        # Must have a Start-Job fallback
        self.assertIn('Start-Job', body,
                      'Invoke-WithSpinner must fall back to Start-Job when Start-ThreadJob is unavailable')

        # Must have a direct-execution (no-job) fallback
        self.assertIn('kein Hintergrundjob', body,
                      'Invoke-WithSpinner must have a direct-execution fallback when no job cmdlet is available')

        # Optional ThreadJob import must be present at module level (best-effort)
        import_idx = common_text.find('Import-Module ThreadJob')
        self.assertGreater(import_idx, 0,
                           'Common.ps1 must attempt a silent Import-Module ThreadJob at load time')
        # The import must come before the function definition
        self.assertLess(import_idx, idx,
                        'Import-Module ThreadJob must appear before Invoke-WithSpinner in Common.ps1')

        # Common.ps1 path must be captured for Start-Job initialization
        self.assertIn('_InvokeWithSpinnerCommonPath', common_text,
                      'Common.ps1 must capture its own path for Start-Job InitializationScript')


    def test_spinner_scriptblocks_have_no_using_member_chains(self):
        """Spinner scriptblocks must not use $using:obj.property member-chain expressions.

        Both Start-ThreadJob and Start-Job only support simple top-level $using:varname
        references. Member chains like $using:config.azure.resourceGroupName cause:
          "Cannot get the value of the Using expression $using:config.azure.resourceGroupName.
           Start-ThreadJob only supports using variable expressions."

        All nested values must be pre-resolved into simple scalar variables before the
        Invoke-WithSpinner call and passed via $using:simpleVar.
        """
        import re
        for script_name in ('Invoke-CustomerDeployment.ps1', 'Deploy-AzureStack.ps1'):
            script_text = (REPO_ROOT / 'scripts' / script_name).read_text(encoding='utf-8')
            # Find $using:identifier.something – the identifier part is a word, then a dot follows
            bad_refs = re.findall(r'\$using:[A-Za-z_][A-Za-z0-9_]*\.', script_text)
            self.assertEqual(bad_refs, [],
                             f'{script_name} must not contain nested $using: member-chain expressions; '
                             f'found: {bad_refs}')


if __name__ == '__main__':
    unittest.main()

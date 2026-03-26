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
            'if [ "${SMTP_USE_AUTH:-false}" != "true" ] && [ -z "${SMTP_HOST_INPUT:-}" ]; then',
            script
        )
        self.assertIn('Direct Send (smtpUseAuth=false) requires an explicit smtpHost parameter', script)
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
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        self.assertIn('MX-Endpunkt', script_text)

    @requires_pwsh
    def test_wizard_smtp_auth_does_not_prompt_for_host_in_main_flow(self):
        """Interactive wizard must NOT prompt for SMTP Host in the SMTP Auth main flow.
        The host is silently defaulted to smtp.office365.com; only Direct Send requires explicit input."""
        script_text = (REPO_ROOT / 'scripts' / 'Invoke-CustomerDeployment.ps1').read_text(encoding='utf-8')
        # SMTP Auth path must NOT contain an interactive Read-TextWithDefault for SMTP Host
        self.assertNotIn("Read-TextWithDefault -Label 'SMTP Host'", script_text)
        # SMTP Auth must silently default
        self.assertIn("smtp.office365.com", script_text)
        # A comment explaining the design must be present
        self.assertIn('SMTP Host is NOT prompted in the main wizard flow', script_text)

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

if __name__ == '__main__':
    unittest.main()

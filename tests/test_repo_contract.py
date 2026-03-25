import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PWSH = pathlib.Path('/mnt/data/work/pwsh/pwsh')

class RepoContractTests(unittest.TestCase):
    def test_main_json_has_dual_mode_parameters(self):
        data = json.loads((REPO_ROOT / 'main.json').read_text(encoding='utf-8'))
        self.assertIn('edgeMode', data['parameters'])
        self.assertIn('enableIngressIpRestrictions', data['parameters'])
        self.assertIn('ingressAllowedCidrs', data['parameters'])
        outputs = data['outputs']
        self.assertIn('containerAppEnvironmentName', outputs)
        self.assertIn('containerAppName', outputs)

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
            subprocess.run([str(PWSH), '-NoProfile', '-Command', parser_command], check=True, capture_output=True, text=True)

    def test_generate_only_cloudflare_customer_files(self):
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-'))
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            cmd = [
                str(PWSH), '-NoProfile', '-File', str(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1'),
                '-CustomerCode', 'kunde01',
                '-ResourceGroupName', 'rg-kunde01-vaultwarden',
                '-Hostname', 'vault.kunde01.example.com',
                '-ZoneName', 'example.com',
                '-Environment', 'prod',
                '-Location', 'germanywestcentral',
                '-Mode', 'cloudflare-managed',
                '-CustomersRoot', str(customers_root),
                '-GenerateOnly',
                '-NonInteractive',
                '-MailRootDomain', 'example.com',
                '-SmtpFrom', 'vaultwarden@example.com',
            ]
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            config_path = customers_root / 'kunde01' / 'deployment.config.json'
            params_path = customers_root / 'kunde01' / 'azure.parameters.json'
            self.assertTrue(config_path.exists())
            self.assertTrue(params_path.exists())
            config = json.loads(config_path.read_text(encoding='utf-8'))
            params = json.loads(params_path.read_text(encoding='utf-8'))
            self.assertEqual(config['edge']['mode'], 'cloudflare-managed')
            self.assertEqual(params['parameters']['edgeMode']['value'], 'cloudflare-managed')
            self.assertEqual(params['parameters']['customHostname']['value'], 'vault.kunde01.example.com')
            self.assertFalse(params['parameters']['enableIngressIpRestrictions']['value'])
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)

    def test_generate_only_basic_customer_files(self):
        temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vw-test-basic-'))
        try:
            customers_root = temp_root / 'customers'
            customers_root.mkdir(parents=True, exist_ok=True)
            cmd = [
                str(PWSH), '-NoProfile', '-File', str(REPO_ROOT / 'scripts/Invoke-CustomerDeployment.ps1'),
                '-CustomerCode', 'basic01',
                '-ResourceGroupName', 'rg-basic01-vaultwarden',
                '-Hostname', 'vault.basic01.example.com',
                '-ZoneName', 'example.com',
                '-Environment', 'test',
                '-Location', 'germanywestcentral',
                '-Mode', 'basic',
                '-CustomersRoot', str(customers_root),
                '-GenerateOnly',
                '-NonInteractive',
                '-MailRootDomain', 'example.com',
                '-SmtpFrom', 'vaultwarden@example.com',
            ]
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            config = json.loads((customers_root / 'basic01' / 'deployment.config.json').read_text(encoding='utf-8'))
            self.assertEqual(config['edge']['mode'], 'basic')
            self.assertFalse(config['edge']['lockOriginToCloudflare'])
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)

if __name__ == '__main__':
    unittest.main()

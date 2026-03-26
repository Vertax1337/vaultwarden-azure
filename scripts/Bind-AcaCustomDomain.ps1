[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiToken,
    [Parameter(Mandatory)][string]$ZoneId,
    [Parameter(Mandatory)][string]$Hostname,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$ContainerAppName,
    [Parameter(Mandatory)][string]$EnvironmentName,
    [string]$ArtifactsRoot,
    [int]$RequestedValidityDays = 5475,
    [int]$RetryCount = 12,
    [int]$RetryDelaySeconds = 15,
    [string]$CertificateName
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')
Test-AzCliPresent
Test-OpenSslPresent

if (-not $CertificateName) {
    $CertificateName = ('cf-origin-{0}' -f ($Hostname -replace '[^a-zA-Z0-9-]', '-'))
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('vw-cf-cert-' + [Guid]::NewGuid().ToString('N'))
Ensure-Directory -Path $tempRoot | Out-Null
$csrPath = Join-Path $tempRoot 'origin.csr'
$keyPath = Join-Path $tempRoot 'origin.key'
$crtPath = Join-Path $tempRoot 'origin.crt'
$pfxPath = Join-Path $tempRoot 'origin.pfx'
$pfxPassword = New-RandomPlaintextSecret -Bytes 24

try {
    Write-Step 'Origin-CSR wird erstellt.'
    & openssl req -new -newkey rsa:2048 -nodes -keyout $keyPath -out $csrPath -subj ('/CN=' + $Hostname) -addext ('subjectAltName=DNS:' + $Hostname) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'openssl req failed.' }

    $csr = Get-Content -LiteralPath $csrPath -Raw -Encoding UTF8
    Write-Step 'Cloudflare Origin-CA-Zertifikat wird erzeugt.'
    $certResult = Invoke-CloudflareApi -Method POST -Path '/certificates' -ApiToken $ApiToken -Body @{
        csr = $csr
        hostnames = @($Hostname)
        request_type = 'origin-rsa'
        requested_validity = $RequestedValidityDays
    }
    [System.IO.File]::WriteAllText($crtPath, $certResult.certificate, [System.Text.UTF8Encoding]::new($false))

    Write-Step 'PFX für Azure Container Apps wird gebaut.'
    & openssl pkcs12 -export -out $pfxPath -inkey $keyPath -in $crtPath -passout ('pass:' + $pfxPassword) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'openssl pkcs12 failed.' }

    for ($i = 1; $i -le $RetryCount; $i++) {
        try {
            Write-Step ("Custom Hostname wird in ACA angelegt (Versuch {0}/{1})." -f $i, $RetryCount)
            az containerapp hostname add -g $ResourceGroupName -n $ContainerAppName --hostname $Hostname --only-show-errors | Out-Null
            break
        }
        catch {
            if ($i -eq $RetryCount) { throw }
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    Write-Step 'Zertifikat wird in das ACA-Environment hochgeladen.'
    $uploadJson = az containerapp env certificate upload -g $ResourceGroupName --name $EnvironmentName --certificate-file $pfxPath --certificate-name $CertificateName --password $pfxPassword --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) { throw 'Certificate upload failed.' }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $upload = $uploadJson | ConvertFrom-Json -Depth 20
    } else {
        $upload = $uploadJson | ConvertFrom-Json
    }
    $certificateId = if ($upload.id) { $upload.id } else { $upload.properties.id }

    Write-Step 'Hostname wird an das Zertifikat gebunden.'
    az containerapp hostname bind -g $ResourceGroupName -n $ContainerAppName --hostname $Hostname --environment $EnvironmentName --certificate $certificateId --only-show-errors | Out-Null

    $result = [ordered]@{
        hostname = $Hostname
        certificateId = $certificateId
        certificateName = $CertificateName
        cloudflareOriginCertificateId = $certResult.id
        certificateExpiresOn = $certResult.expires_on
        boundAt = (Get-Date).ToString('o')
    }
    if ($ArtifactsRoot) {
        Save-JsonUtf8 -Data $result -Path (Join-Path $ArtifactsRoot 'cloudflare-origin-certificate.json')
    }
    $result
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

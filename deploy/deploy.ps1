[CmdletBinding(SupportsShouldProcess = $true)]
Param (
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [ValidatePattern("[a-zA-Z0-9\-]{3,24}")]
    [string] $AppName = "linky",

    [Parameter(Mandatory = $true)] 
    [ValidateSet("dev", "prod")]
    [string] $Environment,

    [Parameter(Mandatory = $true)] 
    [string] $SubscriptionId,

    [ValidateSet("Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS", "Standard_GZRS", "Standard_RAGZRS")]
    [string] $StorageSku = "Standard_LRS",

    [string] $XAuthSecretName = "XAuthHeaderValue",

    # Define the deployer OID that's used to create a Key Vault access policy.
    # If not set, this script will attempt to look up the OID based on the Get-AzContext.
    [string] $deployerOid
)

Import-Module (Join-Path $PSScriptRoot "./functions/functions.psm1") -Force

function Get-KeyVaultArmParameters([bool] $kvExists, [string] $tenantId) {
    if (-not $deployerOid) {
        $deployerOid = Get-CurrentUserAzureAdObjectId -tenantId $tenantId;
    }

    $params = @{
        "appBaseName"       = $AppName;
        "environmentSuffix" = $Environment;
        "deployerOid"       = $deployerOid
        "keyVaultExists"    = $kvExists;
    }

    return $params;
}

function Get-ArmParameters([string] $xAuthSecretUri, [string]$keyVaultName) {
    $params = @{
        "appBaseName"       = $AppName;
        "environmentSuffix" = $Environment;
        "storageSku" = $StorageSku;
        "XAuthSecretResource" = $xAuthSecretUri;
        "keyVaultName" = $keyVaultName;
    }

    return $params;
}

###############################################################################
## Start of script
###############################################################################

if ($VerbosePreference -eq "SilentlyContinue" -and $Env:SYSTEM_DEBUG) {
    #haven't passed -Verbose but do have SYSTEM_DEBUG set, so upgrade verbosity
    $VerbosePreference = "Continue"
}

if (-not $pscmdlet.ShouldProcess("$AppName", "Deploy with powershell")) {
    Write-Verbose "-WhatIf is set, will not execute deployment."

    Write-Host "Deploy would proceed with the following parameters"
    $PSBoundParameters | Format-Table | Out-String | Write-Host
}
else {
    $PSBoundParameters | Format-Table | Out-String | Write-Verbose
    
    ###############################################################################
    ## Ensure we're using the expected subscription
    ###############################################################################

    $context = Get-AzContext
    if (-not $context) {
        throw "Execute Connect-AzAccount and try again"
    }

    if ($context.Subscription.Id -ne $SubscriptionId) {
        $context = Set-AzContext -SubscriptionId $SubscriptionId
    }

    $tenantId = $context.Tenant.Id

    ###############################################################################
    ## ARM deployment
    ###############################################################################

    Write-Host "ARM deployment to Resource Group '$ResourceGroupName'..."
    $expectedKvName = "$AppName-$Environment-kv".ToLowerInvariant()
    Write-Verbose "Testing existence of Key Vault '$expectedKvName'"

    $kvExists = [bool]$(Get-AzKeyVault -ResourceGroupName $ResourceGroupName -Name $expectedKvName)
    Write-Verbose "Key Vault '$expectedKvName' exists : $kvExists"

    $kvArmParameters = Get-KeyVaultArmParameters -kvExists $kvExists -tenantId $tenantId
    $templatePath = Join-Path $PSScriptRoot "./keyvault.json"
    Write-Host "Starting ARM template deployment to deploy Key Vault"
    $kvArmDeployResult = New-AzResourceGroupDeployment `
        -Name "$AppName-keyvault" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $templatePath `
        -TemplateParameterObject $kvArmParameters
    # no -ErrorAction option, let the script die if it errors.
    # (but also don't set -ErrorAction Stop because that can interfere with the script runner on a build agent)

    if (-not $kvArmDeployResult -or $kvArmDeployResult.ProvisioningState -ne "Succeeded") {
        throw "ARM Key Vault deployment failed with provisioning state $($kvArmDeployResult.ProvisioningState). There should be additional error output above 👆"
    }
    Write-Host "Finished ARM template deployment to deploy Key Vault"

    $expectedKvName = $kvArmDeployResult.Outputs.computedKeyVaultName.Value

    Write-Host "Testing the existence of required secret $XAuthSecretName"
    $xAuthSecret = Get-OrSetKeyVaultGeneratedSecret `
        -keyVaultName $expectedKvName `
        -secretName $XAuthSecretName `
        -generator { 
        Write-Host "Secret does not exist, generating new random value"
        Get-RandomString -Length 20 
    } | Out-Null
    Write-Host "Finished ensuring that secret $XAuthSecretName exists"

    $keyVaultDnsSuffix = $(Get-AzContext).Environment.AzureKeyVaultDnsSuffix
    $xAuthSecretUri = "https://$($xAuthSecret.VaultName).$keyVaultDnsSuffix/secrets/$($xAuthSecret.Name)/"
    
    $armParameters = Get-ArmParameters -xAuthSecretUri $xAuthSecretUri -keyVaultName $expectedKvName
    $templatePath = Join-Path $PSScriptRoot "./deploy.json"
    
    Write-Host "Starting ARM template deployment to deploy $AppName resources"
    $armDeployResult = New-AzResourceGroupDeployment `
        -Name "$AppName" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $templatePath `
        -TemplateParameterObject $armParameters
        
    if (-not $armDeployResult -or $armDeployResult.ProvisioningState -ne "Succeeded") {
        throw "ARM deployment failed with provisioning state $($armDeployResult.ProvisioningState). There should be additional error output above 👆"
    }
    Write-Host "Finished ARM template deployment to deploy $AppName resources"

    Write-Host "::set-output name=computedFunctionAppName::$($armDeployResult.Outputs.computedFunctionAppName.Value)"
}

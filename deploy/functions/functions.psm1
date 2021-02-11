function Get-CurrentUserAzureAdObjectId([Parameter(Mandatory = $true)] [string]$tenantId) {
    $account = (Get-AzContext).Account
    if ($account.Type -eq 'User') {
        $user = Get-AzADUser -UserPrincipalName $account.Id
        return $user.Id
    }
    $servicePrincipal = Get-AzADServicePrincipal -ApplicationId $account.Id
    return $servicePrincipal.Id
}

function Get-OrSetKeyVaultSecret($keyVaultName, $secretName, $secretValue) {
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -AsPlainText -ErrorAction SilentlyContinue
    if (-not $secret -or ($secret -ne $secretValue)) {
        $secretValueSecure = ConvertTo-SecureString -String $secretValue -AsPlainText -Force
        $unused = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secretValueSecure
        $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -AsPlaintext
    }
    return $secret
}

function Get-OrSetKeyVaultGeneratedSecret {
    param(
        [Parameter(Mandatory)]
        [string] $keyVaultName, 

        [Parameter(Mandatory)]
        [string] 
        $secretName,

        [Parameter(Mandatory)]
        [ValidateScript( { $_.Ast.ParamBlock.Parameters.Count -eq 0 })]
        [Scriptblock]
        $generator
    )
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -ErrorAction SilentlyContinue
    if (-not $secret) {
        $secretValue = & $generator
        if ($secretValue -isnot [SecureString]) {
            $secretValue = $secretValue | ConvertTo-SecureString -AsPlainText -Force
        }
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secretValue -ErrorAction Stop | Out-Null
        $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -ErrorAction SilentlyContinue
    }
    return $secret
}

function Get-RandomString([int] $length, [string] $charset) {
    if (-not $charset) {
        $charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    }
    $s = $charset.ToCharArray()
    return -join $(0..$length | ForEach-Object { $s | get-random -count 1 })
}

function Test-RequiredKeyVaultSecrets([string]$keyVaultName, [array]$secretNames) {
    $existingSecretNames = Get-AzKeyVaultSecret -VaultName $keyVaultName | Select-Object -ExpandProperty Name
    $missingSecrets = [array] $( $secretNames | Where-Object { $_ -notin $existingSecretNames } ) #cast to an array in case we get 1 thing

    if ($missingSecrets -and $missingSecrets.Length -ne 0) {
        throw "Key vault '$KeyVaultName' did not contain one more required secrets [$($missingSecrets -join ", ")]"
    }
}

Export-ModuleMember -Function *
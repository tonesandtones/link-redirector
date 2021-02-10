param location string = resourceGroup().location
param appBaseName string = 'linky'
param environmentSuffix string {
  default: 'dev'
  allowed: [
    'dev'
    'prod'
  ]
}

param deployerOid string
param keyVaultExists bool

var keyVaultName = '${appBaseName}-${environmentSuffix}-kv'

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    createMode: keyVaultExists ? 'recover' : 'default'
    accessPolicies: []
  }
}

resource keyVaultAccessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2019-09-01' = {
  name: any('${keyVaultName}/add')
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: deployerOid
        permissions:{
          secrets: [
            'get'
            'list'
            'set'
          ]
        }
      }
    ]
  }
}

output computedKeyVaultName string = keyVaultName
output keyVaultResourceId string = keyVault.id
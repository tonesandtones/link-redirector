param location string = resourceGroup().location
param appBaseName string = 'linky'
param environmentSuffix string {
  default: 'dev'
  allowed: [
    'dev'
    'prod'
  ]
}

param storageSku string {
  default: 'Standard_LRS'
  allowed:[
    'Standard_LRS'
  ]
}

param tableNameAka string = 'Aka'
param tableNameStats string = 'stats'

param functionRuntime string = 'dotnet'

param XAuthSecretResource string
param AppInsightsApiKeySecretResource string
param keyVaultName string = 'default'

var storageName = toLower('${appBaseName}${environmentSuffix}${uniqueString(resourceGroup().id)}')
var functionAppName = '${appBaseName}-${environmentSuffix}-app'
var appServiceName = '${appBaseName}-${environmentSuffix}-asp'

//only used to reference a resource, not create one. See declaration in keyvault.bicep
var appInsightsName = '${appBaseName}-${environmentSuffix}-appinsights'

//default name format is defined in keyvault.bicep
var computedKeyVaultName = keyVaultName == 'default' ? '${appBaseName}-${environmentSuffix}-kv' : 'default'

resource stg 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
      name: storageSku
  }
}

resource tableAka 'Microsoft.Storage/storageAccounts/tableServices/tables@2019-06-01' = {
  name: '${stg.name}/default/${tableNameAka}'
}

resource tableStats 'Microsoft.Storage/storageAccounts/tableServices/tables@2019-06-01' = {
  name: '${stg.name}/default/${tableNameStats}'
}

resource appService 'Microsoft.Web/serverFarms@2020-06-01' = {
  name: appServiceName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
  }
}

resource functionApp 'Microsoft.Web/sites@2020-06-01' = {
  name: functionAppName
  kind: 'functionapp'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appService.id
    httpsOnly: true
  }
}

resource functionAppAppSettings 'Microsoft.Web/sites/config@2020-06-01' = {
  name: '${functionApp.name}/appsettings'
  properties:{
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${stg.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(stg.id, stg.apiVersion).keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${stg.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(stg.id, stg.apiVersion).keys[0].value}'
    APPINSIGHTS_INSTRUMENTATIONKEY: reference(resourceId('Microsoft.Insights/components', appInsightsName), '2020-02-02-preview').InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: 'InstrumentationKey=${reference(resourceId('Microsoft.Insights/components', appInsightsName), '2020-02-02-preview').InstrumentationKey}'
    FUNCTIONS_WORKER_RUNTIME: functionRuntime
    FUNCTIONS_EXTENSION_VERSION: '~3'
    WEBSITE_RUN_FROM_PACKAGE: '1'
    'X-Authorization': '@Microsoft.KeyVault(SecretUri=${XAuthSecretResource})'
    AppInsightsApiKey: '@Microsoft.KeyVault(SecretUri=${AppInsightsApiKeySecretResource})'
    AppInsightsAppId: reference(resourceId('Microsoft.Insights/components', appInsightsName), '2020-02-02-preview').AppId
  }
  dependsOn:[
    keyVaultAccessPolicies
  ]
}

resource keyVaultAccessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2019-09-01' = {
  name: any('${keyVaultName}/add')
  properties: {
    accessPolicies: [
      {
        tenantId: functionApp.identity.tenantId
        objectId: functionApp.identity.principalId
        permissions:{
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

output storageId string = stg.id
output computedStorageName string = stg.name
output computedAkaTableName string = tableNameAka
output computedStatsTableName string = tableNameStats
output functionAppHostName string = functionApp.properties.defaultHostName
output computedFunctionAppName string = functionAppName
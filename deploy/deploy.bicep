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

var storageName = toLower('${appBaseName}${environmentSuffix}${uniqueString(resourceGroup().id)}')
var functionAppName = '${appBaseName}-${environmentSuffix}-app'
var appServiceName = '${appBaseName}-${environmentSuffix}-asp'
var appInsightsName = '${appBaseName}-${environmentSuffix}-appinsights'
var keyVaultName = '${appBaseName}-${environmentSuffix}-kv'

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

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
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
  properties: {
    serverFarmId: appService.id
    siteConfig: {
      appSettings:[
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${stg.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(stg.id, stg.apiVersion).keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${stg.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(stg.id, stg.apiVersion).keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
      ]
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
  }
}

output storageId string = stg.id
output computedStorageName string = stg.name
output computedAkaTableName string = tableNameAka
output computedStatsTableName string = tableNameStats
output functionAppHostName string = functionApp.properties.defaultHostName
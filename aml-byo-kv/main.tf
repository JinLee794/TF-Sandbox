########## Variables ##########
variable "aml_client_id" {
    description = "Client ID of the service principal with the AML. Ideally this will be set via HashiVault dynamic creds + OIDC"
}

variable "aml_client_secret" {
    description = "Client secret of the service principal with the AML. Ideally this will be set via HashiVault dynamic creds + OIDC"
}

variable "subscriptionId" {
    type        = string
    description = "The subscription id"
}

variable "tenant_id" {
    type        = string
    description = "Azure tenant ID"
}

variable "location" {
    type        = string
    description = "Azure region for resources"
}

variable "resource_group_name" {
    type        = string
    description = "Resource group name for AML workspace"
}

variable "kv_uai_name" {
    type        = string
    description = "Name of the user-assigned identity for AML"
}

variable "kv_uai_rg_name" {
    type        = string
    description = "Resource group name for user-assigned identity"
}

variable "key_vault_name" {
    type        = string
    description = "Name of the Azure Key Vault"
}

variable "key_vault_rg_name" {
    type        = string
    description = "Resource group name for Azure Key Vault"
}

variable "app_insights_name" {
    type        = string
    description = "Name of the Application Insights resource"
}

variable "storage_account_name" {
    type        = string
    description = "Name of the storage account"
}

variable "aml_workspace_name" {
    type        = string
    description = "Name of the AML workspace"
}

########## Providers ##########
terraform {
        required_providers {
                azurerm = {
                        source  = "hashicorp/azurerm"
                        version = "~> 4.0"
                }
        }
}

## Provider 1: Signed in identity with the Elevance-TFContrib Role
provider "azurerm" {
    alias            = "elevance_tfcontrib"
    subscription_id  = var.subscriptionId
    features {}
}

## Provider 2: Service Principal (can be dynamically set via Hashi Vault) to leverage for the AML deployment.
##              This role JSON can be found in elevance-tfaml-role.json in this directory.
provider "azurerm" {
    alias            = "elevance_tfaml"
    subscription_id  = var.subscriptionId
    client_id        = var.aml_client_id
    client_secret    = var.aml_client_secret
    tenant_id        = var.tenant_id
    features {}
}

########## Data Sources ##########
data "azurerm_user_assigned_identity" "kv-uai-for-aml" {
        provider            = azurerm.elevance_tfcontrib
        name                = var.kv_uai_name
        resource_group_name = var.kv_uai_rg_name
}

data "azurerm_resource_group" "amlws-demo" {
        provider = azurerm.elevance_tfcontrib
        name     = var.resource_group_name
}

data "azurerm_key_vault" "aml_kv" {
        provider            = azurerm.elevance_tfaml
        name                = var.key_vault_name
        resource_group_name = var.key_vault_rg_name
}

########## Resources ##########
## Demonstrate the service principals provisioning resources in parallel, single deployment
resource "azurerm_application_insights" "aml_insights" {
        provider            = azurerm.elevance_tfcontrib
        name                = var.app_insights_name
        location            = var.location
        resource_group_name = data.azurerm_resource_group.amlws-demo.name
        application_type    = "web"
        lifecycle {
                ignore_changes = [
                        workspace_id
                ]
        }
}

resource "azurerm_storage_account" "aml_storage" {
        provider                 = azurerm.elevance_tfcontrib
        name                     = var.storage_account_name
        location                 = var.location
        resource_group_name      = data.azurerm_resource_group.amlws-demo.name
        account_tier             = "Standard"
        account_replication_type = "GRS"
}

## The following resource is a demonstration of the service principal's ability to create the resource using
#   the Hashi Vault stored dynamic credential, which has preconfigured role assignment for AML creation.
resource "azurerm_machine_learning_workspace" "aml_workspace" {
        provider                    = azurerm.elevance_tfaml
        name                        = var.aml_workspace_name
        location                    = var.location
        resource_group_name         = data.azurerm_resource_group.amlws-demo.name
        application_insights_id     = azurerm_application_insights.aml_insights.id
        key_vault_id                = data.azurerm_key_vault.aml_kv.id
        storage_account_id          = azurerm_storage_account.aml_storage.id
        primary_user_assigned_identity = data.azurerm_user_assigned_identity.kv-uai-for-aml.id

        identity {
                type         = "UserAssigned"
                identity_ids = [data.azurerm_user_assigned_identity.kv-uai-for-aml.id]
        }
}
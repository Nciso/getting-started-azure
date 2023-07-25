## --------------------------------------------------------------------------------------------------------------------
## GITHUB REPOSITORY CONFIGURATION
## Define which Github repositories the Terraform blueprint user has access to
## --------------------------------------------------------------------------------------------------------------------

data "autocloud_github_repos" "repos" {}

locals {
  # A list of Github repositories the user is allowed to submit Terraform code to, add specific repositories out of the
  # repositories you have authorized AutoCloud to access to limit users to your infrastructure as code repositories. If
  # you set these, uncomment the filter lines in the `dest_repos` definition on lines 20-23 below.
  # 
  # allowed_repos = [
  #   "example",
  # ]

  # Destination repos where generated code will be submitted
  dest_repos = [
    for repo in data.autocloud_github_repos.repos.data[*].url : repo

    # Uncomment if you have defined an allow list for your repos on lines 12-14 above.
    #
    # if anytrue([
    #   for allowed_repo in local.allowed_repos: length(regexall(format("/%s", allowed_repo), repo)) > 0
    # ])
  ]
}



## --------------------------------------------------------------------------------------------------------------------
## GLOBAL BLUEPRINT CONFIGURATION
## Define form questions the user will be shown which are either not associated with any Terraform module, or are shared
## between multiple Terraform modules.
## --------------------------------------------------------------------------------------------------------------------

data "autocloud_blueprint_config" "global" {
  ###
  # Set the namespace
  variable {
    name         = "namespace"
    display_name = "Namespace"
    helper_text  = "The organization namespace the assets will be deployed in"

    type = "shortText"

    value = "autocloud"
  }

  ###
  # Choose the environment
  variable {
    name         = "environment"
    display_name = "Environment"
    helper_text  = "The environment the assets will be deployed in"

    type = "radio"

    options {
      option {
        label   = "Sandbox"
        value   = "sandbox"
        checked = true
      }
      option {
        label = "Nonprod"
        value = "nonprod"
      }
      option {
        label = "Production"
        value = "production"
      }
    }
  }

  ###
  # Collect the name of the asset group
  variable {
    name         = "name"
    display_name = "Name"
    helper_text  = "The name of the encrypted storage account"

    type = "shortText"

    validation_rule {
      rule          = "isRequired"
      error_message = "You must provide a name for the storage account"
    }
  }
}


## --------------------------------------------------------------------------------------------------------------------
## AZURE CONFIGURATION
## Define Azure specific elements that will be added to all assets, such as tags and tags
## between multiple Terraform modules.
## --------------------------------------------------------------------------------------------------------------------

data "autocloud_blueprint_config" "azure" {
  source = {
    global = data.autocloud_blueprint_config.global.blueprint_config,
  }

  ###
  # Choose the location
  variable {
    name         = "location"
    display_name = "Location"
    helper_text  = "The Azure region the assets will be deployed in"

    type = "radio"

    options {
      option {
        label = "Central US"
        value = "centralus"
      }
      option {
        label   = "East US"
        value   = "eastus"
        checked = true
      }
      option {
        label = "East US 2"
        value = "eastus2"
      }
      option {
        label = "West Central US"
        value = "westcentralus"
      }
      option {
        label = "West US"
        value = "westus"
      }
      option {
        label = "West US 2"
        value = "westus2"
      }
      option {
        label = "West US 3"
        value = "westus3"
      }
    }
  }

  ###
  # Collect tags to apply to assets
  variable {
    name         = "tags"
    display_name = "Tags"
    helper_text  = "A map of tags to apply to the deployed assets"

    type = "map"
  }
}



## --------------------------------------------------------------------------------------------------------------------
## RESOURCE GROUP MODULE
## Define display and output for the resource group associated with the storage account
## --------------------------------------------------------------------------------------------------------------------

resource "autocloud_module" "resource_group" {
  name   = "resourceGroup"
  source = "git@github.com:Azure-Terraform/terraform-azurerm-resource-group.git?ref=v2.1.0"
}

data "autocloud_blueprint_config" "resource_group" {
  source = {
    global         = data.autocloud_blueprint_config.global.blueprint_config,
    azure          = data.autocloud_blueprint_config.azure.blueprint_config,
    resource_group = autocloud_module.resource_group.blueprint_config
  }

  omit_variables = [
    "unique_name",
  ]

  variable {
    name  = "resource_group.variables.unique_name"
    value = "false"
  }

  variable {
    name  = "resource_group.variables.names"
    type  = "raw"
    value = <<-EOT
      {
        environment         = "{{environment}}"
        location            = "{{location}}"
        market              = null
        product_name        = "{{name}}"
        resource_group_type = "{{namespace}}"
      }
      EOT
    variables = {
      namespace   = "global.variables.namespace"
      environment = "global.variables.environment"
      name        = "global.variables.name"
      location    = "azure.variables.location"
    }
  }

  variable {
    name  = "resource_group.variables.location"
    value = "azure.variables.location"
  }

  variable {
    name  = "resource_group.variables.tags"
    value = "azure.variables.tags"
  }
}



## --------------------------------------------------------------------------------------------------------------------
## STORAGE ACCOUNT MODULE
## Define display and output for the resource group associated with the storage account
## --------------------------------------------------------------------------------------------------------------------

resource "autocloud_module" "storage_account" {
  name   = "storageAccount"
  source = "git@github.com:Azure-Terraform/terraform-azurerm-storage-account.git?ref=v0.16.0"
}

data "autocloud_blueprint_config" "storage_account" {
  source = {
    global          = data.autocloud_blueprint_config.global.blueprint_config,
    azure           = data.autocloud_blueprint_config.azure.blueprint_config,
    resource_group  = data.autocloud_blueprint_config.resource_group.blueprint_config,
    storage_account = autocloud_module.storage_account.blueprint_config,
  }

  omit_variables = [
    # Use Default Values
    "access_tier",
    "account_kind",
    "allow_nested_items_to_be_public",
    "blob_cors",
    "custom_404_path",
    "default_network_rule",
    "enable_hns",
    "enable_https_traffic_only",
    "enable_large_file_share",
    "enable_sftp",
    "enable_static_website",
    "encryption_scopes",
    "index_path",
    "infrastructure_encryption_enabled",
    "min_tls_version",
    "nfsv3_enabled",
    "service_endpoints",
    "shared_access_key_enabled",
    "traffic_bypass",
  ]

  variable {
    name         = "storage_account.variables.access_list"
    display_name = "Allowed CIDRs"
    helper_text  = "A list of the CIDR ranges allowed to access the storage account. NOTE: must include the IP address the generated code will be applied from."

    type = "map"

    required_values = jsonencode({
      "terraform_execution" = null
    })

    validation_rule {
      rule          = "minLength"
      value         = 1
      error_message = "You must provide at least one allowed CIDR range to access the storage account"
    }

    validation_rule {
      rule          = "regex"
      value         = "^([0-9]{1,3}\\.){3}[0-9]{1,3}(\\/([0-9]|[1-2][0-9]|3[0-2]))?$"
      scope         = "value"
      error_message = "Must enter a valid CIDR range."
    }
  }

  variable {
    name  = "storage_account.variables.account_tier"
    value = "Standard"
  }

  variable {
    name  = "storage_account.variables.blob_delete_retention_days"
    value = "14"
  }

  variable {
    name  = "storage_account.variables.blob_versioning_enabled"
    value = "true"
  }

  variable {
    name  = "storage_account.variables.container_delete_retention_days"
    value = "30"
  }

  variable {
    name  = "storage_account.variables.location"
    value = "azure.variables.location"
  }

  variable {
    name         = "storage_account.variables.name"
    display_name = "Storage Account Name"
    helper_text  = "The name of the storage account that will be created"
    value        = "{{namespace}}-{{environment}}-{{name}}"
    variables = {
      namespace   = "global.variables.namespace"
      environment = "global.variables.environment"
      name        = "global.variables.name"
    }
  }

  variable {
    name         = "storage_account.variables.replication_type"
    display_name = "Storage Redundancy"
    helper_text  = "The Azure Storage redunancy option the storage account will be configured to use"

    conditional {
      source    = "global.variables.environment"
      condition = "sandbox"
      content {
        value = "LRS"
      }
    }

    conditional {
      source    = "global.variables.environment"
      condition = "nonprod"
      content {
        value = "LRS"
      }
    }

    conditional {
      source    = "global.variables.environment"
      condition = "production"
      content {
        value = "ZRS"
      }
    }
  }

  variable {
    name  = "storage_account.variables.resource_group_name"
    value = autocloud_module.resource_group.outputs["name"]
  }

  variable {
    name  = "storage_account.variables.tags"
    value = "azure.variables.tags"
  }
}



## --------------------------------------------------------------------------------------------------------------------
## COMPLETE BLUEPRINT CONFIGURATION
## Combine all the defined Terraform blueprint configurations into the complete blueprint configuration that will be used
## to create the form shown to the end user.
## --------------------------------------------------------------------------------------------------------------------

data "autocloud_blueprint_config" "complete" {
  source = {
    global          = data.autocloud_blueprint_config.global.blueprint_config,
    azure           = data.autocloud_blueprint_config.azure.blueprint_config,
    resource_group  = data.autocloud_blueprint_config.resource_group.blueprint_config,
    storage_account = data.autocloud_blueprint_config.storage_account.blueprint_config,
  }

  ###
  # Hide variables from user
  omit_variables = [
    # Resource Group
    "resource_group.variables.location",
    "resource_group.variables.tags",
    "resource_group.variables.unique_name",

    # Storage Account
    "storage_account.variables.account_tier",
    "storage_account.variables.blob_delete_retention_days",
    "storage_account.variables.blob_versioning_enabled",
    "storage_account.variables.container_delete_retention_days",
    "storage_account.variables.location",
    "storage_account.variables.tags",
  ]

  display_order {
    priority = 0
    values = [
      "global.variables.namespace",
      "global.variables.environment",
      "global.variables.name",
      "storage_account.variables.name",
      "storage_account.variables.replication_type",
      "storage_account.variables.access_list",
      "azure.variables.tags",
      "azure.variables.location",
    ]
  }
}



## --------------------------------------------------------------------------------------------------------------------
## AUTOCLOUD BLUEPRINT
## Create the AutoCloud Terraform blueprint using the modules and blueprint configurations defined above. 
## --------------------------------------------------------------------------------------------------------------------

resource "autocloud_blueprint" "this" {
  name = "[Getting Started] Azure Storage Account"

  ###
  # UI Configuration
  #
  author       = "example@example.com"
  description  = "Deploy an Azure Storage Account"
  instructions = <<-EOT
    To deploy this generator, these simple steps:

      * step 1: Choose the target environment
      * step 2: Provide a name to identify assets
      * step 3: Add tags to apply to assets
    EOT

  labels = ["azure"]



  ###
  # Form configuration
  config = data.autocloud_blueprint_config.complete.config



  ###
  # File definitions
  file {
    action      = "CREATE"
    destination = "{{namespace}}-{{environment}}-{{name}}.tf"
    variables = {
      namespace   = data.autocloud_blueprint_config.complete.variables["namespace"]
      environment = data.autocloud_blueprint_config.complete.variables["environment"]
      name        = data.autocloud_blueprint_config.complete.variables["name"]
    }

    modules = [
      autocloud_module.resource_group.name,
      autocloud_module.storage_account.name,
    ]
  }



  ###
  # Destination repository git configuraiton
  #
  git_config {
    destination_branch = "main"

    git_url_options = local.dest_repos
    git_url_default = length(local.dest_repos) != 0 ? local.dest_repos[0] : "" # Choose the first in the list by default

    pull_request {
      title                   = "[AutoCloud] new Azure Storage Account {{namespace}}-{{environment}}-{{name}}, created by {{authorName}}"
      commit_message_template = "[AutoCloud] new Azure Storage Account {{namespace}}-{{environment}}-{{name}}, created by {{authorName}}"
      body                    = file("./files/pull_request.md.tpl")
      variables = {
        authorName  = "generic.authorName"
        namespace   = data.autocloud_blueprint_config.complete.variables["namespace"]
        environment = data.autocloud_blueprint_config.complete.variables["environment"]
        name        = data.autocloud_blueprint_config.complete.variables["name"]
      }
    }
  }
}

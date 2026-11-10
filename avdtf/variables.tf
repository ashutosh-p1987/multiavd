# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for the session hosts and networking."
  type        = string
  default     = "eastus"
}

variable "avd_metadata_location" {
  description = "Region for AVD metadata objects (host pool, workspace, app group). Must be an AVD-supported metadata region."
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Short prefix used in resource names (lowercase, no spaces)."
  type        = string
  default     = "avdp"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.prefix))
    error_message = "prefix must be 2-8 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    workload = "avd"
    pooltype = "personal"
  }
}

# ---------------------------------------------------------------------------
# Host pool
# ---------------------------------------------------------------------------
variable "personal_desktop_assignment_type" {
  description = "How users get assigned to a personal desktop: Automatic (first sign-in claims a free host) or Direct (admin assigns)."
  type        = string
  default     = "Automatic"

  validation {
    condition     = contains(["Automatic", "Direct"], var.personal_desktop_assignment_type)
    error_message = "Must be Automatic or Direct."
  }
}

variable "start_vm_on_connect" {
  description = "Start deallocated VMs when an assigned user connects (requires the AVD service principal role assignment created by this config)."
  type        = bool
  default     = true
}

variable "validate_environment" {
  description = "Mark the host pool as a validation pool (receives service updates first)."
  type        = bool
  default     = false
}

variable "registration_token_hours" {
  description = "Validity in hours of the host pool registration token (1-720)."
  type        = number
  default     = 48
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "existing_subnet_id" {
  description = "Use an existing subnet for session hosts (must reach your domain controllers). Leave null to create a new VNet/subnet (required when deploy_adds = true)."
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Address space for the new VNet (ignored when existing_subnet_id is set)."
  type        = list(string)
  default     = ["10.50.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the new session host subnet."
  type        = string
  default     = "10.50.1.0/24"
}

variable "dns_servers" {
  description = "Custom DNS servers for the new VNet (e.g. domain controllers). Empty = Azure DNS."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Session hosts
# ---------------------------------------------------------------------------
variable "session_host_count" {
  description = "Number of personal session hosts (one per user)."
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for each session host."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "os_disk_type" {
  description = "OS disk storage type."
  type        = string
  default     = "Premium_LRS"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB."
  type        = number
  default     = 128
}

variable "image" {
  description = "Marketplace image for session hosts. Personal pools typically use single-session Windows 11 Enterprise."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-ent"
    version   = "latest"
  }
}

variable "admin_username" {
  description = "Local administrator username on session hosts."
  type        = string
  default     = "avdadmin"
}

variable "admin_password" {
  description = "Local administrator password. Leave null to auto-generate (see output)."
  type        = string
  default     = null
  sensitive   = true
}

variable "timezone" {
  description = "Windows time zone for session hosts."
  type        = string
  default     = "UTC"
}

variable "avd_agent_dsc_url" {
  description = "URL of the AVD DSC configuration package that installs the AVD agent and registers the host."
  type        = string
  default     = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02790.438.zip"
}

# ---------------------------------------------------------------------------
# AD DS domain join
# ---------------------------------------------------------------------------
variable "domain_name" {
  description = "AD DS domain FQDN that session hosts join (new forest name when deploy_adds = true)."
  type        = string
  default     = "avdlab.local"
}

variable "domain_ou_path" {
  description = "OU distinguished name for session host computer accounts. Empty = default Computers container."
  type        = string
  default     = ""
}

variable "domain_join_username" {
  description = "Account with rights to join computers to the domain, e.g. joiner@contoso.com. With deploy_adds and null, defaults to admin_username@domain_name."
  type        = string
  default     = null
}

variable "domain_join_password" {
  description = "Password for domain_join_username. With deploy_adds and null, defaults to the admin password."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# AD DS (optional new forest / domain controller)
# ---------------------------------------------------------------------------
variable "deploy_adds" {
  description = "true = Terraform builds a new AD DS forest on a DC VM. false = join an existing domain (set existing_subnet_id, domain_join_username/password)."
  type        = bool
  default     = true
}

variable "adds_domain_netbios_name" {
  description = "NetBIOS name of the new domain (max 15 chars, uppercase), e.g. CONTOSO."
  type        = string
  default     = "AVDLAB"

  validation {
    condition     = can(regex("^[A-Z0-9-]{1,15}$", var.adds_domain_netbios_name))
    error_message = "NetBIOS name must be 1-15 uppercase alphanumeric/hyphen characters."
  }
}

variable "adds_subnet_address_prefix" {
  description = "Address prefix for the domain controller subnet."
  type        = string
  default     = "10.50.0.0/24"
}

variable "adds_dc_private_ip" {
  description = "Static private IP of the domain controller (must be inside adds_subnet_address_prefix). Also used as VNet DNS."
  type        = string
  default     = "10.50.0.4"
}

variable "adds_vm_size" {
  description = "VM size for the domain controller."
  type        = string
  default     = "Standard_B2ms"
}

variable "adds_image" {
  description = "Marketplace image for the domain controller."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

variable "adds_dsrm_password" {
  description = "Directory Services Restore Mode password. Leave null to auto-generate."
  type        = string
  default     = null
  sensitive   = true
}

variable "adds_ready_wait" {
  description = "How long to wait after forest promotion (DC reboot + AD services start) before domain-joining session hosts."
  type        = string
  default     = "8m"
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------
variable "avd_user_group_object_ids" {
  description = "Object IDs (in Entra ID) of hybrid groups/users synced from AD DS, granted access to the personal desktop."
  type        = list(string)
  default     = []
}

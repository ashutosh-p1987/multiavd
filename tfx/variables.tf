variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant ID. Null falls back to ARM_TENANT_ID / Azure CLI."
  type        = string
  default     = null
}

variable "client_id" {
  description = "Service principal (app registration) client ID. Null falls back to ARM_CLIENT_ID / Azure CLI."
  type        = string
  default     = null
}

variable "client_secret" {
  description = "Service principal client secret. Prefer TF_VAR_client_secret or ARM_CLIENT_SECRET over tfvars."
  type        = string
  default     = null
  sensitive   = true
}

variable "machine_type" {
  description = "Type of AVD deployment: 'personal' (dedicated VDI per user) or 'multisession' (pooled, shared hosts)."
  type        = string
  default     = "personal"

  validation {
    condition     = contains(["personal", "multisession"], var.machine_type)
    error_message = "machine_type must be either 'personal' or 'multisession'."
  }
}

variable "location" {
  description = "Azure region for session hosts and networking."
  type        = string
  default     = "eastus"
}

variable "avd_metadata_location" {
  description = "Region for AVD control-plane objects (host pool, app group, workspace)."
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Short name prefix used for all resources (lowercase, no spaces)."
  type        = string
  default     = "avd"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.prefix))
    error_message = "prefix must be 2-8 lowercase alphanumeric characters."
  }
}

variable "tags" {
  type = map(string)
  default = {
    workload    = "avd"
    environment = "dev"
  }
}

# ---------------- Networking ----------------

variable "create_vnet" {
  description = "Create a new VNet/subnet. Set false to use existing_subnet_id."
  type        = bool
  default     = true
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.50.0.0/16"]
}

variable "subnet_address_prefix" {
  type    = string
  default = "10.50.1.0/24"
}

variable "existing_subnet_id" {
  type    = string
  default = null
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

# ---------------- Common session host settings ----------------

variable "session_host_count" {
  type    = number
  default = 2
}

variable "vm_size" {
  description = "VM size. Null uses the default for the machine type (personal: Standard_D4s_v5, multisession: Standard_D8s_v5)."
  type        = string
  default     = null
}

variable "image" {
  description = "Marketplace image. Null uses the default for the machine type (personal: win11-24h2-ent, multisession: win11-24h2-avd)."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = null
}

variable "admin_username" {
  type    = string
  default = "avdadmin"
}

variable "start_vm_on_connect" {
  type    = bool
  default = true
}

variable "enroll_in_intune" {
  type    = bool
  default = false
}

variable "avd_user_group_object_ids" {
  description = "Entra ID group/user object IDs granted desktop access and VM user login."
  type        = list(string)
  default     = []
}

variable "avd_admin_group_object_ids" {
  description = "Entra ID group/user object IDs granted VM administrator login."
  type        = list(string)
  default     = []
}

# ---------------- Personal-only settings ----------------

variable "personal_desktop_assignment_type" {
  description = "[personal] Automatic or Direct."
  type        = string
  default     = "Automatic"
}

# ---------------- Multisession-only settings ----------------

variable "load_balancer_type" {
  description = "[multisession] BreadthFirst or DepthFirst."
  type        = string
  default     = "BreadthFirst"
}

variable "max_sessions_per_host" {
  description = "[multisession] Maximum concurrent sessions per host."
  type        = number
  default     = 10
}

variable "fslogix_vhd_location" {
  description = "[multisession] UNC path for FSLogix profiles, e.g. \\\\stprofiles.file.core.windows.net\\profiles. Null skips FSLogix."
  type        = string
  default     = null
}

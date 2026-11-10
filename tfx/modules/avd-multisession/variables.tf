variable "prefix" {
  description = "Short name prefix (2-8 lowercase alphanumerics)."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  description = "Resource group ID (scope for VM login and power-on role assignments)."
  type        = string
}

variable "location" {
  description = "Region for session hosts."
  type        = string
}

variable "avd_metadata_location" {
  description = "Region for AVD control-plane objects."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for session host NICs."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---------------- Host pool ----------------

variable "load_balancer_type" {
  description = "BreadthFirst spreads users across hosts; DepthFirst fills one host before the next."
  type        = string
  default     = "BreadthFirst"

  validation {
    condition     = contains(["BreadthFirst", "DepthFirst"], var.load_balancer_type)
    error_message = "Must be BreadthFirst or DepthFirst."
  }
}

variable "max_sessions_per_host" {
  description = "Maximum concurrent user sessions per session host."
  type        = number
  default     = 10
}

variable "start_vm_on_connect" {
  type    = bool
  default = true
}

variable "registration_token_hours" {
  type    = number
  default = 48
}

variable "custom_rdp_properties" {
  type    = string
  default = "targetisaadjoined:i:1;enablerdsaadauth:i:1;audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:;redirectclipboard:i:1;redirectprinters:i:1;camerastoredirect:s:*;"
}

# ---------------- Session hosts ----------------

variable "session_host_count" {
  type    = number
  default = 2
}

variable "vm_size" {
  type    = string
  default = "Standard_D8s_v5"
}

variable "os_disk_type" {
  type    = string
  default = "Premium_LRS"
}

variable "os_disk_size_gb" {
  type    = number
  default = 128
}

variable "image" {
  description = "Multi-session Windows image."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-avd"
    version   = "latest"
  }
}

variable "admin_username" {
  type    = string
  default = "avdadmin"
}

variable "enroll_in_intune" {
  type    = bool
  default = false
}

variable "avd_agent_dsc_url" {
  type    = string
  default = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_09-08-2022.zip"
}

# ---------------- FSLogix ----------------

variable "fslogix_vhd_location" {
  description = "UNC path for FSLogix profile containers, e.g. \\\\stavdprofiles.file.core.windows.net\\profiles. Null skips FSLogix configuration."
  type        = string
  default     = null
}

# ---------------- Access ----------------

variable "avd_user_group_object_ids" {
  type    = list(string)
  default = []
}

variable "avd_admin_group_object_ids" {
  type    = list(string)
  default = []
}

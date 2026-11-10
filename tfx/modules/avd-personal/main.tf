locals {
  intune_mdm_id = "0000000a-0000-0000-c000-000000000000"
}

# ---------------------------------------------------------------------------
# AVD control plane: personal host pool, desktop app group, workspace
# ---------------------------------------------------------------------------
resource "azurerm_virtual_desktop_host_pool" "this" {
  name                             = "vdpool-${var.prefix}-personal"
  location                         = var.avd_metadata_location
  resource_group_name              = var.resource_group_name
  friendly_name                    = "Personal Desktops"
  description                      = "AVD personal host pool"
  type                             = "Personal"
  personal_desktop_assignment_type = var.personal_desktop_assignment_type
  load_balancer_type               = "Persistent"
  preferred_app_group_type         = "Desktop"
  start_vm_on_connect              = var.start_vm_on_connect
  validate_environment             = false
  custom_rdp_properties            = var.custom_rdp_properties
  tags                             = var.tags
}

resource "time_rotating" "registration" {
  rotation_hours = var.registration_token_hours
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.this.id
  expiration_date = time_rotating.registration.rotation_rfc3339
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                         = "vdag-${var.prefix}-personal-desktop"
  location                     = var.avd_metadata_location
  resource_group_name          = var.resource_group_name
  host_pool_id                 = azurerm_virtual_desktop_host_pool.this.id
  type                         = "Desktop"
  friendly_name                = "Personal Desktop"
  default_desktop_display_name = "My Desktop"
  tags                         = var.tags
}

resource "azurerm_virtual_desktop_workspace" "this" {
  name                = "vdws-${var.prefix}-personal"
  location            = var.avd_metadata_location
  resource_group_name = var.resource_group_name
  friendly_name       = "Personal Virtual Desktop"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "this" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

# ---------------------------------------------------------------------------
# Session hosts (Microsoft Entra ID joined, single-session)
# ---------------------------------------------------------------------------
resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!@#$%^*()-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_network_interface" "sh" {
  count               = var.session_host_count
  name                = "nic-${var.prefix}-p-${count.index + 1}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "sh" {
  count                 = var.session_host_count
  name                  = "vm-${var.prefix}-p-${count.index + 1}"
  computer_name         = "${var.prefix}-p-${count.index + 1}" # max 15 chars
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.sh[count.index].id]
  license_type          = "Windows_Client"
  secure_boot_enabled   = true
  vtpm_enabled          = true
  provision_vm_agent    = true
  tags                  = var.tags

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${var.prefix}-p-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  boot_diagnostics {}
}

resource "azurerm_virtual_machine_extension" "aad_login" {
  count                      = var.session_host_count
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.sh[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  settings = var.enroll_in_intune ? jsonencode({ mdmId = local.intune_mdm_id }) : null
}

resource "azurerm_virtual_machine_extension" "avd_dsc" {
  count                      = var.session_host_count
  name                       = "Microsoft.PowerShell.DSC"
  virtual_machine_id         = azurerm_windows_virtual_machine.sh[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    modulesUrl            = var.avd_agent_dsc_url
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      HostPoolName             = azurerm_virtual_desktop_host_pool.this.name
      aadJoin                  = true
      UseAgentDownloadEndpoint = true
      mdmId                    = var.enroll_in_intune ? local.intune_mdm_id : ""
    }
  })

  protected_settings = jsonencode({
    properties = {
      registrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.this.token
    }
  })

  lifecycle {
    ignore_changes = [settings, protected_settings]
  }

  depends_on = [azurerm_virtual_machine_extension.aad_login]
}

# ---------------------------------------------------------------------------
# RBAC
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "desktop_users" {
  for_each             = toset(var.avd_user_group_object_ids)
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "vm_user_login" {
  for_each             = toset(var.avd_user_group_object_ids)
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "vm_admin_login" {
  for_each             = toset(var.avd_admin_group_object_ids)
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value
}

data "azuread_service_principal" "avd" {
  count     = var.start_vm_on_connect ? 1 : 0
  client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07" # Azure Virtual Desktop
}

resource "azurerm_role_assignment" "avd_power_on" {
  count                = var.start_vm_on_connect ? 1 : 0
  scope                = var.resource_group_id
  role_definition_name = "Desktop Virtualization Power On Contributor"
  principal_id         = data.azuread_service_principal.avd[0].object_id
}

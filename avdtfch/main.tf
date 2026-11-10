locals {
  name_suffix = "${var.prefix}-${var.environment}-${var.location}"

  tags = merge({
    workload    = "avd-personal"
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)

  # Intune MDM application ID used by the AADLoginForWindows extension.
  intune_mdm_id = "0000000a-0000-0000-c000-000000000000"

  # Well-known app ID of the Azure Virtual Desktop service principal.
  avd_service_principal_client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07"
}

# =====================================================================
# Resource group
# =====================================================================

resource "azurerm_resource_group" "avd" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.tags
}

# =====================================================================
# Networking
# =====================================================================

resource "azurerm_virtual_network" "avd" {
  name                = "vnet-${local.name_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "session_hosts" {
  name                            = "snet-sessionhosts"
  resource_group_name             = azurerm_resource_group.avd.name
  virtual_network_name            = azurerm_virtual_network.avd.name
  address_prefixes                = [var.session_host_subnet_prefix]
  default_outbound_access_enabled = !var.enable_nat_gateway
}

# No inbound rules: users connect through the AVD reverse-connect broker,
# so session hosts need no public IP or open inbound ports.
resource "azurerm_network_security_group" "session_hosts" {
  name                = "nsg-sessionhosts-${local.name_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "session_hosts" {
  subnet_id                 = azurerm_subnet.session_hosts.id
  network_security_group_id = azurerm_network_security_group.session_hosts.id
}

resource "azurerm_public_ip" "nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "pip-nat-${local.name_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "avd" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "ng-${local.name_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "avd" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.avd[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "session_hosts" {
  count          = var.enable_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.session_hosts.id
  nat_gateway_id = azurerm_nat_gateway.avd[0].id
}

# =====================================================================
# AVD control plane: host pool, desktop app group, workspace
# =====================================================================

resource "azurerm_virtual_desktop_host_pool" "personal" {
  name                             = "vdpool-${local.name_suffix}"
  location                         = azurerm_resource_group.avd.location
  resource_group_name              = azurerm_resource_group.avd.name
  friendly_name                    = "Personal Desktops"
  description                      = "Personal (1:1) AVD host pool managed by Terraform"
  type                             = "Personal"
  load_balancer_type               = "Persistent"
  personal_desktop_assignment_type = var.personal_desktop_assignment_type
  preferred_app_group_type         = "Desktop"
  start_vm_on_connect              = var.start_vm_on_connect
  validate_environment             = false

  # targetisaadjoined is required for Entra ID-joined session hosts.
  custom_rdp_properties = join("", [
    "targetisaadjoined:i:1;",
    "drivestoredirect:s:*;",
    "audiomode:i:0;",
    "videoplaybackmode:i:1;",
    "redirectclipboard:i:1;",
    "redirectprinters:i:1;",
    "devicestoredirect:s:*;",
    "redirectsmartcards:i:1;",
    "usbdevicestoredirect:s:*;",
    "enablecredsspsupport:i:1;",
    "use multimon:i:1;",
  ])

  tags = local.tags
}

# Rotates the registration token on a schedule so plans stay stable.
resource "time_rotating" "registration_token" {
  rotation_days = var.registration_token_rotation_days
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "personal" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.personal.id
  expiration_date = time_rotating.registration_token.rotation_rfc3339
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                         = "vdag-desktop-${local.name_suffix}"
  location                     = azurerm_resource_group.avd.location
  resource_group_name          = azurerm_resource_group.avd.name
  host_pool_id                 = azurerm_virtual_desktop_host_pool.personal.id
  type                         = "Desktop"
  friendly_name                = "Personal Desktop"
  default_desktop_display_name = "My Desktop"
  tags                         = local.tags
}

resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = "vdws-${local.name_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  friendly_name       = "Azure Virtual Desktop"
  description         = "Workspace for personal desktops"
  tags                = local.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "desktop" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

# =====================================================================
# Session hosts (Entra ID joined, single-session Windows 11)
# =====================================================================

resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!@#$%*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_network_interface" "session_host" {
  count               = var.session_host_count
  name                = "nic-${var.prefix}-sh-${count.index + 1}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.session_hosts.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "session_host" {
  count                 = var.session_host_count
  name                  = "vm-${var.prefix}-sh-${count.index + 1}"
  computer_name         = substr("${var.prefix}sh${format("%02d", count.index + 1)}", 0, 15)
  location              = azurerm_resource_group.avd.location
  resource_group_name   = azurerm_resource_group.avd.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.session_host[count.index].id]
  license_type          = "Windows_Client" # Use existing M365/Windows E3+ licensing rights
  secure_boot_enabled   = true
  vtpm_enabled          = true
  patch_mode            = "AutomaticByOS"
  tags                  = local.tags

  identity {
    type = "SystemAssigned" # Required for Entra ID join
  }

  os_disk {
    name                 = "osdisk-${var.prefix}-sh-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  boot_diagnostics {}

  depends_on = [
    azurerm_subnet_nat_gateway_association.session_hosts,
    azurerm_subnet_network_security_group_association.session_hosts,
  ]
}

# Join each VM to Microsoft Entra ID (optionally enrolling in Intune).
resource "azurerm_virtual_machine_extension" "aad_login" {
  count                      = var.session_host_count
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  settings = var.enroll_in_intune ? jsonencode({ mdmId = local.intune_mdm_id }) : null
  tags     = local.tags
}

# Install the AVD agent + boot loader and register the VM with the host pool.
resource "azurerm_virtual_machine_extension" "avd_agent" {
  count                      = var.session_host_count
  name                       = "Microsoft.PowerShell.DSC"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    modulesUrl            = var.avd_dsc_artifact_url
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      HostPoolName                           = azurerm_virtual_desktop_host_pool.personal.name
      aadJoin                                = true
      UseAgentDownloadEndpoint               = true
      aadJoinPreview                         = false
      mdmId                                  = var.enroll_in_intune ? local.intune_mdm_id : ""
      sessionHostConfigurationLastUpdateTime = ""
      RegistrationInfoTokenCredential = {
        UserName = "PLACEHOLDER_DO_NOT_USE"
        Password = "PrivateSettingsRef:RegistrationInfoToken"
      }
    }
  })

  protected_settings = jsonencode({
    Items = {
      RegistrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.personal.token
    }
  })

  tags = local.tags

  # Registration only matters on first boot; don't re-run the extension
  # every time the token rotates.
  lifecycle {
    ignore_changes = [settings, protected_settings]
  }

  depends_on = [azurerm_virtual_machine_extension.aad_login]
}

# =====================================================================
# RBAC
# =====================================================================

data "azuread_user" "avd_users" {
  for_each            = toset(var.avd_user_upns)
  user_principal_name = each.value
}

data "azuread_user" "avd_admins" {
  for_each            = toset(var.avd_admin_upns)
  user_principal_name = each.value
}

# Lets users see and launch the desktop in the AVD client.
resource "azurerm_role_assignment" "desktop_users" {
  for_each             = data.azuread_user.avd_users
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = each.value.object_id
}

# Required to sign in to Entra ID-joined VMs.
resource "azurerm_role_assignment" "vm_user_login" {
  for_each             = data.azuread_user.avd_users
  scope                = azurerm_resource_group.avd.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = each.value.object_id
}

resource "azurerm_role_assignment" "vm_admin_login" {
  for_each             = data.azuread_user.avd_admins
  scope                = azurerm_resource_group.avd.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value.object_id
}

# Start VM on Connect: the AVD service needs permission to power on VMs.
data "azuread_service_principal" "avd" {
  count     = var.start_vm_on_connect ? 1 : 0
  client_id = local.avd_service_principal_client_id
}

resource "azurerm_role_assignment" "avd_power_on" {
  count                = var.start_vm_on_connect ? 1 : 0
  scope                = azurerm_resource_group.avd.id
  role_definition_name = "Desktop Virtualization Power On Contributor"
  principal_id         = data.azuread_service_principal.avd[0].object_id
}

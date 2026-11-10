locals {
  name      = var.prefix
  subnet_id = var.existing_subnet_id != null ? var.existing_subnet_id : azurerm_subnet.hosts[0].id

  admin_password = var.admin_password != null ? var.admin_password : random_password.admin[0].result

  # When Terraform builds the forest, the DC's local admin becomes the domain admin and is used for joins.
  domain_join_username = var.domain_join_username != null ? var.domain_join_username : (
    var.deploy_adds ? "${var.admin_username}@${var.domain_name}" : null
  )
  domain_join_password = var.domain_join_password != null ? var.domain_join_password : (
    var.deploy_adds ? local.admin_password : null
  )

  vnet_dns_servers = var.deploy_adds ? [var.adds_dc_private_ip] : var.dns_servers

  rdp_properties = join(";", [
    "drivestoredirect:s:*",
    "audiomode:i:0",
    "videoplaybackmode:i:1",
    "redirectclipboard:i:1",
    "redirectprinters:i:1",
    "devicestoredirect:s:*",
    "redirectcomports:i:1",
    "redirectsmartcards:i:1",
    "usbdevicestoredirect:s:*",
    "enablecredsspsupport:i:1",
    "use multimon:i:1",
  ])
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "avd" {
  name     = "rg-${local.name}-avd"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Networking (created only when no existing subnet is provided)
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "avd" {
  count               = var.existing_subnet_id == null ? 1 : 0
  name                = "vnet-${local.name}-avd"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  address_space       = var.vnet_address_space
  dns_servers         = local.vnet_dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "hosts" {
  count                = var.existing_subnet_id == null ? 1 : 0
  name                 = "snet-${local.name}-hosts"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd[0].name
  address_prefixes     = [var.subnet_address_prefix]
}

resource "azurerm_network_security_group" "hosts" {
  count               = var.existing_subnet_id == null ? 1 : 0
  name                = "nsg-${local.name}-hosts"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = var.tags
  # AVD uses reverse-connect: no inbound rules required.
}

resource "azurerm_subnet_network_security_group_association" "hosts" {
  count                     = var.existing_subnet_id == null ? 1 : 0
  subnet_id                 = azurerm_subnet.hosts[0].id
  network_security_group_id = azurerm_network_security_group.hosts[0].id
}

# ---------------------------------------------------------------------------
# AVD: personal host pool, desktop app group, workspace
# ---------------------------------------------------------------------------
resource "azurerm_virtual_desktop_host_pool" "personal" {
  name                             = "vdpool-${local.name}-personal"
  location                         = var.avd_metadata_location
  resource_group_name              = azurerm_resource_group.avd.name
  friendly_name                    = "Personal Desktops"
  description                      = "Personal (persistent) AVD host pool managed by Terraform"
  type                             = "Personal"
  load_balancer_type               = "Persistent"
  personal_desktop_assignment_type = var.personal_desktop_assignment_type
  start_vm_on_connect              = var.start_vm_on_connect
  validate_environment             = var.validate_environment
  preferred_app_group_type         = "Desktop"
  custom_rdp_properties            = local.rdp_properties
  tags                             = var.tags
}

resource "time_rotating" "registration" {
  rotation_hours = var.registration_token_hours
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "personal" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.personal.id
  expiration_date = time_rotating.registration.rotation_rfc3339
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                         = "vdag-${local.name}-desktop"
  location                     = var.avd_metadata_location
  resource_group_name          = azurerm_resource_group.avd.name
  host_pool_id                 = azurerm_virtual_desktop_host_pool.personal.id
  type                         = "Desktop"
  friendly_name                = "Personal Desktop"
  default_desktop_display_name = "My Desktop"
  tags                         = var.tags
}

resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = "vdws-${local.name}"
  location            = var.avd_metadata_location
  resource_group_name = azurerm_resource_group.avd.name
  friendly_name       = "Azure Virtual Desktop"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "desktop" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

# ---------------------------------------------------------------------------
# RBAC
# ---------------------------------------------------------------------------
# Users (hybrid identities synced from AD DS) can see/launch the desktop
resource "azurerm_role_assignment" "desktop_users" {
  for_each             = toset(var.avd_user_group_object_ids)
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = each.value
}

# Start VM on Connect: allow the AVD service principal to power on VMs
data "azuread_service_principal" "avd" {
  count     = var.start_vm_on_connect ? 1 : 0
  client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07" # Azure Virtual Desktop
}

resource "azurerm_role_assignment" "avd_power_on" {
  count                = var.start_vm_on_connect ? 1 : 0
  scope                = azurerm_resource_group.avd.id
  role_definition_name = "Desktop Virtualization Power On Contributor"
  principal_id         = data.azuread_service_principal.avd[0].object_id
}

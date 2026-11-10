locals {
  is_personal     = var.machine_type == "personal"
  is_multisession = var.machine_type == "multisession"

  subnet_id = var.create_vnet ? azurerm_subnet.avd[0].id : var.existing_subnet_id

  default_vm_size = {
    personal     = "Standard_D4s_v5"
    multisession = "Standard_D8s_v5"
  }

  default_image = {
    personal = {
      publisher = "MicrosoftWindowsDesktop"
      offer     = "windows-11"
      sku       = "win11-24h2-ent" # single-session
      version   = "latest"
    }
    multisession = {
      publisher = "MicrosoftWindowsDesktop"
      offer     = "windows-11"
      sku       = "win11-24h2-avd" # multi-session
      version   = "latest"
    }
  }

  vm_size = coalesce(var.vm_size, local.default_vm_size[var.machine_type])
  image   = var.image != null ? var.image : local.default_image[var.machine_type]
}

# ---------------------------------------------------------------------------
# Shared: resource group and networking
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "avd" {
  name     = "rg-${var.prefix}-avd-${var.machine_type}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "avd" {
  count               = var.create_vnet ? 1 : 0
  name                = "vnet-${var.prefix}-avd"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  address_space       = var.vnet_address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "avd" {
  count                = var.create_vnet ? 1 : 0
  name                 = "snet-${var.prefix}-sessionhosts"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd[0].name
  address_prefixes     = [var.subnet_address_prefix]
}

resource "azurerm_network_security_group" "avd" {
  count               = var.create_vnet ? 1 : 0
  name                = "nsg-${var.prefix}-sessionhosts"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = var.tags
  # No inbound rules needed: AVD uses reverse-connect over outbound 443.
}

resource "azurerm_subnet_network_security_group_association" "avd" {
  count                     = var.create_vnet ? 1 : 0
  subnet_id                 = azurerm_subnet.avd[0].id
  network_security_group_id = azurerm_network_security_group.avd[0].id
}

# ---------------------------------------------------------------------------
# AVD deployment selected by machine_type
# ---------------------------------------------------------------------------
module "avd_personal" {
  source = "./modules/avd-personal"
  count  = local.is_personal ? 1 : 0

  prefix                = var.prefix
  resource_group_name   = azurerm_resource_group.avd.name
  resource_group_id     = azurerm_resource_group.avd.id
  location              = var.location
  avd_metadata_location = var.avd_metadata_location
  subnet_id             = local.subnet_id
  tags                  = var.tags

  personal_desktop_assignment_type = var.personal_desktop_assignment_type
  start_vm_on_connect              = var.start_vm_on_connect

  session_host_count = var.session_host_count
  vm_size            = local.vm_size
  image              = local.image
  admin_username     = var.admin_username
  enroll_in_intune   = var.enroll_in_intune

  avd_user_group_object_ids  = var.avd_user_group_object_ids
  avd_admin_group_object_ids = var.avd_admin_group_object_ids

  depends_on = [azurerm_subnet_network_security_group_association.avd]
}

module "avd_multisession" {
  source = "./modules/avd-multisession"
  count  = local.is_multisession ? 1 : 0

  prefix                = var.prefix
  resource_group_name   = azurerm_resource_group.avd.name
  resource_group_id     = azurerm_resource_group.avd.id
  location              = var.location
  avd_metadata_location = var.avd_metadata_location
  subnet_id             = local.subnet_id
  tags                  = var.tags

  load_balancer_type    = var.load_balancer_type
  max_sessions_per_host = var.max_sessions_per_host
  start_vm_on_connect   = var.start_vm_on_connect
  fslogix_vhd_location  = var.fslogix_vhd_location

  session_host_count = var.session_host_count
  vm_size            = local.vm_size
  image              = local.image
  admin_username     = var.admin_username
  enroll_in_intune   = var.enroll_in_intune

  avd_user_group_object_ids  = var.avd_user_group_object_ids
  avd_admin_group_object_ids = var.avd_admin_group_object_ids

  depends_on = [azurerm_subnet_network_security_group_association.avd]
}

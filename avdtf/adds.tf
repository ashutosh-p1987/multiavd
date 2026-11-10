# ---------------------------------------------------------------------------
# Optional: new AD DS forest on a domain controller VM (deploy_adds = true)
# ---------------------------------------------------------------------------

resource "random_password" "dsrm" {
  count            = var.deploy_adds && var.adds_dsrm_password == null ? 1 : 0
  length           = 20
  special          = true
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%*-_=+"
}

locals {
  dsrm_password = var.adds_dsrm_password != null ? var.adds_dsrm_password : try(random_password.dsrm[0].result, null)
}

resource "azurerm_subnet" "adds" {
  count                = var.deploy_adds ? 1 : 0
  name                 = "snet-${local.name}-adds"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd[0].name
  address_prefixes     = [var.adds_subnet_address_prefix]
}

resource "azurerm_network_security_group" "adds" {
  count               = var.deploy_adds ? 1 : 0
  name                = "nsg-${local.name}-adds"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = var.tags
  # Default rules allow intra-VNet traffic (AD/DNS/Kerberos) and deny inbound from Internet.
}

resource "azurerm_subnet_network_security_group_association" "adds" {
  count                     = var.deploy_adds ? 1 : 0
  subnet_id                 = azurerm_subnet.adds[0].id
  network_security_group_id = azurerm_network_security_group.adds[0].id
}

resource "azurerm_network_interface" "dc" {
  count               = var.deploy_adds ? 1 : 0
  name                = "nic-${local.name}-dc01"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = var.tags

  # Primary = itself (works after promotion); secondary = Azure DNS so the VM
  # can resolve extension download endpoints before it becomes a DNS server.
  dns_servers = [var.adds_dc_private_ip, "168.63.129.16"]

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.adds[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.adds_dc_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  count                 = var.deploy_adds ? 1 : 0
  name                  = "vm-${local.name}-dc01"
  computer_name         = "${local.name}-dc01"
  location              = azurerm_resource_group.avd.location
  resource_group_name   = azurerm_resource_group.avd.name
  size                  = var.adds_vm_size
  admin_username        = var.admin_username
  admin_password        = local.admin_password
  network_interface_ids = [azurerm_network_interface.dc[0].id]
  timezone              = var.timezone
  secure_boot_enabled   = true
  vtpm_enabled          = true
  patch_mode            = "AutomaticByOS"
  tags                  = var.tags

  os_disk {
    name                 = "osdisk-${local.name}-dc01"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = var.adds_image.publisher
    offer     = var.adds_image.offer
    sku       = var.adds_image.sku
    version   = var.adds_image.version
  }

  boot_diagnostics {}

  lifecycle {
    ignore_changes = [admin_password]

    precondition {
      condition     = var.existing_subnet_id == null
      error_message = "deploy_adds = true creates its own VNet; set existing_subnet_id = null (or use deploy_adds = false to join an existing domain)."
    }
  }
}

# NTDS/SYSVOL on a data disk with host caching disabled (Microsoft guidance for DCs in Azure)
resource "azurerm_managed_disk" "dc_ntds" {
  count                = var.deploy_adds ? 1 : 0
  name                 = "datadisk-${local.name}-dc01-ntds"
  location             = azurerm_resource_group.avd.location
  resource_group_name  = azurerm_resource_group.avd.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "dc_ntds" {
  count              = var.deploy_adds ? 1 : 0
  managed_disk_id    = azurerm_managed_disk.dc_ntds[0].id
  virtual_machine_id = azurerm_windows_virtual_machine.dc[0].id
  lun                = 0
  caching            = "None"
}

# Promote to a new forest. Script is passed base64 (UTF-16LE) inside protected settings
# so passwords are encrypted and no quoting issues arise.
resource "azurerm_virtual_machine_extension" "adds_forest" {
  count                      = var.deploy_adds ? 1 : 0
  name                       = "CreateADForest"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(templatefile("${path.module}/scripts/New-ADForest.ps1", {
      domain_name   = var.domain_name
      netbios_name  = var.adds_domain_netbios_name
      dsrm_password = local.dsrm_password
    }), "UTF-16LE")}"
  })

  lifecycle {
    ignore_changes = [protected_settings]
  }

  depends_on = [azurerm_virtual_machine_data_disk_attachment.dc_ntds]
}

# Give the DC time to reboot and start AD DS / DNS before session hosts join.
resource "time_sleep" "adds_ready" {
  count           = var.deploy_adds ? 1 : 0
  create_duration = var.adds_ready_wait

  depends_on = [azurerm_virtual_machine_extension.adds_forest]
}

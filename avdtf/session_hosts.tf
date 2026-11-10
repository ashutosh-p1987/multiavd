resource "random_password" "admin" {
  count            = var.admin_password == null ? 1 : 0
  length           = 20
  special          = true
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%*-_=+"
}

resource "azurerm_network_interface" "host" {
  count               = var.session_host_count
  name                = "nic-${local.name}-sh-${count.index + 1}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = local.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "host" {
  count                 = var.session_host_count
  name                  = "vm-${local.name}-sh-${count.index + 1}"
  computer_name         = "${local.name}-sh-${count.index + 1}" # max 15 chars
  location              = azurerm_resource_group.avd.location
  resource_group_name   = azurerm_resource_group.avd.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = local.admin_password
  network_interface_ids = [azurerm_network_interface.host[count.index].id]
  license_type          = "Windows_Client" # AVD-eligible Windows license
  timezone              = var.timezone
  secure_boot_enabled   = true
  vtpm_enabled          = true
  provision_vm_agent    = true
  patch_mode            = "AutomaticByOS"
  tags                  = var.tags

  os_disk {
    name                 = "osdisk-${local.name}-sh-${count.index + 1}"
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

  boot_diagnostics {} # managed storage account

  lifecycle {
    ignore_changes = [admin_password]
  }
}

# ---------------------------------------------------------------------------
# AD DS domain join
# ---------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "domain_join" {
  count                      = var.session_host_count
  name                       = "DomainJoin"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    Name    = var.domain_name
    OUPath  = var.domain_ou_path
    User    = local.domain_join_username
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = local.domain_join_password
  })

  lifecycle {
    ignore_changes = [settings, protected_settings]

    precondition {
      condition     = local.domain_join_username != null && local.domain_join_password != null
      error_message = "domain_join_username and domain_join_password are required when deploy_adds = false (joining an existing domain)."
    }
  }

  # Wait for the new forest to be up when Terraform builds the DC.
  depends_on = [time_sleep.adds_ready]
}

# ---------------------------------------------------------------------------
# AVD agent install + host pool registration (DSC)
# ---------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "avd_agent" {
  count                      = var.session_host_count
  name                       = "Microsoft.PowerShell.DSC"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    modulesUrl            = var.avd_agent_dsc_url
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      HostPoolName                           = azurerm_virtual_desktop_host_pool.personal.name
      aadJoin                                = false
      UseAgentDownloadEndpoint               = true
      sessionHostConfigurationLastUpdateTime = ""
      registrationInfoTokenCredential = {
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

  # Token rotates; only needed at first registration.
  lifecycle {
    ignore_changes = [settings, protected_settings]
  }

  depends_on = [azurerm_virtual_machine_extension.domain_join]
}

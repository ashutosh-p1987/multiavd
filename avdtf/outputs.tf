output "resource_group_name" {
  value = azurerm_resource_group.avd.name
}

output "host_pool_id" {
  value = azurerm_virtual_desktop_host_pool.personal.id
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.personal.name
}

output "workspace_id" {
  value = azurerm_virtual_desktop_workspace.avd.id
}

output "desktop_app_group_id" {
  value = azurerm_virtual_desktop_application_group.desktop.id
}

output "session_host_names" {
  value = azurerm_windows_virtual_machine.host[*].computer_name
}

output "domain_controller_ip" {
  value = var.deploy_adds ? var.adds_dc_private_ip : null
}

output "domain_name" {
  value = var.domain_name
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  description = "Local admin password (run: terraform output -raw admin_password)."
  value       = local.admin_password
  sensitive   = true
}

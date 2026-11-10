output "host_pool_id" {
  value = azurerm_virtual_desktop_host_pool.this.id
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.this.name
}

output "application_group_id" {
  value = azurerm_virtual_desktop_application_group.desktop.id
}

output "workspace_id" {
  value = azurerm_virtual_desktop_workspace.this.id
}

output "session_host_names" {
  value = azurerm_windows_virtual_machine.sh[*].name
}

output "session_host_private_ips" {
  value = azurerm_network_interface.sh[*].private_ip_address
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}

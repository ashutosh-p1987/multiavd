output "resource_group_name" {
  value = azurerm_resource_group.avd.name
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.personal.name
}

output "workspace_name" {
  value = azurerm_virtual_desktop_workspace.avd.name
}

output "session_host_names" {
  value = azurerm_windows_virtual_machine.session_host[*].name
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  description = "Local admin password (view with: terraform output -raw admin_password)."
  value       = random_password.admin.result
  sensitive   = true
}

output "web_client_url" {
  value = "https://windows.cloud.microsoft/"
}

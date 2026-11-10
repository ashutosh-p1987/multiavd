locals {
  # Exactly one module is deployed (count 0/1), so pick whichever exists.
  avd = one(concat(module.avd_personal, module.avd_multisession))
}

output "machine_type" {
  value = var.machine_type
}

output "resource_group_name" {
  value = azurerm_resource_group.avd.name
}

output "host_pool_id" {
  value = local.avd.host_pool_id
}

output "host_pool_name" {
  value = local.avd.host_pool_name
}

output "application_group_id" {
  value = local.avd.application_group_id
}

output "workspace_id" {
  value = local.avd.workspace_id
}

output "session_host_names" {
  value = local.avd.session_host_names
}

output "session_host_private_ips" {
  value = local.avd.session_host_private_ips
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  description = "Retrieve with: terraform output -raw admin_password"
  value       = local.avd.admin_password
  sensitive   = true
}

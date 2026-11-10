subscription_id = "00000000-0000-0000-0000-000000000000"

# Service principal authentication (leave unset to use `az login`)
tenant_id = "00000000-0000-0000-0000-000000000000"
client_id = "00000000-0000-0000-0000-000000000000"
# client_secret: don't store here - set env var instead:
#   $env:TF_VAR_client_secret = "<secret>"

# "personal" = dedicated VDI per user | "multisession" = pooled shared hosts
machine_type = "personal"

location              = "eastus"
avd_metadata_location = "eastus"
prefix                = "avd"

session_host_count = 2
# vm_size = "Standard_D4s_v5"   # optional; defaults per machine_type

start_vm_on_connect = true
enroll_in_intune    = false

# Entra ID group object IDs
avd_user_group_object_ids  = ["11111111-1111-1111-1111-111111111111"]
avd_admin_group_object_ids = ["22222222-2222-2222-2222-222222222222"]

# ---- personal only ----
personal_desktop_assignment_type = "Automatic"

# ---- multisession only ----
load_balancer_type    = "BreadthFirst"
max_sessions_per_host = 10
# fslogix_vhd_location = "\\\\stavdprofiles.file.core.windows.net\\profiles"

# To use an existing VNet instead:
# create_vnet        = false
# existing_subnet_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/.../subnets/..."

tags = {
  workload    = "avd"
  environment = "dev"
}

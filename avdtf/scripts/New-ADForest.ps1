$ErrorActionPreference = 'Stop'

# Initialise the NTDS data disk as F:
$disk = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1
if ($disk) {
  $disk | Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter F -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'NTDS' -Confirm:$false | Out-Null
}

if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) { exit 0 }  # already a DC

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment

$dsrm = ConvertTo-SecureString '${dsrm_password}' -AsPlainText -Force
Install-ADDSForest -DomainName '${domain_name}' -DomainNetbiosName '${netbios_name}' `
  -SafeModeAdministratorPassword $dsrm -InstallDns `
  -DatabasePath 'F:\NTDS' -LogPath 'F:\NTDS' -SysvolPath 'F:\SYSVOL' `
  -NoRebootOnCompletion -Force -WarningAction SilentlyContinue | Out-Null

# Reboot outside the extension so it reports success
shutdown.exe /r /t 30 /c "AD DS promotion"
exit 0

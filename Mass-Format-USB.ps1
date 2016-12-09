<#
    .SYNOPSIS
    Mass-Format-USB.ps1

    Original Author(s):	Johnathan Milgie

	Version 1.0.0, 12/10/2016

	MIT License
	
	Copyright (c) 2016 Konica Minolta Business Solutions U.S.A., Inc. 
	
	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE. 

    .DESCRIPTION
    Description of the Process/Payload

	Additional Credits:
	Johan Arwidmark
	https://goo.gl/IIIDm9

	Tested On OS Version(s):
	Windows 8.1, 10

    .NOTES

    Revision History
	Version		Date		Description of changes
    --------------------------------------------------------------------------------------------------------------
	1.0.0		12/10/2016	Initial Release

	.EXAMPLE
    .\Mass-Format-USB.ps1

#>

function Get-DeviceLabel{
[void][Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
$title = 'USB Drive Label Entry'
$msg   = 'Please enter the Label for the USB drive(s):'
$script:Labeltext = [Microsoft.VisualBasic.Interaction]::InputBox($msg, $title)
}
Function Get-SelectFolderDialog{
    param([string]$Description="Please Select the drive or folder which contains the source Windows installation media.",[string]$RootFolder="Desktop")
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null     
    $objForm = New-Object System.Windows.Forms.FolderBrowserDialog
    $objForm.Rootfolder = $RootFolder
    $objForm.Description = $Description
    $Show = $objForm.ShowDialog()
    If ($Show -eq "OK"){
        $script:MDTMedia = $objForm.SelectedPath + "\*"
    }
    Else{
        Write-Error "Operation cancelled by user."
        Break
    }
}
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script from a PowerShell window running as Administrator!"
	Break
}
$Disks = Get-Disk | Where-Object {$_.Path -match "USBSTOR"}
If (-not $Disks){
    Write-Warning "No USB drives were found. Exiting."
    Break
}

Get-SelectFolderDialog
Get-DeviceLabel
# Enumerate the USB sticks, format them with NTFS and make them active
foreach ($testDisk in $Disks)
{
    Write-Output $testDisk.FriendlyName
}
 
Read-Host "`nThe above disks will be wiped. If this is not correct, please hit CTRL-C to cancel, or press Enter to continue...`n"
 
foreach ($Disk in $Disks)
{
    Write-Output "Processing Disk number: $($Disk.Number)"
     
    # Clean the disk
    Clear-Disk –InputObject $Disk -RemoveData –confirm:$False
 
    # Create the new partition, format with NTFS, assign drive letter and a label
    $Partition = New-Partition –InputObject $Disk -UseMaximumSize
    Format-Volume -NewFileSystemLabel "$Labeltext" -FileSystem NTFS -Partition $Partition –Confirm:$False
    Add-PartitionAccessPath -DiskNumber $Disk.Number -PartitionNumber 1 -AssignDriveLetter
 
    # Make the USB stick active
    Set-Partition -DiskNumber $Disk.Number -PartitionNumber 1 -IsActive $True
}

# Enumerate the USB Sticks and copy the MDT OEM Media to them (asynchronously)

$Disks = Get-Disk | Where-Object {$_.Path -match "USBSTOR"}
foreach ($Disk in $Disks)
{
    Write-Output "Processing Disk number: $($Disk.Number)"
    $Drive  = Get-Partition -DiskNumber $Disk.Number -PartitionNumber 1
    Start-Job -Scriptblock{ 
        param($MDTMedia,$Destination) 
        Copy-Item $MDTMedia $Destination -Recurse -Force
    } -ArgumentList $MDTMedia,($Drive.DriveLetter+":\")
     
    # Output job info
    Write-Output "`nWaiting for completion...`n"
    Get-Job | ? {$_.State -eq 'Complete' -and $_.HasMoreData} | % {Receive-Job $_}
    }
    while((Get-Job -State Running).count){
        Get-Job | ? {$_.State -eq 'Complete' -and $_.HasMoreData} | % {Receive-Job $_}
        start-sleep -seconds 1
     
}

# Enumerate the USB Sticks and eject them
$Disks = Get-Disk | Where-Object {$_.Path -match "USBSTOR"}
foreach ($Disk in $Disks)
{
    Write-Output "Processing Disk number: $($Disk.Number)"
    $Drive  = Get-Partition -DiskNumber $Disk.Number -PartitionNumber 1
    $driveEject = New-Object -comObject Shell.Application
    $driveEject.Namespace(17).ParseName($Drive.DriveLetter+":").InvokeVerb("Eject")
}
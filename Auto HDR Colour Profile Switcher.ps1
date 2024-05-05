# Note that folders in the registry are called keys
# You can delete everything inside the "Display" key at the following registry path to clear all your current colour management settings and start again. This will it easier to find the currently used ones. They will regenerate as soon as you open the colour management panel in windows again.
# THIS WILL FULLY CLEAR ALL COLOUR PROFILES FROM ALL MONITORS. Though the actual profile files won't be deleted so you can just re-add them in the colour management panel
# If you don't want that, then see the $registryMonitorKey comment for how to find the correct group another way using the individial display.
$registryPrePath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display\'

# Once you have regenerated the display grouping enter the long string here. It may stop working at some point if windows decides to make a new one for some reason.
$registryDisplayGroupKey = '{4d36e96e-e325-11ce-bfc1-08002be10318}'

# To find the individual monitor key which corresponds individual monitor, you can refresh the registry while toggling "use my settings for this device" on the correct monitor in the colour management panel. This will change the entry in the registry called "UsePerUserProfiles". Note that you will need to refresh the registry using F5 or the view menu as its not dynamic.
$registryMonitorKey = '0003'



# Both of the following profiles should be installed in "C:\Windows\System32\spool\drivers\color"

# The file name of your advanced colour profile for HDR. This is usually your result from the windows HDR calibration tool
$HDRProfileName = 'XB1.icc'
# The file name of your SDR advanced colour profile with a corrected gamma curve. See here to get profiles: https://github.com/dylanraga/win11hdr-srgb-to-gamma2.2-icm
$SDRProfileName = 'B30.icm'


#Delay between process scans whenever a process is terminated. This helps limit the hammering your CPU so much.
$processCheckDelay = 5

# Show windows notification on colour profile change
# use $true or $false because that's how powershell works
$enableNotifications = $false


# Enter each exe name here but WITHOUT the ".exe" part
$programWhitelist = @(
	'ManorLords-WinGDK-Shipping'
	'notepad++'
	'paintdotnet'
)





# END OF USER SETTINGS







$Name = 'ICMProfileAC'
$fullRegistryPath = $registryPrePath + $registryDisplayGroupKey + '\' + $registryMonitorKey + '\'

$lastTime = 0
$hasRecentlyChecked = $false
$queuedCheck = $false
$global:currentProfile = ""

# show windows action centre notification with input text params
function Show-Notification {
	param (
        $Text1,
		$Text2
    )

	$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
	[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]

	$Template = [Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText01

	#Gets the Template XML so we can manipulate the values
	[xml]$ToastTemplate = ([Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($Template).GetXml())

	[xml]$ToastTemplate = @"
	<toast launch="app-defined-string">
	  <visual>
		<binding template="ToastGeneric">
		  <text>
			$Text1
			$Text2
		  </text>
		</binding>
	  </visual>
	</toast>
"@

	$ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
	$ToastXml.LoadXml($ToastTemplate.OuterXml)

	$notify = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app)

	$notify.Show($ToastXml)	
}


function New-ProcessEvent {
	param (
        $procName
    )	
	$qu = "Select * from win32_ProcessStartTrace where processname = '" + $procName + ".exe'"

	Register-CimIndicationEvent -Query $qu -SourceIdentifier $procName
	Write-Host "registered new start event for process:" $procname
}

function CheckProcesses {
	[Console]::WriteLine("Checking active processes")
	$processNames = Get-Process | Select-Object -ExpandProperty ProcessName
	$active = Compare-Object -ReferenceObject $programWhitelist -DifferenceObject $processNames -ExcludeDifferent -IncludeEqual | Select-Object -ExpandProperty InputObject
	Write-Output $active
}

function SetHDRProfile{
	if ($currentProfile -eq "HDR"){return}
	[Console]::WriteLine("Enabling HDR profile" )
	New-ItemProperty -Path $fullRegistryPath -Name $Name -Value $HDRProfileName -PropertyType MultiString -Force > $null
	Start-ScheduledTask -TaskName "update active colour profiles"
	$global:currentProfile = "HDR"
	if ($enableNotifications){
		$t1 = "Enabled HDR Profile:`r`n" + $HDRProfileName
		Show-Notification -Text1 $t1 > $null
	}
}

function setSDRProfile{
	if ($currentProfile -eq "SDR"){return}
	[Console]::WriteLine("Enabling SDR profile" )
	New-ItemProperty -Path $fullRegistryPath -Name $Name -Value $SDRProfileName -PropertyType MultiString -Force > $null
	Start-ScheduledTask -TaskName "update active colour profiles"
	$global:currentProfile = "SDR"
	if ($enableNotifications){
		$t1 = "Enabled SDR Profile:`r`n" + $SDRProfileName
		Show-Notification -Text1 $t1  > $null
	}
}

function GetUnixTime {	
	$DateTime = (Get-Date).ToUniversalTime()
	$UnixTimeStamp = [System.Math]::Truncate((Get-Date -Date $DateTime -UFormat %s))
	Write-Output $UnixTimeStamp	
}


function start-init {

	[Console]::WriteLine("Creating events for exe files")	
	foreach ($p in $programWhitelist)
	{
		New-ProcessEvent -procName $p
	}
	
	$quend = "Select * from win32_ProcessStopTrace"	
	Register-CimIndicationEvent -Query $quend -SourceIdentifier "endevent"
	[Console]::WriteLine("registered new global end event called: endevent")


	[Console]::WriteLine("Checking active processes")
	$processNames = Get-Process | Select-Object -ExpandProperty ProcessName
	$active = Compare-Object -ReferenceObject $programWhitelist -DifferenceObject $processNames -ExcludeDifferent -IncludeEqual | Select-Object -ExpandProperty InputObject


	if ($active.length -eq 0){
		setSDRProfile
	}
	else {
		SetHDRProfile
	}
	
	$lastTime = GetUnixTime - $processCheckDelay

	[Console]::WriteLine("Startup Complete")

}


start-init

while($true)
{
	Wait-Event -Timeout $processCheckDelay > $null
	
	# if no event, check if scan is queued
	$events = Get-Event
	if ($events -eq $null){
		if ($queuedCheck){
			$active = CheckProcesses
			if ($active.length -eq 0){
				setSDRProfile
			}
			$queuedCheck = $false		
			$lastTime = GetUnixTime		
		}
		continue
	}
	
	$currEvent = (Get-Event)[0]
	$currSID = $currEvent.SourceIdentifier
	
	# if event is process stopping
	if ($currSID -eq "endevent"){		
		$newTime = GetUnixTime
		# if too soon since last scan then queue next scan
		if (($newTime - $lastTime) -lt $processCheckDelay ){
			$queuedCheck = $true
			Remove-Event -EventIdentifier $currEvent.EventIdentifier
			continue
		}
		# otherwise scan now
		else{
			$active = CheckProcesses			
			if ($active.length -eq 0){
				setSDRProfile
			}
			$queuedCheck = $false		
			$lastTime = GetUnixTime			
		}		
	}
	# else event is process starting or a timeout
	else {
		if ($queuedCheck){
			$active = CheckProcesses
			if ($active.length -eq 0){
				setSDRProfile
			}
			$queuedCheck = $false		
			$lastTime = GetUnixTime		
		}
		SetHDRProfile
	}

	Remove-Event -EventIdentifier $currEvent.EventIdentifier
	
}

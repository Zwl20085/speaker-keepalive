Stop-ScheduledTask -TaskName SpeakerKeepAlive -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName SpeakerKeepAlive -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*keepalive.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host '已卸载'

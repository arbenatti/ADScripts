$date = (Get-Date) - (New-TimeSpan -Days 90)
Get-ADcomputer -Filter 'lastLogondate -gt $date' | ft

# Select the canonicalName,lastlogondate and name for a more readable list
Get-ADcomputer -Filter 'lastLogondate -gt $date' -properties canonicalName,lastlogondate| Where {$_.Enabled -eq 'True'}| select name,canonicalname,lastlogondate | ft -AutoSize


# Export CSV
Get-ADcomputer -Filter 'lastLogondate -gt $date' -properties canonicalName,lastlogondate| Where {$_.Enabled -eq 'True'}| select name,canonicalname,lastlogondate | Export-Csv C:\datasenior\active-computers.csv

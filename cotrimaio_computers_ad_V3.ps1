$pw = read-host "Enter Password for user cotri\admin.fabionunes" -AsSecureString

Connect-QADService -service '192.168.1.14' -ConnectionAccount 'cotri\admin.fabionunes' -ConnectionPassword $pw

Get-QADComputer -includedproperties lastlogontimestamp -sizelimit 0 | select name, samaccountname, type, parentcontainer, lastLogonTimestamp, AccountIsDisabled, OSName, OSVersion, OSServicePack | Export-Csv c:\temp\cotrimaio_computers_ad_v3.csv -Delimiter ';' -NoTypeInformation
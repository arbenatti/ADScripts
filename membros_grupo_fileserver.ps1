$bsgroup = Get-QADGroup -sizelimit 0 | select name | where {$_.name -match "FS_"}

$dados = @()

foreach ($item in $bsgroup)
{
	$membros = Get-QADGroupMember $item.name -SizeLimit 0 | select name, samaccountname, type, parentcontainer, @{Name="Grupo";Expression={$item.name}}

	if ($membros) {
		$dados+= $membros
	} 

}

$dados | Export-Csv c:\temp\export\membros_grupo_fileserver.csv -Delimiter ';' -NoTypeInformation
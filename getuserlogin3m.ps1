# =============================================
# SCRIPT ATUALIZADO: USU�RIOS HABILITADOS COM LOGIN NOS �LTIMOS 3 MESES
# - Filtra apenas usu�rios habilitados (Enabled = $true)
# - Exclui contas de servi�o e m�quinas
# - Verifica logins hist�ricos + sess�es ativas
# =============================================

Import-Module ActiveDirectory

# Configura��es
$DataLimite = (Get-Date).AddMonths(-3)
$Resultados = @()
$UsuariosComLogin = @{}

# 1. Obter todos os Domain Controllers
Write-Host "[1/4] Identificando Domain Controllers..." -ForegroundColor Cyan
$DomainControllers = Get-ADDomainController -Filter * | Sort-Object Name
Write-Host "Encontrados $($DomainControllers.Count) DCs." -ForegroundColor Green

# 2. Buscar SOMENTE usu�rios habilitados (filtro estrito)
Write-Host "`n[2/4] Buscando usu�rios HABILITADOS no AD..." -ForegroundColor Cyan
$UsuariosHabilitados = Get-ADUser -Filter {
        Enabled -eq $true -and 
        ObjectClass -eq "user"
    } -Properties Name, SamAccountName, LastLogonDate, DistinguishedName, Department, Title, Description, WhenCreated

Write-Host "Total de usu�rios habilitados: $($UsuariosHabilitados.Count)" -ForegroundColor Green

# 3. Verificar �ltimo login em TODOS os DCs
Write-Host "`n[3/4] Verificando �ltimo login em cada DC..." -ForegroundColor Cyan
$i = 0

foreach ($Usuario in $UsuariosHabilitados) {
    $i++
    $UltimoLogin = $null
    $DCOrigem = $null

    foreach ($DC in $DomainControllers) {
        try {
            $LogonData = Get-ADUser -Identity $Usuario.SamAccountName `
                -Server $DC.Name `
                -Properties LastLogon, LastLogonTimestamp `
                -ErrorAction SilentlyContinue

            if ($LogonData) {
                # Converter LastLogon (FileTime) para DateTime
                if ($LogonData.LastLogon -and $LogonData.LastLogon -gt 0) {
                    try {
                        $LoginDate = [DateTime]::FromFileTime($LogonData.LastLogon)
                        if (-not $UltimoLogin -or $LoginDate -gt $UltimoLogin) {
                            $UltimoLogin = $LoginDate
                            $DCOrigem = $DC.Name
                        }
                    } catch {
                        Write-Host "Erro ao converter LastLogon para $($Usuario.SamAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                # Fallback para LastLogonTimestamp
                elseif ($LogonData.LastLogonTimestamp -and $LogonData.LastLogonTimestamp -gt 0) {
                    try {
                        $LoginTimestamp = [DateTime]::FromFileTime($LogonData.LastLogonTimestamp)
                        if (-not $UltimoLogin -or $LoginTimestamp -gt $UltimoLogin) {
                            $UltimoLogin = $LoginTimestamp
                            $DCOrigem = $DC.Name
                        }
                    } catch {
                        Write-Host "Erro ao converter LastLogonTimestamp para $($Usuario.SamAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
        } catch {
            Write-Host "Erro ao consultar $($Usuario.SamAccountName) no DC $($DC.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Armazenar o �ltimo login encontrado APENAS se for v�lido
    if ($UltimoLogin -and $UltimoLogin -is [DateTime] -and $UltimoLogin -gt (Get-Date "1900-01-01")) {
        $UsuariosComLogin[$Usuario.SamAccountName] = @{
            UltimoLogin = $UltimoLogin
            DCOrigem    = $DCOrigem
        }
    } else {
        # Log para usu�rios sem data v�lida
        Write-Host "Usu�rio $($Usuario.SamAccountName) n�o possui data de login v�lida." -ForegroundColor Gray
    }


    # Progresso
    if ($i % 100 -eq 0) { Write-Host "Processados: $i/$($UsuariosHabilitados.Count) usu�rios..." -ForegroundColor Gray }
}

# Calcular dias atr�s corretamente
# Adicionar usu�rios com login nos �ltimos 3 meses
foreach ($Usuario in $UsuariosComLogin.Keys) {
    $InfoLogin = $UsuariosComLogin[$Usuario]
    $UltimoLogin = $InfoLogin.UltimoLogin
    
    # Validar se UltimoLogin � uma data v�lida
    if ($UltimoLogin -and $UltimoLogin -is [DateTime]) {
        try {
            # Verificar se est� dentro do per�odo de 3 meses
            if ($UltimoLogin -ge $DataLimite) {
                # Calcular dias de forma segura
                $DiasAtras = [math]::Round((Get-Date).Subtract($UltimoLogin).TotalDays, 0)
                
                # Buscar informa��es adicionais do usu�rio
                $UsuarioInfo = Get-ADUser $Usuario -Properties Name, Department, Title, Description -ErrorAction SilentlyContinue
                
                $Resultados += [PSCustomObject]@{
                    Nome        = if ($UsuarioInfo) { $UsuarioInfo.Name } else { $Usuario }
                    Login       = $Usuario
                    UltimoLogin = $UltimoLogin.ToString("dd/MM/yyyy HH:mm:ss")
                    DiasAtras   = $DiasAtras
                    DCOrigem    = $InfoLogin.DCOrigem
                    Status      = "Login nos �ltimos 3 meses"
                    Departamento = if ($UsuarioInfo) { $UsuarioInfo.Department } else { "N/A" }
                    Cargo       = if ($UsuarioInfo) { $UsuarioInfo.Title } else { "N/A" }
                }
            }
        } catch {
            Write-Host "Erro ao processar usu�rio $Usuario : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Data inv�lida para usu�rio $Usuario - UltimoLogin: $UltimoLogin" -ForegroundColor Yellow
    }
}


# 5. Combinar resultados (logins hist�ricos + sess�es ativas)
Write-Host "`n[5/5] Gerando relat�rio final (somente usu�rios habilitados)..." -ForegroundColor Cyan

# Adicionar usu�rios com login nos �ltimos 3 meses
foreach ($Usuario in $UsuariosComLogin.Keys) {
    $UltimoLogin = $UsuariosComLogin[$Usuario].UltimoLogin
    if ($UltimoLogin -ge $DataLimite) {
        $Resultados += [PSCustomObject]@{
            Nome          = (Get-ADUser $Usuario -Properties Name).Name
            Login         = $Usuario
            UltimoLogin   = $UltimoLogin
            DCOrigem      = $UsuariosComLogin[$Usuario].DCOrigem
            Status        = "Hist�rico"
            Computador    = "N/A"
        }
    }
}

# Adicionar usu�rios com sess�es ATIVAS (mesmo sem LastLogon recente)
foreach ($Sessao in $SessoesAtivas) {
    $Usuario = $Sessao.Usuario
    $Existente = $Resultados | Where-Object { $_.Login -eq $Usuario }

    if (-not $Existente) {
        $Resultados += [PSCustomObject]@{
            Nome          = (Get-ADUser $Usuario -Properties Name).Name
            Login         = $Usuario
            UltimoLogin   = $Sessao.HorarioLogin
            DCOrigem      = "Sess�o Ativa"
            Status        = "LOGADO AGORA"
            Computador    = $Sessao.Computador
        }
    }
}

# 6. Exibir resultados (somente usu�rios habilitados)
if ($Resultados.Count -gt 0) {
    Write-Host "`n=== USU�RIOS HABILITADOS COM LOGIN NOS �LTIMOS 3 MESES ===" -ForegroundColor Green
    Write-Host "Total: $($Resultados.Count) usu�rios" -ForegroundColor Green
    Write-Host ""

    # Ordenar por data de login (mais recente primeiro)
    $Resultados | Sort-Object UltimoLogin -Descending | Format-Table -Property `
        Nome, Login, @{Name="UltimoLogin"; Expression={$_.UltimoLogin.ToString("dd/MM/yyyy HH:mm")}}, `
        Status, Computador, DCOrigem -AutoSize -Wrap

    # Estat�sticas
    Write-Host "`n--- ESTAT�STICAS (somente usu�rios habilitados) ---" -ForegroundColor Cyan
    Write-Host "Usu�rios LOGADOS AGORA:              $($Resultados.Where({$_.Status -eq "LOGADO AGORA"}).Count)" -ForegroundColor Yellow

    # Exportar para CSV
    $Exportar = Read-Host "`nDeseja exportar para CSV? (S/N)"
    if ($Exportar -eq "S" -or $Exportar -eq "s") {
        $CaminhoCSV = "C:\Temp\Usuarios_Habilitados_Ativos_3Meses_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        if (!(Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" -Force }

        $Resultados | Export-Csv -Path $CaminhoCSV -NoTypeInformation -Encoding UTF8
        Write-Host "Arquivo exportado: $CaminhoCSV" -ForegroundColor Green
    }
} else {
    Write-Host "`nNenhum usu�rio HABILITADO encontrado com login nos �ltimos 3 meses!" -ForegroundColor Red
    Write-Host "Isso pode indicar:" -ForegroundColor Yellow
    Write-Host "  - Todos os usu�rios est�o desabilitados ou s�o contas de servi�o." -ForegroundColor Yellow
    Write-Host "  - Problemas na replica��o do AD." -ForegroundColor Yellow
    Write-Host "  - Usu�rios est�o usando contas locais (n�o do AD)." -ForegroundColor Yellow
}

Write-Host "`nScript finalizado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan

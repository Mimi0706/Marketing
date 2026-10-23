# Collecte les indicateurs publiés par l'annuaire officiel pour-les-personnes-agees.gouv.fr (CNSA)
# pour chaque EHPAD de ehpad.js, et les enregistre dans indicateurs.json (lu ensuite par build-data.ps1).
# Contenu sous Licence Ouverte Etalab 2.0. Les requêtes sont espacées pour ménager le site.
#
# Usage :
#   powershell -ExecutionPolicy Bypass -File collect-indicateurs.ps1               # tous les EHPAD manquants
#   powershell -ExecutionPolicy Bypass -File collect-indicateurs.ps1 -Dep 69       # un seul département
#   powershell -ExecutionPolicy Bypass -File collect-indicateurs.ps1 -Refresh      # recollecter la sélection (même déjà en cache)
param([string]$Dep = "", [switch]$Refresh, [int]$DelayMs = 250)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cacheFile = Join-Path $here 'indicateurs.json'
$api = 'https://www.pour-les-personnes-agees.gouv.fr/api/v1/establishment?_format=json&etab_nofinesset='

# Liste des EHPAD (id + département) depuis ehpad.js
$ids = Select-String -Path (Join-Path $here 'ehpad.js') -Pattern '"id":"(\w+)".*?"d":"(\w+)"' -Encoding UTF8 |
    ForEach-Object { [pscustomobject]@{ id = $_.Matches[0].Groups[1].Value; d = $_.Matches[0].Groups[2].Value } } |
    Where-Object { -not $Dep -or $_.d -eq $Dep }

# Cache existant
$cache = @{}
if (Test-Path $cacheFile) {
    $json = [IO.File]::ReadAllText($cacheFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) { $cache[$p.Name] = $p.Value }
}

function Save-Cache {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("{`n")
    $keys = @($cache.Keys | Sort-Object)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        [void]$sb.Append("`"$($keys[$i])`":" + ($cache[$keys[$i]] | ConvertTo-Json -Compress -Depth 3))
        if ($i -lt $keys.Count - 1) { [void]$sb.Append(",`n") }
    }
    [void]$sb.Append("`n}`n")
    [IO.File]::WriteAllText($cacheFile, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
}

$todo = @($ids | Where-Object { $Refresh -or -not $cache.ContainsKey($_.id) })
Write-Host "$($todo.Count) EHPAD à collecter ($($ids.Count) dans la sélection, $($cache.Count) déjà en cache)"
$n = 0; $errors = 0
foreach ($e in $todo) {
    $n++
    try {
        # Le site renvoie parfois une erreur 503 passagère : jusqu'à 3 nouveaux essais espacés
        for ($try = 1; ; $try++) {
            try { $r = Invoke-RestMethod ($api + $e.id) -TimeoutSec 30; break }
            catch { if ($try -ge 4) { throw }; Start-Sleep -Seconds (2 * $try) }
        }
        $o = @($r)[0]
        $ind = $o.indicators
        $rec = [ordered]@{ ok = 1 }
        if ($ind) {
            $rec.an = $ind.indEHPADAnnee                 # année des données
            $rec.enc = $ind.indEHPADEncadrement          # taux d'encadrement (ETP pour 100 résidents)
            $rec.encM = $ind.indEHPADEncadrementMoyenne
            $rec.rot = $ind.indEHPADRotation             # taux de rotation du personnel (%)
            $rec.rotM = $ind.indEHPADRotationMoyenne
            $rec.abs = $ind.indEHPADAbsenteisme          # taux d'absentéisme (%)
            $rec.absM = $ind.indEHPADAbsenteismeMoyenne
            $rec.med = $ind.indEHPADMedCoordo            # médecin coordonnateur (1/0)
            $rec.inf = $ind.indEHPADInfirmierNuit        # infirmier de nuit (1/0)
            $rec.cs = $ind.indEHPADChambreSeule
            $rec.cd = $ind.indEHPADChambreDouble
            $rec.ash = $ind.indEHPADPlacesASH
            $eq = @()
            if ($ind.indEHPADBalneo) { $eq += 'Balnéothérapie' }
            if ($ind.indEHPADSalleStimulation) { $eq += 'Salle de stimulation sensorielle' }
            if ($ind.indEHPADSalleKine) { $eq += 'Salle de kinésithérapie' }
            if ($ind.indEHPADAteliersPedagogiques) { $eq += 'Ateliers pédagogiques' }
            if ($ind.indEHPADPharmacie) { $eq += 'Pharmacie à usage intérieur' }
            $rec.eq = $eq
        }
        $unites = @()
        if ($o.IsALZH) { $unites += 'Unité Alzheimer' }
        if ($o.IsPASA) { $unites += 'PASA (activités adaptées)' }
        if ($o.IsUHR) { $unites += 'UHR (hébergement renforcé)' }
        $rec.un = $unites
        $rec.vt = [int][bool]$o.isViaTrajectoire
        $cache[$e.id] = $rec
        $consecutive = 0
    } catch {
        $errors++; $consecutive++
        Write-Host "  $($e.id) : $($_.Exception.Message)"
        if ($consecutive -ge 20) { Write-Host "20 erreurs d'affilée : le site semble indisponible, arrêt (relancer plus tard pour reprendre)."; break }
    }
    if ($n % 100 -eq 0) { Save-Cache; Write-Host "  $n / $($todo.Count)" }
    Start-Sleep -Milliseconds $DelayMs
}
Save-Cache
Write-Host "Terminé : $n EHPAD traités, $errors erreurs, $($cache.Count) en cache."

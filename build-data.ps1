# Génère ehpad.js (liste des EHPAD géolocalisés) à partir de l'extraction FINESS de data.gouv.fr
# Usage : powershell -ExecutionPolicy Bypass -File build-data.ps1
# (les fichiers sources sont téléchargés automatiquement ; on peut aussi passer des fichiers déjà téléchargés)
param([string]$Csv = "", [string]$EquipCsv = "", [string]$EjCsv = "", [string]$HasXlsx = "")

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-DataFile([string]$datasetId, [string]$pattern, [string]$ext = 'csv') {
    $path = Join-Path ([IO.Path]::GetTempPath()) "$pattern.$ext"
    $meta = Invoke-RestMethod "https://www.data.gouv.fr/api/1/datasets/$datasetId/"
    $res = $meta.resources | Where-Object { $_.url -like "*$pattern*" } | Select-Object -First 1
    Write-Host "Téléchargement de $($res.title)..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $res.url -OutFile $path
    $path
}

# Établissements géolocalisés
if (-not $Csv) { $Csv = Get-DataFile '53699569a3a729239d2046eb' 'cs1100507' }
# Équipements sociaux et médico-sociaux (capacités)
if (-not $EquipCsv) { $EquipCsv = Get-DataFile '5369956ca3a729239d204701' 'cs1100505' }
# Entités juridiques (gestionnaires et statut juridique)
if (-not $EjCsv) { $EjCsv = Get-DataFile '5369956ba3a729239d2046fc' 'cs1100501' }
# Évaluations qualité HAS des ESSMS
if (-not $HasXlsx) { $HasXlsx = Get-DataFile '693822a461b1b759069eba97' 'open_data_par_essms.xlsx' 'xlsx' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
# Lit la 1re feuille d'un .xlsx : renvoie une hashtable { lettre de colonne -> valeur } par ligne
function Read-Xlsx([string]$path) {
    $z = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $ss = New-Object System.Collections.Generic.List[string]
        $e = $z.GetEntry('xl/sharedStrings.xml')
        if ($e) {
            $r = [Xml.XmlReader]::Create($e.Open())
            while (-not $r.EOF) {
                if ($r.NodeType -eq 'Element' -and $r.LocalName -eq 'si') { $ss.Add(([xml]$r.ReadOuterXml()).DocumentElement.InnerText) }
                else { [void]$r.Read() }
            }
            $r.Close()
        }
        $r = [Xml.XmlReader]::Create($z.GetEntry('xl/worksheets/sheet1.xml').Open())
        while (-not $r.EOF) {
            if ($r.NodeType -eq 'Element' -and $r.LocalName -eq 'row') {
                $row = @{}
                foreach ($c in ([xml]$r.ReadOuterXml()).DocumentElement.ChildNodes) {
                    if ($c.LocalName -ne 'c') { continue }
                    $col = $c.GetAttribute('r') -replace '\d', ''
                    $row[$col] = if ($c.GetAttribute('t') -eq 's') { $ss[[int]$c.InnerText] } else { $c.InnerText }
                }
                $row
            } else { [void]$r.Read() }
        }
        $r.Close()
    } finally { $z.Dispose() }
}

Add-Type -TypeDefinition @'
using System;
public static class Proj {
    // Lambert-93 (EPSG:2154) -> WGS84
    public static double[] Lambert93(double x, double y) {
        double n = 0.7256077650532670, c = 11754255.426096, xs = 700000, ys = 12655612.049876;
        double e = 0.08181919112823, lon0 = 3 * Math.PI / 180;
        double dx = x - xs, dy = y - ys;
        double R = Math.Sqrt(dx * dx + dy * dy);
        double gamma = Math.Atan(dx / -dy);
        double lon = lon0 + gamma / n;
        double L = -1 / n * Math.Log(Math.Abs(R / c));
        double phi = 2 * Math.Atan(Math.Exp(L)) - Math.PI / 2;
        for (int i = 0; i < 20; i++) {
            double es = e * Math.Sin(phi);
            phi = 2 * Math.Atan(Math.Pow((1 + es) / (1 - es), e / 2) * Math.Exp(L)) - Math.PI / 2;
        }
        return new double[] { phi * 180 / Math.PI, lon * 180 / Math.PI };
    }
    // UTM (ellipsoïde GRS80/WGS84) -> lat/lon
    public static double[] Utm(double x, double y, int zone, bool south) {
        double a = 6378137, f = 1 / 298.257222101, k0 = 0.9996;
        double e2 = f * (2 - f), ep2 = e2 / (1 - e2);
        x -= 500000; if (south) y -= 10000000;
        double M = y / k0;
        double mu = M / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
        double e1 = (1 - Math.Sqrt(1 - e2)) / (1 + Math.Sqrt(1 - e2));
        double p1 = mu + (3 * e1 / 2 - 27 * Math.Pow(e1, 3) / 32) * Math.Sin(2 * mu)
            + (21 * e1 * e1 / 16 - 55 * Math.Pow(e1, 4) / 32) * Math.Sin(4 * mu)
            + (151 * Math.Pow(e1, 3) / 96) * Math.Sin(6 * mu) + (1097 * Math.Pow(e1, 4) / 512) * Math.Sin(8 * mu);
        double C1 = ep2 * Math.Cos(p1) * Math.Cos(p1), T1 = Math.Tan(p1) * Math.Tan(p1);
        double N1 = a / Math.Sqrt(1 - e2 * Math.Sin(p1) * Math.Sin(p1));
        double R1 = a * (1 - e2) / Math.Pow(1 - e2 * Math.Sin(p1) * Math.Sin(p1), 1.5);
        double D = x / (N1 * k0);
        double lat = p1 - (N1 * Math.Tan(p1) / R1) * (D * D / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * Math.Pow(D, 4) / 24
            + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * Math.Pow(D, 6) / 720);
        double lon = (D - (1 + 2 * T1 + C1) * Math.Pow(D, 3) / 6
            + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * Math.Pow(D, 5) / 120) / Math.Cos(p1);
        return new double[] { lat * 180 / Math.PI, (zone * 6 - 183) + lon * 180 / Math.PI };
    }
}
'@

$lines = [System.IO.File]::ReadAllLines($Csv, [System.Text.Encoding]::UTF8)
$dataDate = ($lines[0] -split ';')[3]

$ehpad = @{}
$geo = @{}
foreach ($l in $lines) {
    if ($l.StartsWith('structureet;')) {
        $f = $l -split ';'
        if ($f[18] -eq '500') { $ehpad[$f[1]] = $f }
    } elseif ($l.StartsWith('geolocalisation;')) {
        $f = $l -split ';'
        $geo[$f[1]] = $f
    }
}

# Capacités installées par EHPAD (colonne 18 = capacité installée totale)
#   p  : hébergement permanent  (discipline 924, activité 11 internat)
#   tp : hébergement temporaire (discipline 657, activité 11)
#   aj : accueil de jour        (disciplines 924/657, activité 21)
# Le fichier croise autorisations et installations : une même installation peut apparaître
# sur plusieurs lignes, on ne la compte qu'une fois (clé = équipement + colonnes d'installation).
$cap = @{}
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in [System.IO.File]::ReadAllLines($EquipCsv, [System.Text.Encoding]::UTF8)) {
    if (-not $l.StartsWith('equipementsocial;')) { continue }
    $f = $l -split ';'
    if (-not $ehpad.ContainsKey($f[1]) -or -not $f[18]) { continue }
    if (-not $seen.Add((@($f[1], $f[2], $f[4], $f[6]) + $f[18..26]) -join '|')) { continue }
    $k = if ($f[4] -eq '11' -and $f[2] -eq '924') { 'p' }
         elseif ($f[4] -eq '11' -and $f[2] -eq '657') { 'tp' }
         elseif ($f[4] -eq '21' -and ($f[2] -eq '924' -or $f[2] -eq '657')) { 'aj' }
         else { $null }
    if (-not $k) { continue }
    if (-not $cap[$f[1]]) { $cap[$f[1]] = @{ p = 0; tp = 0; aj = 0 } }
    $cap[$f[1]][$k] += [int]$f[18]
}

# Prix CNSA : chaque fichier ne contient que les EHPAD ayant déclaré leurs prix sur la période.
# On prend les fichiers annuels + les mensuels postérieurs, et on garde la déclaration la plus récente.
$prix = @{}
$cnsa = (Invoke-RestMethod 'https://www.data.gouv.fr/api/1/datasets/5fc113baffccb502d3fe204e/').resources |
    Where-Object { $_.title -match '_(\d{4})(\d{2})?_brute\.csv$' } |
    ForEach-Object { [pscustomobject]@{ url = $_.url; year = [int]$Matches[1]; month = $Matches[2] } }
$lastYear = ($cnsa | Where-Object { -not $_.month } | Measure-Object year -Maximum).Maximum
$cnsaFiles = $cnsa | Where-Object { (-not $_.month) -or ($_.year -gt $lastYear) }
Write-Host "Téléchargement de $(@($cnsaFiles).Count) fichiers de prix CNSA..."
$frNum = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
function Num([string]$s) { if ($s) { [Math]::Round([double]::Parse($s, $frNum), 2) } else { $null } }
foreach ($file in $cnsaFiles) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'cnsa-prix.csv'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $file.url -OutFile $tmp
    foreach ($r in (Import-Csv $tmp -Delimiter ';' -Encoding UTF8)) {
        $id = $r.finessEt
        if (-not $ehpad.ContainsKey($id)) { continue }
        if ($prix[$id] -and $prix[$id].maj -ge $r.DATE_MAJ) { continue }
        $prix[$id] = @{
            maj = $r.DATE_MAJ
            pc = Num $r.prixHebPermCs; pd = Num $r.prixHebPermCd; pa = Num $r.prixHebPermCsa
            tc = Num $r.prixHebTempCs
            g = @((Num $r.TARIF_GIR_12), (Num $r.TARIF_GIR_34), (Num $r.TARIF_GIR_56))
        }
    }
}

# Gestionnaires : nom et catégorie de statut juridique (codes FINESS : < 40 public,
# 40-69 privé non lucratif, >= 70 privé commercial)
$ej = @{}
foreach ($l in [System.IO.File]::ReadAllLines($EjCsv, [System.Text.Encoding]::UTF8)) {
    if (-not $l.StartsWith('structureej;')) { continue }
    $f = $l -split ';'
    $code = 0; [void][int]::TryParse($f[16], [ref]$code)
    $ej[$f[1]] = @{
        nom = $(if ($f[3]) { $f[3] } else { $f[2] })
        st  = $(if ($code -lt 40) { 'pub' } elseif ($code -lt 70) { 'pnl' } else { 'com' })
    }
}

# Évaluation qualité HAS : niveau global A-D, critères impératifs atteints et cotations (sur 4) des
# 9 thématiques transversales. On garde l'évaluation la plus récente de chaque EHPAD.
Write-Host "Lecture des évaluations HAS (quelques minutes)..."
$has = @{}
$hcol = $null
foreach ($row in (Read-Xlsx $HasXlsx)) {
    if (-not $hcol) { $hcol = @{}; foreach ($k in $row.Keys) { $hcol[$row[$k]] = $k }; continue }
    $id = $row[$hcol['finess_geo']]
    if (-not $ehpad.ContainsKey($id)) { continue }
    $niv = $row[$hcol['indice_qualite']]
    if (-not $niv) { continue }
    $fin = [int]$row[$hcol['eval_date_fin']]  # date au format numérique Excel
    if ($has[$id] -and $has[$id].fin -ge $fin) { continue }
    $th = foreach ($i in 1..9) {
        $v = $row[$hcol["cotation_globale_thematique_0.$i"]]
        if ($v) { [Math]::Round([double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture), 2) } else { $null }
    }
    $atteints = $row[$hcol['nb_ci_atteints']]
    $has[$id] = @{
        fin = $fin; niv = $niv
        ci = $(if ($atteints) { "$atteints/$($row[$hcol['nb_ci']])" } else { $null })
        th = @($th)
    }
}

# GIR moyen pondéré (GMP) : publié uniquement en moyenne par département (CNSA).
# On garde l'année la plus récente disponible pour chaque département, avec les codes FINESS.
Write-Host "Téléchargement des GMP départementaux (CNSA)..."
$gmpDep = @{}
$depFiness = @{ '971' = '9A'; '972' = '9B'; '973' = '9C'; '974' = '9D'; '976' = '9F' }
$gmpRows = Invoke-RestMethod 'https://data-autonomie.cnsa.fr/api/explore/v2.1/catalog/datasets/gir_moyen_pondere_moyens_par_departement/exports/json'
foreach ($r in ($gmpRows | Sort-Object { [int]$_.annee }, { $_.ndeg_dep -eq '69' })) {
    if ($null -eq $r.gmp_moyen_departemental) { continue }
    $codes = switch ($r.ndeg_dep) { '2A/2B' { '2A', '2B' } '69M' { '69' } default { $r.ndeg_dep } }
    foreach ($c in $codes) {
        if ($depFiness[$c]) { $c = $depFiness[$c] }
        $gmpDep[$c] = @([Math]::Round([double]$r.gmp_moyen_departemental), [int]$r.annee)
    }
}
$lastGmp = ($gmpRows | ForEach-Object { [int]$_.annee } | Measure-Object -Maximum).Maximum
$gmpVals = @($gmpRows | Where-Object { [int]$_.annee -eq $lastGmp -and $_.gmp_moyen_departemental } | ForEach-Object { [double]$_.gmp_moyen_departemental })
$gmpMoyen = [Math]::Round(($gmpVals | Measure-Object -Average).Average)

# Indicateurs de l'annuaire officiel (personnel, médecin, chambres...), collectés par collect-indicateurs.ps1
$indic = @{}
$indicFile = Join-Path $here 'indicateurs.json'
if (Test-Path $indicFile) {
    $json = [IO.File]::ReadAllText($indicFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) { $indic[$p.Name] = $p.Value }
    Write-Host "$($indic.Count) EHPAD avec indicateurs de l'annuaire officiel"
} else {
    Write-Host "indicateurs.json absent : lancer collect-indicateurs.ps1 pour ajouter les indicateurs de personnel"
}

# Population au 1er janvier (INSEE, API Melodi) : 75 ans et plus et population totale par département,
# pour rapporter l'offre à la population concernée (agrégation au département avant jointure).
Write-Host "Téléchargement des populations départementales (INSEE)..."
$popYear = (Get-Date).Year - 1
$pop = @{}
$url = "https://api.insee.fr/melodi/data/DS_ESTIMATION_POPULATION?GEO=DEP&TIME_PERIOD=$popYear&SEX=_T&EP_MEASURE=POP_JAN_1ST" +
    "&AGE=_T&AGE=Y75T79&AGE=Y80T84&AGE=Y85T89&AGE=Y90T94&AGE=Y_GE95&maxResult=1000"
while ($url) {
    $resp = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 120
    $page = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    foreach ($o in $page.observations) {
        $code = ($o.dimensions.GEO -split '-')[-1]
        if ($depFiness[$code]) { $code = $depFiness[$code] }
        if (-not $pop[$code]) { $pop[$code] = @{ tot = 0; p75 = 0 } }
        $v = [double]$o.measures.OBS_VALUE_NIVEAU.value
        if ($o.dimensions.AGE -eq '_T') { $pop[$code].tot = $v } else { $pop[$code].p75 += $v }
    }
    $url = if ($page.paging.isLast -eq $false -and $page.paging.next) { $page.paging.next } else { $null }
}

function Clean([string]$s) { ($s -replace '\s+', ' ').Trim() }
$ci = [System.Globalization.CultureInfo]::InvariantCulture
$out = New-Object System.Collections.Generic.List[string]
$missing = 0
foreach ($id in $ehpad.Keys) {
    $f = $ehpad[$id]; $g = $geo[$id]
    if (-not $g -or -not $g[2]) { $missing++; continue }
    $x = [double]::Parse($g[2], $ci); $y = [double]::Parse($g[3], $ci); $src = $g[4]
    if ($src -match '2154') { $p = [Proj]::Lambert93($x, $y) }
    elseif ($src -match 'zone (\d+)([NS])') { $p = [Proj]::Utm($x, $y, [int]$Matches[1], $Matches[2] -eq 'S') }
    else { $missing++; continue }

    $nom = Clean $(if ($f[4]) { $f[4] } else { $f[3] })
    $adr = Clean (@($f[7], $f[8], $f[9], $f[10], $f[11]) -join ' ')
    $cpVille = Clean $f[15]
    $rec = [ordered]@{
        id = $id
        n  = $nom
        a  = $adr
        v  = $cpVille
        d  = $f[13]
        t  = (Clean $f[16])
        h  = $(if ($f[25] -match 'non h') { 0 } else { 1 })  # habilité à l'aide sociale
        p  = $(if ($cap[$id]) { $cap[$id].p } else { $null })
        tp = $(if ($cap[$id]) { $cap[$id].tp } else { $null })
        aj = $(if ($cap[$id]) { $cap[$id].aj } else { $null })
        la = [Math]::Round($p[0], 5)
        lo = [Math]::Round($p[1], 5)
    }
    # Prix journaliers en euros : pc chambre seule, pd chambre double, pa chambre seule tarif aide sociale,
    # tc chambre seule temporaire, g tarifs dépendance GIR 1-2 / 3-4 / 5-6, pm date de déclaration
    $px = $prix[$id]
    if ($px) {
        foreach ($k in 'pc', 'pd', 'pa', 'tc') { if ($px[$k] -ne $null) { $rec[$k] = $px[$k] } }
        if ($px.g[2] -ne $null) { $rec.g = $px.g }
        $rec.pm = $px.maj.Substring(0, 10)
    }
    # Gestionnaire : gn nom, st statut (pub / pnl / com)
    $g = $ej[$f[2]]
    if ($g) { $rec.gn = (Clean $g.nom); $rec.st = $g.st }
    # Qualité HAS : q niveau A-D, qd date de fin d'évaluation, qc critères impératifs atteints, qt thématiques
    $q = $has[$id]
    if ($q) {
        $rec.q = $q.niv
        $rec.qd = [DateTime]::FromOADate($q.fin).ToString('yyyy-MM-dd')
        if ($q.ci) { $rec.qc = $q.ci }
        $rec.qt = $q.th
    }
    # Annuaire officiel : i = indicateurs bruts (voir collect-indicateurs.ps1 pour le sens des champs)
    $ind = $indic[$id]
    if ($ind) { $rec.i = $ind }
    $out.Add(($rec | ConvertTo-Json -Compress))
}

$gmpJs = ($gmpDep.GetEnumerator() | Sort-Object Name | ForEach-Object { "`"$($_.Name)`":[$($_.Value[0]),$($_.Value[1])]" }) -join ','
$js = "window.EHPAD_DATE='$dataDate';`n" +
    "// GMP moyen des EHPAD par département [valeur, année] et moyenne des départements pour $lastGmp`n" +
    "window.GMP_DEP={$gmpJs};`nwindow.GMP_MOYEN=[$gmpMoyen,$lastGmp];`n" +
    "// Population INSEE au 1er janvier $popYear par département : [totale, 75 ans et plus]`n" +
    "window.POP_DEP={" + (($pop.GetEnumerator() | Sort-Object Name | ForEach-Object { "`"$($_.Name)`":[$($_.Value.tot),$($_.Value.p75)]" }) -join ',') + "};`n" +
    "window.POP_YEAR=$popYear;`nwindow.EHPAD=[`n" + ($out -join ",`n") + "`n];`n"
[System.IO.File]::WriteAllText((Join-Path $here 'ehpad.js'), $js, (New-Object System.Text.UTF8Encoding $false))
Write-Host "$($out.Count) EHPAD exportés ($missing sans coordonnées, $($prix.Count) avec prix, $($has.Count) évalués par la HAS) - données du $dataDate"

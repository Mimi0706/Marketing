# Génère ehpad.js (liste des EHPAD géolocalisés) à partir de l'extraction FINESS de data.gouv.fr
# Usage : powershell -ExecutionPolicy Bypass -File build-data.ps1 [chemin_du_csv]
param([string]$Csv = "")

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Csv) {
    $Csv = Join-Path $env:TEMP 'finess-geo.csv'
    $meta = Invoke-RestMethod 'https://www.data.gouv.fr/api/1/datasets/53699569a3a729239d2046eb/'
    $res = $meta.resources | Where-Object { $_.url -like '*cs1100507*' } | Select-Object -First 1
    Write-Host "Téléchargement de $($res.title)..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $res.url -OutFile $Csv
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
        la = [Math]::Round($p[0], 5)
        lo = [Math]::Round($p[1], 5)
    }
    $out.Add(($rec | ConvertTo-Json -Compress))
}

$js = "window.EHPAD_DATE='$dataDate';`nwindow.EHPAD=[`n" + ($out -join ",`n") + "`n];`n"
[System.IO.File]::WriteAllText((Join-Path $here 'ehpad.js'), $js, (New-Object System.Text.UTF8Encoding $false))
Write-Host "$($out.Count) EHPAD exportés ($missing sans coordonnées) - données du $dataDate"

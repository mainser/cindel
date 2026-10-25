<#
.SYNOPSIS
Updates the dark benchmark SVG from one run_app_benchmark.ps1 CSV.
.DESCRIPTION
Uses only measured repetitions, arithmetic means and decimal ms/KB, matching
the console. Does not run benchmarks or modify the README.
.EXAMPLE
.\tool\update_benchmark_svg.ps1 -CsvPath .\tool\benchmark\out\app_benchmark_20261025_014526.csv
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\docs\benchmarks\app-benchmark.svg')
)

$ErrorActionPreference = 'Stop'
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$csvFile = Get-Item -LiteralPath $CsvPath
$outputFile = [System.IO.Path]::GetFullPath($OutputPath)
if ($csvFile.FullName -eq $outputFile) {
    throw 'The SVG output must not overwrite the input CSV.'
}
$rows = @(Import-Csv -LiteralPath $csvFile.FullName | Where-Object { $_.phase -eq 'benchmark' })
if ($rows.Count -eq 0) {
    throw 'The CSV contains no measured benchmark rows.'
}
foreach ($column in @('objects', 'repetitions', 'big', 'generated_at_utc')) {
    $values = @($rows | ForEach-Object { $_.$column } | Select-Object -Unique)
    if ($values.Count -ne 1 -or [string]::IsNullOrWhiteSpace($values[0])) {
        throw "Expected a single nonempty $column value for this benchmark run."
    }
}
$objects = [int]::Parse($rows[0].objects, $culture)
$repetitions = [int]::Parse($rows[0].repetitions, $culture)
$big = $rows[0].big.ToLowerInvariant()
if ($objects -le 0 -or $repetitions -le 0 -or $big -notin @('true', 'false')) {
    throw 'Invalid object count, repetition count or big flag.'
}
$date = [DateTimeOffset]::Parse($rows[0].generated_at_utc, $culture).UtcDateTime.ToString('yyyy-MM-dd', $culture)
$benchmarks = @('Get', 'Insert', 'Update', 'Delete', 'Filter Query', 'Filter & Sort Query', 'Database Size')
$databases = @('Cindel', 'Isar', 'Cindel SQLite', 'Isar SQLite')
$positions = @(520, 700, 890, 1084)
if ($rows.Count -ne $benchmarks.Count * $databases.Count * $repetitions) {
    throw 'Incomplete CSV or unexpected benchmark rows.'
}

function ConvertTo-XmlText([string]$Text) {
    return [System.Security.SecurityElement]::Escape($Text)
}

$svg = [System.Collections.Generic.List[string]]::new()
$svg.Add('<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="490" viewBox="0 0 1120 490" role="img" aria-labelledby="title description">')
$svg.Add('<title id="title">Cindel and Isar benchmark results</title>')
$svg.Add("<desc id=`"description`">$($objects.ToString('N0', $culture)) objects, averages of $repetitions measured repetitions, big=$big. Warmup excluded. Times in milliseconds; database size in decimal kilobytes. Lower values are better.</desc>")
$svg.Add('<rect width="1120" height="490" rx="12" fill="#0d1117"/>')
$svg.Add('<rect x="0.5" y="0.5" width="1119" height="489" rx="12" fill="none" stroke="#30363d"/>')
$svg.Add('<g font-family="Arial, Helvetica, sans-serif" fill="#e6edf3">')
$svg.Add('<text x="28" y="46" font-size="25" font-weight="700">Cindel / Isar &#8212; benchmark results</text>')
$svg.Add("<text x=`"28`" y=`"78`" font-size=`"16`" fill=`"#919ba5`">$($objects.ToString('N0', $culture)) objects &#183; $repetitions repetitions &#183; big=$big &#183; arithmetic mean &#183; warmup excluded</text>")
$svg.Add('<path d="M28 105 H1092" stroke="#30363d"/>')
$svg.Add('<rect x="16" y="118" width="1088" height="42" rx="6" fill="#161b22"/>')
$svg.Add('<g font-size="17" font-weight="700">')
$svg.Add('<text x="28" y="145">Benchmark</text>')
$svg.Add('<text x="326" y="145">Unit</text>')
for ($index = 0; $index -lt $databases.Count; $index++) {
    $svg.Add("<text x=`"$($positions[$index])`" y=`"145`" text-anchor=`"end`">$($databases[$index])</text>")
}
$svg.Add('</g>')

for ($index = 0; $index -lt $benchmarks.Count; $index++) {
    $benchmark = $benchmarks[$index]
    $y = 190 + $index * 39
    if ($index % 2 -eq 1) {
        $svg.Add("<rect x=`"16`" y=`"$($y - 26)`" width=`"1088`" height=`"39`" fill=`"#111820`"/>")
    }
    $unit = if ($benchmark -eq 'Database Size') { 'KB' } else { 'ms' }
    $inputUnit = if ($unit -eq 'KB') { 'bytes' } else { 'microseconds' }
    $svg.Add("<text x=`"28`" y=`"$y`" font-size=`"17`">$(ConvertTo-XmlText $benchmark)</text>")
    $svg.Add("<text x=`"326`" y=`"$y`" font-size=`"16`" fill=`"#919ba5`">$unit</text>")
    for ($column = 0; $column -lt $databases.Count; $column++) {
        $database = $databases[$column]
        $samples = @($rows | Where-Object { $_.benchmark -eq $benchmark -and $_.database -eq $database })
        $iterations = @($samples | ForEach-Object { [int]$_.iteration } | Sort-Object -Unique)
        if ($samples.Count -ne $repetitions -or $iterations.Count -ne $repetitions -or
            $iterations[0] -ne 1 -or $iterations[-1] -ne $repetitions) {
            throw "Missing or duplicate repetitions for $benchmark / $database."
        }
        $sum = [decimal]0
        foreach ($sample in $samples) {
            if ($sample.unit -ne $inputUnit) {
                throw "Unexpected unit for $benchmark / $database."
            }
            $value = [decimal]::Parse($sample.value, [System.Globalization.NumberStyles]::Float, $culture)
            if ($value -lt 0) {
                throw "Negative measurement for $benchmark / $database."
            }
            $sum += $value
        }
        $average = [decimal]::Round(($sum / $repetitions / 1000), 1, [MidpointRounding]::AwayFromZero).ToString('F1', $culture)
        $svg.Add("<text x=`"$($positions[$column])`" y=`"$y`" text-anchor=`"end`" font-family=`"Consolas, DejaVu Sans Mono, monospace`" font-size=`"18`">$average</text>")
    }
}
$svg.Add('<path d="M28 446 H1092" stroke="#30363d"/>')
$svg.Add("<text x=`"28`" y=`"471`" font-size=`"12`" fill=`"#919ba5`">Source: $(ConvertTo-XmlText $csvFile.Name) &#183; $date &#183; Lower is better &#183; KB = 1,000 bytes</text>")
$svg.Add('</g>')
$svg.Add('</svg>')

# Validate the entire run before replacing the previous SVG.
$content = ($svg -join "`n") + "`n"
$null = [xml]$content
$null = New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($outputFile))
[System.IO.File]::WriteAllText($outputFile, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "SVG updated: $outputFile"

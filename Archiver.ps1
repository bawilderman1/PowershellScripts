. "$PSScriptRoot\IntradayFunctions.ps1"

$outputDirectory = "$($env:USERPROFILE)\Documents\StockData\IntradayPrices"
$symbol = "SPY"
$year = 2023

ArchiveHandler -Path $outputDirectory -Symbol $symbol -Year $year
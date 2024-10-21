### Example Usage
# $scriptParams = @{
#     ApiKey = (Get-ChildItem -Path Env:/FmpApiKey).Value
#     FromDate = [datetime] "1993-01-01"
#     ToDate = [datetime] "2023-12-31"
#     FileName = "$($env:USERPROFILE)\Documents\StockData\DailyPrices\SPY_Daily.csv"
# }
# & .\DailyPrices.ps1 @scriptParams

param (
    [Parameter(Mandatory, Position=0)][Alias('k')][string] $apiKey,
    [Parameter(Mandatory, Position=1)][Alias('fd')][datetime] $fromDate,
    [Parameter(Mandatory, Position=2)][Alias('td')][datetime] $toDate,
    [Parameter(Mandatory, Position=3)][Alias('f')][string] $fileName,
	[Parameter()][Alias('a')][switch] $append
)

$fromStr = $fromDate.ToString("yyyy-MM-dd")
$toStr = $toDate.ToString("yyyy-MM-dd")
$json = ((Invoke-WebRequest -Uri "https://financialmodelingprep.com/api/v3/historical-price-full/SPY?from=$($fromStr)&to=$($toStr)&apikey=$($apiKey)" -UseBasicParsing).Content 
    | ConvertFrom-Json).historical

$content = $json
    | Sort-Object -Property date 
    | Select-Object -Property @{Name='dt';Expression={$_.date}},open,high,low,close,adjClose,volume

if ($append.IsPresent) {
    $content | Export-Csv -NoHeader -Append -Path $fileName
} else {
    $content | Export-Csv -Path $fileName
}

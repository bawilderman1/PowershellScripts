### Example Usage
# $scriptParams = @{
#     ApiKey = (Get-ChildItem -Path Env:/FmpApiKey).Value
#     Symbol = "SPY"
#     FileName = "$($env:USERPROFILE)\Documents\StockData\Dividends\SPY_Dividends.csv"
# }
# & .\Dividends.ps1 @scriptParams

param (
    [Parameter(Mandatory, Position=0)][Alias('k')][string] $apiKey,
    [Parameter(Mandatory, Position=3)][Alias('s')][string] $symbol,
    [Parameter(Mandatory, Position=3)][Alias('f')][string] $fileName,
	[Parameter()][Alias('a')][switch] $append
)

$json = ((Invoke-WebRequest -Uri "https://financialmodelingprep.com/api/v3/historical-price-full/stock_dividend/$($symbol)?apikey=$($apiKey)" -UseBasicParsing).Content 
    | ConvertFrom-Json).historical

$content = $json
    | Sort-Object -Property date 
    | Select-Object -Property @{Name='dt';Expression={$_.date}},adjDividend,dividend,recordDate,paymentDate,declarationDate

if ($append.IsPresent) {
    $content | Export-Csv -NoHeader -Append -Path $fileName
} else {
    $content | Export-Csv -Path $fileName
}
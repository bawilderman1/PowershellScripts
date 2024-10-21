function ThrottleHandler {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,Position=0)][Alias('t')][timespan] $Throttle,
        [Parameter(Mandatory,Position=1)][Alias('st')][datetime] $StartTime
    )
    $timer = [timespan]((Get-Date) - $StartTime)
    if ($timer.TotalMilliseconds -lt $Throttle.TotalMilliseconds) {
        Start-Sleep -Duration ([timespan]($Throttle - $timer))
    }
}

function Get-ThrottleTimeSpan {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)][Alias('rpm')][int] $RequestsPerMinute
    )

    if ($null -eq $RequestsPerMinute) {
        $RequestsPerMinute = 300
    }
    $requestBufferMs = 5
    $debounceTarget = ((New-TimeSpan -Minutes 1).TotalMilliseconds / $RequestsPerMinute) + $requestBufferMs

    return New-TimeSpan -Milliseconds $debounceTarget
}

function Get-MarketDates {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory, Position=0)][Alias('k')][string] $ApiKey,
    [Parameter(Mandatory, Position=1)][Alias('s')][string] $Symbol,
    [Parameter(Mandatory, Position=2)][Alias('fd')][datetime] $FromDate,
    [Parameter(Mandatory, Position=3)][Alias('td')][datetime] $ToDate
)

    $fromStr = $FromDate.ToString("yyyy-MM-dd")
    $toStr = $ToDate.ToString("yyyy-MM-dd")
    $uri = "https://financialmodelingprep.com/api/v3/historical-price-full/$($Symbol)?from=$($fromStr)&to=$($toStr)&apikey=$($ApiKey)"
    $json = ((Invoke-WebRequest -Uri $uri -UseBasicParsing).Content 
        | ConvertFrom-Json).historical

    $marketDates = $json
        | Sort-Object -Property date 
        | Select-Object -Property @{Name='dt';Expression={([datetime] $_.date).Date}} -Unique 
        | Select-Object -ExpandProperty dt

    # $marketDates = Get-Content -Path "$($env:USERPROFILE)\Documents\StockData\RefData\MarketDates.csv"
    #     | ForEach-Object { [DateTime] $_ }
    #     | Where-Object { $_ -ge $FromDate -and $_ -le $ToDate }

    return $marketDates
}

function Get-DistinctDates {
    [CmdletBinding()]
    param (
        [Parameter(Position=1, Mandatory)][object[]] $Content
    )
    
    $distinctDates = $Content 
        | Sort-Object -Property date 
        | Select-Object -Property @{Name='dt';Expression={([datetime] $_.date).Date}} -Unique 
        | Where-Object { $_.dt -ge $fromDate -and $_.dt -le $toDate }
        | Select-Object -ExpandProperty dt

    return $distinctDates
}

function CsvHandler {
    [CmdletBinding()]
    param (
        [Parameter(Position=1, Mandatory)][object[]] $Content,
        [Parameter(Position=1, Mandatory)][string] $Path,
        [Parameter(Position=2, Mandatory)][string] $Symbol,
        [Parameter(Position=3, Mandatory)][datetime] $DateTime
    )
    $csvFileName = "$($Path)\$($Symbol)_$($DateTime.Year).csv"
    
    $datePrices = $Content 
        | Where-Object { ([datetime] $_.date).Date -eq $DateTime.Date } 
        | Sort-Object -Property date
        | Select-Object -Property @{Name='dttm';Expression={$([datetime] $_.date).ToString("s")}},open,high,low,close,volume

    if (-not (Test-Path -Path $csvFileName)) {
        $datePrices | Export-Csv -Path $csvFileName
    } else {
        $datePrices | Export-Csv -NoHeader -Append -Path $csvFileName
    }
}

function ArchiveHandler { 
    [CmdletBinding()]
    param (
        [Parameter(Position=1, Mandatory)][string] $Path,
        [Parameter(Position=2, Mandatory)][string] $Symbol,
        [Parameter(Position=3, Mandatory)][string] $Year
    )

    Write-Host "Archiving $($Path)\$($Symbol)_$($Year).csv"
    $csvFileName = "$($Path)\$($Symbol)_$($Year).csv"
    $gzFileName = "$($csvFileName).gz"

    if (Test-Path -Path $gzFileName) {
        Remove-Item -Path $gzFileName
    }

    $contentStr = Import-Csv -Path $csvFileName
        | ConvertTo-Csv 
        | Out-String

    try {
        $zipFileStream = New-Object System.IO.FileStream($gzFileName,([IO.FileMode]::Create),([IO.FileAccess]::Write),([IO.FileShare]::None))
        $gzip = New-Object System.IO.Compression.GzipStream($zipFileStream,[System.IO.Compression.CompressionMode]::Compress)
    
        foreach ($line in $contentStr) {
            $lineByteArr = [System.Text.Encoding]::UTF8.GetBytes($line)
            $gzip.Write($lineByteArr, 0, $lineByteArr.Length)
        }
    }
    finally {
        $gzip.Flush()
        $zipFileStream.Close()
    }

    Remove-Item $csvFileName
}

function Set-IntradayPriceSubset {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)][Alias('k')][string] $ApiKey,
        [Parameter(Mandatory, Position=1)][Alias('s')][string] $Symbol,
        [Parameter(Mandatory, Position=2)][Alias('fd')][datetime] $FromDate,
        [Parameter(Mandatory, Position=3)][Alias('td')][datetime] $ToDate,
        [Parameter(Mandatory, Position=4)][Alias('d')][string] $OutputDirectory,
        [Parameter(Mandatory, Position=5)][Alias('ld')][datetime] $LastDate
    )   
    
    $fromStr = $FromDate.ToString("yyyy-MM-dd")
    $toStr = $ToDate.ToString("yyyy-MM-dd")
    $json = (Invoke-WebRequest -Uri "https://financialmodelingprep.com/api/v3/historical-chart/1min/$($Symbol)?from=$($fromStr)&to=$($toStr)&apikey=$($ApiKey)" -UseBasicParsing).Content 
        | ConvertFrom-Json

    if ($null -eq $json) {
        $LastDate = $ToDate
        return $LastDate
    }

    $dates = Get-DistinctDates -Content $json

    foreach ($dateObj in $dates) {
        if (($null -eq $LastDate.Month) -or ($LastDate.Month -ne $dateObj.Month)) {
            $monthExpr = $dateObj.ToString("MMMM yyyy")
            Write-Host "($Symbol) Starting $monthExpr"
        }
        CsvHandler -Content $json -Path $OutputDirectory -Symbol $Symbol -DateTime $dateObj

        $archive = ($null -ne $LastDate.Year) -and ($LastDate.Year -lt $dateObj.Year) -and (Test-Path -Path "$OutputDirectory\$($Symbol)_$($LastDate.Year).csv") ? $true : $false
        if ($archive) {
            ArchiveHandler -Path $OutputDirectory -Symbol $Symbol -Year $LastDate.Year
        }

        $LastDate = $dateObj
    }

    return $LastDate
}

function Set-MissingDatePriceSubset {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)][Alias('k')][string] $ApiKey,
        [Parameter(Mandatory, Position=1)][Alias('s')][string] $Symbol,
        [Parameter(Mandatory, Position=4)][Alias('if')][string] $InputFile,
        [Parameter(Mandatory, Position=4)][Alias('of')][string] $OutputFile
    )

    $missingDates = Get-Content -Path $InputFile
        | Select-Object -Skip 1  
        | ForEach-Object { [datetime] $_ }

    foreach ($missingDate in $missingDates) {
        $missingStr = $missingDate.ToString("yyyy-MM-dd")
        $json = (Invoke-WebRequest -Uri "https://financialmodelingprep.com/api/v3/historical-chart/1min/$($Symbol)?from=$($missingStr)&to=$($missingStr)&apikey=$($ApiKey)" -UseBasicParsing).Content 
            | ConvertFrom-Json

        $datePrices = $json 
            | Where-Object { ([datetime] $_.date).Date -eq $missingDate.Date } 
            | Sort-Object -Property date
            | Select-Object -Property @{Name='dttm';Expression={$([datetime] $_.date).ToString("s")}},open,high,low,close,volume

        if (-not (Test-Path -Path $OutputFile)) {
            $datePrices | Export-Csv -Path $OutputFile
        } else {
            $datePrices | Export-Csv -NoHeader -Append -Path $OutputFile
        }
    }
}
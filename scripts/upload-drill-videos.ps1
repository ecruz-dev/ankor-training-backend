param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$OrgId,

  [Parameter(Mandatory = $true)]
  [string]$Token,

  [Parameter(Mandatory = $true)]
  [string]$Folder,

  [string]$FileName,

  [int]$Limit = 0,

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Test-Uuid {
  param([string]$Value)
  return $Value -match "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
}

function Get-VideoContentType {
  param([System.IO.FileInfo]$File)

  $extension = $File.Extension.ToLowerInvariant()
  if ($extension -eq ".mp4") {
    return "video/mp4"
  }
  if ($extension -eq ".mov") {
    return "video/quicktime"
  }

  return $null
}

function Read-CurlResponse {
  param([object[]]$CurlOutput)

  $outputLines = @($CurlOutput)
  if ($outputLines.Count -eq 0) {
    return @{ Status = ""; Body = "" }
  }

  $status = $outputLines[-1]
  $body = ""
  if ($outputLines.Count -gt 1) {
    $body = ($outputLines[0..($outputLines.Count - 2)] -join "`n").Trim()
  }

  return @{ Status = $status; Body = $body }
}

function Convert-ResponseJson {
  param(
    [string]$Body,
    [string]$Context,
    [string]$Status
  )

  try {
    return $Body | ConvertFrom-Json
  } catch {
    throw "$Context returned non-JSON response (HTTP $Status): $Body"
  }
}

function Invoke-JsonPost {
  param(
    [string]$Url,
    [string]$Token,
    [string]$Json
  )

  $tempFile = [System.IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tempFile -Value $Json -Encoding utf8 -NoNewline

    return & curl.exe -sS -w "`n%{http_code}" -X POST $Url `
      -H "Authorization: Bearer $Token" `
      -H "Content-Type: application/json" `
      --data-binary "@$tempFile"
  } finally {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
  $parent = Split-Path -Path $Folder -Parent
  $message = "Folder not found: $Folder"

  if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) {
    $availableFolders = Get-ChildItem -LiteralPath $parent -Directory |
      Sort-Object Name |
      Select-Object -ExpandProperty Name

    if ($availableFolders.Count -gt 0) {
      $message += "`nAvailable folders in ${parent}: $($availableFolders -join ', ')"
    }
  }

  throw $message
}

if (-not (Test-Uuid $OrgId)) {
  throw "OrgId must be a UUID."
}

$baseUrl = $ApiBaseUrl.TrimEnd("/")
$uploadUrlEndpoint = $baseUrl + "/drills/media/upload-url"
$mediaEndpoint = $baseUrl + "/drills/media"
$files = Get-ChildItem -LiteralPath $Folder -File |
  Where-Object { $_.Extension.ToLowerInvariant() -in @(".mp4", ".mov") } |
  Sort-Object Name

if ($FileName) {
  $files = @($files | Where-Object { $_.Name -eq $FileName })
  if ($files.Count -eq 0) {
    throw "File not found in ${Folder}: $FileName"
  }
}

if ($Limit -gt 0) {
  $files = @($files | Select-Object -First $Limit)
}

if ($files.Count -eq 0) {
  Write-Host "No .mp4 or .mov files found in $Folder"
  exit 0
}

Write-Host "Uploading $($files.Count) drill video(s) using signed Storage URLs"

$uploaded = 0
$failed = 0

foreach ($file in $files) {
  $drillId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  if (-not (Test-Uuid $drillId)) {
    Write-Warning "Skipping '$($file.Name)': filename stem is not a drill UUID."
    continue
  }

  $title = $drillId
  $contentType = Get-VideoContentType $file
  if (-not $contentType) {
    Write-Warning "Skipping '$($file.Name)': only .mp4 and .mov videos are supported."
    continue
  }

  $uploadUrlBody = @{
    org_id = $OrgId
    drill_id = $drillId
    file_name = $file.Name
    content_type = $contentType
    type = "video"
    title = $title
    position = 1
  } | ConvertTo-Json -Compress

  Write-Host "Uploading $($file.Name) -> drill_id=$drillId"

  if ($DryRun) {
    Write-Host "DRY RUN: would POST $uploadUrlEndpoint"
    Write-Host "DRY RUN body: $uploadUrlBody"
    Write-Host "DRY RUN: would PUT video directly to signed Storage URL"
    Write-Host "DRY RUN: would POST $mediaEndpoint"
    continue
  }

  $uploadUrlOutput = Invoke-JsonPost $uploadUrlEndpoint $Token $uploadUrlBody

  if ($LASTEXITCODE -ne 0) {
    $failed++
    Write-Warning "Failed to create upload URL for $($file.Name): curl exit code $LASTEXITCODE"
    continue
  }

  $uploadUrlResult = Read-CurlResponse $uploadUrlOutput
  try {
    $uploadUrlResponse = Convert-ResponseJson $uploadUrlResult.Body "Upload URL request" $uploadUrlResult.Status
  } catch {
    $failed++
    Write-Warning $_.Exception.Message
    continue
  }

  if ($uploadUrlResponse.ok -ne $true -or -not $uploadUrlResponse.upload) {
    $failed++
    $reason = $uploadUrlResponse.error
    if (-not $reason) {
      $reason = $uploadUrlResult.Body
    }
    Write-Warning "Failed to create upload URL for $($file.Name) (HTTP $($uploadUrlResult.Status)): $reason"
    continue
  }

  $upload = $uploadUrlResponse.upload
  Write-Host "Uploading file to Storage: $($upload.path)"

  $storageOutput = & curl.exe --http1.1 --retry 3 --retry-delay 2 --retry-all-errors -sS -w "`n%{http_code}" -X PUT $upload.signed_url `
    -H "Content-Type: $contentType" `
    -H "Cache-Control: max-age=3600" `
    -H "x-upsert: false" `
    --data-binary "@$($file.FullName)"

  if ($LASTEXITCODE -ne 0) {
    $failed++
    Write-Warning "Storage upload failed for $($file.Name): curl exit code $LASTEXITCODE"
    continue
  }

  $storageResult = Read-CurlResponse $storageOutput
  if ($storageResult.Status -lt 200 -or $storageResult.Status -ge 300) {
    $failed++
    Write-Warning "Storage upload failed for $($file.Name) (HTTP $($storageResult.Status)): $($storageResult.Body)"
    continue
  }

  $mediaBody = @{
    org_id = $OrgId
    drill_id = $drillId
    type = "video"
    url = $upload.public_url
    title = $title
    position = 1
  } | ConvertTo-Json -Compress

  $mediaOutput = Invoke-JsonPost $mediaEndpoint $Token $mediaBody

  if ($LASTEXITCODE -ne 0) {
    $failed++
    Write-Warning "Failed to create media record for $($file.Name): curl exit code $LASTEXITCODE"
    continue
  }

  $mediaResult = Read-CurlResponse $mediaOutput
  try {
    $mediaResponse = Convert-ResponseJson $mediaResult.Body "Media create request" $mediaResult.Status
  } catch {
    $failed++
    Write-Warning $_.Exception.Message
    continue
  }

  if ($mediaResponse.ok -eq $true) {
    $uploaded++
    Write-Host "Uploaded $($file.Name)"
  } else {
    $failed++
    $reason = $mediaResponse.error
    if (-not $reason) {
      $reason = $mediaResult.Body
    }
    Write-Warning "Failed to create media record for $($file.Name) (HTTP $($mediaResult.Status)): $reason"
  }
}

Write-Host "Done. Uploaded: $uploaded. Failed: $failed."

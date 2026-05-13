param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$OrgId,

  [Parameter(Mandatory = $true)]
  [string]$Token,

  [string]$Folder = "C:\Users\developer\source\repos\ankor-training-backend\stickwork",

  [string]$FileName,

  [int]$Limit = 0,

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Test-Uuid {
  param([string]$Value)
  return $Value -match "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
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
  throw "Folder not found: $Folder"
}

if (-not (Test-Uuid $OrgId)) {
  throw "OrgId must be a UUID."
}

$baseUrl = $ApiBaseUrl.TrimEnd("/")
$uploadUrlEndpoint = $baseUrl + "/skills/media/upload-url"
$mediaEndpoint = $baseUrl + "/skills/media"
$files = Get-ChildItem -LiteralPath $Folder -File -Filter "*.mp4" |
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
  Write-Host "No .mp4 files found in $Folder"
  exit 0
}

Write-Host "Uploading $($files.Count) skill video(s) using signed Storage URLs"

$uploaded = 0
$failed = 0

foreach ($file in $files) {
  $skillId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  if (-not (Test-Uuid $skillId)) {
    Write-Warning "Skipping '$($file.Name)': filename stem is not a skill UUID."
    continue
  }

  $title = $skillId
  $uploadUrlBody = @{
    org_id = $OrgId
    skill_id = $skillId
    file_name = $file.Name
    content_type = "video/mp4"
    title = $title
    position = 1
  } | ConvertTo-Json -Compress

  Write-Host "Uploading $($file.Name) -> skill_id=$skillId"

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
    Write-Error "Failed to create upload URL for $($file.Name): curl exit code $LASTEXITCODE"
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
  Write-Host "Uploading file to Storage: $($upload.object_path)"

  $storageOutput = & curl.exe -sS -w "`n%{http_code}" -X PUT $upload.signed_url `
    -H "Content-Type: video/mp4" `
    -H "Cache-Control: max-age=3600" `
    -H "x-upsert: false" `
    --data-binary "@$($file.FullName)"

  if ($LASTEXITCODE -ne 0) {
    $failed++
    Write-Error "Storage upload failed for $($file.Name): curl exit code $LASTEXITCODE"
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
    skill_id = $skillId
    bucket = $upload.bucket
    object_path = $upload.object_path
    media_type = "video"
    title = $title
    position = 1
  } | ConvertTo-Json -Compress

  $mediaOutput = Invoke-JsonPost $mediaEndpoint $Token $mediaBody

  if ($LASTEXITCODE -ne 0) {
    $failed++
    Write-Error "Failed to create media record for $($file.Name): curl exit code $LASTEXITCODE"
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

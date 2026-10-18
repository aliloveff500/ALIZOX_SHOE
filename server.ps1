# Lightweight PowerShell HTTP Server for ALIZOX Website
param(
    [int]$Port = 8080
)

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " 👟  ALIZOX Sneaker Storefront Server Running!" -ForegroundColor Yellow
    Write-Host " Open your browser at: http://localhost:$Port/" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Green

    $baseDir = $PSScriptRoot
    if (-not $baseDir) { $baseDir = (Get-Location).Path }

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # CORS Headers
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 204
            $response.OutputStream.Close()
            continue
        }

        $localPath = $request.Url.LocalPath.TrimStart('/')
        if ([string]::IsNullOrEmpty($localPath)) {
            $localPath = "index.html"
        }

        # Handle Save Store Data API
        if ($request.HttpMethod -eq "POST" -and ($localPath -eq "api/save-store" -or $localPath -eq "store-data.json")) {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $reader.Close()

                $parsed = $bodyText | ConvertFrom-Json
                if ($parsed.products) {
                    $targetJsonPath = Join-Path $baseDir "store-data.json"
                    [System.IO.File]::WriteAllText($targetJsonPath, $bodyText, [System.Text.Encoding]::UTF8)
                    Write-Host "[STORE-DATA SAVED] Updated store-data.json on disk successfully!" -ForegroundColor Green

                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":true,"message":"Saved to disk"}')
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.StatusCode = 200
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                } else {
                    $response.StatusCode = 400
                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Invalid payload"}')
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                }
            } catch {
                $response.StatusCode = 500
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Failed to write file"}')
                $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            }
        # Handle Orders API (Local Development & Server)
        if ($localPath -eq "api/orders" -or $localPath -eq "orders-data.json") {
            $ordersFilePath = Join-Path $baseDir "orders-data.json"
            if (-not (Test-Path $ordersFilePath)) {
                '{"updatedAt":"' + (Get-Date).ToUniversalTime().ToString("o") + '","orders":[]}' | Set-Content -Path $ordersFilePath -Encoding UTF8
            }

            if ($request.HttpMethod -eq "GET") {
                $ordersJson = [System.IO.File]::ReadAllText($ordersFilePath, [System.Text.Encoding]::UTF8)
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes($ordersJson)
                $response.ContentType = "application/json; charset=utf-8"
                $response.StatusCode = 200
                $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                $response.OutputStream.Close()
                continue
            }

            if ($request.HttpMethod -eq "POST") {
                try {
                    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                    $bodyText = $reader.ReadToEnd()
                    $reader.Close()

                    $newOrder = $bodyText | ConvertFrom-Json
                    if (-not $newOrder.id) {
                        $newOrder | Add-Member -NotePropertyName "id" -NotePropertyValue ("ALX-" + (Get-Random -Minimum 10000 -Maximum 99999))
                    }
                    if (-not $newOrder.createdAt) {
                        $newOrder | Add-Member -NotePropertyName "createdAt" -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o"))
                    }
                    if (-not $newOrder.status) {
                        $newOrder | Add-Member -NotePropertyName "status" -NotePropertyValue "Pending"
                    }

                    $currentContent = [System.IO.File]::ReadAllText($ordersFilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                    $orderList = [System.Collections.ArrayList]@($currentContent.orders)
                    $orderList.Insert(0, $newOrder)

                    $dbPayload = @{
                        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
                        orders = $orderList
                    } | ConvertTo-Json -Depth 10

                    [System.IO.File]::WriteAllText($ordersFilePath, $dbPayload, [System.Text.Encoding]::UTF8)
                    Write-Host "[NEW ORDER RECEIVED] Order $($newOrder.id) saved to disk!" -ForegroundColor Green

                    $ret = @{ success = $true; message = "Order stored successfully"; orderId = $newOrder.id; order = $newOrder } | ConvertTo-Json
                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes($ret)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.StatusCode = 201
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                } catch {
                    $response.StatusCode = 500
                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"Failed to store order"}')
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                }
                $response.OutputStream.Close()
                continue
            }

            if ($request.HttpMethod -eq "PUT") {
                try {
                    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                    $bodyText = $reader.ReadToEnd()
                    $reader.Close()

                    $update = $bodyText | ConvertFrom-Json
                    $currentContent = [System.IO.File]::ReadAllText($ordersFilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                    foreach ($ord in $currentContent.orders) {
                        if ($ord.id -eq $update.id) {
                            if ($update.status) { $ord.status = $update.status }
                            if ($update.notes) { $ord.notes = $update.notes }
                        }
                    }
                    $currentContent.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
                    $dbPayload = $currentContent | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($ordersFilePath, $dbPayload, [System.Text.Encoding]::UTF8)

                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":true,"message":"Order updated"}')
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.StatusCode = 200
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                } catch {
                    $response.StatusCode = 500
                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"Failed to update order"}')
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                }
                $response.OutputStream.Close()
                continue
            }

            if ($request.HttpMethod -eq "DELETE") {
                try {
                    $orderId = $request.QueryString["id"]
                    $currentContent = [System.IO.File]::ReadAllText($ordersFilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                    $filtered = @($currentContent.orders | Where-Object { $_.id -ne $orderId })
                    $currentContent.orders = $filtered
                    $currentContent.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
                    $dbPayload = $currentContent | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($ordersFilePath, $dbPayload, [System.Text.Encoding]::UTF8)

                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":true,"message":"Order deleted"}')
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.StatusCode = 200
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                } catch {
                    $response.StatusCode = 500
                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"Failed to delete order"}')
                    $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
                }
                $response.OutputStream.Close()
                continue
            }
        }

        # Normalize path
        $localPath = $localPath -replace '/', '\'
        $filePath = Join-Path $baseDir $localPath

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = switch ($ext) {
                ".html" { "text/html; charset=utf-8" }
                ".css"  { "text/css; charset=utf-8" }
                ".js"   { "application/javascript; charset=utf-8" }
                ".json" { "application/json; charset=utf-8" }
                ".png"  { "image/png" }
                ".jpg"  { "image/jpeg" }
                ".svg"  { "image/svg+xml" }
                ".ico"  { "image/x-icon" }
                default { "application/octet-stream" }
            }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.ContentType = $contentType
            $response.ContentLength64 = $bytes.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
            $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
        }

        $response.OutputStream.Close()
    }
}
catch {
    Write-Host "Server stopped or error occurred: $_" -ForegroundColor Red
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}

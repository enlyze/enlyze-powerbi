# PowerShell script to deploy custom connector using VS Code's Power Query SDK

# Configuration
$projectPath = $PSScriptRoot # Assumes the script is in the project directory
$mezFileName = "enlyze-powerbi.mez" # Replace with your .mez file name
#$customConnectorsPath = "C:\Mac\Home\Documents\Microsoft Power BI Desktop\Custom Connectors" # Default Power BI custom connectors path
$customConnectorsPath = "C:\Program Files\Microsoft Power BI Desktop\Custom Connectors" # Default Power BI custom connectors path


function Find-PowerBIDesktop {
    $possiblePaths = @(
        "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
        "C:\Program Files (x86)\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
        "$env:LocalAppData\Microsoft\WindowsApps\PBIDesktop.exe",
        "C:\Program Files\WindowsApps\Microsoft.MicrosoftPowerBIDesktop_2.131.1203.0_x64__8wekyb3d8bbwe\bin\PBIDesktop.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # If not found in predefined paths, search in common directories
    $commonDirs = @("C:\Program Files", "C:\Program Files (x86)", "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LocalAppData")
    foreach ($dir in $commonDirs) {
        $found = Get-ChildItem -Path $dir -Recurse -ErrorAction SilentlyContinue | 
                 Where-Object { $_.Name -eq "PBIDesktop.exe" } | 
                 Select-Object -First 1 -ExpandProperty FullName
        if ($found) {
            return $found
        }
    }

    return $null
}


# Find the .mez file
Write-Host "Searching for the compiled .mez file..."
$mezFile = Get-ChildItem -Path $projectPath -Recurse -Filter $mezFileName | Select-Object -First 1

# Check if compilation was successful
if ($null -eq $mezFile) {
    Write-Host "Compilation failed or .mez file not found. Please check for errors in VS Code and try again."
    exit 1
}

Write-Host ".mez file found at: $($mezFile.FullName)"

# Copy .mez file to custom connectors directory
Write-Host "Copying .mez file to custom connectors directory..."
Copy-Item $mezFile.FullName -Destination $customConnectorsPath -Force

# Check if copy was successful
if ($?) {
    Write-Host ".mez file successfully copied to custom connectors directory."
} else {
    Write-Host "Failed to copy .mez file. Please check permissions and try again."
    exit 1
}


Write-Host "Closing Power BI..."
Get-Process "PBIDesktop" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Starting Power BI..."
$pbiPath = Find-PowerBIDesktop
if ($null -eq $pbiPath) {
    Write-Host "Power BI Desktop executable not found. Please start Power BI Desktop manually."
} else {
    Write-Host "Closing Power BI..."
    Get-Process "PBIDesktop" -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Host "Starting Power BI..."
    Start-Process $pbiPath
}

Write-Host "Deployment complete!"
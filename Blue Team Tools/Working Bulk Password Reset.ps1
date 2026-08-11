#Requires -Modules ActiveDirectory

# --- SCRIPT CONFIGURATION ---
# 1. Set the path to your input CSV file.
$csvPath = "C:\Temp\input-usersnoreset.csv"

# 2. Set the path for the output log file. This file will store the new passwords.
$logPath = "C:\temp\password_reset_log.csv"

# 3. Set the desired length for the random passwords.
$passwordLength = 14

# --- Function to Generate a Random Password ---
function New-RandomPassword {
    param ([int]$length = 14)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>/?'
    $password = -join ($chars.ToCharArray() | Get-Random -Count $length)
    # This simplified function generates a random string. For guaranteed complexity, see the previous single-user script.
    return $password
}

# --- MAIN SCRIPT ---
# Check if the input file exists before starting.
if (-not (Test-Path $csvPath)) {
    Write-Error "Input CSV file not found at: $csvPath"
    return
}

Write-Host "Starting bulk password reset process..."

# Import the CSV and process each user in a loop.
$results = Import-Csv -Path $csvPath | ForEach-Object {
    # Get the username from the 'Username' column of the CSV.
    $user = $_.Username

    # Use a Try/Catch block to handle users that might not be found.
    try {
        # Check if the user exists before proceeding.
        $adUser = Get-ADUser -Identity $user
        
        # Generate a new random password.
        $newPassword = New-RandomPassword -length $passwordLength
        $securePassword = $newPassword | ConvertTo-SecureString -AsPlainText -Force

        # Reset the password and force change at next logon.
        Set-ADAccountPassword -Identity $adUser -NewPassword $securePassword -Reset
        Set-ADUser -Identity $adUser -ChangePasswordAtLogon $true

        Write-Host "✅ Successfully reset password for: $user"
        
        # Create an object for the log file with the successful result.
        [PSCustomObject]@{
            Username    = $user
            Status      = 'Success'
            NewPassword = $newPassword
            Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    catch {
        Write-Warning "❌ FAILED to reset password for: $user. Error: $($_.Exception.Message)"
        
        # Create an object for the log file with the failure details.
        [PSCustomObject]@{
            Username    = $user
            Status      = 'Failed'
            Error       = $_.Exception.Message
            Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

# Export the results to the log file.
$results | Export-Csv -Path $logPath -NoTypeInformation

Write-Host "---"
Write-Host "Bulk password reset process complete."
Write-Host "A detailed log has been saved to: $logPath"
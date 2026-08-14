Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All"

Get-MgServicePrincipal -All `
    -Property DisplayName,PreferredSingleSignOnMode,AccountEnabled,AppId |
Where-Object {$_.PreferredSingleSignOnMode} |
Select-Object DisplayName,
              AppId,
              PreferredSingleSignOnMode,
              AccountEnabled |
Export-Csv .\EnterpriseSSOApps.csv -NoTypeInformation
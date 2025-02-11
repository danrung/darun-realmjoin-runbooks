<#
.SYNOPSIS
Retrieves the members of a specified EntraID group, including members from nested groups.

.DESCRIPTION
This script retrieves the members of a specified EntraID group. This includes both the direct group members and the indirect ones, which are members through nested groups.
The results are output in CSV format with columns for User Principal Name (UPN), Direct Membership Status and Group Path.
Group path contains the “path” of the users. 
If the nested group “Secondary” is contained in the group “Primary” and the user is contained in the latter, the path would be: Primary,Secondary

.PARAMETER GroupId
The ObjectId of the EntraID group whose membership is to be retrieved.

.PARAMETER CallerName
The name of the caller, used for auditing purposes.

.NOTES
Required Permissions:
- Group.Read.All
- User.Read.All

.INPUTS
RunbookCustomization: {
    "Parameters": {
        "CallerName": {
            "Hide": true
        }
    }
}
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript( { Use-RJInterface -Type Graph -Entity Group -DisplayName "Group" } )]
    [string]$GroupId,

    # CallerName is tracked purely for auditing purposes
    [string] $CallerName
)

#Requires -Modules @{ModuleName = "RealmJoin.RunbookHelper"; ModuleVersion = "0.8.3" }
#Requires -Modules @{ModuleName = "Microsoft.Graph.Authentication"; ModuleVersion = "2.25.0" }

########################################################
#region     function declaration
##          
########################################################
function Get-GroupMembership {
    param (
        [string]$GroupObjectId,
        [string]$ParentGroupPath = ""
    )

    $report = @()

    # Get the group object
    $group = Invoke-MGGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$GroupObjectId"
    $CurrentGroupPath = if ($ParentGroupPath) { "$ParentGroupPath;$($group.DisplayName)" } else { $group.DisplayName }
    
    # Get the members of the group
    $members = @()
    $uri = "https://graph.microsoft.com/v1.0/groups/$GroupObjectId/members"
    do {
        $response = Invoke-MGGraphRequest -Method GET -Uri $uri
        $members += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    # Process the members - if a member is a user, add it to the report, if it's a group, call the function recursively
    foreach ($member in $members) {
        if ($member."@odata.type" -eq "#microsoft.graph.user") {
            $DirectMemberStatus = if ($ParentGroupPath) { "No" } else { "Yes" }
            $report += [PSCustomObject]@{
                UPN          = $member.UserPrincipalName
                DirectMember = $DirectMemberStatus
                GroupPath    = $CurrentGroupPath
            }
        }
        elseif ($member."@odata.type" -eq "#microsoft.graph.group") {
            $report += Get-GroupMembership -GroupObjectId $($member.id) -ParentGroupPath $CurrentGroupPath
        }
    }

    return $report
}

#endregion

########################################################
#region     RJ Log Part
##          
########################################################

# Add Caller in Verbose output
if ($CallerName) {
    Write-RjRbLog -Message "Caller: '$CallerName'" -Verbose
}

# Add Version in Verbose output
$Version = "1.0.0"
Write-RjRbLog -Message "Version: $Version" -Verbose

# Add Parameter in Verbose output
Write-RjRbLog -Message "Submitted parameters:" -Verbose
Write-RjRbLog -Message "GroupObjectId: $GroupId" -Verbose
Write-RjRbLog -Message "CallerName: $CallerName" -Verbose

#endregion

########################################################
#region     Connect Part
##          
########################################################

# Initiate Graph Session
Write-Output "Initiate MGGraph Session..."
try {
    $VerbosePreference = "SilentlyContinue"
    Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    $VerbosePreference = "Continue"
}
catch {
    Write-Error "MGGraph Connect failed - stopping script"
    Exit 
}

#endregion

########################################################
#region     Main Part
##
########################################################

Write-Output "Getting group membership (also indirect memberships based on nested groups) for group with ObjectId '$GroupObjectId'..."
$report = Get-GroupMembership -GroupObjectId $GroupId

Write-Output "Result:"
Write-Output ""
Write-Output "UPN,DirectMember,GroupPath"
$report | ForEach-Object {
    Write-Output "$($_.UPN),$($_.DirectMember),$($_.GroupPath)"
}
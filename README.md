# PrivilegesDemoter

While the [SAP Privileges application](https://github.com/SAP/macOS-enterprise-privileges) is excellent at its intended function, you may want some help encouraging users to act as an administrator only when required (instead of setting themselves as an admin and never looking back). Additionally, you may want some way of logging who is using admin privileges for an extended period of time and how often. That's where PrivilegesDemoter comes in.

PrivilegesDemoter consists of two scripts and two LaunchDaemons. The first LaunchDaemon runs a script every 5 minutes to check if the currently logged in user (or the last user if there is no current user) is an administrator. If this user is an admin, it adds a timestamp to a file and calculates how long the user has had admin rights.

Once that calculation passes a certain threshold, a signal file gets created. The signal file tells the second LaunchDaemon to call a Jamf policy.

The Jamf policy displays an IBM Notifer (or jamf helper) message asking if the user still requires admin rights.

<img width="641" alt="PrivilegesDemoter" src="https://user-images.githubusercontent.com/1520833/167688261-3c2b6956-a772-4cac-8385-65efd3afc22b.png">

- Clicking “Yes” resets the timer allowing the user to remain an administrator for another period of time, at which point the reminder will reappear.
- Clicking “No” revokes administrator privileges immediately. 
- If the user does nothing, the reminder will timeout and revoke administrator privileges in the background.
- Users may use the Privileges application normally to gain administrator rights again whenever needed.
- Each privilege escalation and demotion event is logged in `/var/log/privileges.log`

## Admin Threshold Calculation
As of version 2.1 the threshold for when the reminder popup appears may be customized. In all previous versons the threshold was hard coded to 15 minutes.

In version 2.1 and later, the threshold is calculated based on the `DockToggleTimeout` key set in the SAP Privileges preference domain `corp.sap.privileges`

You may find more detailed info [below](#configuraton-profiles), and an [example configuration profile](https://github.com/sgmills/PrivilegesDemoter/blob/main/Example_DockToggleTimeout.mobileconfig) in this repo.

### Admin Threshold Caveats
In version 2.1 and later, if you do not manage the SAP Privileges `DockToggleTimeout` key with a configuration profile, the defualt value will be 15 minutes. For more information on the `DockToggleTimeout` key see the [SAP Privileges GitHub page](https://github.com/SAP/macOS-enterprise-privileges)

The reminder notification may occur up to 5 minutes later than the admin threshold you set. This is because the admin check script only runs once every 5 minutes. Additonally, the way this mechanism works means that 5 minutes is the minimum time you may set.

## Setup and Installation
1. Upload a package from the [releases page](https://github.com/sgmills/PrivilegesDemoter/releases).
    * There are two packages, one with just the PrivilegesDemoter pieces, and one that includes the Privileges Application. I reccomend deploying `PrivilegesDemoter_PrivilegesApp-2.0` as that ensures the Privileges application is installed properly.
1. Create a policy to install the package on your devices.
2. Add the [Demote Admin Privileges.sh](https://github.com/sgmills/PrivilegesDemoter/blob/main/Demote%20Admin%20Privileges.sh) script to Jamf Pro.
3. Create a Jamf Pro policy to run "Demote Admin Privileges.sh" with custom trigger `privilegesDemote`, set it to ongoing and make it available offline. Scope to all devices with Privileges installed.
    * Note the `privilegesDemote` trigger is hard coded in the demotion LaunchDaemon. If you would like to use a different trigger, you must also edit it there.
<img width="679" alt="Screen Shot 2021-11-22 at 11 07 31 AM" src="https://user-images.githubusercontent.com/1520833/142895481-f186ac1d-0560-49a8-943d-48bf7d543d5b.png">
4. Configure the options for `Demote Admin Privileges.sh` by editing the script, or using Jamf Pro script parameters.
    * `help_button_status` should be set to 1 to enable the help button, or 0 to disable.
    * `help_button_type` may be set to either `link` or `infopopup`
    * `help_button_payload` defines the payload for the help button. Either a URL for `link` type, or text for `infopopup` type.
    * `notification_sound` is enabled by default. Set to 0 to disable. Leave blank or set to 1 to enable.
    * `admin_to_exclude` may be set to the username of an admin that should be excluded from the reminder and never be demoted.
    * `ibm_notifier_path` may be used if you deploy IBM Notifer to a non-standard location. Set the alternate path here. Leave blank to use the default path of `/Applications/IBM Notifier.app`
        * If using an alternate path add something like the following either as a post-install script, or Files and Process > Execute Command to remove the version of IBM Notifier deployed by PrivilegesDemoter. 
            * This will delete the app deployed by PrivilegesDemoter `rm -r "/Applications/IBM Notifier.app"`
            * This will move the version of IBM Notifer deployed by PrivilegesDemoter to the /Applicatons/Utilities folder `mv "/Applications/IBM Notifier.app" "/Applications/Utilities/IBM Notifier.app"` 

        <img width="374" alt="pd_config" src="https://user-images.githubusercontent.com/1520833/167688766-ca7b3326-6a89-418c-b47c-9acc484cee5d.png">
        
### Configuraton Profiles
The following configuation profiles are optional, but reccomended.


**Set Admin Timeout Threshold** - [Example Profile](https://github.com/sgmills/PrivilegesDemoter/blob/main/Example_DockToggleTimeout.mobileconfig)</br>
**Preference domain:** corp.sap.privileges </br>
**Key:** DockToggleTimeout </br>
**Value:** Integer </br>
**Available for:** PrivilegesDemoter 2.1 and later. </br>
**Description:** Set a fixed timeout, in minutes, for when the reminder popup will occur.

**Background Service Management** - [Example Profile](https://github.com/sgmills/PrivilegesDemoter/blob/main/Example_BackgroundServiceManagement.mobileconfig)</br>
**Preference domain:** com.apple.servicemanagement </br>
**Key:** RuleType </br>
**Value:** LabelPrefix </br>
**Key:** RuleValue </br>
**Value:** blog.mostlymac </br>
**Available for:** macOS 13 and later. </br>
**Description:** In macOS 13 Ventura and later users are able to toggle background services (LaunchDaemons) on and off in the System Settings GUI. It is reccomended to disable this ability so that the user cannot turn off the demotion reminders.

## Logging
Events from SAP Privileges are gathered alongside each PrivilegesDemoter decision made by the user and logged in `/var/log/privileges.log`

Events from SAP Privileges will look like this </br>
`2022-09-07 12:11:03.343 Df corp.sap.privileges.helper[1369:4df13b] SAPCorp: User mostly.mac has now admin rights on MachineID: DD43D462-57B4-4C5D-91CC-D430507277D1`

Events from PrivilegesDemoter will look like this </br>
`2022-09-07 12:16:30-0400 blog.mostlymac.privileges.demoter Decision: mostly.mac no longer needs admin rights. Removing rights on MachineID: DD43D462-57B4-4C5D-91CC-D430507277D1 now.`
 

## Testing
You may test the workflow without waiting the full demotion period by using the following terminal command. This command simulates the threshold being passed by creating the signal file, thus triggering the Jamf policy. Then it removes the signal file so that the policy does not run again.

`touch /tmp/privilegesDemote; sleep 5; rm /tmp/privilegesDemote`
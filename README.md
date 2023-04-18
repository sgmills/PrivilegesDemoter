# PrivilegesDemoter

## [Please refer to the wiki for detailed documentation](https://github.com/sgmills/PrivilegesDemoter/wiki)

PrivilegesDemoter allows users to self manage local administrator rights, while reminding them not to operate as an administrator for extended periods of time. Additionally, each elevation and demotion event is recorded and saved to a log file.

PrivilegesDemoter 3.0 has been written to be customizable for a number of different deployment scenarios. PrivilegesDemoter may be used on its own in standalone mode, or conjunction with [SAP Privileges](https://github.com/SAP/macOS-enterprise-privileges). It may be configured to notify users with [IBM Notifier](https://github.com/IBM/mac-ibm-notifications), [Swift Dialog](https://github.com/bartreardon/swiftDialog), or [Jamf Helper](https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Applications_and_Utilities.html).

The PrivilegesDemoter script runs every 5 minutes to check if the currently logged in user is an administrator. If this user is an admin, it adds a timestamp to a file and calculates how long the user has had admin rights. Once that calculation passes a certain threshold, the user is reminded to operate as a standard user whenever possible:

<img width="641" alt="PrivilegesDemoter" src="https://user-images.githubusercontent.com/1520833/167688261-3c2b6956-a772-4cac-8385-65efd3afc22b.png">

- Clicking “Yes” resets the timer allowing the user to remain an administrator for another period of time, at which point the reminder will reappear.
- Clicking “No” revokes administrator privileges immediately. 
- If the user does nothing, the reminder will timeout and revoke administrator privileges in the background.
- Users may use the Privileges application or a self-service policy to gain administrator rights again whenever needed.
- Each privilege escalation and demotion event is logged in `/var/log/privileges.log`

## Configuration

As of version 3.0 and higher, PrivilegesDemoter is configured using a Configuration Profile. This script was originally designed to work with Macs enrolled in Jamf Pro with SAP Privileges installed. Versions 3.0 and higher have additional options for use with other agents and workflows. Please see the [wiki](https://github.com/sgmills/PrivilegesDemoter/wiki) for more information on available options.
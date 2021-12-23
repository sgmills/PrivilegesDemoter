# PrivilegesDemoter

While the [SAP Privileges application](https://github.com/SAP/macOS-enterprise-privileges) is excellent at its intended function, you may want some help encouraging users to act as an administrator only when required (instead of setting themselves as an admin and never looking back). Additionally, you may want some way of logging who is using admin privileges for an extended period of time and how often. That's where PrivilegesDemoter comes in.

PrivilegesDemoter consists of two scripts and two launchDaemons. The first launchDaemon runs a script every 5 minutes to check if the currently logged in user (or the last user if there is no current user) is an administrator. If this user is an admin, it adds a timestamp to a file and calculates how long the user has had admin rights.

Once that calculation passes 15 minutes, a signal file gets created. The signal file tells the second launchDaemon to call a Jamf policy. I chose 15 minutes here because that should be more than enough time to perform an admin task or two (like installing an update).

So far we have confirmed that there is an admin user on the machine, and that user has been an admin for more than 15 minutes. The Jamf policy is where all the real work gets done. We use a jamf helper message to ask if the user still requires admin rights.

<img width="587" alt="Privileges Demoter" src="https://user-images.githubusercontent.com/1520833/142893041-9a2383d4-f5ff-44b9-a222-69e382ee26d1.png">

- Clicking “Yes” resets the timer allowing the user to remain an administrator for another 15 minutes, at which point the reminder will reappear.
- Clicking “No” revokes administrator privileges immediately. 
- If the user does nothing, the reminder will timeout and revoke administrator privileges in the background.
- Users may use the Privileges application normally to gain administrator rights again whenever needed.
- Each privilege escalation and demotion event is logged in /var/log/privileges.log

## Setup and Installation
1. Use the ready-made package on the [releases page](https://github.com/sgmills/PrivilegesDemoter/releases), or create your own package containing the launchDaemons and scripts from the pkg folder.
2. Add the [Demote Admin Privileges.sh](https://github.com/sgmills/PrivilegesDemoter/blob/main/Demote%20Admin%20Privileges.sh) script to Jamf Pro.
3. Create a Jamf Pro policy to run "Demote Admin Privileges.sh" with custom trigger "privilegesDemote", set it to ongoing and make it available offline. Scope to all devices with Privileges installed. <img width="679" alt="Screen Shot 2021-11-22 at 11 07 31 AM" src="https://user-images.githubusercontent.com/1520833/142895481-f186ac1d-0560-49a8-943d-48bf7d543d5b.png">
4. Install the PrivilegesDemote package beside Privileges.pkg on your clients.

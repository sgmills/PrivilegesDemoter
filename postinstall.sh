#!/bin/bash

# Load launchDaemon to check for admin every 5 minutes
launchctl bootstrap system /Library/LaunchDaemons/blog.mostlymac.privileges.check.plist

# Load launchDaemon to confirm and optionally demote user if time limit is reached
launchctl bootstrap system /Library/LaunchDaemons/blog.mostlymac.privileges.demote.plist
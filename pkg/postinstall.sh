#!/bin/bash

# Load launchDaemon to check for admin every 5 minutes
launchctl bootstrap system /Library/LaunchDaemons/blog.mostlymac.privileges.check.plist
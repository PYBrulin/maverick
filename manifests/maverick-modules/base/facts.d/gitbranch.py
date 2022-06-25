#!/usr/bin/env python3
# This fact finds the current branch of the git repo it is running from

import os,re,subprocess

# Define main data container
url = subprocess.getoutput("/usr/bin/git remote get-url --push origin")
print("giturl=" + str(url) + ".git")

branch = subprocess.getoutput("/usr/bin/git branch |/bin/grep '\*'")
branch = re.sub("\* ", "", branch.strip())
print("gitbranch=" + str(branch))
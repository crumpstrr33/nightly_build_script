# LCLS Conda Nighly Build Script
This is exactly what the title suggests. It uses the ana-rel-admin command to retrieve the tags for the repos on Github and the few repos on SVN. And uses conda-build to build it.

The latest MAX_BUILDS builds are found in ${HOSTNAME}_nightly.

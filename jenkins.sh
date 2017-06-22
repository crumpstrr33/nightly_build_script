#!/bin/bash
#
# Running this script builds either:
#    1) A psana environment
# or 2) If a version number is given, a complete
#       ana environment for both python 2 and 3
#
# It will exit for the following reasons:
# [(Official) means that it can only happen for offical builds
#  and (Unofficial) means it can only happen for the nightly builds
#   - It can't find the RHEL version number
#   - (Official) The build version number is invalid
#   - (Official) The build version number already exists
#   - (Unofficial) The number of nightly tarballs does not equal
#     the number of envs (they should be equal)

#############################################################################
#---------------------------------VARIABLES---------------------------------#
#############################################################################
conda_setup="/reg/g/psdm/bin/conda_setup"
PREFIX="[JENKINS SCRIPT]:"
BUILDER=$(whoami)
HOSTNAME=$(hostname)
DATE=`date +%Y%m%d_hour%H`
MAX_BUILDS=5
echo "$PREFIX Building on ${HOSTNAME} as ${BUILDER}..."

# Find the RHEL number from the redhat-release text file
RHEL_VER=UNKNOWN
cat /etc/redhat-release | grep -q "release 7" && RHEL_VER=7
cat /etc/redhat-release | grep -q "release 6" && RHEL_VER=6
cat /etc/redhat-release | grep -q "release 5" && RHEL_VER=5
if [ $RHEL_VER = UNKNOWN ]; then
	echo "$PREFIX RHEL version could not be found. Aborting..."
	exit
fi

# Relevant directories
BASE_DIR="/reg/g/psdm/sw/conda/inst/miniconda2-prod-rhel${RHEL_VER}/envs"
CONDA_DIR="$BASE_DIR/conda-root"
CHANNEL_DIR="/reg/g/psdm/sw/conda/channels/psana-rhel${RHEL_VER}"

# Optionally accept a version number. Defaults to 99.99.99
VERSION=${1-"99.99.99"}
# Checks to make sure the version number is valid
# Of the form: d.d.d where d is 1 or more digits
if [[ ! $VERSION =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
	echo "$PREFIX Invalid version number given: $VERSION"
	echo "$PREFIX Must be of form d.d.d where d is at least 1 digit. Aborting..."
	exit
fi
# Decides whether this is an official release or not
if [ $VERSION == "9.9.9" ]; then
	echo "$PREFIX Not building an official release..."
	OFFICIAL=false
	PREFIX="[JENKINS SCRIPT (NIGHTLY)]:"
else
	# If it is, make sure the version number doesn't already exist
	if [ ! -z $(ls | grep $VERSION) ]; then
		echo "$PREFIX Version $VERSION already exists for the psana-conda build. Aborting..."
		exit
	fi
	echo "$PREFIX Building an official release of version $VERSION..."
	OFFICIAL=true
	PREFIX="[JENKINS SCRIPT (OFFICIAL)]:"
fi

####################################################################################
#---------------------------------END OF VARIABLES---------------------------------#
####################################################################################

# Exit with an exit code if there is an error
set -e

# Activate conda
source $conda_setup ""

# Remove old tmp directory and remake it
cd $BASE_DIR
[ -d "conda-root" ] && rm -rf conda-root
mkdir -p conda-root/downloads/anarel

# Get the tags for the packages to be installed
cd $CONDA_DIR
echo "$PREFIX Retrieving tags..."
ana-rel-admin --force --cmd psana-conda-src --name $VERSION --basedir $CONDA_DIR
# Don't append "nightly" onto the tar file if it's official... cause it's official... not nightly
if [ $OFFICIAL == "false" ]; then
	mv downloads/anarel/psana-conda-${VERSION}.tar.gz downloads/anarel/psana-conda-nightly-${VERSION}.tar.gz
fi

# Get the recipe
echo "$PREFIX Retrieving recipe..."
cp -r /reg/g/psdm/sw/conda/manage/recipes/psana/psana-conda-opt .

# Make some changes to the conda build yaml file
echo "$PREFIX Editing meta.yaml..."
# Don't append "nightly" onto the package name if it's official... cause it's official... not nightly (deja vu?)
if [ $OFFICIAL == "false" ]; then
	sed -i "s/{% set pkg =.*/{% set pkg = 'psana-conda-nightly' %}/" psana-conda-opt/meta.yaml
else
	# Get the environment creating yaml files for the official release for both python 2 and 3
	cp "/reg/neh/home/jscott/jenkins_sh/ana-official-py2.yml" .
	cp "/reg/neh/home/jscott/jenkins_sh/ana-official-py3.yml" .
	sed -i "/^name:/ s/$/-${VERSION}/" ana-official-py2.yml
	sed -i "/^name:/ s/$/-${VERSION}-py3/" ana-official-py3.yml
fi
# Change version and source directory to what it should be
sed -i "s/{% set version =.*/{% set version = '$VERSION' %}/" psana-conda-opt/meta.yaml
sed -i "/source:/!b;n;c \ \ fn: $CONDA_DIR/downloads/anarel/{{ pkg }}-{{ version }}.tar.gz" psana-conda-opt/meta.yaml

# Now build it
cd $CONDA_DIR
echo "$PREFIX Building tarball into $CHANNEL_DIR..."
conda-build --output-folder $CHANNEL_DIR psana-conda-opt

# It builds the tarball into $CHANNEL_DIR, now lets make the environment(s)
cd $CHANNEL_DIR/linux-64
if [ $OFFICIAL == "false" ]; then
	# Rename tarball cause nightly... duh.
	TAR_NAME=$(ls psana-conda-nightly-${VERSION}*)
	echo "$PREFIX Changing name from $TAR_NAME to psana-conda-nightly-${DATE}..."
	mv $TAR_NAME psana-conda-nightly-${DATE}.tar.gz
	# Create the environment from just the psana tarball
	echo "$PREFIX Creating env for ${CHANNEL_DIR}/${TAR_NAME} in ${BASE_DIR}/ana-nightly-${DATE}"
	conda create -y -p ${BASE_DIR}/ana-nightly-${DATE} -c file://${CHANNEL_DIR} psana-conda-nightly
else
	# Don't rename the tarball (also duh)
	TAR_NAME=$(ls psana-conda-${VERSION}*)
	# Create the environments based on the yaml files (since it's everything, not just psana...
	# also psana isn't on python3 and so on)
	echo "$PREFIX Creating env for ${CHANNEL_DIR}/${TAR_NAME} in ${BASE_DIR}/ana-test-${VERSION}"
	conda env create -q -f $CONDA_DIR/ana-official-py2.yml
	conda env create -q -f $CONDA_DIR/ana-official-py3.yml
fi

# Remove things not needed
echo "$PREFIX Running conda build purge..."
conda build purge
cd $BASE_DIR
rm -rf conda-root

# If nightly check env/tarball count to maintain circular buffer of $MAX_BUILDS
if [ $OFFICIAL == "false" ]; then
	cd $BASE_DIR
	NUM_ENVS=$(ls | grep ana-nightly | wc -l)

	cd $CHANNEL_DIR/linux-64
	NUM_TARS=$(ls | grep psana-conda-nightly | wc -l)

	# First lets make sure there are an equal number of tarballs and environment since they
	# should be isomorphic (yay math terms)
	if [ $NUM_TARS -ne $NUM_ENVS ]; then
		echo "$PREFIX There are $NUM_TARS tarballs and $NUM_ENVS envs. They should be equal..."
		echo "$PREFIX Something is wrong. Aborting..."
		exit
	fi

	# If they are, determine which environment(s) to delete if there are any
	cd $BASE_DIR
	if [ $NUM_ENVS -gt $MAX_BUILDS ]; then
		NUM_ENVS_TO_REMOVE=$(($NUM_ENVS - $MAX_BUILDS))
		ENVS_TO_REMOVE=$(ls -t | grep ana-nightly | tail -n $NUM_ENVS_TO_REMOVE)

		echo "$PREFIX Removing $NUM_ENVS_TO_REMOVE env(s):"
		echo $ENVS_TO_REMOVE
		rm -rf $ENVS_TO_REMOVE
	else
		echo "$PREFIX There are less than or equal to $MAX_BUILDS envs..."
		echo "$PREFIX No envs to remove..."
	fi

	# And same with tarball
	cd $CHANNEL_DIR/linux-64
	if [ $NUM_TARS -gt $MAX_BUILDS ]; then
		NUM_TARS_TO_REMOVE=$(($NUM_TARS - $MAX_BUILDS))
		TARS_TO_REMOVE=$(ls -t | grep psana-conda-nightly | tail -n $NUM_TARS_TO_REMOVE)

		echo "$PREFIX Removing $NUM_TARS_TO_REMOVE tarball(s):"
		echo $TARS_TO_REMOVE
		rm -rf $TARS_TO_REMOVE
	else
		echo "$PREFIX There are less than or equal to $MAX_BUILDS tarballs..."
		echo "$PREFIX No tarballs to remove..."
	fi

	echo "$PREFIX Finished building for $HOSTNAME as $BUILDER..."
else
	echo "$PREFIX Finished building official ana release version $VERSION for $HOSTNAME as $BUILDER..."
fi

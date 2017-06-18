#!/bin/bash

RHEL_VER=UNKNOWN
cat /etc/redhat-release | grep -q "release 7" && RHEL_VER=7
cat /etc/redhat-release | grep -q "release 6" && RHEL_VER=6
cat /etc/redhat-release | grep -q "release 5" && RHEL_VER=5
if [ $RHEL_VER = UNKNOWN ]; then
	echo "$PREFIX RHEL version could not be found. Aborting..."
	exit
fi

BASE_DIR="/reg/g/psdm/sw/conda/inst/miniconda2-prod-rhel${RHEL_VER}/envs"
CONDA_DIR="$BASE_DIR/conda-root"
CHANNEL_DIR="/reg/g/psdm/sw/conda/channels/psana-rhel${RHEL_VER}"

conda_setup="/reg/g/psdm/bin/conda_setup"
PREFIX="[JENKINS SCRIPT]:"
BUILDER=$(whoami)
HOSTNAME=$(hostname)
VERSION="9.9.9"
DATE=`date +%Y%m%d_hour%H`
UNZIP=true
MAX_BUILDS=5


# Exit as failure if any errors so Jenkins sees it as a failure
set -e


# Source conda and begin script
source $conda_setup ""
echo "$PREFIX Building on ${HOSTNAME} as ${BUILDER}..."


# Initial setup, clean directory before using
cd $BASE_DIR
[ -d "conda-root" ] && rm -rf conda-root
mkdir -p conda-root/downloads/anarel


# Remove old tags and get new ones
cd $CONDA_DIR
echo "PREFIX Retrieving tags..."
ana-rel-admin --force --cmd psana-conda-src --name $VERSION --basedir $CONDA_DIR --tagsfile /reg/g/psdm/sw/conda/manage/config/psana-conda-svn-pkgs
mv downloads/anarel/psana-conda-${VERSION}.tar.gz downloads/anarel/psana-conda-nightly-${VERSION}.tar.gz

# Get recipes and edit meta.yaml
echo "$PREFIX Retrieving recipe..."
cp -r /reg/g/psdm/sw/conda/manage/recipes/psana/psana-conda-opt .

echo "$PREFIX Editing meta.yaml..."
sed -i "s/{% set pkg =.*/{% set pkg = 'psana-conda-nightly' %}/" psana-conda-opt/meta.yaml
sed -i "s/{% set version =.*/{% set version = '$VERSION' %}/" psana-conda-opt/meta.yaml
sed -i "/source:/!b;n;c \ \ fn: $CONDA_DIR/downloads/anarel/{{ pkg }}-{{ version }}.tar.gz" psana-conda-opt/meta.yaml


# Build it and put tarball in CHANNEL_DIR with right name, abort if more than one (or 0) files found to rename
cd $CONDA_DIR
echo "$PREFIX Building tarball into $CHANNEL_DIR..."
conda-build --output-folder $CHANNEL_DIR psana-conda-opt
cd $CHANNEL_DIR/linux-64
TAR_NAME=$(ls psana-conda-nightly-${VERSION}*)
echo "$PREFIX Changing name from $TAR_NAME to psana-conda-nightly-${DATE}..."
mv $TAR_NAME psana-conda-nightly-${DATE}.tar.gz


# Create new environment by using tarball and place in BASE_DIR
echo "$PREFIX Creating env for ${CHANNEL_DIR}/${TAR_NAME} in ${BASE_DIR}/ana-nightly-${DATE}"
conda create -y -p ${BASE_DIR}/ana-nightly-${DATE} -c file://${CHANNEL_DIR} psana-conda-nightly


# Remove conda-bld extra directories
echo "$PREFIX Running conda build purge..."
conda build purge


# Before checking to remove, check to make sure nothing is weird
cd $CHANNEL_DIR/linux-64
NUM_TARS=$(ls | grep psana-conda-nightly | wc -l)

cd $BASE_DIR
NUM_ENVS=$(ls | grep ana-nightly | wc -l)

if [ $NUM_TARS -ne $NUM_ENVS ]; then
	echo "$PREFIX There are $NUM_TARS tarballs and $NUM_ENVS envs. They should be equal..."
	echo "$PREFIX Something is wrong. Aborting..."
	exit
fi


# Remove oldest envs and tarballs if there's more than MAX_BUILDS of them
if [ $NUM_ENVS -gt $MAX_BUILDS ]; then
	NUM_ENVS_TO_REMOVE=$(($NUM_ENVS - $MAX_BUILDS))
	ENVS_TO_REMOVE=$(ls -t | grep ana-nightly | tail -n $NUM_ENVS_TO_REMOVE)

	echo "$PREFIX Removing $NUM_ENVS_TO_REMOVE env(s):"
	echo $ENVS_TO_REMOVE
	rm -rf $ENVS_TO_REMOVE
else
	echo "$PREFIX There are less than $MAX_BUILDS envs..."
	echo "$PREFIX No envs to remove..."
fi

if [ $NUM_TARS -gt $MAX_BUILDS ]; then
	NUM_TARS_TO_REMOVE=$(($NUM_TARS - $MAX_BUILDS))
	TARS_TO_REMOVE=$(ls -t | grep psana-conda-nightly | tail -n $NUM_TARS_TO_REMOVE)

	echo "$PREFIX Removing $NUM_TARS_TO_REMOVE tarball(s):"
	echo $TARS_TO_REMOVE
	rm -rf $TARS_TO_REMOVE
else
	echo "$PREFIX There are less than $MAX_BUILDS tarballs..."
	echo "$PREFIX No tarballs to remove..."
fi

echo "$PREFIX Finished building for $HOSTNAME as $BUILDER..."

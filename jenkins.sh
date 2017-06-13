#!/bin/bash

RHEL_VER=UNKNOWN
cat /etc/redhat-release | grep -q "release 7" && RHEL_VER=7
cat /etc/redhat-release | grep -q "release 6" && RHEL_VER=6
cat /etc/redhat-release | grep -q "release 5" && RHEL_VER=5

conda_setup="/reg/g/psdm/bin/conda_setup"
PREFIX="[JENKINS SCRIPT]:"
BUILDER=$(whoami)
HOSTNAME=$(hostname)
BASE_DIR="/reg/g/psdm/sw/conda/inst/miniconda2-prod-rhel${RHEL_VER}/envs"
VERSION="9.9.9"
UNZIP=true
MAX_BUILDS=10


# Exit as failure if any errors so Jenkins sees it as a failure
set -e


# Source conda and begin script
source $conda_setup ""
echo "$PREFIX Building on ${HOSTNAME} as ${BUILDER}..."


# Initial setup, clean directory before using
cd $BASE_DIR
[ -d "tmp_nightly" ] && rm -rf tmp_nightly
mkdir -p tmp_nightly/conda-root/downloads/anarel
TMP_DIR="$BASE_DIR/tmp_nightly"
CONDA_DIR="$TMP_DIR/conda-root"
cd $TMP_DIR


# Remove old tags and get new ones
cd conda-root
echo "PREFIX Retrieving tags..."
ana-rel-admin --force --cmd psana-conda-src --name $VERSION --basedir $CONDA_DIR --tagsfile /reg/g/psdm/sw/conda/manage/config/psana-conda-svn-pkgs


# Get recipes and edit meta.yaml
echo "$PREFIX Retrieving recipe..."
cp -r /reg/g/psdm/sw/conda/manage/recipes/psana/psana-conda-opt .

echo "$PREFIX Editing meta.yaml..."
sed -i "s/{% set version =.*/{% set version = '$VERSION' %}/" psana-conda-opt/meta.yaml
sed -i "/source:/!b;n;c \ \ fn: $CONDA_DIR/downloads/anarel/{{ pkg }}-{{ version }}.tar.gz" psana-conda-opt/meta.yaml


# Build it
echo "$PREFIX Building..."
conda-build --output-folder $TMP_DIR psana-conda-opt


# Extracting or moving build
echo "$PREFIX Done building..."
cd $BASE_DIR
DATE=`date +%Y%m%d_hour%H`
mkdir ana-nightly-$DATE
BUILD_FILE=$(ls $TMP_DIR/linux-64 | grep psana-conda-$VERSION)
if [ $UNZIP = true ]; then
	echo "$PREFIX Extracting build data to $BASE_DIR/ana-nightly-$DATE..."
	tar jxf $TMP_DIR/linux-64/$BUILD_FILE -C ana-nightly-$DATE
else
	echo "$PREFIX Moving .tar.bz2 file to $BASE_DIR/ana-nightly-$DATE..."
	mv $TMP_DIR/linux-64/$BUILD_FILE ana-nightly-$DATE
fi


# Remove conda-bld extra directories
echo "$PREFIX Removing tmp_nightly directory from $BASE_DIR..."
conda build purge
rm -rf tmp_nightly


# Remove oldest build(s) if there's more than MAX_BUILDS builds
NUM_BUILDS=$(ls | grep ana-nightly | wc -l)

if [ $NUM_BUILDS -gt $MAX_BUILDS ]; then
	NUM_BUILDS_TO_REMOVE=$(($NUM_BUILDS - $MAX_BUILDS))
    BUILDS_TO_REMOVE=$(ls -t | grep ana-nightly | tail -n $NUM_BUILDS_TO_REMOVE)
  
	echo "$PREFIX Removing $NUM_BUILDS build(s):"
	echo $BUILDS_TO_REMOVE
	rm -rf $BUILDS_TO_REMOVE
else
	echo "$PREFIX There are less than $MAX_BUILDS builds..."
    echo "$PREFIX No builds to remove..."
fi

echo "$PREFIX Finished building for $HOSTNAME as $BUILDER..."

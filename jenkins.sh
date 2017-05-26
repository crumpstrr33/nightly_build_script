#!/bin/bash

PREFIX="[JENKINS SCRIPT]:"
conda_setup="/reg/g/psdm/bin/conda_setup"
VERSION="9.9.9"
BASE_DIR="/reg/g/psdm/sw/releases/test_nightly"
FULL_HOSTNAME=$(hostname)
HOSTNAME=(${FULL_HOSTNAME//./ }) && HOSTNAME=${HOSTNAME[0]}
CONDA_DIR="$BASE_DIR/conda-root"
MAX_BUILDS=10

cd $BASE_DIR
source $conda_setup

echo "$PREFIX Building on ${FULL_HOSTNAME}..."

# Initial setup
[ ! -d "${HOSTNAME}_nightly" ] && mkdir ${HOSTNAME}_nightly


# Makes directories
if [ ! -d "conda-root/downloads/anarel" ]; then
	echo "$PREFIX Creating dirs..."
	mkdir -p conda-root/downloads/anarel
fi


# cd into directories
cd conda-root


# Remove old tags and get new ones
[ ! -z $(ls downloads/anarel) ] && rm downloads/anarel/*
echo "PREFIX Retrieving tags..."
ana-rel-admin --force --cmd psana-conda-src --name $VERSION --basedir $CONDA_DIR --tagsfile /reg/g/psdm/sw/conda/manage/config/psana-conda-svn-pkgs


# Get recipes and edit meta.yaml
echo "$PREFIX Retrieving recipe..."
rm -rf psana-conda-opt
cp -r /reg/g/psdm/sw/conda/manage/recipes/psana/psana-conda-opt .

echo "$PREFIX Editing meta.yaml..."
sed -i "s/{% set version =.*/{% set version = '$VERSION' %}/" psana-conda-opt/meta.yaml
sed -i "/source:/!b;n;c \ \ fn: $CONDA_DIR/downloads/anarel/{{ pkg }}-{{ version }}.tar.gz" psana-conda-opt/meta.yaml


# Build it
cd $BASE_DIR
mkdir tmp_${HOSTNAME}_nightly

cd conda-root
echo "$PREFIX Building..."
conda-build --output-folder $BASE_DIR/tmp_${HOSTNAME}_nightly psana-conda-opt


# Extracting build
cd $BASE_DIR
DATE=`date +%Y%m%d%H`
echo "$PREFIX Extracting build data to $BASE_DIR/${HOSTNAME}_nightly/$DATE"
mkdir ${HOSTNAME}_nightly/$DATE
tar jxf tmp_${HOSTNAME}_nightly/linux-64/psana-conda-$VERSION-py27_2.tar.bz2 -C ${HOSTNAME}_nightly/$DATE


# Remove conda-bld extra directories
echo "$PREFIX Removing conda-bld, conda-root and tmp_${HOSTNAME}_nightly directory from $BASE_DIR"
conda build purge
rm -rf conda-bld conda-root tmp_${HOSTNAME}_nightly


# Remove oldest build(s) if there's more than MAX_BUILDS builds
NUM_BUILDS=$(ls ${HOSTNAME}_nightly | wc -l)
cd ${HOSTNAME}_nightly

if [ $NUM_BUILDS -gt $MAX_BUILDS ]; then
	NUM_BUILDS_TO_REMOVE=$(($NUM_BUILDS - $MAX_BUILDS))
    BUILDS_TO_REMOVE=$(ls -t | tail -n $NUM_BUILDS_TO_REMOVE)
  
	echo "$PREFIX Removing $BUILDS_TO_REMOVE build(s)..."
	rm -rf $BUILDS_TO_REMOVE
else
	echo "$PREFIX There are less than $MAX_BUILDS builds..."
    echo "$PREFIX No builds to remove..."
fi

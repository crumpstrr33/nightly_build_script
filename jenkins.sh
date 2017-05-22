#!/bin/bash

VERSION="9.9.9"
BASE_DIR=$HOME
CONDA_DIR="$BASE_DIR/conda-root"
MAX_BUILDS=10

cd $BASE_DIR
source conda_setup

# Initial setup
[ ! -d "nightly" ] && mkdir nightly

# Makes directories
if [ ! -d "conda-root/downloads/anarel" ]; then
	echo "Creating dirs..."
	mkdir -p conda-root/downloads/anarel
fi

# cd into directories
cd conda-root

# Remove old tags and get new ones
[ ! -z $(ls downloads/anarel) ] && rm downloads/anarel/*
echo "Retrieving tags..."
ana-rel-admin --force --cmd psana-conda-src --name $VERSION --basedir $CONDA_DIR --tagsfile /reg/g/psdm/sw/conda/manage/config/psana-conda-svn-pkgs

# Get recipes and edit meta.yaml
echo "Retrieving recipe..."
rm -rf psana-conda-opt
cp -r /reg/g/psdm/sw/conda/manage/recipes/psana/psana-conda-opt .

echo "Editing meta.yaml..."
sed -i "s/{% set version =.*/{% set version = '$VERSION' %}/" psana-conda-opt/meta.yaml
sed -i "/source:/!b;n;c \ \ fn: $CONDA_DIR/downloads/anarel/{{ pkg }}-{{ version }}.tar.gz" psana-conda-opt/meta.yaml

# Build it
cd $BASE_DIR
mkdir tmp_nightly

cd conda-root
echo "Building..."
conda-build --output-folder $BASE_DIR/tmp_nightly psana-conda-opt

# Extracting build
cd $BASE_DIR
DATE=`date +%Y%m%d%H`
echo "Extracting build data to $BASE_DIR/nightly/$DATE"
mkdir nightly/$DATE
tar jxf tmp_nightly/linux-64/psana-conda-$VERSION-py27_2.tar.bz2 -C nightly/$DATE

# Remove conda-bld
echo "Removing conda-bld, conda-root and tmp_nightly directory from $BASE_DIR"
conda build purge
rm -rf conda-bld conda-root tmp_nightly

# Remove builds older than $NUM_DAYS
if [ ! -z "$(find nightly/* -mtime +$MAX_BUILDS)" ]; then
	echo "Removing the following older build(s):"
	find nightly/* -mtime +$MAX_BUILDS
	find nightly/* -mtime +$MAX_BUILDS -delete
else
	echo "No builds at least $MAX_BUILDS days old to remove..." 
	echo "There aren't more than $MAX_BUILDS. No builds to remove..."
fi

NUM_BUILDS=$(ls nightly | wc -l)
if [ $NUM_BUILDS > $MAX_BUILDS ]; then
	BUILDS_TO_REMOVE = $NUM_BUILDS - $MAX_BUILDS

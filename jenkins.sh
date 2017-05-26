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


# Remove conda-bld extra directories
echo "Removing conda-bld, conda-root and tmp_nightly directory from $BASE_DIR"
conda build purge
rm -rf conda-bld conda-root tmp_nightly


# Remove oldest build(s) if there's more than MAX_BUILDS builds
NUM_BUILDS=$(ls nightly | wc -l)
cd nightly

if [ $NUM_BUILDS -gt $MAX_BUILDS ]; then
	NUM_BUILDS_TO_REMOVE=$(($NUM_BUILDS - $MAX_BUILDS))
    BUILDS_TO_REMOVE=$(ls -t | tail -n $NUM_BUILDS_TO_REMOVE)
  
	echo "Removing $BUILDS_TO_REMOVE build(s)..."
	rm -rf $BUILDS_TO_REMOVE
else
	echo "There are less than $MAX_BUILDS builds..."
    echo "No builds to remove..."
fi

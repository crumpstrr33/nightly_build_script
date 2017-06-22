#!/bin/bash

conda_setup="/reg/g/psdm/bin/conda_setup"
PREFIX="[JENKINS SCRIPT]:"
BUILDER=$(whoami)
HOSTNAME=$(hostname)
DATE=`date +%Y%m%d_hour%H`
MAX_BUILDS=5

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

VERSION=${1-"9.9.9"}
if [[ ! $VERSION =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
	echo "$PREFIX Invalid version number given: $VERSION"
	echo "$PREFIX Must be of form d.d.d where d is at least 1 digit. Aborting..."
	exit
fi
if [ $VERSION == "9.9.9" ]; then
	echo "$PREFIX Not building an official release..."
	OFFICIAL=false
	PREFIX="[JENKINS SCRIPT (NIGHTLY)]:"
else
	if [ ! -z $(ls | grep $VERSION) ]; then
		echo "$PREFIX Version $VERSION already exists for the psana-conda build. Aborting..."
		exit
	fi
	echo "$PREFIX Building an official release of version $VERSION..."
	OFFICIAL=true
	PREFIX="[JENKINS SCRIPT (OFFICIAL)]:"
fi



set -e


source $conda_setup ""
echo "$PREFIX Building on ${HOSTNAME} as ${BUILDER}..."


cd $BASE_DIR
[ -d "conda-root" ] && rm -rf conda-root
mkdir -p conda-root/downloads/anarel


cd $CONDA_DIR
echo "$PREFIX Retrieving tags..."
ana-rel-admin --force --cmd psana-conda-src --name $VERSION --basedir $CONDA_DIR
if [ $OFFICIAL == "false" ]; then
	mv downloads/anarel/psana-conda-${VERSION}.tar.gz downloads/anarel/psana-conda-nightly-${VERSION}.tar.gz
fi


echo "$PREFIX Retrieving recipe..."
cp -r /reg/g/psdm/sw/conda/manage/recipes/psana/psana-conda-opt .

echo "$PREFIX Editing meta.yaml..."
if [ $OFFICIAL == "false" ]; then
	sed -i "s/{% set pkg =.*/{% set pkg = 'psana-conda-nightly' %}/" psana-conda-opt/meta.yaml
else
	cp "/reg/neh/home/jscott/jenkins_sh/ana-official-py2.yml" .
	cp "/reg/neh/home/jscott/jenkins_sh/ana-official-py3.yml" .
	sed -i "/^name:/ s/$/-${VERSION}/" ana-official-py2.yml
	sed -i "/^name:/ s/$/-${VERSION}-py3/" ana-official-py3.yml
fi
sed -i "s/{% set version =.*/{% set version = '$VERSION' %}/" psana-conda-opt/meta.yaml
sed -i "/source:/!b;n;c \ \ fn: $CONDA_DIR/downloads/anarel/{{ pkg }}-{{ version }}.tar.gz" psana-conda-opt/meta.yaml


cd $CONDA_DIR
echo "$PREFIX Building tarball into $CHANNEL_DIR..."
conda-build --output-folder $CHANNEL_DIR psana-conda-opt
cd $CHANNEL_DIR/linux-64
if [ $OFFICIAL == "false" ]; then
	TAR_NAME=$(ls psana-conda-nightly-${VERSION}*)
	echo "$PREFIX Changing name from $TAR_NAME to psana-conda-nightly-${DATE}..."
	mv $TAR_NAME psana-conda-nightly-${DATE}.tar.gz
	echo "$PREFIX Creating env for ${CHANNEL_DIR}/${TAR_NAME} in ${BASE_DIR}/ana-nightly-${DATE}"
	conda create -y -p ${BASE_DIR}/ana-nightly-${DATE} -c file://${CHANNEL_DIR} psana-conda-nightly
else
	TAR_NAME=$(ls psana-conda-${VERSION}*)
	echo "$PREFIX Creating env for ${CHANNEL_DIR}/${TAR_NAME} in ${BASE_DIR}/ana-test-${VERSION}"
	conda env create -q -f $CONDA_DIR/ana-official-py2.yml
	conda env create -q -f $CONDA_DIR/ana-official-py3.yml
fi


echo "$PREFIX Running conda build purge..."
conda build purge
cd $BASE_DIR
rm -rf conda-root

if [ $OFFICIAL == "false" ]; then
	cd $BASE_DIR
	NUM_ENVS=$(ls | grep ana-nightly | wc -l)

	cd $CHANNEL_DIR/linux-64
	NUM_TARS=$(ls | grep psana-conda-nightly | wc -l)

	if [ $NUM_TARS -ne $NUM_ENVS ]; then
		echo "$PREFIX There are $NUM_TARS tarballs and $NUM_ENVS envs. They should be equal..."
		echo "$PREFIX Something is wrong. Aborting..."
		exit
	fi


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

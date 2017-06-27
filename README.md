# LCLS Conda Nighly Build Script
&#10024; Now can do a little more than what the title suggests &#10024;

It will build a conda environment for the LCLS psana package and will keep a circular buffer so that only the newest n environments are kept.

Also, if given a version number, it will create an official release of the LCLS ana environment will a version number of the number given. It will do this for both python 2 and python 3 (that's what yaml files are for).

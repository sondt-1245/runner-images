#!/bin/bash -e -o pipefail
################################################################################
##  File:  install-pypy.sh
##  Desc:  Install PyPy
################################################################################

source ~/utils/utils.sh

InstallPyPy() {
    local package_url=$1

    PACKAGE_TAR_NAME=$(basename $package_url)
    echo "Downloading tar archive '$PACKAGE_TAR_NAME'"
    archive_path=$(download_with_retry $package_url)

    echo "Expand '$PACKAGE_TAR_NAME' to the /tmp folder"
    tar xf $archive_path -C /tmp

    # Get Python version
    PACKAGE_NAME=${PACKAGE_TAR_NAME/.tar.bz2/}
    MAJOR_VERSION=$(echo ${PACKAGE_NAME/pypy/} | cut -d. -f1)
    PYTHON_MAJOR="python$MAJOR_VERSION"

    if [[ $MAJOR_VERSION != 2 ]]; then
        PYPY_MAJOR="pypy$MAJOR_VERSION"
    else
        PYPY_MAJOR="pypy"
    fi

    PACKAGE_TEMP_FOLDER="/tmp/$PACKAGE_NAME"
    PYTHON_FULL_VERSION=$("$PACKAGE_TEMP_FOLDER/bin/$PYPY_MAJOR" -c "import sys;print('{}.{}.{}'.format(sys.version_info[0],sys.version_info[1],sys.version_info[2]))")
    PYPY_FULL_VERSION=$("$PACKAGE_TEMP_FOLDER/bin/$PYPY_MAJOR" -c "import sys;print('{}.{}.{}'.format(*sys.pypy_version_info[0:3]))")
    echo "Put '$PYPY_FULL_VERSION' to PYPY_VERSION file"
    echo $PYPY_FULL_VERSION > "$PACKAGE_TEMP_FOLDER/PYPY_VERSION"

    # PyPy folder structure
    PYPY_TOOLCACHE_PATH=$AGENT_TOOLSDIRECTORY/PyPy
    PYPY_TOOLCACHE_VERSION_PATH=$PYPY_TOOLCACHE_PATH/$PYTHON_FULL_VERSION
    PYPY_TOOLCACHE_VERSION_ARCH_PATH=$PYPY_TOOLCACHE_VERSION_PATH/x64

    echo "Check if PyPy hostedtoolcache folder exist..."
    if [[ ! -d $PYPY_TOOLCACHE_PATH ]]; then
        mkdir -p $PYPY_TOOLCACHE_PATH
    fi

    echo "Create PyPy '$PYPY_TOOLCACHE_VERSION_PATH' folder"
    mkdir $PYPY_TOOLCACHE_VERSION_PATH

    echo "Move PyPy $PACKAGE_TEMP_FOLDER binaries to $PYPY_TOOLCACHE_VERSION_ARCH_PATH folder"
    mv $PACKAGE_TEMP_FOLDER $PYPY_TOOLCACHE_VERSION_ARCH_PATH

    echo "Create additional symlinks (Required for UsePythonVersion Azure DevOps task)"
    cd $PYPY_TOOLCACHE_VERSION_ARCH_PATH/bin

    PYPY_FULL_VERSION=$(./$PYPY_MAJOR -c "import sys;print('{}.{}.{}'.format(*sys.pypy_version_info[0:3]))")
    echo "PYPY_FULL_VERSION is $PYPY_FULL_VERSION"
    echo $PYPY_FULL_VERSION > "PYPY_VERSION"

    # Starting from PyPy 7.3.4 these links are already included in the package
    [[ -f ./$PYTHON_MAJOR ]] || ln -s $PYPY_MAJOR $PYTHON_MAJOR
    [[ -f ./python ]] || ln -s $PYTHON_MAJOR python

    chmod +x ./python ./$PYTHON_MAJOR

    echo "Install latest Pip"
    ./python -m ensurepip
    ./python -m pip install --ignore-installed pip

    echo "Create complete file"
    touch $PYPY_TOOLCACHE_VERSION_PATH/x64.complete
}

arch=$(get_arch)
versions_json_path=$(download_with_retry "https://downloads.python.org/pypy/versions.json")
toolsetVersions=$(get_toolset_value '.toolcache[] | select(.name | contains("PyPy")) | .arch.'$arch'.versions[]')

for toolsetVersion in $toolsetVersions; do
    latestMajorPyPyVersion=$(cat $versions_json_path |
        jq -r --arg toolsetVersion $toolsetVersion '.[]
        | select((.python_version | startswith($toolsetVersion)) and .stable == true).files[]
        | select(.platform == "darwin").download_url' | head -1)
    if [[ -z $latestMajorPyPyVersion ]]; then
        echo "Failed to get PyPy version $toolsetVersion"
        exit 1
    fi
    InstallPyPy $latestMajorPyPyVersion
done

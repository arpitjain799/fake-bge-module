#!/usr/bin/env bash
# require: bash version >= 4
# usage example: bash batch_gen_modules.sh 2.79 out
set -eEu

SUPPORTED_BLENDER_VERSIONS=(
    "2.78" "2.79" "2.80" "2.81" "2.82" "2.83"
    "2.90" "2.91" "2.92" "2.93"
    "latest"
)

SUPPORTED_UPBGE_VERSIONS=(
    "0.2.5"
    "latest"
)

declare -A BLENDER_TAG_NAME=(
    ["v2.78"]="v2.78c"
    ["v2.79"]="v2.79b"
    ["v2.80"]="v2.80"
    ["v2.81"]="v2.81a"
    ["v2.82"]="v2.82a"
    ["v2.83"]="v2.83.9"
    ["v2.90"]="v2.90.0"
    ["v2.91"]="v2.91.0"
    ["v2.92"]="v2.92.0"
    ["v2.93"]="v2.93.0"
    ["vlatest"]="master"
)

declare -A UPBGE_TAG_NAME=(
    ["v0.2.5"]="v0.2.5"
    ["vlatest"]="master"
)

declare -A PACKAGE_NAME=(
    ["blender"]="bpy"
    ["upbge"]="bge"
)

TMP_DIR_NAME="tmp"
RAW_MODULES_DIR="raw_modules"
RELEASE_DIR="release"
SCRIPT_DIR=$(cd $(dirname $0); pwd)
CURRENT_DIR=`pwd`
PYTHON_BIN=${PYTHON_BIN:-python}

# check arguments
if [ $# -ne 5 ] && [ $# -ne 6 ]; then
    echo "Usage: bash build_pip_package.sh <develop|release> <target> <target-version> <source-dir> <blender-dir> [<mod-version>]"
    exit 1
fi

deploy_target=${1}
target=${2}
target_version=${3}
source_dir=${4}
blender_dir=${5}
mod_version=${6:-not-specified}

# check if PYTHON_BIN binary is availble
if ! command -v ${PYTHON_BIN} > /dev/null; then
    echo "Error: Cannot find ${PYTHON_BIN} binary."
    exit 1
fi
python_bin=$(command -v ${PYTHON_BIN})

# check if python version meets our requirements
IFS=" " read -r -a python_version <<< "$(${python_bin} -c 'import sys; print(sys.version_info[:])' | tr -d '(),')"
if [ ${python_version[0]} -lt 3 ] || [[ "${python_version[0]}" -eq 3 && "${python_version[1]}" -lt 7 ]]; then
    echo "Error: Unsupported python version \"${python_version[0]}.${python_version[1]}\". Requiring python 3.7 or higher."
    exit 1
fi

if [ ${RELEASE_VERSION:-not_exist} = "not_exist" ]; then
    echo "Environment variable 'RELEASE_VERSION' does not exist, so use date as release version"
    release_version=`date '+%Y%m%d'`
else
    echo "Environment variable 'RELEASE_VERSION' exists, so use it as release version"
    release_version="${RELEASE_VERSION}"
fi

# Verify that the version is compatible with PEP 440: https://www.python.org/dev/peps/pep-0440/
# This is assumed in further steps below, so check abort early in case it does not match
if ! ${python_bin} -c "from setuptools._vendor.packaging.version import Version; Version(\"${release_version}\")"; then
    echo "Error: Found invalid release version: \"${release_version}\""
    exit 1
fi

# check if the deploy_target is develop or release
if [ ! ${deploy_target} = "release" ] && [ ! ${deploy_target} = "develop" ]; then
    echo "deploy_target must be release or develop"
    exit 1
fi


# check if the specified version is supported
supported=0
if [ ${target} = "blender" ]; then
    for v in "${SUPPORTED_BLENDER_VERSIONS[@]}"; do
        if [ ${v} = ${target_version} ]; then
            supported=1
        fi
    done
    if [ ${supported} -eq 0 ]; then
        echo "${target_version} is not supported."
        echo "Supported version is ${SUPPORTED_BLENDER_VERSIONS[@]}."
        exit 1
    fi
elif [ ${target} = "upbge" ]; then
    for v in "${SUPPORTED_UPBGE_VERSIONS[@]}"; do
        if [ "${v}" = "${target_version}" ]; then
            supported=1
        fi
    done
    if [ ${supported} -eq 0 ]; then
        echo "${target_version} is not supported."
        echo "Supported version is ${SUPPORTED_UPBGE_VERSIONS[*]}."
        exit 1
    fi
else
    echo "${target} is not supported."
    exit 1
fi


# check if release dir and tmp dir are not exist
tmp_dir=${SCRIPT_DIR}/${TMP_DIR_NAME}-${target_version}
raw_modules_dir=${CURRENT_DIR}/${RAW_MODULES_DIR}
release_dir=${CURRENT_DIR}/${RELEASE_DIR}
if [ -e ${tmp_dir} ]; then
    echo "${tmp_dir} is already exists."
    exit 1
fi


if [ ${deploy_target} = "release" ]; then
    # setup pre-generated-modules/release/temp directories
    mkdir -p ${raw_modules_dir}
    mkdir -p ${release_dir}
    mkdir -p ${tmp_dir} && cd ${tmp_dir}

    # generate fake module
    fake_module_dir="out"
    ver=v${target_version}
    if [ ${target} = "blender" ]; then
        if [ ${mod_version} = "not-specified" ]; then
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${BLENDER_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir}
        else
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${BLENDER_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir} ${mod_version}
        fi
    elif [ ${target} = "upbge" ]; then
        if [ ${mod_version} = "not-specified" ]; then
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${UPBGE_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir}
        else
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${UPBGE_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir} ${mod_version}
        fi
    else
        echo "${target} is not supported."
        exit 1
    fi
    zip_dir="fake_${PACKAGE_NAME[$target]}_modules_${target_version}-${release_version}"
    cp -r ${fake_module_dir} ${zip_dir}
    zip_file_name="fake_${PACKAGE_NAME[$target]}_modules_${target_version}-${release_version}.zip"
    zip -r ${zip_file_name} ${zip_dir}
    mv ${zip_file_name} ${raw_modules_dir}
    mv ${fake_module_dir}/* .
    rm -r ${zip_dir}
    rm -r ${fake_module_dir}

    # build pip package
    cp ${SCRIPT_DIR}/setup.py .
    cp ${SCRIPT_DIR}/../../README.md .
    pandoc -f markdown -t rst -o README.rst README.md
    rm README.md
    rm -rf fake_${PACKAGE_NAME[$target]}_module*.egg-info/ dist/ build/
    ls -R .
    ${python_bin} setup.py sdist
    ${python_bin} setup.py bdist_wheel

    # move the generated package to releaes directory
    mv dist ${release_dir}/${target_version}

    # clean up
    cd ${CURRENT_DIR}
    rm -rf ${tmp_dir}

elif [ ${deploy_target} = "develop" ]; then
    # setup pre-generated-modules/release/temp directories
    mkdir -p ${raw_modules_dir}
    mkdir -p ${release_dir} && cd ${release_dir}
    cp ${SCRIPT_DIR}/setup.py .

    # generate fake module
    fake_module_dir="out"
    ver=v${target_version}
    if [ ${target} = "blender" ]; then
        if [ ${mod_version} = "not-specified" ]; then
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${BLENDER_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir}
        else
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${BLENDER_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir} ${mod_version}
        fi
    elif [ ${target} = "upbge" ]; then
        if [ ${mod_version} = "not-specified" ]; then
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${UPBGE_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir}
        else
            bash ${SCRIPT_DIR}/../../src/gen_module.sh ${CURRENT_DIR}/${source_dir} ${CURRENT_DIR}/${blender_dir} ${target} ${UPBGE_TAG_NAME[${ver}]} ${target_version} ${fake_module_dir} ${mod_version}
        fi
    else
        echo "${target} is not supported."
        exit 1
    fi
    zip_dir="fake_${PACKAGE_NAME[$target]}_modules_${target_version}-${release_version}"
    cp -r ${fake_module_dir} ${zip_dir}
    zip_file_name="fake_${PACKAGE_NAME[$target]}_modules_${target_version}-${release_version}.zip"
    zip -r ${zip_file_name} ${fake_module_dir}
    mv ${zip_file_name} ${raw_modules_dir}
    mv ${fake_module_dir}/* .
    rm -r ${zip_dir}
    rm -r ${fake_module_dir}

    # build and install package
    ls -R .
    ${python_bin} setup.py develop

    # clean up
    cd ${CURRENT_DIR}
    rm -rf ${tmp_dir}
fi

exit 0

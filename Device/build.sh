#!/bin/bash
set -e

BUILD_CONTAINER_ID=""
BUILD_CONTAINER_NAME="iotzbuild"
SETUP_CONTAINER_ID=""
STOP_CONTAINER_AFTER_BUILD=true
REMOVE_CONTAINER_AFTER_BUILD=false
BUILD_IMAGE_PATH="/images/arduino.tar.gz"
MXCHIP=""
BASEPATH="$(dirname "$0")"

usage() {
        cat <<EOF
USAGE: ./build.sh [--no-stop] [-r | --remove] [-n | --name] [-c | --copy-to] [--cleanup] [-h | --help]

DESCRIPTION:
  This script builds the software contained in this directory. To work correctly,
  it needs docker installed.
  WARNING: The images created by this script will use ~3GB in total! Make sure you
  have enough free space available.

OPTIONS:
  -c, --copy-to string           Copies the built software onto the given destination
      --copy-only                Only copy the software onto the mxchip (flag --copy-to needed)
      --cleanup                  Cleans up all images created by this script and removes the BUILD directory (not yet implemented)
  -h, --help                     Shows this help
  -n, --name string              Sets the name for the build container. Default: "$BUILD_CONTAINER_NAME"
      --no-stop                  Does not stop the container after the build. Useful for debugging
  -q, --quiet                    Does not output anything on the build process (script messages will be printed anyways!)
  -r, --remove                   Removes the container after the build. Will force a recreation on the next run
  --wifi-ssid, --wifi-password   Set and write the given WiFi credentials to auth.h for automatic WiFi connection on copy

EOF
}

exit_routine() {
    BUILD_CONTAINER_ID="$(docker ps -a | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
    if [ -n "$BUILD_CONTAINER_ID" ]; then
        if $STOP_CONTAINER_AFTER_BUILD || $REMOVE_CONTAINER_AFTER_BUILD; then
            docker stop "$BUILD_CONTAINER_ID" > /dev/null
        fi
        if $REMOVE_CONTAINER_AFTER_BUILD; then
            docker rm "$BUILD_CONTAINER_ID" > /dev/null
        fi
    fi
}

cleanup() {
    BUILD_CONTAINER_ID="$(docker ps | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
    if [ -n "$BUILD_CONTAINER_ID" ]; then
        docker stop "$BUILD_CONTAINER_ID" > /dev/null
    fi

    BUILD_CONTAINER_ID="$(docker ps -a | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
    if [ -n "$BUILD_CONTAINER_ID" ]; then
        docker rm "$BUILD_CONTAINER_ID" > /dev/null
    fi

    # Removes all iotz images
    IMAGE_LIST=$(docker image list | grep iotz | grep -E '(final|setup)' | awk '{print $3}')
    if [ -n "$IMAGE_LIST" ]; then
        docker image list | grep iotz | grep -E '(final|setup)' | awk '{print $3}' | xargs docker rmi
    fi
    rm -rf ./BUILD
    exit
}


while [ "$1" != "" ]; do
    case $1 in
        --no-stop )         shift
                            echo "not stopping container after build"
                            STOP_CONTAINER_AFTER_BUILD=false
                            ;;
        -h | --help )       usage
                            exit 0
                            ;;
        -r | --remove )     shift
                            echo "Removing container after build"
                            REMOVE_CONTAINER_AFTER_BUILD=true
                            ;;
        -n | --name )       shift
                            if [ -z "$1" ]; then
                                echo "Parameter name (-n / --name) needs an argument!"
                            fi
                            echo "setting build container name to $1"
                            BUILD_CONTAINER_NAME="$1"
                            shift
                            ;;
        -c | --copy-to )    shift
                            MXCHIP="$1"
                            echo "will copy final file to $MXCHIP"
                            shift
                            ;;
        --copy-only )       COPY_ONLY="true"
                            shift
                            ;;
        -q | --quiet )      shift
                            QUIET=true
                            ;;
        --wifi-password )   shift
                            WIFI_PASSWORD="$1"
                            shift
                            ;;
        --wifi-ssid )       shift
                            WIFI_SSID="$1"
                            shift
                            ;;
        --cleanup )         shift
                            cleanup
                            ;;
        *)                  echo "Unrecognized option or parameter: $1"
                            exit 1
                            ;;
    esac
done

setup_build_container() {
    build_build_container
    run_build_container
    create_build_image
    save_build_image
    commit_build_image
    stop_build_container
}

build_build_container() {
    echo "Building base container"
    docker build -t iotz:setup -f "$BASEPATH/setup_dockerfile" "$BASEPATH"
}

run_build_container() {
    echo "Starting container to create build image"
    SETUP_CONTAINER_ID=$(docker run --privileged -d iotz:setup)
}

create_build_image() {
    echo "Creating build image"
    docker exec "$SETUP_CONTAINER_ID" sh -c "\
        cd iotapp && \
        iotz init"
}

save_build_image() {
    echo "Saving build image"
    docker exec "$SETUP_CONTAINER_ID" sh -c "\
        mkdir /images && \
        docker save -o $BUILD_IMAGE_PATH azureiot/iotz_local_arduino:latest"
}

commit_build_image() {
    echo "Committing build container"
    docker commit "$SETUP_CONTAINER_ID" iotz:final
}

stop_build_container() {
    echo "Stopping and removing setup container"
    docker stop "$SETUP_CONTAINER_ID"
    docker rm "$SETUP_CONTAINER_ID"
}

write_wifi_credentials() {
    echo "Writing WiFi credentials"
    cat <<EOF > "$BASEPATH/auth.h"
// Copyright (c) IGSS. All rights reserved.
// Licensed under the MIT license.

#ifndef IGSS_AUTH_H
#define IGSS_AUTH_H

#define WIFI_USER ((char *)"$WIFI_SSID")
#define WIFI_PASS ((const char *)"$WIFI_PASSWORD")

#endif /* IGSS_AUTH_H */
EOF
    echo "Written WiFi credentials to auth.h"
}

build_software() {
    echo "Building software..."
    BUILD_CONTAINER_ID="$(docker ps | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
    # Build container not yet started
    if [ -z "$BUILD_CONTAINER_ID" ]; then
        BUILD_CONTAINER_ID="$(docker ps -a | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
        if [ -z "$BUILD_CONTAINER_ID" ]; then
            echo "Starting container $BUILD_CONTAINER_ID"
            BUILD_CONTAINER_ID="$(docker run --privileged --mount source="$BASEPATH",target=/iotapp,type=bind --name iotzbuild -d iotz:final)"
            echo "Container $BUILD_CONTAINER_ID started"
        else
            docker start "$BUILD_CONTAINER_ID" > /dev/null
        fi
    else
        echo "Container already started, ID $BUILD_CONTAINER_ID"
    fi

    IMAGE_LOADED=$(docker exec "$BUILD_CONTAINER_ID" sh -c 'docker image list | grep azureiot/iotz_local_arduino | awk '\''{print $1}'\''' || [[ $? == 1 ]])
    if [ -z "$IMAGE_LOADED" ]; then
        echo "Importing base image"
        docker exec "$BUILD_CONTAINER_ID" docker load -i "$BUILD_IMAGE_PATH"
    else
        echo "Base image already imported in container $BUILD_CONTAINER_ID"
    fi;

    echo "Compiling software..."
    if [ "$QUIET" ]; then
        docker exec "$BUILD_CONTAINER_ID" sh -c 'cd iotapp && iotz compile' > /dev/null
    else
        docker exec "$BUILD_CONTAINER_ID" sh -c 'cd iotapp && iotz compile'
    fi
}

copy() {
    mount "$MXCHIP" /media/mxchip
    cp "$BASEPATH/BUILD/Main.ino.bin" /media/mxchip
    echo "copied Main.ino.bin to $MXCHIP"
    umount "$MXCHIP"
}

trap exit_routine 0

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  if [[ -n "$message" ]] ; then
    echo "Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
  else
    echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  fi
  exit "${code}"
}

trap 'error ${LINENO}' ERR

# Actual "main" part of the program
if "$COPY_ONLY"; then
    if [ -n "$MXCHIP" ]; then
        echo "copying software"
        copy
    else
        echo "not copying as no device is given"
        exit 1
    fi
    exit
fi

SETUP_CONTAINER=$(docker image list --format='{{ .Repository }}:{{ .Tag }}' | grep "iotz:final" || [[ $? == 1 ]])
if [ -z "$SETUP_CONTAINER" ]; then
    setup_build_container
fi

if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PASSWORD" ]; then
    write_wifi_credentials
fi

build_software

if [ -n "$MXCHIP" ]; then
    copy
fi

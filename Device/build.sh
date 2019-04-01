#!/bin/bash
set -e

BUILD_CONTAINER_ID=""
BUILD_CONTAINER_NAME="iotzbuild"
SETUP_CONTAINER_ID=""
STOP_CONTAINER_AFTER_BUILD=true
REMOVE_CONTAINER_AFTER_BUILD=false
BUILD_IMAGE_PATH="/images/arduino.tar.gz"


while getopts ":src:n:" opt; do
  case $opt in
      s)
          echo "stopping container after build"
          if [ ! "$OPTARG" == "true" ] && [ ! "$OPTARG" == "false" ];
          then
              echo "boolean value (\"true\" / \"false\") expected for option $opt"
          fi
          STOP_CONTAINER_AFTER_BUILD=$OPTARG
          ;;
      r)
          echo "removing container after build"
          REMOVE_CONTAINER_AFTER_BUILD=true
          ;;
      n)
          echo "setting build container name to $OPTARG"
          BUILD_CONTAINER_NAME="$OPTARG"
          ;;
      c)
            echo "$opt not yet implemented"
            # TODO: Implement copy to device / location
            #echo "-a was triggered, Parameter: $OPTARG" >&2
            ;;
      \?)
          echo "Invalid option: -$OPTARG" >&2
          exit 1
          ;;
      :)
          echo "Option -$OPTARG requires an argument." >&2
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
    docker build -t iotz:setup .
}

run_build_container() {
    echo "Starting container to create build image"
    SETUP_CONTAINER_ID=$(docker run --privileged -d iotz:setup)
}

create_build_image() {
    echo "Creating build image"
    docker exec -ti "$SETUP_CONTAINER_ID" sh -c "\
        cd iotapp && \
        iotz init"
}

save_build_image() {
    echo "Saving build image"
    docker exec -ti "$SETUP_CONTAINER_ID" sh -c "\
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

build_software() {
    BUILD_CONTAINER_ID="$(docker ps | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
    # Build container not yet started
    if [ -z "$BUILD_CONTAINER_ID" ]; then
        BUILD_CONTAINER_ID="$(docker ps -a | grep "$BUILD_CONTAINER_NAME" | awk '{print $1}' || [[ $? == 1 ]])"
        if [ -z "$BUILD_CONTAINER_ID" ]; then
            echo "Starting container $BUILD_CONTAINER_ID"
            BUILD_CONTAINER_ID="$(docker run --privileged --mount source="$(pwd)",target=/iotapp,type=bind --name iotzbuild -d iotz:final)"
            echo "Container $BUILD_CONTAINER_ID started"
        else
            docker start "$BUILD_CONTAINER_ID"
        fi
    else
        echo "Container already started, ID $BUILD_CONTAINER_ID"
    fi

    IMAGE_LOADED=$(docker exec -ti "$BUILD_CONTAINER_ID" sh -c 'docker image list | grep azureiot/iotz_local_arduino | awk '\''{print $1}'\''' || [[ $? == 1 ]])
    if [ -z "$IMAGE_LOADED" ]; then
        echo "Importing base image"
        docker exec -ti "$BUILD_CONTAINER_ID" docker load -i "$BUILD_IMAGE_PATH"
    else
        echo "Base image $IMAGE_LOADED still imported in container $BUILD_CONTAINER_ID"
    fi;

    echo "Compiling software..."
    docker exec -ti "$BUILD_CONTAINER_ID" sh -c 'cd iotapp && iotz compile'

    if $STOP_CONTAINER_AFTER_BUILD || $REMOVE_CONTAINER_AFTER_BUILD; then
        docker stop "$BUILD_CONTAINER_ID"
    fi;
    if $REMOVE_CONTAINER_AFTER_BUILD; then
        docker rm "$BUILD_CONTAINER_ID"
    fi;
}


SETUP_CONTAINER=$(docker image list --format='{{ .Repository }}:{{ .Tag }}' | grep "iotz:final" || [[ $? == 1 ]])
if [ -z "$SETUP_CONTAINER" ]; then
    setup_build_container
fi;

build_software

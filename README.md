# Ice Guard MXChip

## Installation

1. Clone the repository and open the folder ´Device´ with VSCode.
1. Follow the [Getting Started Guide](https://microsoft.github.io/azure-iot-developer-kit/docs/get-started/).

For more info visit the [IoT DevKit](https://aka.ms/devkit) landing page.

## Usage

Make sure docker service is running on your machine and switch to the Device directory to get started.

	cd Device

Build the software

	./build.sh

Build and deploy software to mxchip

	./build.sh -c {mxchip mount dir}


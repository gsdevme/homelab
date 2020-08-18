default: build

build:
	cd services/hue/ && docker build -t hue-mqtt:latest .

all: build

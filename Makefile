.PHONY: all
default: all;

home-assistant:
	cd services/home-assistant docker build . --no-cache --build-arg HOME_ASSISTANT_VERSION=latest

.PHONY: all
default: all;

tag=latest
version=2020.12.1

build:
	docker build . --file Dockerfile --build-arg HOME_ASSISTANT_VERSION=$(version) --tag gsdevme/home-assistant:$(tag)

build-no-cache:
	docker build . --file Dockerfile --no-cache --build-arg HOME_ASSISTANT_VERSION=$(version) --tag gsdevme/home-assistant:$(tag)

push:
	docker push gsdevme/home-assistant:$(tag)

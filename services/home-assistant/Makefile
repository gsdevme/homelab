.PHONY: all
default: all;

tag=latest
version=latest

build:
	docker build . --file Dockerfile --build-arg HOME_ASSISTANT_VERSION=$(version) --tag gsdevme/home-assistant:$(tag)

push:
	docker push gsdevme/home-assistant:$(tag)

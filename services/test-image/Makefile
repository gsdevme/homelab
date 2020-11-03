.PHONY: all
default: all;

tag=latest

build:
	docker build . --file Dockerfile --tag gsdevme/tester_image:$(tag)

push:
	docker push gsdevme/tester_image:$(tag)

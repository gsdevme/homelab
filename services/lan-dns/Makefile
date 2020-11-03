.PHONY: all
default: all;

tag=latest

build:
	docker build . --file Dockerfile --tag gsdevme/lan_dns:$(tag)

push:
	docker push gsdevme/lan_dns:$(tag)

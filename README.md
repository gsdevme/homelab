# Prerequisites & Disaster Recovery

@todo

## Services

### Home Assistant

#### Building the Image

Due to the deprecation of YAML a .storage bootstrap should create a single user/password but its
a brittle setup

```
cd services/home-assistant

make build version=0.117.1
```

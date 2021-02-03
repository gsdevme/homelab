#!/bin/bash

git diff --quiet HEAD master -- services/home-assistant || echo changed

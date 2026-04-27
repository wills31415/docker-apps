#!/bin/bash

# USER=$(whoami)
# UID=$(id -u)
# GID=$(id -g)
# DIRECTORY=uploads

# CONFIGURATION=$USER::$UID:$GID:$DIRECTORY
# echo $CONFIGURATION

echo $(whoami)::$(id -u):$(id -g):uploads

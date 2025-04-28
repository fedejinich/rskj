#!/bin/bash

set -e

rm -rf logs/
mkdir logs/
./gradlew clean
./gradlew assemble

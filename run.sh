#!/bin/bash

set -e

./gradlew assemble
java17 -Xmx8g -cp rskj-core/build/libs/rskj-core-*-SNAPSHOT-all.jar co.rsk.Start

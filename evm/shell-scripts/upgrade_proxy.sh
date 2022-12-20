#!/bin/bash

set -euo pipefail

ts-node $(dirname $0)/../ts/scripts/upgrade_proxy.ts $@
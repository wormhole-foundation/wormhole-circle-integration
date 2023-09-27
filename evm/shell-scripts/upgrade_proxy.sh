#!/usr/bin/env bash

set -euo pipefail

npx ts-node $(dirname $0)/../ts/scripts/upgrade_proxy.ts $@
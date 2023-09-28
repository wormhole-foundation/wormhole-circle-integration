#!/usr/bin/env bash

set -euo pipefail

npx tsx $(dirname $0)/../ts/scripts/upgrade_proxy.ts $@
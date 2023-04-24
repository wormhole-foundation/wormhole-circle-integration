#!/bin/bash

forge script $(dirname $0)/../forge-scripts/test_outbound_transfer.sol \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow

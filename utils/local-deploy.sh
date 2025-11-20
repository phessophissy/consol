#!/bin/bash

# Load environment variables
set -a
source .env
set +a

# Kill the script and any child processes when Ctrl+C is pressed
trap "exit" INT TERM
trap "kill 0" EXIT

# Start anvil in the background and save its PID
# Start anvil from scratch and run all of the setup scripts
echo "Starting anvil from scratch"
anvil &
ANVIL_PID=$!

# Wait a few seconds for anvil to start up
sleep 2

# Set balance for specific address (amount in hex, this example is 2_000 hype)
echo "Setting balance for address: $DEPLOYER_ADDRESS"

cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x6C7974123F64A40000 --rpc-url http://localhost:8545

# Set the WHYPE precompile to the 0x555... address
echo "Deploying WHYPE precompile to 0x5555555555555555555555555555555555555555"
cast rpc anvil_setCode 0x5555555555555555555555555555555555555555 "$(jq -r '.deployedBytecode.object' script/artifacts/WHYPE9.json)" --rpc-url http://localhost:8545
# Initialize state variables for WHYPE contract
echo "Initializing WHYPE state variables"
# Slot 0: name = "Wrapped HYPE" (12 chars = 0x18 length, stored as length*2 = 0x18 in last byte)
cast rpc anvil_setStorageAt 0x5555555555555555555555555555555555555555 0x0 0x5772617070656420485950450000000000000000000000000000000000000018 --rpc-url http://localhost:8545
# Slot 1: symbol = "WHYPE" (5 chars = 0x0a length, stored as length*2 = 0x0a in last byte)
cast rpc anvil_setStorageAt 0x5555555555555555555555555555555555555555 0x1 0x574859504500000000000000000000000000000000000000000000000000000a --rpc-url http://localhost:8545
# Slot 2: decimals = 18 (0x12)
cast rpc anvil_setStorageAt 0x5555555555555555555555555555555555555555 0x2 0x0000000000000000000000000000000000000000000000000000000000000012 --rpc-url http://localhost:8545

# Set the Multicall3 precompile to the 0xcA11bde05977b3631167028862bE2a173976CA11 address
echo "Deploying Multicall3 precompile to 0xcA11bde05977b3631167028862bE2a173976CA11"
cast rpc anvil_setCode 0xcA11bde05977b3631167028862bE2a173976CA11 "$(jq -r '.deployedBytecode.object' script/artifacts/Multicall3.json)" --rpc-url http://localhost:8545

# Deploy the contracts using forge
echo "Deploying contracts"
forge script script/DeployAll.s.sol --rpc-url http://localhost:8545 --broadcast --slow

# Run the localhost setup script part 1
forge script script/LocalhostSetupPart1.s.sol --rpc-url http://localhost:8545 --broadcast --slow --ffi

# Move time forward to the origination pool's deploy phase
cast rpc evm_increaseTime 86400 --rpc-url http://localhost:8545
cast rpc evm_mine --rpc-url http://localhost:8545

# # Run the localhost setup script part 2
# forge script script/LocalhostSetupPart2.s.sol --rpc-url http://localhost:8545 --broadcast --slow --ffi

# # Move time forward to the origination pool's redeem phase
# cast rpc evm_increaseTime 604800 --rpc-url http://localhost:8545
# cast rpc evm_mine --rpc-url http://localhost:8545

# # Run the localhost setup script part 3
# forge script script/LocalhostSetupPart3.s.sol --rpc-url http://localhost:8545 --broadcast --slow --ffi

# The script will keep running until you press Ctrl+C
# When that happens, the trap above will kill anvil
# kill $ANVIL_PID
# wait $ANVIL_PID # When that happens, the trap above will kill anvil
wait $ANVIL_PID 

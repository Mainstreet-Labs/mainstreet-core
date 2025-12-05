// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Script.sol";
import {DeploymentUtility} from "../utils/DeploymentUtility.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {msUSDV2} from "../../src/v2/msUSDV2.sol";
import {msUSDV2Satellite} from "../../src/v2/msUSDV2Satellite.sol";
import {msUSDV2Sonic} from "../../src/v2/msUSDV2Sonic.sol";
import "../../test/utils/Constants.sol";

/** 
    @dev Architecture:
    ETH: msUSDV2 (Home Chain)
    Sonic: msUSDV2Sonic (Sonic legacy version)
    Other: msUSDV2Satellite

    @dev To run: 
    forge script script/ethereum/DeploymsUSDV2CrossChain.s.sol:DeploymsUSDV2CrossChain --broadcast --verify -vvvv

    @dev To verify msUSDV2:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 1 \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
        src/v2/msUSDV2.sol:msUSDV2

    @dev To verify msUSDV2Satellite:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id <CHAIN_ID> \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>" \
        src/v2/msUSDV2Satellite.sol:msUSDV2Satellite \
        --constructor-args $(cast abi-encode "constructor(address)" <LZ_ENDPOINT>)

    @dev To verify Proxies:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id <CHAIN_ID> \
        --watch \
        --verifier custom \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>" \
        lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy

    forge verify-contract \
        0x4ba01f22827018b4772CD326C7627FB4956A7C00 \
        --chain-id 1 \
        --watch \
        --verifier custom \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
        lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy

    @dev Deployment 12/4/25
    == Logs ==
        msUSDV2 deployed to 0x7Ea01d56932F82370b11686dEe4d8Fa777845bd8
        Empty UUPS implementation contract deployed to 0xc05Fb730FFC1099464118A705aCd2BF5d81844cC
        msUSDV2 proxy deployed to 0x4ba01f22827018b4772CD326C7627FB4956A7C00
*/

interface IOFTCore {
    function isTrustedRemote(uint16, bytes calldata) external view returns (bool);
    function setTrustedRemoteAddress(uint16, bytes calldata) external;
}

/**
 * @title DeploymsUSDV2CrossChain
 * @notice This script deploys the protocol to various chains.
 * @dev This script was written during the migration of Sonic as the legacy home-chain to Ethereum as the home-chain.
 */
contract DeploymsUSDV2CrossChain is DeploymentUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        address remoteAddress;
        uint16 chainId;
        bool mainChain;
    }

    NetworkData[] internal allChains;

    mapping(string rpc => uint256 forkId) internal forkIdTracker;

    string constant public NAME = "msUSD"; /// @dev assign
    string constant public SYMBOL = "msUSD"; /// @dev assign

    address constant public MSUSD_SONIC = 0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D; /// @dev assign
    uint256 constant public SONIC_TOTALSUPPLY = 1_894_785_811599046426739012;

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        _setup("msUSD.testnet.deployment.3"); /// @dev assign

        allChains.push(NetworkData(
            {
                chainName: "Ethereum", // 1
                rpc_url: vm.envString("ETH_RPC_URL"), 
                lz_endpoint: ETH_LZ_ENDPOINT_V1, 
                remoteAddress: address(0),
                chainId: ETH_LZ_CHAIN_ID_V1,
                mainChain: true
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "Sonic", // 146
                rpc_url: vm.envString("SONIC_RPC_URL"), 
                lz_endpoint: SONIC_LZ_ENDPOINT_V1,
                remoteAddress: MSUSD_SONIC,
                chainId: SONIC_LZ_CHAIN_ID_V1,
                mainChain: false
            }
        ));
    }

    function run() public {

        // Deploy
        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {

            vm.createSelectFork(allChains[i].rpc_url);
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

            forkIdTracker[allChains[i].rpc_url] = i;

            if (allChains[i].chainId == SONIC_LZ_CHAIN_ID_V1) {
                require(msUSDV2(allChains[i].remoteAddress).totalSupply() == SONIC_TOTALSUPPLY, "total supply doesnt match");
            }

            if (allChains[i].remoteAddress == address(0)) {

                if (allChains[i].mainChain) {
                    allChains[i].remoteAddress = _deploymsUSDV2(allChains[i].lz_endpoint);
                }
                else {
                    allChains[i].remoteAddress = _deploymsUSDV2ForSatellite(allChains[i].lz_endpoint);
                }
            }

            vm.stopBroadcast();
        }

        // Configure trusted remote
        for (uint256 i; i < len; ++i) {

            vm.selectFork(forkIdTracker[allChains[i].rpc_url]);
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

            IOFTCore oftInterface = IOFTCore(allChains[i].remoteAddress);

            // set trusted remote address on all other chains for each token.
            for (uint256 j; j < len; ++j) {
                if (i != j) {
                    if (
                        !oftInterface.isTrustedRemote(
                            allChains[j].chainId, abi.encodePacked(allChains[j].remoteAddress, allChains[i].remoteAddress)
                        )
                    ) {
                        oftInterface.setTrustedRemoteAddress(
                            allChains[j].chainId, abi.encodePacked(allChains[j].remoteAddress)
                        );
                    }
                }
            }

            vm.stopBroadcast();
        }
    }

    /**
     * @dev This method is in charge of deploying and upgrading msUSDV2 on the home chain.
     * This method will perform the following steps:
     *    - Compute the msUSDV2 implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the msUSDV2
     *      address computed, it will upgrade that proxy.
     */
    function _deploymsUSDV2(address layerZeroEndpoint) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(msUSDV2).creationCode);
        address computedContractAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint)))
        );

        msUSDV2 msUSDToken;

        if (_isDeployed(computedContractAddress)) {
            console.log("msUSDV2 is already deployed to %s", computedContractAddress);
            msUSDToken = msUSDV2(computedContractAddress);
        } else {
            msUSDToken = new msUSDV2{salt: _SALT}(layerZeroEndpoint);
            assert(computedContractAddress == address(msUSDToken));
            console.log("msUSDV2 deployed to %s", computedContractAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            msUSDV2.initialize.selector,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL,
            SONIC_TOTALSUPPLY
        );

        proxyAddress = _deployProxy("msUSDV2", address(msUSDToken), init);
    }

    /**
     * @dev This method is in charge of deploying and upgrading msUSDV2Satellite on a satellite chain.
     * This method will perform the following steps:
     *    - Compute the msUSDV2Satellite implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the msUSDV2Satellite
     *      address computed, it will upgrade that proxy.
     */
    function _deploymsUSDV2ForSatellite(address layerZeroEndpoint) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(msUSDV2Satellite).creationCode);
        address computedContractAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint)))
        );

        msUSDV2Satellite msUSDSatelliteToken;

        if (_isDeployed(computedContractAddress)) {
            console.log("msUSDV2Satellite is already deployed to %s", computedContractAddress);
            msUSDSatelliteToken = msUSDV2Satellite(computedContractAddress);
        } else {
            msUSDSatelliteToken = new msUSDV2Satellite{salt: _SALT}(layerZeroEndpoint);
            assert(computedContractAddress == address(msUSDSatelliteToken));
            console.log("msUSDV2Satellite deployed to %s", computedContractAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            msUSDV2Satellite.initialize.selector,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL
        );

        proxyAddress = _deployProxy("msUSDV2", address(msUSDSatelliteToken), init);
    }
}
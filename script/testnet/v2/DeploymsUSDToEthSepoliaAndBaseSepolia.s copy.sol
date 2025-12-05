// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Script.sol";
import {DeploymentUtility} from "../../utils/DeploymentUtility.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDV2Satellite} from "../../../src/v2/msUSDV2Satellite.sol";
import {msUSDV2Sonic} from "../../../src/v2/msUSDV2Sonic.sol";
import "../../../test/utils/Constants.sol";

/** 
    @dev Architecture:
    ETH Sepolia: Main Chain
    Base Sepolia: Legacy Chain (Mocks Sonic deployment)
    Other: Satellite

    @dev To run: 
    forge script script/testnet/v2/DeploymsUSDToEthSepoliaAndBaseSepolia.s.sol:DeploymsUSDToEthSepoliaAndBaseSepolia --broadcast -vvvv

    @dev To verify msUSDV2:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 11155111 \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=11155111" \
        src/v2/msUSDV2.sol:msUSDV2 \
        --constructor-args $(cast abi-encode "constructor(address)" 0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1)

    @dev To verify msUSDV2Sonic:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 84532 \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=84532" \
        src/v2/msUSDV2Sonic.sol:msUSDV2Sonic \
        --constructor-args $(cast abi-encode "constructor(address)" 0x55370E0fBB5f5b8dAeD978BA1c075a499eB107B8)

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

    @dev Deployment 11/26/25
    == Logs ==
        msUSDV2Sonic deployed to 0x31c4313c30d1513735D719CB914c4a4684F7E619
        Empty UUPS implementation contract deployed to 0xc05Fb730FFC1099464118A705aCd2BF5d81844cC
        msUSDV2 proxy deployed to 0x4ba01f22827018b4772CD326C7627FB4956A7C00
        msUSDV2 deployed to 0x37C8820c45683dfBF7011531a517145783DAC1ee
        Empty UUPS implementation contract deployed to 0xc05Fb730FFC1099464118A705aCd2BF5d81844cC
        msUSDV2 proxy deployed to 0x4ba01f22827018b4772CD326C7627FB4956A7C00
*/

/**
 * @title DeploymsUSDToEthSepoliaAndBaseSepolia
 * @notice This script deploys the protocol to various testnet chains.
 * @dev This script was written during the migration of Sonic as the legacy home-chain to Ethereum as the home-chain.
 */
contract DeploymsUSDToEthSepoliaAndBaseSepolia is DeploymentUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint16 chainId;
        bool mainChain;
        bool legacy;
    }

    NetworkData[] internal allChains;

    string constant public NAME = "msUSD"; /// @dev assign
    string constant public SYMBOL = "msUSD"; /// @dev assign

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        _setup("msUSD.testnet.deployment.3"); /// @dev assign

        allChains.push(NetworkData(
            {
                chainName: "Base Sepolia", 
                rpc_url: vm.envString("BASE_SEPOLIA_RPC_URL"), 
                lz_endpoint: BASE_SEPOLIA_LZ_ENDPOINT_V1, 
                chainId: BASE_SEPOLIA_LZ_CHAIN_ID_V1,
                mainChain: false,
                legacy: true
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "Ethereum Sepolia", 
                rpc_url: vm.envString("SEPOLIA_RPC_URL"), 
                lz_endpoint: SEPOLIA_LZ_ENDPOINT_V1, 
                chainId: SEPOLIA_LZ_CHAIN_ID_V1,
                mainChain: true,
                legacy: false
            }
        ));
    }

    function run() public {

        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {

            vm.createSelectFork(allChains[i].rpc_url);
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

            address msUSDTokenAddress;
            if (allChains[i].mainChain) {
                msUSDTokenAddress = _deploymsUSDV2(allChains[i].lz_endpoint);
            }
            else if (allChains[i].legacy) {
                msUSDTokenAddress = _deploymsUSDV2ForLegacy(allChains[i].lz_endpoint);
            }
            else {
                msUSDTokenAddress = _deploymsUSDV2ForSatellite(allChains[i].lz_endpoint);
            }

            msUSDV2 msUSDToken = msUSDV2(msUSDTokenAddress);

            // set trusted remote address on all other chains for each token.
            for (uint256 j; j < len; ++j) {
                if (i != j) {
                    if (
                        !msUSDToken.isTrustedRemote(
                            allChains[j].chainId, abi.encodePacked(msUSDTokenAddress, msUSDTokenAddress)
                        )
                    ) {
                        msUSDToken.setTrustedRemoteAddress(
                            allChains[j].chainId, abi.encodePacked(msUSDTokenAddress)
                        );
                    }
                }
            }

            // mint tokens to deployer
            if (allChains[i].mainChain) {
                msUSDToken.setSupplyLimit(type(uint256).max);
                msUSDToken.setMinter(DEPLOYER_ADDRESS);
                msUSDToken.mint(DEPLOYER_ADDRESS, 1000 ether);
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
            0
        );

        proxyAddress = _deployProxy("msUSDV2", address(msUSDToken), init);
    }

    /**
     * @dev This method is in charge of deploying and upgrading msUSDV2Sonic on the legacy chain.
     * This method will perform the following steps:
     *    - Compute the msUSDV2Sonic implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the msUSDV2Sonic
     *      address computed, it will upgrade that proxy.
     */
    function _deploymsUSDV2ForLegacy(address layerZeroEndpoint) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(msUSDV2Sonic).creationCode);
        address computedContractAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint)))
        );

        msUSDV2Sonic msUSDLegacyToken;

        if (_isDeployed(computedContractAddress)) {
            console.log("msUSDV2Sonic is already deployed to %s", computedContractAddress);
            msUSDLegacyToken = msUSDV2Sonic(computedContractAddress);
        } else {
            msUSDLegacyToken = new msUSDV2Sonic{salt: _SALT}(layerZeroEndpoint);
            assert(computedContractAddress == address(msUSDLegacyToken));
            console.log("msUSDV2Sonic deployed to %s", computedContractAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            msUSDV2Sonic.initialize.selector,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL
        );

        proxyAddress = _deployProxy("msUSDV2", address(msUSDLegacyToken), init);
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
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Script.sol";
import {DeploymentUtility} from "../utils/DeploymentUtility.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {msUSDV2} from "../../src/v2/msUSDV2.sol";
import {StakedmsUSD} from "../../src/v2/StakedmsUSD.sol";
import {StakedmsUSDSatellite} from "../../src/v2/StakedmsUSDSatellite.sol";
import {msYBridger} from "../../src/v2/msYBridger.sol";
import "../../test/utils/Constants.sol";

/** 
    @dev Architecture:
    ETH: Main Chain
    Others: Satellite

    ETH chainId: 1
    Sonic chainId: 146

    @dev To run: 
    forge script script/ethereum/DeployStakedmsUSDCrossChain.s.sol:DeployStakedmsUSDCrossChain --broadcast -vvvv

    @dev To verify StakedmsUSD:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 1 \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
        src/v2/StakedmsUSD.sol:StakedmsUSD

    @dev To verify msYBridger:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 1 \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
        src/v2/msYBridger.sol:msYBridger

    @dev To verify StakedmsUSDSatellite:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id <CHAIN_ID> \
        --verifier custom \
        --watch \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>" \
        src/v2/StakedmsUSDSatellite.sol:StakedmsUSDSatellite

    @dev To verify Proxies:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id <CHAIN_ID> \
        --watch \
        --verifier custom \
        --verifier-url "https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>" \
        lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy

    @dev Deployment 12/4/25
    == Logs ==
        StakedmsUSD deployed to 0x06Ae3906B1683783000AF7d3aFcD7DdE1A9BC789
        Empty UUPS implementation contract deployed to 0x35fd435ddF77A1BBBD5d9Ecf105652C1482DA7e9
        StakedmsUSD proxy deployed to 0x890A5122Aa1dA30fEC4286DE7904Ff808F0bd74A
        msYBridger deployed to 0x413521a9D7A38242DF3c5473C2c865275F2a4D40
        msYBridger proxy deployed to 0x22eB4e61FE4D4e31113979e8b1F4377D46bc98F2
        StakedmsUSDSatellite deployed to 0xC79242EF7aB4ac94928Ab7b3B0c247e30Fa8d9c4
        Empty UUPS implementation contract deployed to 0x35fd435ddF77A1BBBD5d9Ecf105652C1482DA7e9
        StakedmsUSD proxy deployed to 0x890A5122Aa1dA30fEC4286DE7904Ff808F0bd74A
*/

interface IOFTCore {
    function isTrustedRemote(uint16, bytes calldata) external view returns (bool);
    function setTrustedRemoteAddress(uint16, bytes calldata) external;
}

/**
 * @title DeployStakedmsUSDCrossChain
 * @notice This script deploys the StakedmsUSD token to various testnets.
 */
contract DeployStakedmsUSDCrossChain is DeploymentUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        address remoteAddress;
        uint16 chainId;
        bool mainChain;
    }

    NetworkData[] internal allChains; /// @dev assign - push network data

    string constant public NAME = "msY"; /// @dev assign
    string constant public SYMBOL = "msY"; /// @dev assign

    msUSDV2 constant public MSUSD_TOKEN = msUSDV2(0x4ba01f22827018b4772CD326C7627FB4956A7C00); /// @dev assign

    // Manager of rewards
    address internal ADMIN = 0xc72a250EbC623D7AC44766aE318d159CE4a618E8; /// @dev assign

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    mapping(string rpc => uint256 forkId) internal forkIdTracker;

    function setUp() public {
        _setup("msY.mainnet.deployment.1"); /// @dev assign
        // latest msY: "msY.mainnet.deployment.1"

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
                remoteAddress: address(0),
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

            address stakedmsUSDTokenAddress;
            if (allChains[i].mainChain) {
                stakedmsUSDTokenAddress = _deployStakedmsUSD();
                allChains[i].remoteAddress = _deployBridger(allChains[i].lz_endpoint, stakedmsUSDTokenAddress);
            }
            else {
                stakedmsUSDTokenAddress = _deploymsUSDV2ForSatellite(allChains[i].lz_endpoint);
                allChains[i].remoteAddress = stakedmsUSDTokenAddress;
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
     * @dev This method is in charge of deploying and upgrading StakedmsUSD on the home chain.
     * This method will perform the following steps:
     *    - Compute the StakedmsUSD implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the StakedmsUSD
     *      address computed, it will upgrade that proxy.
     */
    function _deployStakedmsUSD() internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(StakedmsUSD).creationCode);
        address computedContractAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode))
        );

        StakedmsUSD vaultToken;

        if (_isDeployed(computedContractAddress)) {
            console.log("StakedmsUSD is already deployed to %s", computedContractAddress);
            vaultToken = StakedmsUSD(computedContractAddress);
        } else {
            vaultToken = new StakedmsUSD{salt: _SALT}();
            assert(computedContractAddress == address(vaultToken));
            console.log("StakedmsUSD deployed to %s", computedContractAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            StakedmsUSD.initialize.selector,
            address(MSUSD_TOKEN),
            ADMIN,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL
        );

        proxyAddress = _deployProxy("StakedmsUSD", address(vaultToken), init);
    }

    /**
     * @dev This method is in charge of deploying and upgrading msYBridger on the home chain.
     * This method will perform the following steps:
     *    - Compute the msYBridger implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the msYBridger
     *      address computed, it will upgrade that proxy.
     */
    function _deployBridger(address layerZeroEndpoint, address oft) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(msYBridger).creationCode);
        address computedContractAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint, oft)))
        );

        msYBridger bridgerContract;

        if (_isDeployed(computedContractAddress)) {
            console.log("msYBridger is already deployed to %s", computedContractAddress);
            bridgerContract = msYBridger(computedContractAddress);
        } else {
            bridgerContract = new msYBridger{salt: _SALT}(layerZeroEndpoint, oft);
            assert(computedContractAddress == address(bridgerContract));
            console.log("msYBridger deployed to %s", computedContractAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            msYBridger.initialize.selector,
            DEPLOYER_ADDRESS
        );

        proxyAddress = _deployProxy("msYBridger", address(bridgerContract), init);
    }

    /**
     * @dev This method is in charge of deploying and upgrading StakedmsUSDSatellite on a satellite chain.
     * This method will perform the following steps:
     *    - Compute the StakedmsUSDSatellite implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the StakedmsUSDSatellite
     *      address computed, it will upgrade that proxy.
     */
    function _deploymsUSDV2ForSatellite(address layerZeroEndpoint) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(StakedmsUSDSatellite).creationCode);
        address computedContractAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint)))
        );

        StakedmsUSDSatellite vaultSatelliteToken;

        if (_isDeployed(computedContractAddress)) {
            console.log("StakedmsUSDSatellite is already deployed to %s", computedContractAddress);
            vaultSatelliteToken = StakedmsUSDSatellite(computedContractAddress);
        } else {
            vaultSatelliteToken = new StakedmsUSDSatellite{salt: _SALT}(layerZeroEndpoint);
            assert(computedContractAddress == address(vaultSatelliteToken));
            console.log("StakedmsUSDSatellite deployed to %s", computedContractAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            StakedmsUSDSatellite.initialize.selector,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL
        );

        proxyAddress = _deployProxy("StakedmsUSD", address(vaultSatelliteToken), init);
    }
}
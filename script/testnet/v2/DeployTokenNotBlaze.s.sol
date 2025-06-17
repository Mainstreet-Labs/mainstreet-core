// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Script.sol";
import {DeploymentUtility} from "../../utils/DeploymentUtility.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDV2Satellite} from "../../../src/v2/msUSDV2Satellite.sol";
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/testnet/v2/DeployTokenNotBlaze.s.sol:DeployTokenNotBlaze --broadcast \
    --verify --verifier-url https://api-sepolia.basescan.org/api -vvvv

    @dev To verify msUSDV2:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 57054 \
        --watch \
        --verifier-url https://api-testnet.sonicscan.org/api \
        src/v2/msUSDV2.sol:msUSDV2 \
        --constructor-args $(cast abi-encode "constructor(address)" 0x83c73Da98cf733B03315aFa8758834b36a195b87)

    @dev To verify msUSDV2Satellite:
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract \
        <CONTRACT_ADDRESS> \
        --chain-id 11155111 \
        --watch \
        --verifier-url https://api-sepolia.etherscan.io/api \
        src/v2/msUSDV2Satellite.sol:msUSDV2Satellite \
        --constructor-args $(cast abi-encode "constructor(address)" 0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1)

    @dev To verify Proxy manually (Etherscan):
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract <CONTRACT_ADDRESS> --chain-id <CHAIN_ID> --watch \
    lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" <EMPTY_UUPS> 0x) --verifier etherscan

    @dev To verify msUSDV2Satellite manually (Etherscan):
    export ETHERSCAN_API_KEY=<API_KEY>
    forge verify-contract <CONTRACT_ADDRESS> --chain-id <CHAIN_ID> --watch \
    src/v2/msUSDV2Satellite.sol:msUSDV2Satellite --constructor-args \
    $(cast abi-encode "constructor(address)" <LZ_ENDPOINT_ADDRESS>) --verifier etherscan

    @dev Deployment
    == Logs ==
        Base Sepolia:
        msUSDV2 deployed to 0x82a19255429d17b9fb2f947E8F71d542CcDF8164
        Empty UUPS implementation contract deployed to 0xc595a90921e4350Dd605B7A5C4928bBBF34370d1
        msUSDV2 proxy deployed to 0x22Fd57e5653D1B7F3f820889ef6F3ea127f9826e
        Ethereum Sepolia:
        msUSDV2Satellite deployed to 0xE865943a7917BD4897576919396e5CdFAC49d6f3
        Empty UUPS implementation contract deployed to 0xc595a90921e4350Dd605B7A5C4928bBBF34370d1
        msUSDV2 proxy deployed to 0x22Fd57e5653D1B7F3f820889ef6F3ea127f9826e
*/

/**
 * @title DeployTokenNotBlaze
 * @notice This script deploys a new instance of the msUSDV2 token to various testent chains
 */
contract DeployTokenNotBlaze is DeploymentUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint16 chainId;
        bool mainChain;
    }

    NetworkData[] internal allChains;

    string constant public NAME = "msUSD"; // TODO
    string constant public SYMBOL = "msUSD"; // TODO

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        _setup("msUSD.testnet.deployment.2"); // TODO

        allChains.push(NetworkData(
            {
                chainName: "Base Sepolia", 
                rpc_url: vm.envString("BASE_SEPOLIA_RPC_URL"), 
                lz_endpoint: BASE_SEPOLIA_LZ_ENDPOINT_V1, 
                chainId: BASE_SEPOLIA_LZ_CHAIN_ID_V1,
                mainChain: true
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "Ethereum Sepolia", 
                rpc_url: vm.envString("SEPOLIA_RPC_URL"), 
                lz_endpoint: SEPOLIA_LZ_ENDPOINT_V1, 
                chainId: SEPOLIA_LZ_CHAIN_ID_V1,
                mainChain: false
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
            SYMBOL
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
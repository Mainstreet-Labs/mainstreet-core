// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Utils, ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EmptyUUPS} from "./EmptyUUPS.sol";

/**
 * @title DeploymentUtility
 */
abstract contract DeploymentUtility is Script {
    /// @notice Slot for the proxy's implementation address, based on EIP-1967.
    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    /// @notice Salt used for generating CREATE2 addresses.
    bytes32 internal _SALT;
    /// @notice Address of the deployer.
    address internal _deployer;
    /// @dev Private key used for broadcasting.
    uint256 internal _pk;
    /// @dev Address for the initial EmptyUUPS implementation.
    address private _emptyUUPS;

    function _setup(bytes memory _salt) public {
        _loadPrivateKey();
        _SALT = keccak256(bytes.concat(_salt, "-2025"));
    }

    /// @dev Loads private key from env.DEPLOYER_PRIVATE_KEY
    function _loadPrivateKey() internal {
        _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployer = vm.addr(_pk);
    }
    
    /// @dev Ensures the deployment of the EmptyUUPS contract.
    function _ensureEmptyUUPSIsDeployed() internal {
        _emptyUUPS = vm.computeCreate2Address(
            _SALT,
            hashInitCode(type(EmptyUUPS).creationCode, abi.encode(_deployer))
        );

        if (!_isDeployed(_emptyUUPS)) {
            assert(address(new EmptyUUPS{salt: _SALT}(_deployer)) == _emptyUUPS);
            console.log("Empty UUPS implementation contract deployed to %s", _emptyUUPS);
        }
    }

    /// @dev Computes the address and salt for a proxy corresponding to a specific contract. This is essential for
    ///      deploying or upgrading proxies in a deterministic manner.
    function _computeProxyAddress(string memory forContract) internal view returns (address proxyAddress, bytes32 salt) {
        proxyAddress = vm.computeCreate2Address(
            keccak256(abi.encodePacked(_SALT, forContract)),
            hashInitCode(type(ERC1967Proxy).creationCode, abi.encode(_emptyUUPS, ""))
        );
    }

    /// @dev Deploys or upgrades a UUPS proxy for a specified contract with a given implementation and initialization
    ///      data.
    function _deployProxy(string memory forContract, address implementation, bytes memory data) internal returns (address proxyAddress) {
        _ensureEmptyUUPSIsDeployed();

        bytes32 salt;
        (proxyAddress, salt) = _computeProxyAddress(forContract);

        if (_isDeployed(proxyAddress)) {
            ERC1967Proxy proxy = ERC1967Proxy(payable(proxyAddress));
            address _implementation = address(uint160(uint256(vm.load(address(proxy), PROXY_IMPLEMENTATION_SLOT))));
            if (_implementation != implementation) {
                UUPSUpgradeable(address(proxy)).upgradeToAndCall(implementation, "");
                console.log("%s proxy at %s has been upgraded", forContract, proxyAddress);
            } else {
                console.log("%s proxy at %s remains unchanged", forContract, proxyAddress);
            }
        } else {
            ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(_emptyUUPS, "");
            assert(proxyAddress == address(proxy));
            UUPSUpgradeable(address(proxy)).upgradeToAndCall(implementation, data);
            console.log("%s proxy deployed to %s", forContract, proxyAddress);
        }
    }

    /// @dev Checks whether a contract is deployed at a given address.
    function _isDeployed(address contractAddress) internal view returns (bool isDeployed) {
        // slither-disable-next-line assembly
        assembly {
            let cs := extcodesize(contractAddress)
            if iszero(iszero(cs)) { isDeployed := true }
        }
    }
}

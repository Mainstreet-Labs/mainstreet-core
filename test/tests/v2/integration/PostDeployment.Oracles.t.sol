// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MainstreetMinter} from "../../../../src/MainstreetMinter.sol";
import {msUSDV2} from "../../../../src/v2/msUSDV2.sol";
import {StakedmsUSD} from "../../../../src/v2/StakedmsUSD.sol";
import {FeeSilo} from "../../../../src/FeeSilo.sol";
import {msUSDSilo} from "../../../../src/v2/msUSDSilo.sol";
import {CustodianManager} from "../../../../src/CustodianManager.sol";
import {smsUSDOracle} from "../../../../src/oracles/smsUSDOracle.sol";
import {StaticPriceOracleChainlink} from "../../../../src/oracles/StaticPriceOracleChainlink.sol";
import {ImsUSDV2} from "../../../../src/interfaces/ImsUSDV2.sol";
import {Actors} from "../../../utils/Actors.sol";
import "../../../utils/Constants.sol";

contract PostDeploymentOraclesTest is Actors {
    msUSDV2 internal constant msUSDToken = msUSDV2(0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D);
    MainstreetMinter internal constant msMinter = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D);
    StakedmsUSD internal constant smsUSD = StakedmsUSD(0xc7990369DA608C2F4903715E3bD22f2970536C29);
    msUSDSilo internal constant silo = msUSDSilo(0xecC73952d38E98D37Cb0151615dFDB73af65FF6c);
    // FeeSilo internal constant constantfeeSilo = FeeSilo(); /// @dev Not deployed
    CustodianManager internal constant custodian = CustodianManager(0x57A4082E43DeD720e93838d34C0a6acd43AdA7e0);
    smsUSDOracle internal stakedmsUSDOracle;
    StaticPriceOracleChainlink internal msUSDStaticOracle;

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 33454592);
        _createAddresses();

        // ~ Deploy Contracts ~

        // Deploy msUSDV2 static oracle
        msUSDStaticOracle = new StaticPriceOracleChainlink(1e8, 8, "msUSD Static Price Oracle", 1);

        // Deploy smsUSD Oracle
        stakedmsUSDOracle = new smsUSDOracle(address(smsUSD), address(msUSDStaticOracle));

        vm.stopPrank();

        vm.label(address(msUSDStaticOracle), "msUSD Static Price Oracle");
        vm.label(address(stakedmsUSDOracle), "Staked msUSD Oracle");
    }

    function testmsUSDStaticOracleReturnsCorrectPrice() public {
        (uint80 roundId,int256 answer,uint256 startedAt,uint256 updatedAt,uint80 answeredInRound)
            = msUSDStaticOracle.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 1e8);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testStakedmsUSDOracleReturnsCorrectPrice() public {
        uint256 vaultBalance = msUSDToken.balanceOf(address(smsUSD));
        (uint80 roundId,int256 answer,uint256 startedAt,uint256 updatedAt,uint80 answeredInRound)
            = stakedmsUSDOracle.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 1e8);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
        
        // Increase price by 20%
        deal(address(msUSDToken), address(smsUSD), vaultBalance + (vaultBalance*20/100));
        (roundId,answer,startedAt,updatedAt,answeredInRound) = stakedmsUSDOracle.latestRoundData();

        assertEq(roundId, 1);
        assertApproxEqAbs(answer, 1.2e8, 1);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);

        // Double price
        deal(address(msUSDToken), address(smsUSD), vaultBalance*2);
        (roundId,answer,startedAt,updatedAt,answeredInRound) = stakedmsUSDOracle.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 2e8);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }
}

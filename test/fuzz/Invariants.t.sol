// SPDX-License-Identifier: MIT

// Have our invariant aka (also known as) properties

// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view funtions should never revert <- evergreen invariant

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        // don't call redeemCollateral, unless there is collateral to redeem!
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(weth, totalBtcDeposited);
        console.log("Total Supply: ", totalSupply);
        console.log("Weth Value: ", wethValue);
        console.log("Wbtc Value: ", wbtcValue);
        console.log("Times mint is called: ", handler.timeMintIsCalled());
        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public {
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getCollateralTokens();
        dsce.getCollateralTokenPriceFeed(weth);
        dsce.getCollateralTokenPriceFeed(wbtc);
        dsce.getCollateralBalanceOfUser(weth, address(this));
        dsce.getCollateralBalanceOfUser(wbtc, address(this));
        dsce.getUsdValue(weth, 1);
        dsce.getUsdValue(wbtc, 1);
        dsce.getTokenAmountFromUsd(weth, 1);
        dsce.getTokenAmountFromUsd(wbtc, 1);
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getLiquidationPrecision();
        dsce.getHealthFactor(address(this));
        dsce.getLiquidationBonus();
        dsce.getDsc();
        dsce.getAdditionalFeedPrecision();
        dsce.getAccountInfo(address(this));
        dsce.getAccountCollateralValue(address(this));
    }
}

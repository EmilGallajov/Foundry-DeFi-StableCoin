/*
=>Layout of Contract:
-version
-imports
-errors
-interfaces, libraries, contracts
-Type declarations
-State variables
-Events
-Modifiers
-Functions

=>Layout of Functions:
-constructor
-receive function (if exists)
-fallback function (if exists)
-external
-public
-internal
-private
-view & pure functions
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author Emil Gallajov
 *
 * This system is designed to be as minimal as possible, and have the tokens maintain a
 * 1 token == 1$ peg.
 *
 * This stablecoin has below mentioned properties:
 * - Exogenous Colleteral
 * - Dollar Pegged
 * - Algoritmically Stable
 *
 * It looks like to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC.
 *
 * Our DSC system should always be "overcolletarelized". At no point, should the value
 * of all collateral <= the $ backed value of all the DSC
 *
 * @notice This contract is the core of the DSC System, It handles all the logic for mining and
 * redeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) System.
 */

contract DSCEngine is DecentralizedStableCoin, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__ShouldBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__UnsuccessfulTransfer();
    error DSCEngine__BrokesHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproves();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;
    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_colleteralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;
    uint256 private ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private PRECISION = 1e18;
    uint256 private LIQUIDATION_THRESHOLD = 50;
    uint256 private LIQUIDATION_PRECISION = 100;
    uint256 private MIN_HEALTH_FACTOR = 1e18;
    uint256 private LIQUIDATION_BONUS = 10; // this is a liquidation bonus

    DecentralizedStableCoin private immutable i_dsc;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__ShouldBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddresses) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // ETH / USD, BTC / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddresses);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress => The address of the token to deposit as collateral
     * @param amountCollateral => The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_colleteralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__UnsuccessfulTransfer();
        }
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, amountCollateral, tokenCollateralAddress, msg.sender);
        _revertIfHealtFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountToMintDsc = The amount of the decentralized stablecoin to mint
     * @notice they must have more collateral value more than the threshold
     */
    function mintDsc(uint256 amountToMintDsc) public moreThanZero(amountToMintDsc) nonReentrant {
        s_dscMinted[msg.sender] += amountToMintDsc;
        // if they minted too much (150$ DSC, 100$ ETH collateral)
        _revertIfHealtFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountToMintDsc);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @param tokenCollateralAddress => the address of the token deposit as a collateral
     * @param amountCollateral => the amount of the collateral for depositing
     * @param amountToMintDsc => the amount of the DSC which will be used for minting
     * @notice This function is used for depositing and minting DSC in one transaction.
     */
    function depositColletarelAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountToMintDsc
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountToMintDsc);
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealtFactorIsBroken(msg.sender);
    }

    // If we do start nearing undercollateralization, we need someone to liquidate positions

    // 100$ ETH backing 50$ DSC
    // 20$ ETH back 50$ DSC <- DSC isn't worth it!!!

    // 75$ backing 50$ DSC
    // Liquidator take 75$ backing and burns off the 50$ DSC

    // If someone is almost undercollateralized, we'll pay you to liquidate them!

    /**
     * @param collateral => The erc20 collateral to liquidate
     * @param user => The user who has broken health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover => The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate the user
     * @notice You will get a liquidation bonus for taking users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollaterlaized in order for this work.
     * @notice A known bug would if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     * @notice Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // we want to burn their DSC "debt" and take their collateral
        uint256 getTokenAmountDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (getTokenAmountDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 tokenCollateralToRedeem = getTokenAmountDebtCovered + bonusCollateral;

        _redeemCollateral(user, tokenCollateralToRedeem, collateral, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproves();
        }
        _revertIfHealtFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /*//////////////////////////////////////////////////////////////
                    PRIVATE & INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_colleteralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__UnsuccessfulTransfer();
        }
    }
    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking health factors being broken
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom)
        private
        moreThanZero(amountDscToBurn)
    {
        s_dscMinted[msg.sender] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);

        if (!success) {
            revert DSCEngine__UnsuccessfulTransfer();
        }
        _revertIfHealtFactorIsBroken(msg.sender);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 colleteralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        colleteralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        view
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * check health factor (do they have enough collateral?)
     * if they don't, revert it
     */
    function _revertIfHealtFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokesHealthFactor(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    PUBLIC & EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        view
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalColletarelValueInUsd) {
        // loop through all the token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_colleteralDeposited[user][token];
            totalColletarelValueInUsd += getUsdValue(token, amount);
        }
        return totalColletarelValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * 1 ETH = 2000$, 0.5 ETH = 1000$;
     * price = 1 ETH (2000$)
     * usdAmountInWei = 0.5$ (1000$)
     * usdAmountInWei / price => 1000$ / 2000$ = 0.5 ETH
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInfo(address user) public view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(msg.sender);
    }

    function getPrecision() external view returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external view returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external view returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_colleteralDeposited[user][token];
    }

    function getLiquidationBonus() external view returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external view returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external view returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}

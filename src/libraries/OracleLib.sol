// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Emil Gallajov
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale (old), the function will revert, and render the DSCEngine unusable - this is by desing.
 * We want the DSCEngine to freeze if price is stale.
 *
 * If the Chainlink network explodes and you have a lot of money locked in the protocol.
 *
 */
library OracleLib {
    error OracleLib__StablePrice();

    uint256 private constant TIMEOUT = 3 hours; //10k seconds

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) {
            revert OracleLib__StablePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

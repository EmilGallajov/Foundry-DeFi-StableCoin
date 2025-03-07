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

import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Emil Gallajov
 * @notice This is Decentralized Stable Coin
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algoritmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20
 * implementration of our stablecoin system.
 *
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BalanceShouldBeMoreThanAmount();
    error DecentralizedStableCoin__CannotSendAddressZero();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStableCoin__BalanceShouldBeMoreThanAmount();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__CannotSendAddressZero();
        }

        if (_amount < 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}

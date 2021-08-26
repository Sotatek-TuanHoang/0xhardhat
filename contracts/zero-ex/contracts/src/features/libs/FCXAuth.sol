// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

/**
 * @dev fcx user manager
 */
interface IWhiteList {
    function whitelisted(address account) external view returns (bool);
}

contract FCXAuth {
    modifier _roles_(address _whitelist) {
        bool canAccess = IWhiteList(_whitelist).whitelisted(msg.sender);
        require(canAccess, "FCXAccessControl: sender requires permission");
        _;
    }
}

// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "@0x/contracts-erc20/contracts/src/v06/IERC20TokenV06.sol";
import "../libs/LibSignature.sol";
import "../libs/LibNativeOrder.sol";


/// @dev Feature for interacting with limit orders.
interface ILimitOrderFeature
{
  event LockedBalanceOrder(
    bytes32 indexed orderHash,
    IERC20TokenV06 makerToken,  
    IERC20TokenV06 takerToken,
    address indexed makerAddress,         // Address that created the order.
    address takerAddress,                 // Address that filled the order.
    address matchOrderAddress
  );

  event TransferDone(
    address maker,
    address matchOrderAddress
  );

  event LimitOrderCancelled(
      bytes32 orderHash,
      uint256 orderLocked
  );

  function createLimitOrder(
      LibNativeOrder.LimitOrder calldata order,
      LibSignature.Signature calldata signature
  )
  external returns (LibNativeOrder.OrderInfo memory orderInfo);
  
  function cancelLimitOrderWithHash(bytes32 orderHash, IERC20TokenV06 token, address maker) external;
  function getOrderLocked(bytes32 orderHash) external view returns(uint256);
  function getFilledOrder(bytes32 orderHash) external view returns(uint256);


  // function setRoles(uint256[] memory _roles) external;
  // function getCurrentRoles() external view returns (uint256[] memory);
  // function getCurrentRolesV2() external view returns (uint256[] memory);
  // function getCurrentRolesV3() external returns (uint256[] memory);
  // function getCurrentRolesV4() external view returns (bool);
  // function everyBodyCanCall() external pure returns (string memory);
  function getWhitelist() external view returns (address);
  function setWhitelist(address _whitelist) external;
}

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
interface IMatchOrdersFeature
{
  event Fill(
      bytes32 indexed orderHash,
      uint256 makerAmountFinal,       
      uint256 takerAmountFinal,       
      uint256 feePaid
  );

  event TransferMatchDone(
    uint256 stt,
    address from,
    address to,
    uint256 amount
  );

  function matchOrders(
      LibNativeOrder.LimitOrder calldata leftOrder,
      LibNativeOrder.LimitOrder calldata rightOrder,
      LibSignature.Signature calldata leftSignature,
      LibSignature.Signature calldata rightSignature,
      uint256 price,
      uint8 sellType,
      uint8 buyType
  )
      external
      payable
      returns (LibNativeOrder.MatchedFillResults memory matchedFillResults);


  function getOrderHashInfo(
        bytes32 orderHash
    )
        external
        view
        returns (uint256 filled, uint256 feeLock, uint256 locked);

  function getMatchOrderResult(
        LibNativeOrder.LimitOrder calldata sellOrder,
        LibNativeOrder.LimitOrder calldata buyOrder,
        uint256 price,
        uint8 sellType,
        uint8 buyType
    )
        external
        view
      returns (LibNativeOrder.MatchedFillResults memory matchedFillResults);

  function setDecimalPrice(uint256 _decimal) external;
  function getDecimalPrice() view external returns (uint256);
  function compare(uint8 typeOrder) view external returns (uint256 sellRemaining);

  function getOrderInfo(LibNativeOrder.LimitOrder memory order, uint128 amount)
    external
    view
    returns (LibNativeOrder.OrderInfo memory orderInfo);
}

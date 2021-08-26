/*

  Copyright 2019 ZeroEx Intl.

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

import "./libs/LibRichErrors.sol";
import "./libs/LibExchangeRichErrors.sol";
import "./libs/LibNativeOrder.sol";
import "./libs/LibSignature.sol";
import "./native_orders/NativeOrdersInfo.sol";
import "@0x/contracts-utils/contracts/src/v06/LibMathV06.sol";
import "../fixins/FixinTokenSpender.sol";
import "../fixins/FixinCommon.sol";
import "../migrations/LibMigrate.sol";
import "@0x/contracts-utils/contracts/src/v06/LibBytesV06.sol";
import "@0x/contracts-utils/contracts/src/v06/LibSafeMathV06.sol";
import "@0x/contracts-erc20/contracts/src/v06/IERC20TokenV06.sol";
import "./interfaces/IMatchOrdersFeature.sol";
import "./interfaces/IFeature.sol";

contract MatchOrdersFeature is
    IFeature,
    IMatchOrdersFeature,
    FixinCommon,
    FixinTokenSpender,
    NativeOrdersInfo
{
    using LibBytesV06 for bytes;
    using LibSafeMathV06 for uint256;
    using LibSafeMathV06 for uint128;

    string public constant override FEATURE_NAME = "MatchOrders";
    /// @dev Version of this feature.
    uint256 public immutable override FEATURE_VERSION = _encodeVersion(1, 1, 1);

    constructor(address zeroExAddress)
        public
        FixinCommon()
        NativeOrdersInfo(zeroExAddress)
    {
        // solhint-disable-next-line no-empty-blocks
    }

    function matchOrders(
        LibNativeOrder.LimitOrder calldata sellOrder,
        LibNativeOrder.LimitOrder calldata buyOrder,
        LibSignature.Signature calldata sellSignature,
        LibSignature.Signature calldata buySignature,
        uint256 price,
        uint8 sellType,
        uint8 buyType
    )
        external
        onlyOwner
        override
        payable
        // refundFinalBalanceNoReentry
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        return _matchOrders(
            sellOrder,
            buyOrder,
            sellSignature,
            buySignature,
            price,
            sellType,
            buyType
        );
    }
    /// @dev Validates context for matchOrders. Succeeds or throws.
    /// @param sellOrder First order to match.
    /// @param buyOrder Second order to match.
    /// @param sellOrderHash First matched order hash.
    /// @param buyOrderHash Second matched order hash.
    function _assertValidMatch(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        bytes32 sellOrderHash,
        bytes32 buyOrderHash
    )
        internal
        pure
    {
        // Make sure there is a profitable spread.
        // There is a profitable spread iff the cost per unit bought (OrderA.MakerAmount/OrderA.TakerAmount) for each order is greater
        // than the profit per unit sold of the matched order (OrderB.TakerAmount/OrderB.MakerAmount).
        // This is satisfied by the equations below:
        // <sellOrder.makerAssetAmount> / <sellOrder.takerAssetAmount> >= <buyOrder.takerAssetAmount> / <buyOrder.makerAssetAmount>
        // AND
        // <buyOrder.makerAssetAmount> / <buyOrder.takerAssetAmount> >= <sellOrder.takerAssetAmount> / <sellOrder.makerAssetAmount>
        // These equations can be combined to get the following:
        if (sellOrder.makerAmount.safeMul(buyOrder.makerAmount) <
            sellOrder.takerAmount.safeMul(buyOrder.takerAmount)) {
            LibRichErrors.rrevert(LibExchangeRichErrors.NegativeSpreadError(
                sellOrderHash,
                buyOrderHash
            ));
        }
    }

    /// @dev Match two complementary orders that have a profitable spread.
    ///      Each order is filled at their respective price point. However, the calculations are
    ///      carried out as though the orders are both being filled at the buy order's price point.
    ///      The profit made by the sell order goes to the taker (who matched the two orders). This
    ///      function is needed to allow for reentrant order matching (used by `batchMatchOrders` and
    ///      `batchMatchOrdersWithMaximalFill`).
    /// @param sellOrder First order to match.
    /// @param buyOrder Second order to match.
    /// @param sellSignature Proof that order was created by the sell maker.
    /// @param buySignature Proof that order was created by the buy maker.
    /// @return matchedFillResults Amounts filled and fees paid by maker and taker of matched orders.
    function _matchOrders(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        LibSignature.Signature memory sellSignature,
        LibSignature.Signature memory buySignature,
        uint256 price,
        uint8 sellType,
        uint8 buyType
    )
        private
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // We assume that buyOrder.takerAssetData == sellOrder.makerAssetData and buyOrder.makerAssetData == sellOrder.takerAssetData
        // by pointing these values to the same location in memory. This is cheaper than checking equality.
        // If this assumption isn't true, the match will fail at signature validation.
        buyOrder.makerToken = sellOrder.takerToken;
        buyOrder.takerToken = sellOrder.makerToken;

        // Get sell & buy order info
        uint128 amountSellByType = sellType == LibNativeOrder.MATCH_AMOUNT ? sellOrder.makerAmount : sellOrder.takerAmount;
        uint128 amountBuyByType = buyType == LibNativeOrder.MATCH_AMOUNT ? buyOrder.takerAmount : buyOrder.makerAmount;
        LibNativeOrder.OrderInfo memory sellOrderInfo = getOrderInfo(sellOrder, amountSellByType);
        LibNativeOrder.OrderInfo memory buyOrderInfo = getOrderInfo(buyOrder, amountBuyByType);

        // Either our context is valid or we revert
        _assertFillableOrder(
            sellOrder,
            sellOrderInfo,
            msg.sender,
            sellSignature
        );
        _assertFillableOrder(
            buyOrder,
            buyOrderInfo,
            msg.sender,
            buySignature
        );

        LibNativeOrder.MatchOrderInfoPlus memory matchInfo;

        matchInfo.sellOrderFilledAmount = sellOrderInfo.makerTokenFilledAmount;
        matchInfo.buyOrderFilledAmount = buyOrderInfo.makerTokenFilledAmount;
        matchInfo.price = price;
        matchInfo.sellOrderHash = sellOrderInfo.orderHash;
        matchInfo.buyOrderHash = buyOrderInfo.orderHash;
        matchInfo.sellType = sellType;
        matchInfo.buyType = buyType;
        // Compute proportional fill amounts
        matchedFillResults = calculateMatchedFillResults(
            sellOrder,
            buyOrder,
            matchInfo
        );

        // Settle matched orders. Succeeds or throws.
        {
            _settleMatchedOrders(
                sellOrderInfo.orderHash,
                buyOrderInfo.orderHash,
                sellOrder,
                buyOrder,
                msg.sender,
                matchedFillResults
            );
        }


        {
            uint256 recentAmountSell = sellType == LibNativeOrder.MATCH_AMOUNT ? matchedFillResults.makerAmountFinal : matchedFillResults.takerAmountFinal;
            uint256 recentAmountBuy = buyType == LibNativeOrder.MATCH_AMOUNT ? matchedFillResults.makerAmountFinal : matchedFillResults.takerAmountFinal;

            // Update exchange state
            _updateFilledState(
                sellOrderInfo.orderHash,
                matchedFillResults.makerAmountFinal,
                matchedFillResults.takerAmountFinal,
                matchedFillResults.makerAmountFinal,
                matchedFillResults.sellFeePaid,
                matchedFillResults.returnSellAmount,
                recentAmountSell
            );

            _updateFilledState(
                buyOrderInfo.orderHash,
                matchedFillResults.makerAmountFinal,
                matchedFillResults.takerAmountFinal,
                matchedFillResults.takerAmountFinal,
                matchedFillResults.buyFeePaid,
                matchedFillResults.returnBuyAmount,
                recentAmountBuy
            );
        }

        return matchedFillResults;
    }

    function getMatchOrderResult(
        LibNativeOrder.LimitOrder calldata sellOrder,
        LibNativeOrder.LimitOrder calldata buyOrder,
        uint256 price,
        uint8 sellType,
        uint8 buyType
    )
        public
        override
        view
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // Get sell & buy order info
        uint128 amountSellByType = sellType == LibNativeOrder.MATCH_AMOUNT ? sellOrder.makerAmount : sellOrder.takerAmount;
        uint128 amountBuyByType = buyType == LibNativeOrder.MATCH_AMOUNT ? buyOrder.takerAmount : buyOrder.makerAmount;
        LibNativeOrder.OrderInfo memory sellOrderInfo = getOrderInfo(sellOrder, amountSellByType);
        LibNativeOrder.OrderInfo memory buyOrderInfo = getOrderInfo(buyOrder, amountBuyByType);

        LibNativeOrder.MatchOrderInfoPlus memory matchInfo;
        matchInfo.sellOrderFilledAmount = sellOrderInfo.makerTokenFilledAmount;
        matchInfo.buyOrderFilledAmount = buyOrderInfo.makerTokenFilledAmount;
        matchInfo.price = price;
        matchInfo.sellOrderHash = sellOrderInfo.orderHash;
        matchInfo.buyOrderHash = buyOrderInfo.orderHash;
        matchInfo.sellType = sellType;
        matchInfo.buyType = buyType;

        // Compute proportional fill amounts
        matchedFillResults = calculateMatchedFillResults(
            sellOrder,
            buyOrder,
            matchInfo
        );
    }

    function getOrderHashInfo(bytes32 orderHash) public override view returns (uint256 filled, uint256 feeLock, uint256 locked) {
        filled = LibNativeOrdersStorage
        .getStorage()
        .orderHashToFilledAmount[orderHash];

        feeLock = LibNativeOrdersStorage
        .getStorage()
        .orderHashToFeeAmountRemaining[orderHash];

        locked = LibNativeOrdersStorage
        .getStorage()
        .orderLocked[orderHash];
    }

    function getOrderInfo(LibNativeOrder.LimitOrder memory order, uint128 amount)
    public
    override
    view
    returns (LibNativeOrder.OrderInfo memory orderInfo)
    {
        // Compute the order hash and fetch the amount of takerAsset that has already been filled
        LibNativeOrder.OrderInfo memory orderInfo = getLimitOrderInfoV2(order, amount);

        // If order.makerAssetAmount is zero, we also reject the order.
        // While the Exchange contract handles them correctly, they create
        // edge cases in the supporting infrastructure because they have
        // an 'infinite' price when computed by a simple division.
        if (order.makerAmount == 0) {
            orderInfo.status = LibNativeOrder.OrderStatus.INVALID;
            return orderInfo;
        }

        // If order.takerAssetAmount is zero, then the order will always
        // be considered filled because 0 == takerAssetAmount == orderTakerAssetFilledAmount
        // Instead of distinguishing between unfilled and filled zero taker
        // amount orders, we choose not to support them.
        if (order.takerAmount == 0) {
            orderInfo.status = LibNativeOrder.OrderStatus.INVALID;
            return orderInfo;
        }

        return orderInfo;
    }


    function _assertFillableOrder(
        LibNativeOrder.LimitOrder memory order,
        LibNativeOrder.OrderInfo memory orderInfo,
        address takerAddress,
        LibSignature.Signature memory signature
    )
    internal
    view
    {

        uint256 hasLocked = LibNativeOrdersStorage.getStorage().orderLocked[orderInfo.orderHash];
        if (hasLocked == 0) {
            LibRichErrors.rrevert(LibExchangeRichErrors.OrderStatusError(
                orderInfo.orderHash,
                LibNativeOrder.OrderStatus(LibNativeOrder.OrderStatus.INVALID)
            ));
        }

        // An order can only be filled if its status is FILLABLE.
        if (orderInfo.status != LibNativeOrder.OrderStatus.FILLABLE) {
            LibRichErrors.rrevert(LibExchangeRichErrors.OrderStatusError(
                    orderInfo.orderHash,
                    LibNativeOrder.OrderStatus(orderInfo.status)
                ));
        }
        // Validate sender is allowed to fill this order
        if (order.sender != address(0)) {
            if (order.sender != msg.sender) {
                LibRichErrors.rrevert(LibExchangeRichErrors.ExchangeInvalidContextError(
                    LibExchangeRichErrors.ExchangeContextErrorCodes.INVALID_SENDER,
                    orderInfo.orderHash,
                    msg.sender
                ));
            }
        }

        // Validate taker is allowed to fill this order
        if (order.taker != address(0)) {
            if (order.taker != takerAddress) {
                LibRichErrors.rrevert(LibExchangeRichErrors.ExchangeInvalidContextError(
                    LibExchangeRichErrors.ExchangeContextErrorCodes.INVALID_TAKER,
                    orderInfo.orderHash,
                    takerAddress
                ));
            }
        }

        // Signature must be valid for the order.
        {
            address signer = LibSignature.getSignerOfHash(
                orderInfo.orderHash,
                signature
            );
            if (signer != order.maker) {
                LibRichErrors.rrevert(LibExchangeRichErrors.SignatureError(
                    LibExchangeRichErrors.SignatureErrorCodes.BAD_ORDER_SIGNATURE,
                    orderInfo.orderHash
                ));
            }
        }
    }

    function calculateMatchedFillResults(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        LibNativeOrder.MatchOrderInfoPlus memory matchInfo
    )
    internal
    view
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        uint256 decimal = LibNativeOrdersStorage.getStorage().decimalPrice;
        // Derive maker asset amounts for sell & buy orders, given store taker assert amounts
        uint256 sellRemaining = matchInfo.sellType == LibNativeOrder.MATCH_AMOUNT 
            ? sellOrder.makerAmount.safeSub(matchInfo.sellOrderFilledAmount)
            : sellOrder.takerAmount.safeSub(matchInfo.sellOrderFilledAmount);
        uint256 buyRemaining = matchInfo.buyType == LibNativeOrder.MATCH_AMOUNT
            ? buyOrder.takerAmount.safeSub(matchInfo.buyOrderFilledAmount)
            : buyOrder.makerAmount.safeSub(matchInfo.buyOrderFilledAmount);

        uint256 sellAmountRemaining = matchInfo.sellType == LibNativeOrder.MATCH_AMOUNT ? sellRemaining : 
            sellRemaining.safeMul(decimal).safeDiv(matchInfo.price);

        uint256 buyAmountRemaining = matchInfo.buyType == LibNativeOrder.MATCH_AMOUNT ? buyRemaining : 
            buyRemaining.safeMul(decimal).safeDiv(matchInfo.price);

        if (sellAmountRemaining == buyAmountRemaining) {
            matchedFillResults.makerAmountFinal = sellAmountRemaining;
            matchedFillResults.takerAmountFinal = sellAmountRemaining.safeMul(matchInfo.price).safeDiv(decimal);
            //fee
            matchedFillResults.sellFeePaid = LibNativeOrdersStorage.getStorage().orderHashToFeeAmountRemaining[matchInfo.sellOrderHash];
            matchedFillResults.buyFeePaid = LibNativeOrdersStorage.getStorage().orderHashToFeeAmountRemaining[matchInfo.buyOrderHash];

        } else if (sellAmountRemaining > buyAmountRemaining) {
            matchedFillResults.makerAmountFinal = buyAmountRemaining;
            matchedFillResults.takerAmountFinal = buyAmountRemaining.safeMul(matchInfo.price).safeDiv(decimal);
            // fee
            matchedFillResults.sellFeePaid = getFeeMatch(
                sellRemaining,
                sellAmountRemaining,
                matchInfo.sellType,
                sellOrder.takerTokenFeeAmount,
                matchedFillResults.makerAmountFinal,
                matchedFillResults.takerAmountFinal
            );
            matchedFillResults.buyFeePaid = LibNativeOrdersStorage.getStorage().orderHashToFeeAmountRemaining[matchInfo.buyOrderHash];

        } else {
            // sell order will full filled.
            matchedFillResults.makerAmountFinal = sellAmountRemaining;
            matchedFillResults.takerAmountFinal = sellAmountRemaining.safeMul(matchInfo.price).safeDiv(decimal);
            //fee
            matchedFillResults.sellFeePaid = LibNativeOrdersStorage.getStorage().orderHashToFeeAmountRemaining[matchInfo.sellOrderHash];
            matchedFillResults.buyFeePaid = getFeeMatch(
                buyRemaining,
                buyAmountRemaining,
                matchInfo.buyType,
                buyOrder.takerTokenFeeAmount,
                matchedFillResults.makerAmountFinal,
                matchedFillResults.takerAmountFinal
            );
        }

        if (matchInfo.sellType == LibNativeOrder.MATCH_TOTAL) {
            uint256 makerAmountRemainingSell = sellRemaining
                .safeSub(matchedFillResults.takerAmountFinal)
                .safeMul(sellOrder.makerAmount)
                .safeDiv(sellOrder.takerAmount);
            matchedFillResults.returnSellAmount = sellRemaining.safeMul(sellOrder.makerAmount).safeDiv(sellOrder.takerAmount);
            matchedFillResults.returnSellAmount = matchedFillResults.returnSellAmount.safeSub(matchedFillResults.makerAmountFinal).safeSub(makerAmountRemainingSell);
        }

        if (matchInfo.buyType == LibNativeOrder.MATCH_AMOUNT) {
            uint256 takerAmountRemainingBuy = buyRemaining
                .safeSub(matchedFillResults.makerAmountFinal)
                .safeMul(buyOrder.makerAmount)
                .safeDiv(buyOrder.takerAmount);
            matchedFillResults.returnBuyAmount =
                buyRemaining
                .safeMul(buyOrder.makerAmount)
                .safeDiv(buyOrder.takerAmount)
                .safeSub(matchedFillResults.takerAmountFinal)
                .safeSub(takerAmountRemainingBuy);
        }

        return matchedFillResults;
    }

    function getFeeMatch(
        uint256 remaining,
        uint256 amountRemaining,
        uint256 typeOrder,
        uint256 feeTotal,
        uint256 makerAmountFinal,
        uint256 takerAmountFinal
    )
    internal
    view
    returns (uint256 fee) {
        if (typeOrder == LibNativeOrder.MATCH_AMOUNT) {
            fee = LibMathV06.safeGetPartialAmountFloor(
                makerAmountFinal,
                amountRemaining,
                feeTotal
            );
        } else {
            fee = LibMathV06.safeGetPartialAmountFloor(
                takerAmountFinal,
                remaining,
                feeTotal
            );
        }
    }

    /// @dev Settles matched order by transferring appropriate funds between order makers, taker, and fee recipient.
    /// @param sellOrderHash First matched order hash.
    /// @param buyOrderHash Second matched order hash.
    /// @param sellOrder First matched order.
    /// @param buyOrder Second matched order.
    /// @param senderAddress Address that matched the orders. The taker receives the spread between orders as profit.
    /// @param matchedFillResults Struct holding amounts to transfer between makers, taker, and fee recipients.
    function _settleMatchedOrders(
        bytes32 sellOrderHash,
        bytes32 buyOrderHash,
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        address senderAddress,
        LibNativeOrder.MatchedFillResults memory matchedFillResults
    )
        private
    {
        {
            sendBalanceTo(
                buyOrder.makerToken,
                sellOrder.maker,
                matchedFillResults.takerAmountFinal
            );
        }

        {
            sendBalanceTo(
                sellOrder.makerToken,
                buyOrder.maker,
                matchedFillResults.makerAmountFinal
            );
        }

        {
            //fee for each order
            sendBalanceTo(
                buyOrder.makerToken,
                senderAddress,
                matchedFillResults.buyFeePaid
            );
        }

        {
            sendBalanceTo(
                sellOrder.makerToken,
                senderAddress,
                matchedFillResults.sellFeePaid
            );
        }


        if (matchedFillResults.returnSellAmount > 0) {
            sendBalanceTo(
                sellOrder.makerToken,
                sellOrder.maker,
                matchedFillResults.returnSellAmount
            );
        }

        if (matchedFillResults.returnBuyAmount > 0) {
            sendBalanceTo(
                buyOrder.makerToken,
                buyOrder.maker,
                matchedFillResults.returnBuyAmount
            );
        }

    }

    function _updateFilledState(
        bytes32 orderHash,
        uint256 makerAmountFinal,
        uint256 takerAmountFinal,
        uint256 makerRecentFilledAmount,
        uint256 feePaid,
        uint256 returnAmount,
        uint256 recentAmount
        
    )
    private
    {
        LibNativeOrdersStorage.getStorage().orderHashToFilledAmount[orderHash] = 
            LibNativeOrdersStorage.getStorage()
            .orderHashToFilledAmount[orderHash]
            .safeAdd(recentAmount);

        LibNativeOrdersStorage
        .getStorage()
        .orderHashToFeeAmountRemaining[orderHash] = LibNativeOrdersStorage.getStorage().orderHashToFeeAmountRemaining[orderHash].safeSub(feePaid);

        LibNativeOrdersStorage
        .getStorage()
        .orderLocked[orderHash] = LibNativeOrdersStorage.getStorage().orderLocked[orderHash]
                                                        .safeSub(makerRecentFilledAmount)
                                                        .safeSub(feePaid)
                                                        .safeSub(returnAmount);

        // Update state

        emit Fill(
            orderHash,
            makerAmountFinal,
            takerAmountFinal,
            feePaid
        );
    }

    function setDecimalPrice(uint256 _decimal) override public onlyOwner {
        LibNativeOrdersStorage
        .getStorage()
        .decimalPrice = _decimal;
    }

    function getDecimalPrice() view override public returns (uint256) {
        uint256 decimal = LibNativeOrdersStorage.getStorage().decimalPrice;
        if (decimal == 0) {
            decimal = 10 ** 10;
        }
        // return LibNativeOrdersStorage.getStorage().decimalPrice;
        return decimal;
    }


    function compare(uint8 typeOrder) view override public returns (uint256 sellRemaining) {
        sellRemaining = typeOrder == LibNativeOrder.MATCH_AMOUNT 
            ? 100
            : 200;
    }

    function migrate()
    external
    returns (bytes4 success)
    {
        _registerFeatureFunction(this.matchOrders.selector);
        _registerFeatureFunction(this.getOrderHashInfo.selector);
        _registerFeatureFunction(this.getMatchOrderResult.selector);
        _registerFeatureFunction(this.setDecimalPrice.selector);
        _registerFeatureFunction(this.getDecimalPrice.selector);
        _registerFeatureFunction(this.getOrderInfo.selector);
        _registerFeatureFunction(this.compare.selector);
        return LibMigrate.MIGRATE_SUCCESS;
    }
}


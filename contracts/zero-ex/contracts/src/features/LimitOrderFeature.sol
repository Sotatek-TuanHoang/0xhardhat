pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "./interfaces/ILimitOrderFeature.sol";
import "./libs/FCXAuth.sol";
import "./libs/LibRichErrors.sol";
import "./libs/LibExchangeRichErrors.sol";
import "./libs/LibNativeOrder.sol";
import "./libs/LibSignature.sol";
import "./native_orders/NativeOrdersInfo.sol";
import "../fixins/FixinTokenSpender.sol";
import "../fixins/FixinCommon.sol";
import "../migrations/LibMigrate.sol";
import "@0x/contracts-utils/contracts/src/v06/LibBytesV06.sol";
import "@0x/contracts-utils/contracts/src/v06/LibSafeMathV06.sol";
import "@0x/contracts-erc20/contracts/src/v06/IERC20TokenV06.sol";
import "./interfaces/IFeature.sol";

contract LimitOrderFeature is
    IFeature,
    ILimitOrderFeature,
    FixinCommon,
    FixinTokenSpender,
    NativeOrdersInfo,
    FCXAuth
{
    using LibBytesV06 for bytes;
    using LibSafeMathV06 for uint256;
    using LibSafeMathV06 for uint128;

    string public constant override FEATURE_NAME = "LimitOrders";
    /// @dev Version of this feature.
    uint256 public immutable override FEATURE_VERSION = _encodeVersion(1, 1, 1);

    constructor(address zeroExAddress) 
        public
        FCXAuth()
        FixinCommon()
        NativeOrdersInfo(zeroExAddress)
    {
    }


    function getWhitelist() public view override onlyOwner returns (address) {
        return LibNativeOrdersStorage.getStorage().whitelist;
    }

    function setWhitelist(address _whitelist) onlyOwner public override {
        LibNativeOrdersStorage.getStorage().whitelist = _whitelist;
    }


    function createLimitOrder(
        LibNativeOrder.LimitOrder calldata order,
        LibSignature.Signature calldata signature
    )
    public
    override
    returns (LibNativeOrder.OrderInfo memory orderInfo)
    {    
        address takerAddress = msg.sender;

        orderInfo = getOrderInfo(order);
        // Either our context is valid or we revert
        _assertFillableOrder(
            order,
            orderInfo,
            takerAddress,
            signature
        );

        _transferERC20Tokens(
            order.makerToken,
            order.maker,
            address(this),
            order.makerAmount.safeAdd(order.takerTokenFeeAmount)
        );


        LibNativeOrdersStorage
        .getStorage()
        .orderLocked[orderInfo.orderHash] = order.makerAmount.safeAdd(order.takerTokenFeeAmount);
        
        LibNativeOrdersStorage
        .getStorage()
        .orderHashToFeeAmountRemaining[orderInfo.orderHash] = order.takerTokenFeeAmount;

        emit TransferDone(order.maker, address(this));
        emit LockedBalanceOrder(
            orderInfo.orderHash,
            order.makerToken,
            order.takerToken,
            order.maker,
            order.taker,
            address(this)
        );

        return orderInfo;
    }

    function getOrderLocked(bytes32 orderHash) public view override returns(uint256) {
        return LibNativeOrdersStorage
        .getStorage()
        .orderLocked[orderHash];
    }

    function getFilledOrder(bytes32 orderHash) public view override returns(uint256) {
        return LibNativeOrdersStorage
        .getStorage()
        .orderHashToFilledAmount[orderHash];
    }

    function cancelLimitOrderWithHash(bytes32 orderHash, IERC20TokenV06 token, address maker) onlyOwner public override
    {

        LibNativeOrdersStorage.Storage storage stor = LibNativeOrdersStorage.getStorage();
        sendBalanceTo(
            token,
            maker,
            stor.orderLocked[orderHash]
        );

        stor.orderHashToFilledAmount[orderHash] |= 1 << 255;
        stor.orderLocked[orderHash] = 0;

        emit LimitOrderCancelled(orderHash, stor.orderLocked[orderHash]);
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
        // An order can only be filled if its status is FILLABLE.
        if (orderInfo.status != LibNativeOrder.OrderStatus.FILLABLE) {
            LibRichErrors.rrevert(LibExchangeRichErrors.OrderStatusError(
                    orderInfo.orderHash,
                        LibNativeOrder.OrderStatus(orderInfo.status)
                ));
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


    function getOrderInfo(LibNativeOrder.LimitOrder memory order)
    public
    view
    returns (LibNativeOrder.OrderInfo memory orderInfo)
    {
        // Compute the order hash and fetch the amount of takerAsset that has already been filled
        LibNativeOrder.OrderInfo memory orderInfo = getLimitOrderInfoV2(order, order.makerAmount);

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

    function migrate()
    external
    returns (bytes4 success)
    {
        // _registerFeatureFunction(this.setRoles.selector);
        _registerFeatureFunction(this.createLimitOrder.selector);
        _registerFeatureFunction(this.cancelLimitOrderWithHash.selector);
        _registerFeatureFunction(this.getOrderLocked.selector);
        _registerFeatureFunction(this.getFilledOrder.selector);
        _registerFeatureFunction(this.getWhitelist.selector);
        _registerFeatureFunction(this.setWhitelist.selector);
        return LibMigrate.MIGRATE_SUCCESS;
    }


}

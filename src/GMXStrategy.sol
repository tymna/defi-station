// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Pausable} from "./abstract/Pausable.sol";
import {IGMXStrategy} from "./interfaces/IGMXStrategy.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IExchangeRouter} from "./interfaces/gmx/IExchangeRouter.sol";
import {IBaseOrderUtils} from "./interfaces/gmx/IBaseOrderUtils.sol";
import {IReader} from "./interfaces/gmx/IReader.sol";
import {Order} from "./types/gmx/Order.sol";
import {Position} from "./types/gmx/Position.sol";
import {Price} from "./types/gmx/Price.sol";
import {MarketUtils} from "./types/gmx/MarketUtils.sol";
import {ReaderPositionUtils} from "./types/gmx/ReaderPositionUtils.sol";
import "./libraries/Constants.sol";

contract GMXStrategy is Ownable, Pausable, IGMXStrategy {
    // ---- Errors ---- //
    error GMXStrategy__NotInitialized();
    error GMXStrategy__NotVault();
    error GMXStrategy__NotVaultOrOwner();
    error GMXStrategy__StalePrice();

    // ---- Constants ---- //
    uint256 public constant GMX_EXECUTION_FEE = 0.00006 ether;
    uint256 private constant PRICE_MULTIPLIER = 1e4;
    uint256 private constant CHAINLINK_MULTIPLIER = 1e8;
    uint256 private constant CALLBACK_GAS_LIMIT = 2_000_000;
    uint256 private constant ETH_HEARTBEAT = 3600;
    uint256 private constant USDC_HEARTBEAT = 86400;
    uint256 private constant ACCEPTABLE_PRICE_BPS = 200;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MIN_OUTPUT_SLIPPAGE_BPS = 200;

    IExchangeRouter private constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);
    IReader private constant reader = IReader(READER);

    // ---- Immutables ---- //
    address public immutable i_vault;
    address public immutable i_callback;

    // ---- State ---- //
    bool public s_initialized;

    // ---- Modifiers ---- //
    modifier onlyVault() {
        if (msg.sender != i_vault) revert GMXStrategy__NotVault();
        _;
    }

    modifier onlyVaultOrOwner() {
        if (msg.sender != i_vault && msg.sender != owner()) revert GMXStrategy__NotVaultOrOwner();
        _;
    }

    modifier whenInitialized() {
        if (!s_initialized) revert GMXStrategy__NotInitialized();
        _;
    }

    // ---- Initialization ---- //
    constructor(address _vault, address _callback) {
        _initializeOwner(msg.sender);
        i_vault = _vault;
        i_callback = _callback;
    }

    function initialize(uint256 amount, uint256 sizeDeltaUsd, uint256 acceptablePrice) external payable onlyOwner {
        if (s_initialized) revert AlreadyInitialized();
        s_initialized = true;

        SafeTransferLib.safeTransferFrom(WETH, msg.sender, address(this), amount);

        _createOrder(amount, sizeDeltaUsd, acceptablePrice, msg.value, true, 0);
    }

    // ---- Vault ---- //
    function increasePosition(uint256 amount) external onlyVault whenInitialized whenNotPaused {
        uint256 price = _getChainlinkPrice();
        uint256 sizeDeltaUsd = _getSizeDeltaUsd(price, amount, true);
        uint256 acceptablePrice =
            price * PRICE_MULTIPLIER / CHAINLINK_MULTIPLIER * (BPS_DENOMINATOR - ACCEPTABLE_PRICE_BPS) / BPS_DENOMINATOR;

        _createOrder(amount, sizeDeltaUsd, acceptablePrice, GMX_EXECUTION_FEE, true, 0);
    }

    function decreasePosition(uint256 amount) external onlyVaultOrOwner whenInitialized whenNotPaused returns (bytes32) {
        uint256 price = _getChainlinkPrice();
        uint256 sizeDeltaUsd = _getSizeDeltaUsd(price, amount, false);
        uint256 acceptablePrice =
            price * PRICE_MULTIPLIER / CHAINLINK_MULTIPLIER * (BPS_DENOMINATOR + ACCEPTABLE_PRICE_BPS) / BPS_DENOMINATOR;
        uint256 minOutputAmount = amount * (BPS_DENOMINATOR - MIN_OUTPUT_SLIPPAGE_BPS) / BPS_DENOMINATOR;

        return _createOrder(amount, sizeDeltaUsd, acceptablePrice, GMX_EXECUTION_FEE, false, minOutputAmount);
    }

    function transferWETH(address to, uint256 amount) external onlyVaultOrOwner {
        SafeTransferLib.safeTransfer(WETH, to, amount);
    }

    function totalAssets() external view returns (uint256) {
        uint256 bal = SafeTransferLib.balanceOf(WETH, address(this));
        int256 positionValue = _getPositionWithPnlInToken();

        if (positionValue >= 0) {
            bal += uint256(positionValue);
        } else {
            uint256 loss = uint256(-positionValue);
            bal = bal > loss ? bal - loss : 0;
        }

        return bal;
    }

    // ---- Admin ---- //
    function adminIncreasePosition(uint256 amount, uint256 sizeDeltaUsd, uint256 acceptablePrice)
        external
        payable
        onlyOwner
        whenInitialized
    {
        SafeTransferLib.safeTransferFrom(WETH, msg.sender, address(this), amount);
        _createOrder(amount, sizeDeltaUsd, acceptablePrice, msg.value, true, 0);
    }

    function claimFundingFees(address[] memory markets, address[] memory tokens) external onlyOwner {
        exchangeRouter.claimFundingFees(markets, tokens, address(this));
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---- Internal: Position Sizing ---- //
    function _getSizeDeltaUsd(uint256 price, uint256 amount, bool isIncrease)
        internal
        view
        returns (uint256 sizeDeltaUsd)
    {
        Position.Props memory position = _getPosition();

        if (isIncrease) {
            uint256 newCollateral = position.numbers.collateralAmount + amount;
            uint256 newSizeUsd = newCollateral * price * PRICE_MULTIPLIER;
            if (newSizeUsd > position.numbers.sizeInUsd) {
                sizeDeltaUsd = newSizeUsd - position.numbers.sizeInUsd;
            }
        } else {
            uint256 newCollateral =
                amount >= position.numbers.collateralAmount ? 0 : position.numbers.collateralAmount - amount;
            uint256 newSizeUsd = newCollateral * price * PRICE_MULTIPLIER;
            if (position.numbers.sizeInUsd > newSizeUsd) {
                sizeDeltaUsd = position.numbers.sizeInUsd - newSizeUsd;
            }
        }
    }

    function _getPosition() internal view returns (Position.Props memory) {
        bytes32 positionKey = Position.getPositionKey(address(this), GM_TOKEN_ETH_WETH_USDC, WETH, false);
        return reader.getPosition(DATA_STORE, positionKey);
    }

    function _getChainlinkPrice() internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            IPriceFeed(CHAINLINK_ETH_USD).latestRoundData();
        if (answer <= 0 || answeredInRound < roundId || updatedAt == 0 || block.timestamp - updatedAt > ETH_HEARTBEAT)
        {
            revert GMXStrategy__StalePrice();
        }
        return uint256(answer);
    }

    function _getPositionWithPnlInToken() internal view returns (int256) {
        Position.Props memory position = _getPosition();

        if (position.numbers.sizeInUsd == 0 || position.numbers.collateralAmount == 0) {
            return int256(0);
        }

        uint256 ethPrice = _getChainlinkPrice();
        uint256 usdcPrice = _getUsdcPrice();

        uint256 ethPrice30 = ethPrice * PRICE_MULTIPLIER;
        uint256 usdcPrice30 = usdcPrice * 1e16;

        MarketUtils.MarketPrices memory prices = MarketUtils.MarketPrices({
            indexTokenPrice: Price.Props({min: ethPrice30 * 999 / 1000, max: ethPrice30 * 1001 / 1000}),
            longTokenPrice: Price.Props({min: ethPrice30 * 999 / 1000, max: ethPrice30 * 1001 / 1000}),
            shortTokenPrice: Price.Props({min: usdcPrice30 * 999 / 1000, max: usdcPrice30 * 1001 / 1000})
        });

        bytes32 positionKey = Position.getPositionKey(address(this), GM_TOKEN_ETH_WETH_USDC, WETH, false);

        ReaderPositionUtils.PositionInfo memory info = reader.getPositionInfo({
            dataStore: DATA_STORE,
            referralStorage: REFERRAL_STORAGE,
            positionKey: positionKey,
            prices: prices,
            sizeDeltaUsd: 0,
            uiFeeReceiver: address(0),
            usePositionSizeAsSizeDeltaUsd: true
        });

        uint256 minPrice = ethPrice30 * 999 / 1000;
        int256 collateralUsd = int256(position.numbers.collateralAmount * minPrice);
        int256 costUsd = int256(info.fees.totalCostAmount * minPrice);

        int256 remainingUsd = collateralUsd + info.pnlAfterPriceImpactUsd - costUsd;

        return remainingUsd / int256(minPrice);
    }

    function _getUsdcPrice() internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            IPriceFeed(CHAINLINK_USDC_USD).latestRoundData();
        if (
            answer <= 0 || answeredInRound < roundId || updatedAt == 0 || block.timestamp - updatedAt > USDC_HEARTBEAT
        ) {
            revert GMXStrategy__StalePrice();
        }
        return uint256(answer);
    }

    // ---- Internal: Orders ---- //
    function _createOrder(
        uint256 amount,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 executionFee,
        bool isIncrease,
        uint256 minOutputAmount
    ) internal returns (bytes32) {
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        if (isIncrease) {
            SafeTransferLib.safeApprove(WETH, ROUTER, amount);
            exchangeRouter.sendTokens(WETH, ORDER_VAULT, amount);
        }

        address orderReceiver = isIncrease ? i_callback : address(this);

        return exchangeRouter.createOrder(
            IBaseOrderUtils.CreateOrderParams({
                addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                    receiver: orderReceiver,
                    cancellationReceiver: orderReceiver,
                    callbackContract: i_callback,
                    uiFeeReceiver: address(0),
                    market: GM_TOKEN_ETH_WETH_USDC,
                    initialCollateralToken: WETH,
                    swapPath: new address[](0)
                }),
                numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                    sizeDeltaUsd: sizeDeltaUsd,
                    initialCollateralDeltaAmount: isIncrease ? 0 : amount,
                    triggerPrice: 0,
                    acceptablePrice: acceptablePrice,
                    executionFee: executionFee,
                    callbackGasLimit: CALLBACK_GAS_LIMIT,
                    minOutputAmount: minOutputAmount,
                    validFromTime: 0
                }),
                orderType: isIncrease ? Order.OrderType.MarketIncrease : Order.OrderType.MarketDecrease,
                decreasePositionSwapType: isIncrease
                    ? Order.DecreasePositionSwapType.NoSwap
                    : Order.DecreasePositionSwapType.SwapPnlTokenToCollateralToken,
                isLong: false,
                shouldUnwrapNativeToken: false,
                autoCancel: false,
                referralCode: bytes32(0),
                dataList: new bytes32[](0)
            })
        );
    }

    receive() external payable {}
}

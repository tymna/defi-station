// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Price} from "./Price.sol";

library MarketUtils {
    struct MarketPrices {
        Price.Props indexTokenPrice;
        Price.Props longTokenPrice;
        Price.Props shortTokenPrice;
    }
}

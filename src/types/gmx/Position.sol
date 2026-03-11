// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

library Position {
    struct Props {
        Addresses addresses;
        Numbers numbers;
        Flags flags;
    }

    struct Addresses {
        address account;
        address market;
        address collateralToken;
    }

    struct Numbers {
        uint256 sizeInUsd;
        uint256 sizeInTokens;
        uint256 collateralAmount;
        uint256 borrowingFactor;
        uint256 fundingFeeAmountPerSize;
        uint256 longTokenClaimableFundingAmountPerSize;
        uint256 shortTokenClaimableFundingAmountPerSize;
        uint256 increasedAtTime;
        uint256 decreasedAtTime;
    }

    struct Flags {
        bool isLong;
    }

    function getPositionKey(address account, address market, address collateralToken, bool isLong)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(account, market, collateralToken, isLong));
    }
}

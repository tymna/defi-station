// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ---- Arbitrum One Addresses ---- //
// GMX V2 core contracts live on Arbitrum. Base users interact via LayerZero multichain relay.

// Tokens
address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

// GMX V2 Core
address constant DATA_STORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
address constant EXCHANGE_ROUTER = 0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41;
address constant ROUTER = 0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
address constant ORDER_VAULT = 0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5;
address constant ORDER_HANDLER = 0x63492B775e30a9E6b4b4761c12605EB9d071d5e9;
address constant READER = 0x470fbC46bcC0f16532691Df360A07d8Bf5ee0789;
address constant REFERRAL_STORAGE = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;

// GMX Markets (GM Tokens)
address constant GM_TOKEN_ETH_WETH_USDC = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;

// Chainlink Price Feeds (Arbitrum)
address constant CHAINLINK_ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
address constant CHAINLINK_USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.8.9;

/**
 * @title FxPriceFeed interface
 * @notice Provides a way to create a token pair with an exchange rate.
 */
interface IFxPriceFeed {
    /**
     * @notice Function to get the price feed pair description
     * @return price feed pair description
     */
    function pair() external view returns (string calldata);

    /**
     * @notice Function to get the price feed base token address
     * @return price feed base token address
     */
    function baseTokenAddr() external view returns (address);

    /**
     * @notice Function to get the price feed exchange rate decimal places
     * @return price feed exchange rate decimal places
     */
    function decimalPlaces() external view returns (uint256);

    /**
     * @notice Returns the time of the last change to the exchange rate.
     * @return time of the last change.
     */
    function updateTime() external view returns (uint256);

    /**
     * @notice Returns the current exchange rate of the token pair.
     * @return Exchange rate value
     */
    function exchangeRate() external view returns (uint256);
}

/**
 * @title MutableFxPriceFeed interface
 * @notice Provides mutable methods for managing the exchange rate of a token pair.
 */
interface IMutableFxPriceFeed is IFxPriceFeed {
    /**
     * @notice Sets a new exchange rate for the token pair.
     * @param exchangeRate_ New exchange rate value.
     * @param pricingTime_ Time when the new exchange rate was set.
     * @return true if exchange rate setting was successful
     */
    function setExchangeRate(uint256 exchangeRate_, uint256 pricingTime_) external returns (bool);
}

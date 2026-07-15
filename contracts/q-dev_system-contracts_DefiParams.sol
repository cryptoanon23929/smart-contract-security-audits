// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.8.9;

library DefiParams {
    string constant PREFIX = "governed.EPDR.";
    string constant DEFI = "defi";
    string constant DOT = ".";
    string constant UNDERSCORE = "_";

    function concatenate(
        string memory col_,
        string memory stc_,
        string memory ending_
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(PREFIX, col_, UNDERSCORE, stc_, UNDERSCORE, ending_));
    }

    function concatenate(string memory param_, string memory ending_) internal pure returns (string memory) {
        return string(abi.encodePacked(PREFIX, param_, UNDERSCORE, ending_));
    }

    function concatenate(string memory ending_) internal pure returns (string memory) {
        return string(abi.encodePacked(PREFIX, ending_));
    }

    function stableCoinAddress(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "coin"));
    }

    function liquidationAuctionAddress(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "liquidationAuction"));
    }

    function systemBalanceAddress(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "systemBalance"));
    }

    function borrowingAddress(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "borrowing"));
    }

    function savingAddress(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "saving"));
    }

    function compoundRateKeeperAddress(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "compoundRateKeeper"));
    }

    function oracle(string memory col_, string memory stc_) internal pure returns (string memory) {
        return concatenate(col_, stc_, "oracle");
    }

    function ceiling(string memory col_, string memory stc_) internal pure returns (string memory) {
        return concatenate(col_, stc_, "ceiling");
    }

    function step(string memory stc_) internal pure returns (string memory) {
        return concatenate(stc_, "step");
    }

    function collateralizationRatio(string memory col_, string memory stc_) internal pure returns (string memory) {
        return concatenate(col_, stc_, "collateralizationRatio");
    }

    function liquidationRatio(string memory col_, string memory stc_) internal pure returns (string memory) {
        return concatenate(col_, stc_, "liquidationRatio");
    }

    function liquidationFee(string memory col_, string memory stc_) internal pure returns (string memory) {
        return concatenate(col_, stc_, "liquidationFee");
    }

    function interestRate(string memory col_, string memory stc_) internal pure returns (string memory) {
        return concatenate(col_, stc_, "interestRate");
    }

    function systemSurplusAuction(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "systemSurplusAuction"));
    }

    function systemDebtAuction(string memory stc_) internal pure returns (string memory) {
        return string(abi.encodePacked(DEFI, DOT, stc_, DOT, "systemDebtAuction"));
    }

    function surplusThreshold(string memory stc_) internal pure returns (string memory) {
        return concatenate(stc_, "surplusThreshold");
    }

    function surplusLot(string memory stc_) internal pure returns (string memory) {
        return concatenate(stc_, "surplusLot");
    }

    function savingRate(string memory stc_) internal pure returns (string memory) {
        return concatenate(stc_, "savingRate");
    }

    function debtThreshold(string memory stc_) internal pure returns (string memory) {
        return concatenate(stc_, "debtThreshold");
    }

    function contractAddress(string memory col_) internal pure returns (string memory) {
        return concatenate(col_, "address");
    }
}

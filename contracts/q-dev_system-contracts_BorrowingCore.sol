// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./DefiParams.sol";

import "./oracles/IFxPriceFeed.sol";

import "../governance/IParameters.sol";

import "../interfaces/IContractRegistry.sol";
import "../interfaces/defi/IStableCoin.sol";

import "../common/Globals.sol";
import "../common/FullMath.sol";
import "../common/CompoundRateKeeper.sol";
import "../common/CompoundRateKeeperFactory.sol";

contract BorrowingCore is Initializable {
    using FullMath for uint256;
    using DefiParams for string;

    struct Vault {
        string colKey;
        uint256 colAsset;
        uint256 normalizedDebt;
        uint256 mintedAmount;
        bool isLiquidated;
        uint256 liquidationFullDebt;
    }

    struct VaultStats {
        ColStats colStats;
        StcStats stcStats;
    }

    struct ColStats {
        string key;
        uint256 balance;
        uint256 price;
        uint256 withdrawableAmount;
        uint256 liquidationPrice;
    }

    struct StcStats {
        string key;
        uint256 outstandingDebt;
        uint256 normalizedDebt;
        uint256 compoundRate;
        uint256 lastUpdateOfCompoundRate;
        uint256 borrowingLimit;
        uint256 availableToBorrow;
        uint256 liquidationLimit;
        uint256 borrowingFee;
    }

    struct AggregatedTotalsInfo {
        uint256 outstandingDebt;
        uint256 mintedAmount;
        uint256 owedBorrowingFees;
    }

    struct CalcValues {
        uint256 colPrice;
        uint256 colDecimals;
        uint256 collateralValue;
        uint256 stcAmount;
        uint256 stcDecimals;
    }

    IContractRegistry private _registry;
    string private _stc;

    string[] private _colKeys;
    mapping(string => bool) private _colKeyExist;

    uint256 public aggregatedMintedAmount;
    mapping(string => uint256) public aggregatedNormalizedDebts;

    mapping(address => mapping(uint256 => Vault)) public userVaults;
    mapping(address => uint256) public userVaultsCount;
    mapping(address => uint256) public totalStcBackedByCol;
    mapping(string => CompoundRateKeeper) public compoundRateKeeper;

    event VaultCreated(address indexed user, uint256 indexed vaultId, string colKey);
    event ColDeposited(address indexed user, uint256 indexed vaultId, uint256 amount);
    event ColWithdrawn(address indexed user, uint256 indexed vaultId, uint256 amount);
    event StcGenerated(address indexed user, uint256 indexed vaultId, uint256 amount);
    event StcRepaid(address indexed user, uint256 indexed vaultId, uint256 burnt, uint256 surplus);
    event Liquidated(address indexed user, uint256 indexed vaultId);

    /**
     * @notice Restricts only the LiquidationAuction can interact
     */
    modifier onlyLiquidationAuction() {
        _onlyLiquidationAuction();
        _;
    }

    /**
     * @notice Restricts only for not liquidated vaults
     * @param vaultId_ Vault id
     */
    modifier onlyNotLiquidated(address user_, uint256 vaultId_) {
        _onlyNotLiquidated(user_, vaultId_);
        _;
    }

    /**
     * @notice Restricts only for existing vaults
     * @param user_ User address
     * @param vaultId_ Vault id
     */
    modifier shouldExist(address user_, uint256 vaultId_) {
        _shouldExist(user_, vaultId_);
        _;
    }

    constructor() {}

    function initialize(address registry_, string memory stc_) external initializer {
        _registry = IContractRegistry(registry_);
        _stc = stc_;
    }

    /**
     * @notice Inits a Vault with the desired collateral asset
     * @param colKey_ The key of collateral
     * @return Vault id
     */
    function createVault(string memory colKey_) external returns (uint256) {
        require(
            IParameters(_getEPDRParams()).getAddr(colKey_.contractAddress()) != address(0),
            "[QEC-021003]-Unsupported collateral asset."
        );

        if (address(compoundRateKeeper[colKey_]) == address(0)) {
            compoundRateKeeper[colKey_] = _getCrKeeperFactory().create();
        }

        uint256 id_ = userVaultsCount[msg.sender];

        userVaults[msg.sender][id_].colKey = colKey_;
        userVaultsCount[msg.sender] = id_ + 1;

        if (!_colKeyExist[colKey_]) {
            _colKeys.push(colKey_);
            _colKeyExist[colKey_] = true;
        }

        emit VaultCreated(msg.sender, id_, colKey_);

        return id_;
    }

    /**
     * @notice Increases the collateral balance of a Vault by the given amount
     * @param vaultId_ Vault id
     * @param amount_ Amount of collateral to deposit
     * @return true if everything went well
     */
    function depositCol(uint256 vaultId_, uint256 amount_)
        external
        shouldExist(msg.sender, vaultId_)
        onlyNotLiquidated(msg.sender, vaultId_)
        returns (bool)
    {
        require(amount_ > 0, "[QEC-021004]-Collateral deposit must not be zero.");

        address colTokenAddress_ = IParameters(_getEPDRParams()).getAddr(
            userVaults[msg.sender][vaultId_].colKey.contractAddress()
        );

        amount_ = _pullCollateralToken(colTokenAddress_, msg.sender, amount_);

        userVaults[msg.sender][vaultId_].colAsset = userVaults[msg.sender][vaultId_].colAsset + amount_;

        emit ColDeposited(msg.sender, vaultId_, amount_);

        return true;
    }

    /**
     * @notice Mints STC to the user vault
     * @param vaultId_ Vault id
     * @param stcAmount_ Amount of STC to generate
     * @return true if everything went well
     */
    function generateStc(uint256 vaultId_, uint256 stcAmount_)
        external
        shouldExist(msg.sender, vaultId_)
        onlyNotLiquidated(msg.sender, vaultId_)
        returns (bool)
    {
        Vault memory vault_ = userVaults[msg.sender][vaultId_];
        CompoundRateKeeper compoundRateKeeper_ = compoundRateKeeper[vault_.colKey];

        uint256 normalizedAmount_ = compoundRateKeeper_.normalizeAmount(stcAmount_);
        stcAmount_ = compoundRateKeeper_.denormalizeAmount(normalizedAmount_);

        IParameters params_ = IParameters(_getEPDRParams());

        require(
            stcAmount_ >= params_.getUint(_stc.step()),
            "[QEC-021007]-The amount of STC is less than the acceptable minimum."
        );

        {
            address colTokenAddress_ = params_.getAddr(vault_.colKey.contractAddress());
            uint256 totalStcBackedByCol_ = totalStcBackedByCol[colTokenAddress_];

            require(
                totalStcBackedByCol_ + stcAmount_ <= params_.getUint(vault_.colKey.ceiling(_stc)),
                "[QEC-021008]-The amount of STC exceeds the ceiling."
            );

            totalStcBackedByCol[colTokenAddress_] = totalStcBackedByCol_ + stcAmount_;
        }

        require(
            _getColRatio(msg.sender, vaultId_, vault_.colAsset, stcAmount_) >=
                params_.getUint(vault_.colKey.collateralizationRatio(_stc)),
            "[QEC-021009]-Not enough collateral."
        );

        vault_.normalizedDebt += normalizedAmount_;
        vault_.mintedAmount += stcAmount_;
        userVaults[msg.sender][vaultId_] = vault_;

        aggregatedMintedAmount += stcAmount_;
        aggregatedNormalizedDebts[vault_.colKey] += normalizedAmount_;

        require(
            IStableCoin(_registry.mustGetAddress(_stc.stableCoinAddress())).mint(msg.sender, stcAmount_),
            "[QEC-021010]-Failed to mint the synthetic asset amount."
        );

        emit StcGenerated(msg.sender, vaultId_, stcAmount_);

        return true;
    }

    /**
     * @notice Decreases the collateral balance of a Vault by the given amount
     * @param vaultId_ Vault id
     * @param amount_ Amount of collateral to withdraw
     * @return true if everything went well
     */
    function withdrawCol(uint256 vaultId_, uint256 amount_)
        external
        shouldExist(msg.sender, vaultId_)
        onlyNotLiquidated(msg.sender, vaultId_)
        returns (bool)
    {
        IParameters params_ = IParameters(_getEPDRParams());

        require(
            userVaults[msg.sender][vaultId_].colAsset >= amount_,
            "[QEC-021018]-Withdrawal amount is greater than the available collateral asset."
        );

        userVaults[msg.sender][vaultId_].colAsset -= amount_;

        string memory colKey_ = userVaults[msg.sender][vaultId_].colKey;
        require(
            getCurrentColRatio(msg.sender, vaultId_) >= params_.getUint(colKey_.collateralizationRatio(_stc)),
            "[QEC-021011]-Dropping below minimum collateralization ratio, withdrawal failed."
        );

        address colTokenAddress_ = params_.getAddr(userVaults[msg.sender][vaultId_].colKey.contractAddress());
        require(
            IERC20(colTokenAddress_).transfer(msg.sender, amount_),
            "[QEC-021012]-Transfer of the collateral asset failed."
        );

        emit ColWithdrawn(msg.sender, vaultId_, amount_);

        return true;
    }

    /**
     * @notice Liquidates user vault
     * @param user_ User address
     * @param vaultId_ Vault id
     * @return true if everything went well
     */
    function liquidate(address user_, uint256 vaultId_)
        external
        shouldExist(user_, vaultId_)
        onlyNotLiquidated(user_, vaultId_)
        returns (bool)
    {
        IParameters params_ = IParameters(_getEPDRParams());

        Vault memory vault_ = userVaults[user_][vaultId_];
        require(
            getCurrentColRatio(user_, vaultId_) <= params_.getUint(vault_.colKey.liquidationRatio(_stc)),
            "[QEC-021016]-Vault is above liquidation ratio."
        );

        vault_.isLiquidated = true;
        vault_.liquidationFullDebt = getFullDebt(user_, vaultId_);
        userVaults[user_][vaultId_] = vault_;

        emit Liquidated(user_, vaultId_);

        return true;
    }

    /**
     * @notice Calculates and updates the compound rate
     * @param colKey_ The key of collateral
     * @return New compound rate
     */
    function updateCompoundRate(string memory colKey_) external returns (uint256) {
        if (address(compoundRateKeeper[colKey_]) == address(0)) {
            require(
                IParameters(_getEPDRParams()).getAddr(colKey_.contractAddress()) != address(0),
                "[QEC-021013]-Cannot update compound rate for unsupported collateral."
            );

            compoundRateKeeper[colKey_] = _getCrKeeperFactory().create();
        }

        uint256 interestRate_ = IParameters(_getEPDRParams()).getUint(colKey_.interestRate(_stc));

        return compoundRateKeeper[colKey_].update(interestRate_);
    }

    /**
     * @notice Pays back STC to the vault to reduce outstanding debt
     * @param vaultId_ Vault id
     * @param amount_ Amount of STC to pay back
     */
    function payBackStc(uint256 vaultId_, uint256 amount_) external shouldExist(msg.sender, vaultId_) {
        _payBackStc(vaultId_, amount_);
    }

    /**
     * @notice Clears the vault
     * @param user_ User address
     * @param vaultId_ Vault id
     * @param amountToClear_ Amount of tokens to burn
     * @param beneficiary_ receiver of collateral
     */
    function clearVault(
        address user_,
        uint256 vaultId_,
        uint256 amountToClear_,
        address beneficiary_
    ) external onlyLiquidationAuction shouldExist(user_, vaultId_) {
        IERC20 colToken_ = IERC20(
            IParameters(_getEPDRParams()).getAddr(userVaults[user_][vaultId_].colKey.contractAddress())
        );

        uint256 invariantBalance_ = colToken_.balanceOf(address(this)) - userVaults[user_][vaultId_].colAsset;
        require(
            colToken_.transfer(beneficiary_, userVaults[user_][vaultId_].colAsset),
            "[QEC-021006]-Transfer of the collateral asset failed."
        );

        assert(invariantBalance_ == colToken_.balanceOf(address(this)));

        _clearVault(user_, vaultId_, amountToClear_);
    }

    /**
     * @notice Gets stats for the user vault
     * @param user_ User address
     * @param vaultId_ Vault id
     * @return structure of type VaultStats
     */
    function getVaultStats(address user_, uint256 vaultId_)
        external
        view
        shouldExist(user_, vaultId_)
        returns (VaultStats memory)
    {
        IParameters params_ = IParameters(_getEPDRParams());

        VaultStats memory stats_;
        Vault memory vault_ = userVaults[user_][vaultId_];
        IFxPriceFeed feed_ = IFxPriceFeed(params_.getAddr(vault_.colKey.oracle(_stc)));

        stats_.colStats.key = vault_.colKey;

        stats_.colStats.price =
            (feed_.exchangeRate() * (10**IStableCoin(_registry.mustGetAddress(_stc.stableCoinAddress())).decimals())) /
            (10**feed_.decimalPlaces());

        stats_.colStats.balance = vault_.colAsset;

        uint256 decimal_ = getDecimal();
        uint256 colDecimal_ = 10**IERC20Metadata(params_.getAddr(vault_.colKey.contractAddress())).decimals();
        uint256 minColRatio_ = params_.getUint(vault_.colKey.collateralizationRatio(_stc));

        uint256 fullDebt_ = getFullDebt(user_, vaultId_);

        if (fullDebt_ == 0) {
            stats_.colStats.withdrawableAmount = stats_.colStats.balance;
        } else if (stats_.colStats.price > 0) {
            uint256 minColBalance_ = (fullDebt_ * minColRatio_ * colDecimal_) / stats_.colStats.price / decimal_;

            if (_getColRatio(user_, vaultId_, minColBalance_, 0) < minColRatio_) {
                // can happen because of integer truncation of _minColBalance
                minColBalance_++;
            }

            if (stats_.colStats.balance > minColBalance_) {
                stats_.colStats.withdrawableAmount = stats_.colStats.balance - minColBalance_;
            }
        }

        uint256 liquidationRatio_ = params_.getUint(vault_.colKey.liquidationRatio(_stc));

        if (vault_.colAsset != 0) {
            stats_.colStats.liquidationPrice =
                (liquidationRatio_ * fullDebt_ * colDecimal_) /
                decimal_ /
                vault_.colAsset;
        } else {
            stats_.colStats.liquidationPrice = type(uint256).max;
        }

        // STC
        stats_.stcStats.key = _stc;
        stats_.stcStats.outstandingDebt = fullDebt_;
        stats_.stcStats.normalizedDebt = vault_.normalizedDebt;
        stats_.stcStats.borrowingFee = params_.getUint(vault_.colKey.interestRate(stats_.stcStats.key));
        stats_.stcStats.borrowingLimit =
            (vault_.colAsset * stats_.colStats.price * decimal_) /
            minColRatio_ /
            colDecimal_;

        if (stats_.stcStats.borrowingLimit > fullDebt_) {
            stats_.stcStats.availableToBorrow = stats_.stcStats.borrowingLimit - stats_.stcStats.outstandingDebt;
        }

        CompoundRateKeeper compoundRateKeeper_ = compoundRateKeeper[vault_.colKey];

        stats_.stcStats.compoundRate = compoundRateKeeper_.getCurrentRate();
        stats_.stcStats.lastUpdateOfCompoundRate = compoundRateKeeper_.getLastUpdate();

        stats_.stcStats.liquidationLimit =
            (vault_.colAsset * stats_.colStats.price * decimal_) /
            liquidationRatio_ /
            colDecimal_;

        return stats_;
    }

    /**
     * @notice Returns info about minted amount, owed borrowing fees and outstanding debt
     * @return structure of type AggregatedTotalsInfo
     */
    function getAggregatedTotals() external view returns (AggregatedTotalsInfo memory) {
        AggregatedTotalsInfo memory totalsInfo_;
        string[] memory colKeys_ = _colKeys;

        for (uint256 i = 0; i < colKeys_.length; i++) {
            string memory colKey_ = colKeys_[i];

            uint256 colOutstandingDebt_ = compoundRateKeeper[colKey_].denormalizeAmount(
                aggregatedNormalizedDebts[colKey_]
            );

            totalsInfo_.outstandingDebt = totalsInfo_.outstandingDebt + colOutstandingDebt_;
        }

        totalsInfo_.mintedAmount = aggregatedMintedAmount;
        totalsInfo_.owedBorrowingFees = totalsInfo_.outstandingDebt - totalsInfo_.mintedAmount;

        return totalsInfo_;
    }

    /**
     * @notice Gets the collateral ratio
     * @param user_ User address
     * @param vaultId_ Vault id
     * @return Current collateral ratio
     */
    function getCurrentColRatio(address user_, uint256 vaultId_)
        public
        view
        shouldExist(user_, vaultId_)
        returns (uint256)
    {
        return _getColRatio(user_, vaultId_, userVaults[user_][vaultId_].colAsset, 0);
    }

    /**
     * @notice Gets debt of vault
     * @param user_ User address
     * @param vaultId_ Vault id
     * @return Amount of the vault debt
     */
    function getFullDebt(address user_, uint256 vaultId_) public view shouldExist(user_, vaultId_) returns (uint256) {
        Vault storage vault_ = userVaults[user_][vaultId_];

        return compoundRateKeeper[vault_.colKey].denormalizeAmount(vault_.normalizedDebt);
    }

    function _payBackStc(uint256 vaultId_, uint256 amount_) private onlyNotLiquidated(msg.sender, vaultId_) {
        require(amount_ != 0, "[QEC-021014]-Payback amount must not be zero.");

        uint256 currentFullDebt_ = getFullDebt(msg.sender, vaultId_);

        if (amount_ > currentFullDebt_) {
            amount_ = currentFullDebt_;
        }

        uint256 burnAmount_;
        uint256 actualSurplus_ = amount_;

        // distribute payback amount between surplus (accrued interest)
        // and minted amount (should be burnt)
        Vault storage vault_ = userVaults[msg.sender][vaultId_];

        uint256 accruedInterest_ = currentFullDebt_ - vault_.mintedAmount;

        if (amount_ > accruedInterest_) {
            burnAmount_ = amount_ - accruedInterest_;
            actualSurplus_ = accruedInterest_;
        }

        CompoundRateKeeper compoundRateKeeper_ = compoundRateKeeper[vault_.colKey];

        uint256 canceledDebtAmount_;

        if (amount_ == currentFullDebt_) {
            canceledDebtAmount_ = vault_.normalizedDebt;
        } else {
            canceledDebtAmount_ = compoundRateKeeper_.normalizeAmount(amount_);

            // try to compensate for rounding issues (rather cancel less than too much)
            uint256 debtLookAhead_ = compoundRateKeeper_.denormalizeAmount(vault_.normalizedDebt - canceledDebtAmount_);
            uint256 mintedLookAhead_ = vault_.mintedAmount - burnAmount_;

            if (debtLookAhead_ < mintedLookAhead_) {
                canceledDebtAmount_ -= 1;
            }
        }

        vault_.normalizedDebt -= canceledDebtAmount_;
        vault_.mintedAmount -= burnAmount_;

        aggregatedNormalizedDebts[vault_.colKey] -= canceledDebtAmount_;
        aggregatedMintedAmount -= burnAmount_;

        // surplus goes to system balance
        IStableCoin stcContract_ = IStableCoin(_registry.mustGetAddress(_stc.stableCoinAddress()));

        stcContract_.transferFrom(msg.sender, _registry.mustGetAddress(_stc.systemBalanceAddress()), actualSurplus_);

        if (burnAmount_ > 0) {
            stcContract_.burnFrom(msg.sender, burnAmount_);

            address colTokenAddress_ = IParameters(_getEPDRParams()).getAddr(vault_.colKey.contractAddress());

            totalStcBackedByCol[colTokenAddress_] -= burnAmount_;
        }

        emit StcRepaid(msg.sender, vaultId_, burnAmount_, actualSurplus_);
    }

    function _clearVault(
        address user_,
        uint256 vaultId_,
        uint256 amount_
    ) private {
        Vault memory vault_ = userVaults[user_][vaultId_];

        uint256 accruedInterest_ = vault_.liquidationFullDebt - vault_.mintedAmount;
        uint256 actualSurplus_ = accruedInterest_;
        uint256 burnAmount_ = vault_.mintedAmount;

        if (amount_ < vault_.mintedAmount) {
            actualSurplus_ = 0;
            burnAmount_ = amount_;
        } else if (amount_ < vault_.liquidationFullDebt) {
            actualSurplus_ = amount_ - vault_.mintedAmount;
        }

        IStableCoin stcContract_ = IStableCoin(_registry.mustGetAddress(_stc.stableCoinAddress()));
        if (actualSurplus_ > 0) {
            // just to avoid useless actions
            stcContract_.transferFrom(
                msg.sender,
                _registry.mustGetAddress(_stc.systemBalanceAddress()),
                actualSurplus_
            );
        }

        // decreasing the total number of STC backed by COL
        address colTokenAddress_ = IParameters(_getEPDRParams()).getAddr(vault_.colKey.contractAddress());

        totalStcBackedByCol[colTokenAddress_] -= vault_.mintedAmount;

        stcContract_.burnFrom(msg.sender, burnAmount_);

        aggregatedMintedAmount -= vault_.mintedAmount;
        aggregatedNormalizedDebts[vault_.colKey] -= vault_.normalizedDebt;

        delete userVaults[user_][vaultId_].colAsset;
        delete userVaults[user_][vaultId_].normalizedDebt;
        delete userVaults[user_][vaultId_].mintedAmount;
    }

    function _pullCollateralToken(
        address colTokenAddress_,
        address user_,
        uint256 amount_
    ) private returns (uint256) {
        IERC20 colToken_ = IERC20(colTokenAddress_);

        uint256 initialBalance_ = colToken_.balanceOf(address(this));

        require(
            colToken_.transferFrom(user_, address(this), amount_),
            "[QEC-021006]-Transfer of the collateral asset failed."
        );

        return colToken_.balanceOf(address(this)) - initialBalance_;
    }

    function _getCrKeeperFactory() private view returns (CompoundRateKeeperFactory) {
        return CompoundRateKeeperFactory(_registry.mustGetAddress(RKEY__CR_KEEPER_FACTORY));
    }

    function _onlyNotLiquidated(address user_, uint256 vaultId_) private view {
        require(!userVaults[user_][vaultId_].isLiquidated, "[QEC-021000]-The vault is liquidated.");
    }

    function _onlyLiquidationAuction() private view {
        require(
            msg.sender == _registry.mustGetAddress(_stc.liquidationAuctionAddress()),
            "[QEC-021001]-Permission denied - only the LiquidationAuction contract has access."
        );
    }

    function _shouldExist(address user_, uint256 vaultId_) private view {
        require(userVaultsCount[user_] > vaultId_, "[QEC-021005]-The vault does not exist.");
    }

    function _getEPDRParams() private view returns (address) {
        return _registry.mustGetAddress(RKEY__EPDR_PARAMETERS);
    }

    /**
     * @notice Gets the collateral ratio
     * @param user_ User address
     * @param vaultId_ Vault id
     * @param colAsset_ Collateral balance
     * @param additionalStc_ Amount of additional STC
     * @return Current collateral ratio
     */
    function _getColRatio(
        address user_,
        uint256 vaultId_,
        uint256 colAsset_,
        uint256 additionalStc_
    ) private view returns (uint256) {
        CalcValues memory calcValues_;
        calcValues_.stcAmount = getFullDebt(user_, vaultId_) + additionalStc_;

        if (calcValues_.stcAmount == 0) {
            return type(uint256).max;
        }

        address oracleAddress_ = IParameters(_getEPDRParams()).getAddr(userVaults[user_][vaultId_].colKey.oracle(_stc));
        require(oracleAddress_ != address(0), "[QEC-021015]-The price feed for the collateral does not exist.");

        calcValues_.stcDecimals = IStableCoin(_registry.mustGetAddress(_stc.stableCoinAddress())).decimals();
        calcValues_.colPrice =
            (IFxPriceFeed(oracleAddress_).exchangeRate() * (10**calcValues_.stcDecimals)) /
            (10**IFxPriceFeed(oracleAddress_).decimalPlaces());

        calcValues_.colDecimals = IERC20Metadata(
            IParameters(_getEPDRParams()).getAddr(userVaults[user_][vaultId_].colKey.contractAddress())
        ).decimals();

        return
            (calcValues_.colPrice).mulDiv(getDecimal(), 10**calcValues_.colDecimals).mulDiv(
                colAsset_,
                calcValues_.stcAmount
            );
    }
}

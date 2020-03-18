pragma solidity 0.5.10;

import "./interfaces/IOptionsExchange.sol";
import "./OptionsContract.sol";

/**
 * @title Opyn's Options Contract
 * @author Opyn
 */

contract oToken is OptionsContract {
    /**
    * @param _collateral The collateral asset
    * @param _collExp The precision of the collateral (-18 if ETH)
    * @param _underlying The asset that is being protected
    * @param _underlyingExp The precision of the underlying asset
    * @param _oTokenExchangeExp The precision of the `amount of underlying` that 1 oToken protects
    * @param _strikePrice The amount of strike asset that will be paid out
    * @param _strikeExp The precision of the strike asset (-18 if ETH)
    * @param _strike The asset in which the insurance is calculated
    * @param _expiry The time at which the insurance expires
    * @param _optionsExchangeAddress The contract address which interfaces with the exchange + oracle
    * @param _oracleAddress The address of the oracle
    * @param _windowSize UNIX time. Exercise window is from `expiry - _windowSize` to `expiry`.
    */
    constructor(
        IERC20 _collateral,
        int32 _collExp,
        IERC20 _underlying,
        int32 _underlyingExp,
        int32 _oTokenExchangeExp,
        uint256 _strikePrice,
        int32 _strikeExp,
        IERC20 _strike,
        uint256 _expiry,
        address _optionsExchangeAddress,
        address _oracleAddress,
        uint256 _windowSize
    )
        public
        OptionsContract(
            _collateral,
            _collExp,
            _underlying,
            _underlyingExp,
            _oTokenExchangeExp,
            _strikePrice,
            _strikeExp,
            _strike,
            _expiry,
            _optionsExchangeAddress,
            _oracleAddress,
            _windowSize
        )
    {}

    /**
     * @notice opens a Vault, adds ETH collateral, and mints new oTokens in one step
     * Remember that creating oTokens can put the owner at a risk of losing the collateral
     * if an exercise event happens.
     * The sell function provides the owner a chance to earn premiums.
     * Ensure that you create and immediately sell oTokens atmoically.
     * @param amtToCreate number of oTokens to create
     * @param receiver address to send the Options to
     */
    function createETHCollateralOption(uint256 amtToCreate, address receiver)
        external
        payable
    {
        openVault();
        addETHCollateralOption(amtToCreate, receiver);
    }

    /**
     * @notice adds ETH collateral, and mints new oTokens in one step to an existing Vault
     * Remember that creating oTokens can put the owner at a risk of losing the collateral
     * if an exercise event happens.
     * The sell function provides the owner a chance to earn premiums.
     * Ensure that you create and immediately sell oTokens atmoically.
     * @param amtToCreate number of oTokens to create
     * @param receiver address to send the Options to
     */
    function addETHCollateralOption(uint256 amtToCreate, address receiver)
        public
        payable
    {
        addETHCollateral(msg.sender);
        issueOTokens(amtToCreate, receiver);
    }

    /**
     * @notice opens a Vault, adds ETH collateral, mints new oTokens and sell in one step
     * @param amtToCreate number of oTokens to create
     * @param receiver address to receive the premiums
     */
    function createAndSellETHCollateralOption(
        uint256 amtToCreate,
        address payable receiver
    ) external payable {
        openVault();
        addETHCollateralOption(amtToCreate, address(this));
        this.approve(optionsExchangeAddress, amtToCreate);
        IOptionsExchange(optionsExchangeAddress).sellOTokens(
            receiver,
            address(this),
            address(0),
            amtToCreate
        );
    }

    /**
     * @notice adds ETH collateral to an existing Vault, and mints new oTokens and sells the oTokens in one step
     * @param amtToCreate number of oTokens to create
     * @param receiver address to send the Options to
     */
    function addAndSellETHCollateralOption(
        uint256 amtToCreate,
        address payable receiver
    ) public payable {
        addETHCollateral(msg.sender);
        issueOTokens(amtToCreate, address(this));
        this.approve(optionsExchangeAddress, amtToCreate);
        IOptionsExchange(optionsExchangeAddress).sellOTokens(
            receiver,
            address(this),
            address(0),
            amtToCreate
        );
    }

    /**
     * @notice opens a Vault, adds ERC20 collateral, and mints new oTokens in one step
     * Remember that creating oTokens can put the owner at a risk of losing the collateral
     * if an exercise event happens.
     * The sell function provides the owner a chance to earn premiums.
     * Ensure that you create and immediately sell oTokens atmoically.
     * @param amtToCreate number of oTokens to create
     * @param amtCollateral amount of collateral added
     * @param receiver address to send the Options to
     */
    function createERC20CollateralOption(
        uint256 amtToCreate,
        uint256 amtCollateral,
        address receiver
    ) external {
        openVault();
        addERC20CollateralOption(amtToCreate, amtCollateral, receiver);
    }

    /**
     * @notice adds ERC20 collateral, and mints new oTokens in one step
     * Remember that creating oTokens can put the owner at a risk of losing the collateral
     * if an exercise event happens.
     * The sell function provides the owner a chance to earn premiums.
     * Ensure that you create and immediately sell oTokens atmoically.
     * @param amtToCreate number of oTokens to create
     * @param amtCollateral amount of collateral added
     * @param receiver address to send the Options to
     */
    function addERC20CollateralOption(
        uint256 amtToCreate,
        uint256 amtCollateral,
        address receiver
    ) public {
        addERC20Collateral(msg.sender, amtCollateral);
        issueOTokens(amtToCreate, receiver);
    }

    /**
     * @notice opens a Vault, adds ERC20 collateral, mints new oTokens and sells the oTokens in one step
     * @param amtToCreate number of oTokens to create
     * @param amtCollateral amount of collateral added
     * @param receiver address to send the Options to
     */
    function createAndSellERC20CollateralOption(
        uint256 amtToCreate,
        uint256 amtCollateral,
        address payable receiver
    ) external {
        openVault();
        addERC20CollateralOption(amtToCreate, amtCollateral, address(this));
        this.approve(optionsExchangeAddress, amtToCreate);
        IOptionsExchange(optionsExchangeAddress).sellOTokens(
            receiver,
            address(this),
            address(0),
            amtToCreate
        );
    }

    /**
     * @notice adds ERC20 collateral, mints new oTokens and sells the oTokens in one step
     * @param amtToCreate number of oTokens to create
     * @param amtCollateral amount of collateral added
     * @param receiver address to send the Options to
     */
    function addAndSellERC20CollateralOption(
        uint256 amtToCreate,
        uint256 amtCollateral,
        address payable receiver
    ) public {
        addERC20Collateral(msg.sender, amtCollateral);
        issueOTokens(amtToCreate, address(this));
        this.approve(optionsExchangeAddress, amtToCreate);
        IOptionsExchange(optionsExchangeAddress).sellOTokens(
            receiver,
            address(this),
            address(0),
            amtToCreate
        );
    }
}

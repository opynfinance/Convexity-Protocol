pragma solidity 0.5.10;

import "./lib/CompoundOracleInterface.sol";
import "./OptionsUtils.sol";
import "./lib/UniswapFactoryInterface.sol";
import "./lib/UniswapExchangeInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OptionsExchange {
    uint256 constant LARGE_BLOCK_SIZE = 1651753129000;
    uint256 constant LARGE_APPROVAL_NUMBER = 10**30;

    UniswapFactoryInterface public UNISWAP_FACTORY;

    constructor(address _uniswapFactory) public {
        UNISWAP_FACTORY = UniswapFactoryInterface(_uniswapFactory);
    }

    /*** Events ***/
    event SellOTokens(
        address seller,
        address payable receiver,
        address oTokenAddress,
        address payoutTokenAddress,
        uint256 oTokensToSell
    );
    event BuyOTokens(
        address buyer,
        address payable receiver,
        address oTokenAddress,
        address paymentTokenAddress,
        uint256 oTokensToBuy,
        uint256 premiumPaid
    );

    /**
    * @notice This function sells oTokens on Uniswap and sends back payoutTokens to the receiver
    * @param receiver The address to send the payout tokens back to
    * @param oTokenAddress The address of the oToken to sell
    * @param payoutTokenAddress The address of the token to receive the premiums in
    * @param oTokensToSell The number of oTokens to sell
    */
    function sellOTokens(
        address payable receiver,
        address oTokenAddress,
        address payoutTokenAddress,
        uint256 oTokensToSell
    ) public {
        // @note: first need to bootstrap the uniswap exchange to get the address.
        IERC20 oToken = IERC20(oTokenAddress);
        IERC20 payoutToken = IERC20(payoutTokenAddress);
        oToken.transferFrom(msg.sender, address(this), oTokensToSell);
        uniswapSellOToken(oToken, payoutToken, oTokensToSell, receiver);

        emit SellOTokens(
            msg.sender,
            receiver,
            oTokenAddress,
            payoutTokenAddress,
            oTokensToSell
        );
    }

    /**
    * @notice This function buys oTokens on Uniswap and using paymentTokens from the receiver
    * @param receiver The address to send the oTokens back to
    * @param oTokenAddress The address of the oToken to buy
    * @param paymentTokenAddress The address of the token to pay the premiums in
    * @param oTokensToBuy The number of oTokens to buy
    */
    function buyOTokens(
        address payable receiver,
        address oTokenAddress,
        address paymentTokenAddress,
        uint256 oTokensToBuy
    ) public payable {
        IERC20 oToken = IERC20(oTokenAddress);
        IERC20 paymentToken = IERC20(paymentTokenAddress);
        uniswapBuyOToken(paymentToken, oToken, oTokensToBuy, receiver);
    }

    /**
    * @notice This function calculates the amount of premiums that the seller
    * will receive if they sold oTokens on Uniswap
    * @param oTokenAddress The address of the oToken to sell
    * @param payoutTokenAddress The address of the token to receive the premiums in
    * @param oTokensToSell The number of oTokens to sell
    */
    function premiumReceived(
        address oTokenAddress,
        address payoutTokenAddress,
        uint256 oTokensToSell
    ) public view returns (uint256) {
        // get the amount of ETH that will be paid out if oTokensToSell is sold.
        UniswapExchangeInterface oTokenExchange = getExchange(oTokenAddress);
        uint256 ethReceived = oTokenExchange.getTokenToEthInputPrice(
            oTokensToSell
        );

        if (!isETH(IERC20(payoutTokenAddress))) {
            // get the amount of payout tokens that will be received if the ethRecieved is sold.
            UniswapExchangeInterface payoutExchange = getExchange(
                payoutTokenAddress
            );
            return payoutExchange.getEthToTokenInputPrice(ethReceived);
        }
        return ethReceived;

    }

    /**
    * @notice This function calculates the premiums to be paid if a buyer wants to
    * buy oTokens on Uniswap
    * @param oTokenAddress The address of the oToken to buy
    * @param paymentTokenAddress The address of the token to pay the premiums in
    * @param oTokensToBuy The number of oTokens to buy
    */
    function premiumToPay(
        address oTokenAddress,
        address paymentTokenAddress,
        uint256 oTokensToBuy
    ) public view returns (uint256) {
        // get the amount of ETH that needs to be paid for oTokensToBuy.
        UniswapExchangeInterface oTokenExchange = getExchange(oTokenAddress);
        uint256 ethToPay = oTokenExchange.getEthToTokenOutputPrice(
            oTokensToBuy
        );

        if (!isETH(IERC20(paymentTokenAddress))) {
            // get the amount of paymentTokens that needs to be paid to get the desired ethToPay.
            UniswapExchangeInterface paymentTokenExchange = getExchange(
                paymentTokenAddress
            );
            return paymentTokenExchange.getTokenToEthOutputPrice(ethToPay);
        }

        return ethToPay;
    }

    function uniswapSellOToken(
        IERC20 oToken,
        IERC20 payoutToken,
        uint256 _amt,
        address payable _transferTo
    ) internal returns (uint256) {
        require(!isETH(oToken), "Can only sell oTokens");
        UniswapExchangeInterface exchange = getExchange(address(oToken));

        if (isETH(payoutToken)) {
            //Token to ETH
            oToken.approve(address(exchange), _amt);
            return
                exchange.tokenToEthTransferInput(
                    _amt,
                    1,
                    LARGE_BLOCK_SIZE,
                    _transferTo
                );
        } else {
            //Token to Token
            oToken.approve(address(exchange), _amt);
            return
                exchange.tokenToTokenTransferInput(
                    _amt,
                    1,
                    1,
                    LARGE_BLOCK_SIZE,
                    _transferTo,
                    address(payoutToken)
                );
        }
    }

    function uniswapBuyOToken(
        IERC20 paymentToken,
        IERC20 oToken,
        uint256 _amt,
        address payable _transferTo
    ) public returns (uint256) {
        require(!isETH(oToken), "Can only buy oTokens");

        if (!isETH(paymentToken)) {
            UniswapExchangeInterface exchange = getExchange(
                address(paymentToken)
            );

            uint256 paymentTokensToTransfer = premiumToPay(
                address(oToken),
                address(paymentToken),
                _amt
            );
            paymentToken.transferFrom(
                msg.sender,
                address(this),
                paymentTokensToTransfer
            );

            // Token to Token
            paymentToken.approve(address(exchange), LARGE_APPROVAL_NUMBER);

            emit BuyOTokens(
                msg.sender,
                _transferTo,
                address(oToken),
                address(paymentToken),
                _amt,
                paymentTokensToTransfer
            );

            return
                exchange.tokenToTokenTransferInput(
                    paymentTokensToTransfer,
                    1,
                    1,
                    LARGE_BLOCK_SIZE,
                    _transferTo,
                    address(oToken)
                );
        } else {
            // ETH to Token
            UniswapExchangeInterface exchange = UniswapExchangeInterface(
                UNISWAP_FACTORY.getExchange(address(oToken))
            );

            uint256 ethToTransfer = exchange.getEthToTokenOutputPrice(_amt);

            require(msg.value == ethToTransfer, "Not enough ETH to buy");

            emit BuyOTokens(
                msg.sender,
                _transferTo,
                address(oToken),
                address(paymentToken),
                _amt,
                ethToTransfer
            );

            return
                exchange.ethToTokenTransferOutput.value(ethToTransfer)(
                    _amt,
                    LARGE_BLOCK_SIZE,
                    _transferTo
                );
        }
    }

    function getExchange(address _token)
        internal
        view
        returns (UniswapExchangeInterface)
    {
        UniswapExchangeInterface exchange = UniswapExchangeInterface(
            UNISWAP_FACTORY.getExchange(_token)
        );

        if (address(exchange) == address(0)) {
            revert("No payout exchange");
        }

        return exchange;
    }

    function isETH(IERC20 _ierc20) internal pure returns (bool) {
        return _ierc20 == IERC20(0);
    }

    function() external payable {
        // to get ether from uniswap exchanges
    }

}

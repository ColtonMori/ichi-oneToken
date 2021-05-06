// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../../interface/IOneTokenV1.sol";
import "../../_openzeppelin/token/ERC20/SafeERC20.sol";
import "./OneTokenV1Base.sol";

contract OneTokenV1 is IOneTokenV1, OneTokenV1Base {

    using AddressSet for AddressSet.Set;
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint public override mintingFee; // defaults to 0%
    uint public override redemptionFee; // defaults to 0%

    /**
     @notice withdrawals are delayed for at least one block (resist flash loan attacks)
     @dev collateral token => user => balance.
     */ 
    /*
    mapping(address => mapping(address => uint)) public override userBalances;
    mapping(address => mapping(address => uint)) public override userCreditBlocks;
    */

    /**
     @notice sum of userBalances for each collateral token are not counted in treasury valuations
     @dev token => liability
     */
    mapping(address => uint) public liabilities;

    event UserWithdrawal(address indexed sender, address indexed token, uint amount);
    event UserBalanceIncreased(address indexed user, address indexed token, uint amount);
    event UserBalanceDecreased(address indexed user, address indexed token, uint amount);    
    event Minted(address indexed sender, address indexed collateral, uint oneTokens, uint memberTokens, uint collateralTokens);
    event Redeemed(address indexed sender, address indexed collateral, uint amount);
    event NewMintingFee(address sender, uint fee);
    event NewRedemptionFee(address sender, uint fee);
    
    /// @dev there is no constructor for proxy deployment. Use init()

    /**
     @notice returns the available user balance in a given token
     @dev returns 0 if the balances was increased in this block
     @param user user to report
     @param token ERC20 asset to report
     */ 
    /*   
    function availableBalance(address user, address token) public view returns(uint) {
        uint userBlock = userCreditBlocks[token][user];
        // there is no case when userBlock is uninitialized and balance > 0
        if(userBlock < block.number) return userBalances[token][user];
        return 0;
    }
    */
    
    /**
     @notice transfers collateral tokens to the user
     @dev user withdrawals are delayed 1 block after any balance increase
     @param token ERC20 token to transfer
     @param amount amount to transfer
     */
    /*
    function withdraw(address token, uint amount) public override {
        require(isCollateral(token), "OTV1: token isn't COLLAT");
        require(amount > 0, "OTV1: amount must be > 0");
        require(amount <= availableBalance(msg.sender, token), "OTV1: INSUF funds");
        decreaseUserBalance(msg.sender, token, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
        emit UserWithdrawal(msg.sender, token, amount);
    }
    */

    /**
     @notice records collateral token liabilities owed to user, e.g. oneToken redemption
     @dev prevents any withdrawal of the token by the user for 1 block
     @param user user balance to adjust
     @param token ERC20 token
     @param amount amount of increase
     */   
    /* 
    function increaseUserBalance(address user, address token, uint amount) private {
        userBalances[token][user] = userBalances[token][user].add(amount);
        userCreditBlocks[token][user] = block.number;
        liabilities[token] = liabilities[token].add(amount);
        emit UserBalanceIncreased(user, token, amount);
    }
    */

    /**
     @notice reduces collateral token liabilities owed to user, e.g. withdrawal
     @dev does not prevent further withdrawals including same block
     @param user user balance to adjust
     @param token ERC20 token
     @param amount amount of decrease
     */
    /*
    function decreaseUserBalance(address user, address token, uint amount) private {
        userBalances[token][user] = userBalances[token][user].sub(amount, "OTV1: INSUF funds");
        liabilities[token] = liabilities[token].sub(amount);
        emit UserBalanceDecreased(user, token, amount);        
    }
    */

    /**
     @notice convert member tokens and collateral tokens into oneTokens. requires sufficient allowances for both tokens
     @dev takes the lessor of memberTokens allowance or the maximum allowed by the minting ratio and the balance in collateral
     @param collateralToken a registered ERC20 collateral token contract
     @param oneTokens exact number of oneTokens to receive
     */

    // TODO: precision
    function mint(address collateralToken, uint oneTokens) external initialized override {
        require(collateralTokenSet.exists(collateralToken), "OTV1: offer a COLLAT token");
        require(oneTokens > 0, "OTV1: order must be > 0");
        
        // update collateral oracle
        IOracle(assets[collateralToken].oracle).update(collateralToken);
        
        // this will also update the member token oracle price history
        (uint mintingRatio, uint maxOrderVolume) = updateMintingRatio(collateralToken);

        // future mintmasters may return a maximum order volume to tamp down on possible manipulation
        require(oneTokens <= maxOrderVolume, "OTV1: order exceeds max limit");

        // compute the member token value and collateral value requirement
        uint collateralUSDValue = oneTokens.mul(mintingRatio).div(PRECISION);
        uint memberTokensUSDValue = oneTokens.sub(collateralUSDValue);
        collateralUSDValue = collateralUSDValue.add(oneTokens.mul(mintingFee).div(PRECISION));

        // compute the member tokens required
        (uint memberTokensReq, /* volatility */) = IOracle(assets[memberToken].oracle).amountRequired(memberToken, memberTokensUSDValue);

        // check the memberToken allowance - the maximum we can draw from the user
        uint memberTokenAllowance = IERC20(memberToken).allowance(msg.sender, address(this));

        // increase collateral required if the memberToken allowance is too low
        if(memberTokensReq > memberTokenAllowance) {
            uint memberTokenRate = memberTokensUSDValue.mul(PRECISION).div(memberTokensReq);
            memberTokensReq = memberTokenAllowance;
            // re-evaluate the memberToken value and collateral value required using the oracle rate already obtained
            memberTokensUSDValue = memberTokenRate.mul(memberTokensReq).div(PRECISION);
            collateralUSDValue = oneTokens.sub(memberTokensUSDValue);
            collateralUSDValue = collateralUSDValue.add(oneTokens.mul(mintingFee).div(PRECISION));
        }

        require(IERC20(memberToken).balanceOf(msg.sender) >= memberTokensReq, "OTV1: INSUF MEM token balance");

        // compute actual collateral tokens required in case of imperfect collateral pegs
        // a pegged oracle can be used to reduce the cost of this step but it will not account for price differences
        (uint collateralTokensReq, /* volatility */) = IOracle(assets[collateralToken].oracle).amountRequired(collateralToken, collateralUSDValue);

        // draw from available user balance if possible
        /*
        uint userCollateralBalance = availableBalance(msg.sender, collateralToken);
        uint collateralFromBalance = (collateralTokensReq <= userCollateralBalance) ? 
            collateralTokensReq : userCollateralBalance;
        if(collateralFromBalance > 0) {
            decreaseUserBalance(msg.sender, collateralToken, collateralFromBalance);
        }
        */

        // uint collateralTokensToTransfer = collateralTokensReq.sub(collateralFromBalance);
        require(IERC20(collateralToken).balanceOf(msg.sender) >= collateralTokensReq, "OTV1: INSUF COLLAT token balance");

        // transfer tokens in
        IERC20(memberToken).safeTransferFrom(msg.sender, address(this), memberTokensReq);
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralTokensReq);
        
        // mint oneTokens
        _mint(msg.sender, oneTokens);

        /// avoiding the controller reduces transaction cost for minting
        // IController(controller).periodic();

        emit Minted(msg.sender, collateralToken, oneTokens, memberTokensReq, collateralTokensReq);
    }

    /**
     @notice redeem oneTokens for collateral tokens - applies fee %
     @dev first grant allowances, then redeem. Consider infinite collateral and a sufficient memberToken allowance.
     @param collateral form of ERC20 stable token to receive
     @param amount oneTokens to redeem equals collateral tokens to receive
     */

    // TODO - precision

    function redeem(address collateral, uint amount) external override {
        require(isCollateral(collateral), "OTV1: unrecognized COLLAT");
        IOracle(assets[collateral].oracle).update(collateral);
        // implied transfer approval and allowance
        // transferFrom(msg.sender, address(this), amount);
        _transfer(msg.sender, address(this), amount);
        uint netTokens = amount.sub(amount.mul(redemptionFee).div(PRECISION));
        // increaseUserBalance(msg.sender, collateral, netTokens);
        IERC20(collateral).safeTransfer(msg.sender, netTokens);
        emit Redeemed(msg.sender, collateral, amount);
        // updates the oracle price history for oneToken, only
        updateMintingRatio(collateral);
        IController(controller).periodic();
    }

    /**
     @notice governance sets the adjustable fee
     @param fee fee, 18 decimals, e.g. 2% = 0020000000000000000
     */
    function setMintingFee(uint fee) external onlyOwner override {
        require(fee <= PRECISION, "OTV1: fee must be <= 100%");
        mintingFee = fee;
        emit NewMintingFee(msg.sender, fee);
    }

    /**
     @notice governance sets the adjustable fee
     @param fee fee, 18 decimals, e.g. 2% = 0020000000000000000
     */
    function setRedemptionFee(uint fee) external onlyOwner override {
        require(fee <= PRECISION, "OTV1: fee must be <= 100%");
        redemptionFee = fee;
        emit NewRedemptionFee(msg.sender, fee);
    }    

    /**
     @notice adjust the minting ratio
     @dev acceptable for gas-paying external actors to call this function
     */
    function updateMintingRatio(address collateralToken) public override returns(uint ratio, uint maxOrderVolume) {
        return IMintMaster(mintMaster).updateMintingRatio(collateralToken);
    }

    /**
     @notice read the minting ratio and maximum order volume prescribed by the mintMaster
     @param collateralToken token to use for ratio calculation
     */
    function getMintingRatio(address collateralToken) external view override returns(uint ratio, uint maxOrderVolume) {
        return IMintMaster(mintMaster).getMintingRatio(collateralToken);
    }

    /**
     @notice read the vault balance and strategy balance of a given token
     @dev not restricted to registered assets
     @param token ERC20 asset to report
     */
    function getHoldings(address token) external view override returns(uint vaultBalance, uint strategyBalance) {   
        IERC20 t = IERC20(token);
        vaultBalance = t.balanceOf(address(this));
        Asset storage a = assets[token];
        if(a.strategy != NULL_ADDRESS) strategyBalance = t.balanceOf(a.strategy);
    } 
}

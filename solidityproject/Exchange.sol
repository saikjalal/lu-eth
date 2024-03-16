// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Exchange {

    IERC20 public immutable token;

    //reserve
    uint public contractERC20TokenBalance;
    uint public contractEthBalance;

    //supply
    uint public totalLiquidityPositions;
    mapping(address => uint) public liquidityPositions;

    /* K
    K is updated whenever liquidity is provided or withdrawn. 
    We will use this to calculate the amount of tokens to give a user when they swap one token for another.
    */
    uint public K;

    //constructor
    constructor(address _token) {
        token = IERC20(_token);
    }

    receive() external payable {}

    // Helper function to update contract balances
    function _updateBalances(uint _newERC20TokenBalance, uint _newEthBalance) private {
        contractERC20TokenBalance = _newERC20TokenBalance;
        contractEthBalance = _newEthBalance;
    }

    //events
    event LiquidityProvided(uint amountERC20TokenDeposited, uint amountEthDeposited, uint liquidityPositionsIssued);
    event LiquidityWithdrew(uint amountERC20TokenWithdrew, uint amountEthWithdrew, uint liquidityPositionsBurned);
    event SwapForEth(uint amountERC20TokenDeposited, uint amountEthWithdrew);
    event SwapForERC20Token(uint amountERC20TokenWithdrew, uint amountEthDeposited);

    //provideLiquidity
    /*
    – Caller deposits Ether and ERC20 token in ratio equal to the current ratio of tokens in the contract
    and receives liquidity positions (that is:
    totalLiquidityPositions * amountERC20Token/contractERC20TokenBalance == totalLiquidityPositions *amountEth/contractEthBalance)
    – Transfer Ether and ERC-20 tokens from caller into contract
    – If caller is the first to provide liquidity, give them 100 liquidity positions
    – Otherwise, give them liquidityPositions = totalLiquidityPositions * amountERC20Token / contractERC20TokenBalance
    – Update K: K = newContractEthBalance * newContractERC20TokenBalance
    – Return a uint of the amount of liquidity positions issued
    */
    function provideLiquidity(uint _amountERC20Token) public payable returns (uint){

        // Calculate liquidity provided and amount of eth to send
        uint _liquidityProvided;
        uint _amountEth;
        // If caller is the first to provide liquidity, give them 100 liquidity positions
        if (totalLiquidityPositions == 0) {
            _liquidityProvided = 100;
            _amountEth = msg.value;
        // Otherwise, give them liquidityPositions = totalLiquidityPositions * amountERC20Token / contractERC20TokenBalance
        } else {
            _liquidityProvided = totalLiquidityPositions * _amountERC20Token / contractERC20TokenBalance;
            _amountEth = contractEthBalance * _amountERC20Token / contractERC20TokenBalance;
        }

        // Transfer Ether and ERC20 tokens from caller into contract
        token.transferFrom(msg.sender, address(this), _amountERC20Token);
        (bool sent, ) = payable(address(this)).call{value: _amountEth}("");
        require(sent, "Failed to send Ether");

        // Update caller liquidityPositions
        liquidityPositions[msg.sender] += _liquidityProvided;

        // Update totalLiquidityPositions
        totalLiquidityPositions += _liquidityProvided;

        // Update contract balances
        contractERC20TokenBalance += _amountERC20Token;
        contractEthBalance += _amountEth;

        // Update K
        K = contractEthBalance * contractERC20TokenBalance;

        // Emit LiquidityProvided event
        emit LiquidityProvided(_amountERC20Token, _amountEth, _liquidityProvided);

        // Return amount of liquidity positions issued
        return _liquidityProvided;
    }


    //estimateEthToProvide
    /*
    – Users who want to provide liquidity won’t know the current ratio of the tokens in the contract so
    they’ll have to call this function to find out how much Ether to deposit if they want to deposit a
    particular amount of ERC-20 tokens.
    – Return a uint of the amount of Ether to provide to match the ratio in the contract if caller wants
    to provide a given amount of ERC20 tokens
    Use the above to get amountEth =
    contractEthBalance * amountERC20Token / contractERC20TokenBalance) 
    */
    function estimateEthToProvide(uint _amountERC20Token) public view returns (uint) {
        require(contractERC20TokenBalance > 0, "contractERC20TokenBalance = 0");
        return contractEthBalance * _amountERC20Token / contractERC20TokenBalance;
    }

    //estimateERC20TokenToProvide
    /*
    – Users who want to provide liquidity won’t know the current ratio of the tokens in the contract so
    they’ll have to call this function to find out how much ERC-20 token to deposit if they want to
    deposit an amount of Ether
    – Return a uint of the amount of ERC20 token to provide to match the ratio in the contract if the
    caller wants to provide a given amount of Ether
    Use the above to get amountERC20 = contractERC20TokenBalance * amountEth/contractEthBalance)
    */
    function estimateERC20TokenToProvide(uint _amountEth) public view returns (uint) {
        require(contractEthBalance > 0, "contractEthBalance = 0");
        return contractERC20TokenBalance * _amountEth / contractEthBalance;
    }

    //getMyLiquidityPositions
    /*
    – Return a uint of the amount of the caller’s liquidity positions (the uint associated to the address
    calling in your liquidityPositions mapping) for when a user wishes to view their liquidity positions
    */
    function getMyLiquidityPositions() public view returns (uint) {
        return liquidityPositions[msg.sender];
    }

    //withdrawLiquidity
    /*
    – Caller gives up some of their liquidity positions and receives some Ether and ERC20 tokens in
    return.
    Use the above to get
    amountEthToSend = liquidityPositionsToBurn*contractEthBalance / totalLiquidityPositions
    and
    amountERC20ToSend =
    liquidityPositionsToBurn * contractERC20TokenBalance / totalLiquidityPositions
    – Decrement the caller’s liquidity positions and the total liquidity positions
    – Caller shouldn’t be able to give up more liquidity positions than they own
    – Caller shouldn’t be able to give up all the liquidity positions in the pool
    – Update K: K = newContractEthBalance * newContractERC20TokenBalance
    – Transfer Ether and ERC-20 from contract to caller
    – Return 2 uints, the amount of ERC20 tokens sent and the amount of Ether sent
    */
    function withdrawLiquidity(uint _liquidityPositionsToBurn) public returns (uint, uint){

        // Calculate Ether and ERC20 tokens to send to caller
        uint amountERC20ToSend = _liquidityPositionsToBurn * contractERC20TokenBalance / totalLiquidityPositions;
        uint amountEthToSend = _liquidityPositionsToBurn * contractEthBalance / totalLiquidityPositions;

        // Caller can't give up more liquidity than they own
        require(_liquidityPositionsToBurn <= liquidityPositions[msg.sender], "Can't give up more liquidity positions than you own");
        // Caller can't give up all the liquidity in the pool
        require(_liquidityPositionsToBurn < totalLiquidityPositions, "Can't give up all the liquidity positions in the pool");
        
        // Decrement caller liquidity and total liquidity
        liquidityPositions[msg.sender] -= _liquidityPositionsToBurn;
        totalLiquidityPositions -= _liquidityPositionsToBurn;

        // Transfer Ether and ERC20 from contract to caller
        token.transfer(msg.sender, amountERC20ToSend);
        (bool sent, ) = payable(msg.sender).call{value: amountEthToSend}("");
        require(sent, "failed to send Ether");

        // Update contract balances
        contractERC20TokenBalance -= amountERC20ToSend;
        contractEthBalance -= amountEthToSend;

        // Update K
        K = contractEthBalance * contractERC20TokenBalance;

        //event LiquidityWithdrew(uint amountERC20TokenWithdrew, uint amountEthWithdrew, uint liquidityPositionsBurned);
        // Emit LiquidityWithdrew event
        emit LiquidityWithdrew(amountERC20ToSend, amountEthToSend , _liquidityPositionsToBurn);

        // Return amount of ERC20 tokens sent and amount of Ether sent
        return (amountERC20ToSend, amountEthToSend);
    }

    //swapForEth
    // – Caller deposits some ERC20 token in return for some Ether
    // – hint: ethToSend = contractEthBalance - contractEthBalanceAfterSwap
    // where contractEthBalanceAfterSwap = K / contractERC20TokenBalanceAfterSwap
    // – Transfer ERC-20 tokens from caller to contract
    // – Transfer Ether from contract to caller
    // – Return a uint of the amount of Ether sent
    function swapForEth(uint _amountERC20Token) public returns (uint) {
        // require balances > 0 before swap?
        uint contractERC20TokenBalanceAfterSwap = contractERC20TokenBalance + _amountERC20Token;
        uint contractEthBalanceAfterSwap = K / contractERC20TokenBalanceAfterSwap;
        uint ethToSend = contractEthBalance - contractEthBalanceAfterSwap;
        // Transfer ERC20 tokens from caller to contract
        token.transferFrom(msg.sender, address(this), _amountERC20Token);
        // Transfer Ether from contract to caller
        (bool sent, ) = payable(msg.sender).call{value: ethToSend}("");
        require(sent, "failed to send Ether");
        // Update contract balances
        contractERC20TokenBalance = contractERC20TokenBalanceAfterSwap;
        contractEthBalance = contractEthBalanceAfterSwap;
        // Emit SwapForEth event
        emit SwapForEth(_amountERC20Token, ethToSend);
        // Return amount of Ether sent
        return ethToSend;
    }

    //estimateSwapForEth
    // – estimates the amount of Ether to give caller based on amount ERC20 token caller wishes to swap
    // for when a user wants to know how much Ether to expect when calling swapForEth
    // – hint: ethToSend = contractEthBalance-contractEthBalanceAfterSwap where contractEthBalanceAfterSwap = K/contractERC20TokenBalanceAfterSwap
    // – Return a uint of the amount of Ether caller would receive
    function estimateSwapForEth(uint _amountERC20Token) public view returns (uint) {
        uint contractERC20TokenBalanceAfterSwap = contractERC20TokenBalance + _amountERC20Token;
        uint contractEthBalanceAfterSwap = K / contractERC20TokenBalanceAfterSwap;
        uint ethToSend = contractEthBalance - contractEthBalanceAfterSwap;
        return ethToSend;
    }

    //swapForERC20Token
    // – Caller deposits some Ether in return for some ERC20 tokens
    // – hint: ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap
    // where contractERC20TokenBalanceAfterSwap = K /contractEthBalanceAfterSwap
    // – Transfer Ether from caller to contract
    // – Transfer ERC-20 tokens from contract to caller
    // – Return a uint of the amount of ERC20 tokens sent
    function swapForERC20Token() public payable returns (uint) {
        uint _amountEth = msg.value;
        require(_amountEth > 0, "Eth msg.value = 0");
        // require balances > 0 before swap?
        uint contractEthBalanceAfterSwap = contractEthBalance + _amountEth;
        uint contractERC20TokenBalanceAfterSwap = K / contractEthBalanceAfterSwap;
        uint ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap;
        // Transfer Ether from caller to contract
        (bool sent, ) = payable(address(this)).call{value: _amountEth}("");
        require(sent, "Failed to send Ether");
        // Transfer ERC20 tokens from contract to caller
        token.transfer(msg.sender, ERC20TokenToSend);
        // Update contract balances
        contractERC20TokenBalance = contractERC20TokenBalanceAfterSwap;
        contractEthBalance = contractEthBalanceAfterSwap;
        // Emit SwapForERC20Token event
        emit SwapForERC20Token(ERC20TokenToSend, _amountEth);
        // Return amount of ERC20 tokens sent
        return ERC20TokenToSend;
    }

    //estimateSwapForERC20Token
    // – estimates the amount of ERC20 token to give caller based on amount Ether caller wishes to
    // swap for when a user wants to know how many ERC-20 tokens to expect when calling swapForERC20Token
    // – hint: ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap
    // where contractERC20TokenBalanceAfterSwap = K /contractEthBalanceAfterSwap
    // – Return a uint of the amount of ERC20 tokens caller would receive
    function estimateSwapForERC20Token(uint _amountEth) public view returns (uint) {
        uint contractEthBalanceAfterSwap = contractEthBalance + _amountEth;
        uint contractERC20TokenBalanceAfterSwap = K / contractEthBalanceAfterSwap;
        uint ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap;
        return ERC20TokenToSend;
    }

}
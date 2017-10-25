pragma solidity ^0.4.18;
/*
    Copyright 2017, Jordi Baylina

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/


/// @dev This declares a few functions from `Vault` so that the
///  `WithdrawContract` can interface with the `MiniMeToken`
contract MiniMeToken {
    function balanceOfAt(address _owner, uint _blockNumber) public constant returns (uint);
    function totalSupplyAt(uint _blockNumber) public constant returns(uint);
}

import "../node_modules/giveth-common-contracts/contracts/ERC20.sol";
import "../node_modules/giveth-common-contracts/contracts/Escapable.sol";

/// @dev This is the main contract, it is intended to distribute deposited funds 
///  from a TRUSTED `owner` to token holders of a MiniMe style ERC-20 Token;
///  only deposits from the `owner` using the functions `newTokenPayment()` &
///  `newEtherPayment()` will be distributed, any other funds sent to this
///  contract can only be removed via the `escapeHatch()`
contract WithdrawContract is Escapable {

    /// @dev Tracks the deposits made to this contract
    struct Payment {
        uint block;    // Determines which token holders are able to collect
        ERC20 token;   // The token address (0x0 if ether)
        uint amount;   // The amount deposited in the smallest unit (wei if ETH)
        bool canceled; // True if canceled by the `owner`
    }

    Payment[] public payments; // Array of deposits to this contract
    MiniMeToken distToken;     // Token that is used for withdraws

    mapping (address => uint) public nextRefundToPay; // Tracks Payouts 
    mapping (address => mapping(uint => bool)) skipPayments;

/////////
// Constructor
/////////

    /// @notice The Constructor creates the `WithdrawContract` on the blockchain
    ///  the `owner` role is assigned to the address that deploys this contract
    /// @param _distToken The address of the token that is used to determine the
    ///  distribution of the deposits according to the balance held at the
    ///  deposit's specified `block` 
    /// @param _escapeHatchCaller The address of a trusted account or contract
    ///  to call `escapeHatch()` to send the specified token (or ether) held in
    ///  this contract to the `escapeHatchDestination`
    /// @param _escapeHatchDestination The address of a safe location (usu a
    ///  Multisig) to send the ether and tokens held in this contract when the
    ///  `escapeHatch()` is called
    function WithdrawContract(
        MiniMeToken _distToken,
        address _escapeHatchCaller,
        address _escapeHatchDestination) // TODO: should this `)` be on the next line?
        Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        distToken = _distToken;
    }

    /// @dev When ether is sent to this contract `newEtherPayment()` is called
    function () payable public {
        newEtherPayment(0);
    }
/////////
// Owner Functions
/////////

    /// @notice Adds an ether deposit to `deposits[]`; only the `owner` can
    ///  deposit into this contract 
    /// @param _block The block height that determines the snapshot of token
    ///  holders that will be able to withdraw their share of this deposit; this
    ///  block must be set in the past, if 0 it defaults to one block before the
    ///  transaction 
    /// @return _idPayment The id number for the deposit
    function newEtherPayment(uint _block) public onlyOwner payable returns (uint _idPayment) {// TODO conform to 80 char
        require(msg.value>0);
        require(_block < block.number);
        _idPayment = payments.length ++;

        // Record the deposit 
        Payment storage payment = payments[_idPayment];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = ERC20(0);
        payment.amount = msg.value;
        NewPayment(_idPayment, ERC20(0), msg.value);
    }

    /// @notice Adds a token deposit to `deposits[]`; only the `owner` can
    ///  call this function and it will only work if the account sending the 
    ///  tokens has called `approve()` so that this contract can call
    ///  `transferFrom()` and take the tokens
    /// @param _token The address for the ERC20 that is being deposited 
    /// @param _amount The quantity of tokens that is deposited into the
    ///  contract in the smallest unit of tokens (if a token has its decimals
    ///  set to 18 and 1 token is sent, the `_amount` would be 10^18)
    /// @param _block The block height that determines the snapshot of token
    ///  holders that will be able to withdraw their share of this deposit; this
    ///  block must be set in the past, if 0 it defaults to one block before the
    ///  transaction 
    /// @return _idPayment The id number for the deposit
    function newTokenPayment(ERC20 _token, uint _amount, uint _block) public onlyOwner returns (uint _idPayment) {// TODO conform to 80 char
        require(_amount > 0);
        require(_block < block.number);

        // Must `approve()` this contract in a previous transaction
        require( _token.transferFrom(msg.sender, address(this), _amount) );
        _idPayment = payments.length ++;

        // Record the deposit 
        Payment storage payment = payments[_idPayment];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = _token;
        payment.amount = _amount;
        NewPayment(_idPayment, _token, _amount);
    }
    /// @notice This function is a failsafe function in case a token is
    ///  deposited that has an issue that could prevent it's withdraw (e.g.
    ///  transfers are disabled), can only be called by the `owner`
    /// @param _idPayment The id number for the deposit being canceled
    function cancelPaymentGlobally(uint _idPayment) public onlyOwner {
        require(_idPayment < payments.length);
        payments[_idPayment].canceled = true;
        CancelPaymentGlobally(_idPayment);
    }

/////////
// Public Functions
/////////
    /// @notice Sends all the tokens and ether to the token holder by looping
    ///  through all the deposits, determining the appropriate amount by
    ///  dividing the `totalSupply` by the number of tokens the token holder had
    ///  at `deposit.block` for each deposit; this function may have to be
    ///  called multiple times if their are many deposits  
    function withdraw() public {
        uint acc = 0; // Counts the amount of tokens/ether to be sent
        ERC20 currentToken = ERC20(0x0); // Sets the `currentToken` to ether
        uint i = nextRefundToPay[msg.sender]; // Iterates through the deposits

        require(msg.gas>149000); // Checks there is enough gas to make the send
        while (( i< payments.length) && ( msg.gas > 148000)) { // TODO Adjust the minimum to a lower value
            Payment storage payment = payments[i];

            // Make sure `deposit[i]` shouldn't be skipped
            if ((!payment.canceled)&&(!isPaymentSkiped(msg.sender, i))) {
                
                // This makes the withdraw after it accumulated all the
                // consecutive deposits of the same token
                if (currentToken != payment.token) {
                    nextRefundToPay[msg.sender] = i;
                    require(doPayment(i-1, msg.sender, currentToken, acc));
                    assert(nextRefundToPay[msg.sender] == i)
                    currentToken = payment.token;
                    acc =0;
                }

                // Accumulate the amount to send for the `currentToken`
                acc +=  payment.amount *
                        distToken.balanceOfAt(msg.sender, payment.block) /
                            distToken.totalSupplyAt(payment.block);
            }

            i++; // Next deposit :-D 
        }
        // If there is not enough gas, do one last payment
        nextRefundToPay[msg.sender] = i;
        require(doPayment(i-1, msg.sender, currentToken, acc));
        assert(nextRefundToPay[msg.sender] == i)
    }

    /// @notice This function is a failsafe function in case a token holder
    ///  wants to skip a payment, can only be applied to one deposit at a time
    ///  and only affects the payment for the `msg.sender` calling the function;
    ///  can be undone by calling again with `skip == false` 
    /// @param _idPayment The id number for the deposit being canceled
    /// @param _skip True if the caller wants to skip the payment for `idDeposit`
    function skipPayment(uint _idPayment, bool _skip) public {
        require(_idPayment < payments.length);
        skipPayments[msg.sender][_idPayment] = _skip;
    }

/////////
// Constant Functions
/////////

    /// @notice Calculates the amount of a given token (or ether) the holder can
    ///  receive 
    /// @param token The address of the token being queried, 0x0 = ether
    /// @param holder The address being checked 
    /// @return The amount of `token` able to be collected in the smallest
    ///  unit of the `token` (wei for ether)
    function getPendingReward(ERC20 _token, address _holder) public constant returns(uint) {
        uint acc =0;
        for (uint i=nextRefundToPay[msg.sender]; i<payments.length; i++) {
            Payment storage payment = payments[i];
            if ((payment.token == _token)&&(!payment.canceled) && (!isPaymentSkiped(_holder, i))) {
                acc +=  payment.amount *
                    distToken.balanceOfAt(_holder, payment.block) /
                        distToken.totalSupplyAt(payment.block);
            }
        }
        return acc;
    }

    /// @notice A check to see if a specific address has anything to collect
    /// @param holder The address being checked for available payments
    /// @return True if there are payments to be collected
    function hasFundsAvailable(address _holder) constant returns (bool) {
        return nextRefundToPay[_holder] < payments.length;
    }

    /// @notice Checks how many deposits have been made
    /// @return The number of deposits
    function nPayments() constant returns (uint) {
        return payments.length;
    }

    /// @notice Checks to see if a specific deposit has been skipped
    /// @param holder The address being checked for available payments
    /// @param idPayment The id number for the deposit being canceled
    /// @return True if the specified deposit has been skipped
    function isPaymentSkiped(address _holder, uint _idPayment) constant returns(bool) {
        return skipPayments[_holder][_idPayment];
    }

/////////
// Internal Functions
/////////

    /// @notice Transfers `amount` of `token` to `dest`, only used internally,
    ///  and does not throw, will always return `true` or `false`
    /// @param token The address for the ERC20 that is being transferred
    /// @param dest The destination address of the transfer
    /// @param amount The quantity of tokens that is being transferred
    ///  denominated in the smallest unit of tokens (if a token has its decimals
    ///  set to 18 and 1 token is being transferred the `amount` would be 10^18)
    /// @return True if the payment succeeded 
    function doPayment(uint _idPayment,  address _dest, ERC20 _token, uint _amount) internal returns (bool) {
        if (_amount == 0) return true;
        if (address(_token) == 0) {
            if (!_dest.send(_amount)) return false;   // If we can't send, we continue...
        } else {
            if (!_token.transfer(_dest, _amount)) return false;
        }
        Withdraw(_idPayment, _dest, _token, _amount);
        return true;
    }

    function getBalance(ERC20 _token, address _holder) internal constant returns (uint) {
        if (address(_token) == 0) {
            return _holder.balance;
        } else {
            return _token.balanceOf(_holder);
        }
    }

/////////
// Events
/////////

    event Withdraw(uint indexed lastIdPayment, address indexed tokenHolder, ERC20 indexed tokenContract, uint amount);
    event NewPayment(uint indexed idPayment, ERC20 indexed tokenContract, uint amount);
    event CancelPaymentGlobally(uint indexed idPayment);
}

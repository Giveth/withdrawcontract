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


/// @dev This declares a few functions from `MiniMeToken` so that the
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
    struct Deposit {
        uint block;    // Determines which token holders are able to collect
        ERC20 token;   // The token address (0x0 if ether)
        uint amount;   // The amount deposited in the smallest unit (wei if ETH)
        bool canceled; // True if canceled by the `owner`
    }

    Deposit[] public deposits; // Array of deposits to this contract
    MiniMeToken rewardToken;     // Token that is used for withdraws

    mapping (address => uint) public nextDepositToPayout; // Tracks Payouts
    mapping (address => mapping(uint => bool)) skipDeposits;

/////////
// Constructor
/////////

    /// @notice The Constructor creates the `WithdrawContract` on the blockchain
    ///  the `owner` role is assigned to the address that deploys this contract
    /// @param _rewardToken The address of the token that is used to determine the
    ///  distribution of the deposits according to the balance held at the
    ///  deposit's specified `block`
    /// @param _escapeHatchCaller The address of a trusted account or contract
    ///  to call `escapeHatch()` to send the specified token (or ether) held in
    ///  this contract to the `escapeHatchDestination`
    /// @param _escapeHatchDestination The address of a safe location (usu a
    ///  Multisig) to send the ether and tokens held in this contract when the
    ///  `escapeHatch()` is called
    function WithdrawContract(
        MiniMeToken _rewardToken,
        address _escapeHatchCaller,
        address _escapeHatchDestination)
        Escapable(_escapeHatchCaller, _escapeHatchDestination)
        public
    {
        rewardToken = _rewardToken;
    }

    /// @dev When ether is sent to this contract `newEtherDeposit()` is called
    function () payable public {
        newEtherDeposit(0);
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
    /// @return _idDeposit The id number for the deposit
    function newEtherDeposit(uint _block)
        public onlyOwner payable
        returns (uint _idDeposit)
    {
        require(msg.value>0);
        require(_block < block.number);
        _idDeposit = deposits.length ++;

        // Record the deposit
        Deposit storage d = deposits[_idDeposit];
        d.block = _block == 0 ? block.number -1 : _block;
        d.token = ERC20(0);
        d.amount = msg.value;
        NewDeposit(_idDeposit, ERC20(0), msg.value);
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
    /// @return _idDeposit The id number for the deposit
    function newTokenDeposit(ERC20 _token, uint _amount, uint _block)
        public onlyOwner
        returns (uint _idDeposit)
    {
        require(_amount > 0);
        require(_block < block.number);

        // Must `approve()` this contract in a previous transaction
        require( _token.transferFrom(msg.sender, address(this), _amount) );
        _idDeposit = deposits.length ++;

        // Record the deposit
        Deposit storage d = deposits[_idDeposit];
        d.block = _block == 0 ? block.number -1 : _block;
        d.token = _token;
        d.amount = _amount;
        NewDeposit(_idDeposit, _token, _amount);
    }

    /// @notice This function is a failsafe function in case a token is
    ///  deposited that has an issue that could prevent it's withdraw loop break
    ///  (e.g. transfers are disabled), can only be called by the `owner`
    /// @param _idDeposit The id number for the deposit being canceled
    function cancelPaymentGlobally(uint _idDeposit) public onlyOwner {
        require(_idDeposit < deposits.length);
        deposits[_idDeposit].canceled = true;
        CancelPaymentGlobally(_idDeposit);
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
        uint acc = 0; // Accumulates the amount of tokens/ether to be sent
        ERC20 currentToken = ERC20(0x0); // Sets the `currentToken` to ether
        uint i = nextDepositToPayout[msg.sender]; // Iterates through the deposits

        require(msg.gas>149000); // Throws if there is no gas to do at least a single transfer.
        while (( i< deposits.length) && ( msg.gas > 148000)) {
            Deposit storage d = deposits[i];

            // Make sure `deposit[i]` shouldn't be skipped
            if ((!d.canceled)&&(!isDepositSkiped(msg.sender, i))) {

                // The current diposti is different of the accumulated until now,
                // so we return the accumulated tokens until now and resset the
                // accumulator.
                if (currentToken != d.token) {
                    nextDepositToPayout[msg.sender] = i;
                    require(doPayment(i-1, msg.sender, currentToken, acc));
                    assert(nextDepositToPayout[msg.sender] == i);
                    currentToken = d.token;
                    acc =0;
                }

                // Accumulate the amount to send for the `currentToken`
                acc +=  d.amount *
                        rewardToken.balanceOfAt(msg.sender, d.block) /
                            rewardToken.totalSupplyAt(d.block);
            }

            i++; // Next deposit :-D
        }
        // Return the accumulated tokens.
        nextDepositToPayout[msg.sender] = i;
        require(doPayment(i-1, msg.sender, currentToken, acc));
        assert(nextDepositToPayout[msg.sender] == i);
    }

    /// @notice This function is a failsafe function in case a token holder
    ///  wants to skip a payment, can only be applied to one deposit at a time
    ///  and only affects the payment for the `msg.sender` calling the function;
    ///  can be undone by calling again with `skip == false`
    /// @param _idDeposit The id number for the deposit being canceled
    /// @param _skip True if the caller wants to skip the payment for `idDeposit`
    function skipPayment(uint _idDeposit, bool _skip) public {
        require(_idDeposit < deposits.length);
        skipDeposits[msg.sender][_idDeposit] = _skip;
        SkipPayment(_idDeposit, _skip);
    }

/////////
// Constant Functions
/////////

    /// @notice Calculates the amount of a given token (or ether) the holder can
    ///  receive
    /// @param _token The address of the token being queried, 0x0 = ether
    /// @param _holder The address being checked
    /// @return The amount of `token` able to be collected in the smallest
    ///  unit of the `token` (wei for ether)
    function getPendingReward(ERC20 _token, address _holder) public constant returns(uint) {
        uint acc =0;
        for (uint i=nextDepositToPayout[msg.sender]; i<deposits.length; i++) {
            Deposit storage d = deposits[i];
            if ((d.token == _token)&&(!d.canceled) && (!isDepositSkiped(_holder, i))) {
                acc +=  d.amount *
                    rewardToken.balanceOfAt(_holder, d.block) /
                        rewardToken.totalSupplyAt(d.block);
            }
        }
        return acc;
    }

    /// @notice A check to see if a specific address has anything to collect
    /// @param _holder The address being checked for available deposits
    /// @return True if there are payments to be collected
    function canWithdraw(address _holder) public constant returns (bool) {
        if (nextDepositToPayout[_holder] == deposits.length) return false;
        for (uint i=nextDepositToPayout[msg.sender]; i<deposits.length; i++) {
            Deposit storage d = deposits[i];
            if ((!d.canceled) && (!isDepositSkiped(_holder, i))) {
                uint amount =  d.amount *
                    rewardToken.balanceOfAt(_holder, d.block) /
                        rewardToken.totalSupplyAt(d.block);
                if (amount>0) return true;
            }
        }
        return false;
    }

    /// @notice Checks how many deposits have been made
    /// @return The number of deposits
    function nDeposits() public constant returns (uint) {
        return deposits.length;
    }

    /// @notice Checks to see if a specific deposit has been skipped
    /// @param _holder The address being checked for available deposits
    /// @param _idDeposit The id number for the deposit being canceled
    /// @return True if the specified deposit has been skipped
    function isDepositSkiped(address _holder, uint _idDeposit) public constant returns(bool) {
        return skipDeposits[_holder][_idDeposit];
    }

/////////
// Internal Functions
/////////

    /// @notice Transfers `amount` of `token` to `dest`, only used internally,
    ///  and does not throw, will always return `true` or `false`
    /// @param _token The address for the ERC20 that is being transferred
    /// @param _dest The destination address of the transfer
    /// @param _amount The quantity of tokens that is being transferred
    ///  denominated in the smallest unit of tokens (if a token has its decimals
    ///  set to 18 and 1 token is being transferred the `amount` would be 10^18)
    /// @return True if the payment succeeded
    function doPayment(uint _idDeposit,  address _dest, ERC20 _token, uint _amount) internal returns (bool) {
        if (_amount == 0) return true;
        if (address(_token) == 0) {
            if (!_dest.send(_amount)) return false;   // If we can't send, we continue...
        } else {
            if (!_token.transfer(_dest, _amount)) return false;
        }
        Withdraw(_idDeposit, _dest, _token, _amount);
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

    event Withdraw(uint indexed lastIdPayment, address indexed holder, ERC20 indexed tokenContract, uint amount);
    event NewDeposit(uint indexed idDeposit, ERC20 indexed tokenContract, uint amount);
    event CancelPaymentGlobally(uint indexed idDeposit);
    event SkipPayment(uint indexed idDeposit, bool skip);
}

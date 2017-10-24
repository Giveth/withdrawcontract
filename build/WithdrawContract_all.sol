
//File: node_modules/giveth-common-contracts/contracts/ERC20.sol
pragma solidity ^0.4.15;


/**
 * @title ERC20
 * @dev A standard interface for tokens.
 * @dev https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
 */
contract ERC20 {
  
    /// @dev Returns the total token supply.
    function totalSupply() public constant returns (uint256 supply);

    /// @dev Returns the account balance of another account with address _owner.
    function balanceOf(address _owner) public constant returns (uint256 balance);

    /// @dev Transfers _value amount of tokens to address _to
    function transfer(address _to, uint256 _value) public returns (bool success);

    /// @dev Transfers _value amount of tokens from address _from to address _to
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    /// @dev Allows _spender to withdraw from your account multiple times, up to the _value amount
    function approve(address _spender, uint256 _value) public returns (bool success);

    /// @dev Returns the amount which _spender is still allowed to withdraw from _owner.
    function allowance(address _owner, address _spender) public constant returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}
//File: node_modules/giveth-common-contracts/contracts/Owned.sol
pragma solidity ^0.4.15;


/// @title Owned
/// @author Adrià Massanet <adria@codecontext.io>
/// @notice The Owned contract has an owner address, and provides basic 
///  authorization control functions, this simplifies & the implementation of
///  "user permissions"
contract Owned {

    address public owner;
    address public newOwnerCandidate;

    event OwnershipRequested(address indexed by, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event OwnershipRemoved();

    /// @dev The constructor sets the `msg.sender` as the`owner` of the contract
    function Owned() {
        owner = msg.sender;
    }

    /// @dev `owner` is the only address that can call a function with this
    /// modifier
    modifier onlyOwner() {
        require (msg.sender == owner);
        _;
    }

    /// @notice `owner` can step down and assign some other address to this role
    /// @param _newOwner The address of the new owner.
    function changeOwnership(address _newOwner) onlyOwner {
        require(_newOwner != 0x0);

        address oldOwner = owner;
        owner = _newOwner;
        newOwnerCandidate = 0x0;

        OwnershipTransferred(oldOwner, owner);
    }

    /// @notice `onlyOwner` Proposes to transfer control of the contract to a
    ///  new owner
    /// @param _newOwnerCandidate The address being proposed as the new owner
    function proposeOwnership(address _newOwnerCandidate) onlyOwner {
        newOwnerCandidate = _newOwnerCandidate;
        OwnershipRequested(msg.sender, newOwnerCandidate);
    }

    /// @notice Can only be called by the `newOwnerCandidate`, accepts the
    ///  transfer of ownership
    function acceptOwnership() {
        require(msg.sender == newOwnerCandidate);

        address oldOwner = owner;
        owner = newOwnerCandidate;
        newOwnerCandidate = 0x0;

        OwnershipTransferred(oldOwner, owner);
    }

    /// @notice Decentralizes the contract, this operation cannot be undone 
    /// @param _dac `0xdac` has to be entered for this function to work
    function removeOwnership(address _dac) onlyOwner {
        require(_dac == 0xdac);
        owner = 0x0;
        newOwnerCandidate = 0x0;
        OwnershipRemoved();     
    }

} 

//File: node_modules/giveth-common-contracts/contracts/Escapable.sol
/*
    Copyright 2016, Jordi Baylina
    Contributor: Adrià Massanet <adria@codecontext.io>

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

pragma solidity ^0.4.15;





/// @dev `Escapable` is a base level contract built off of the `Owned`
///  contract that creates an escape hatch function to send its ether to
///  `escapeHatchDestination` when called by the `escapeHatchCaller` in the case that
///  something unexpected happens
contract Escapable is Owned {
    address public escapeHatchCaller;
    address public escapeHatchDestination;
    mapping (address=>bool) private escapeBlacklist;

    /// @notice The Constructor assigns the `escapeHatchDestination` and the
    ///  `escapeHatchCaller`
    /// @param _escapeHatchDestination The address of a safe location (usu a
    ///  Multisig) to send the ether held in this contract
    /// @param _escapeHatchCaller The address of a trusted account or contract to
    ///  call `escapeHatch()` to send the ether in this contract to the
    ///  `escapeHatchDestination` it would be ideal that `escapeHatchCaller` cannot move
    ///  funds out of `escapeHatchDestination`
    function Escapable(address _escapeHatchCaller, address _escapeHatchDestination) {
        escapeHatchCaller = _escapeHatchCaller;
        escapeHatchDestination = _escapeHatchDestination;
    }

    modifier onlyEscapeHatchCallerOrOwner {
        require ((msg.sender == escapeHatchCaller)||(msg.sender == owner));
        _;
    }

    /// @notice The `blacklistEscapeTokens()` marks a token in a whitelist to be
    ///   escaped. The proupose is to be done at construction time.
    /// @param _token the be bloacklisted for escape
    function blacklistEscapeToken(address _token) internal {
        escapeBlacklist[_token] = true;
        EscapeHatchBlackistedToken(_token);
    }

    function isTokenEscapable(address _token) constant public returns (bool) {
        return !escapeBlacklist[_token];
    }

    /// @notice The `escapeHatch()` should only be called as a last resort if a
    /// security issue is uncovered or something unexpected happened
    /// @param _token to transfer, use 0x0 for ethers
    function escapeHatch(address _token) public onlyEscapeHatchCallerOrOwner {   
        require(escapeBlacklist[_token]==false);

        uint256 balance;

        if (_token == 0x0) {
            balance = this.balance;
            escapeHatchDestination.transfer(balance);
            EscapeHatchCalled(_token, balance);
            return;
        }

        ERC20 token = ERC20(_token);
        balance = token.balanceOf(this);
        token.transfer(escapeHatchDestination, balance);
        EscapeHatchCalled(_token, balance);
    }

    /// @notice Changes the address assigned to call `escapeHatch()`
    /// @param _newEscapeHatchCaller The address of a trusted account or contract to
    ///  call `escapeHatch()` to send the ether in this contract to the
    ///  `escapeHatchDestination` it would be ideal that `escapeHatchCaller` cannot
    ///  move funds out of `escapeHatchDestination`
    function changeHatchEscapeCaller(address _newEscapeHatchCaller) onlyEscapeHatchCallerOrOwner {
        escapeHatchCaller = _newEscapeHatchCaller;
    }

    event EscapeHatchBlackistedToken(address token);
    event EscapeHatchCalled(address token, uint amount);
}

//File: ./contracts/WithdrawContract.sol
pragma solidity ^0.4.18;

contract MiniMeToken {
    function balanceOfAt(address _owner, uint _blockNumber) public constant returns (uint);
    function totalSupplyAt(uint _blockNumber) public constant returns(uint);
}




contract WithdrawContract is Escapable {
    struct Payment {
        uint block;
        ERC20 token;
        uint amount;
        bool canceled;
    }

    Payment[] public payments;
    MiniMeToken distToken;

    mapping (address => uint) public nextRefundToPay;
    mapping (address => mapping(uint => bool)) skipPayments;

    function WithdrawContract(
        MiniMeToken _distToken,
        address _escapeHatchCaller,
        address _escapeHatchDestination)
        Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        distToken = _distToken;
    }

    function () payable public {
        newEtherPayment(0);
    }

    function newEtherPayment(uint _block) public onlyOwner payable returns (uint _idPayment) {
        require(msg.value>0);
        require(_block < block.number);
        _idPayment = payments.length ++;
        Payment storage payment = payments[_idPayment];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = ERC20(0);
        payment.amount = msg.value;
        NewPayment(_idPayment, ERC20(0), msg.value);
    }

    function newTokenPayment(ERC20 _token, uint _amount, uint _block) public onlyOwner returns (uint _idPayment) {
        require(_amount > 0);
        require(_block < block.number);
        require( _token.transferFrom(msg.sender, address(this), _amount) );
        _idPayment = payments.length ++;
        Payment storage payment = payments[_idPayment];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = _token;
        payment.amount = _amount;
        NewPayment(_idPayment, _token, _amount);
    }

    function cancelPaymentGlobally(uint _idPayment) public onlyOwner {
        require(_idPayment < payments.length);
        payments[_idPayment].canceled = true;
        CancelPaymentGlobally(_idPayment);
    }

    function withdraw() public {
        uint acc = 0;
        ERC20 currentToken = ERC20(0x0);
        uint i = nextRefundToPay[msg.sender];

        require(msg.gas>149000);
        while (( i< payments.length) && ( msg.gas > 148000)) { // TODO Adjust the miminum to a lowe value
            Payment storage payment = payments[i];

            if ((!payment.canceled)&&(!isPaymentSkiped(msg.sender, i))) {
                if (currentToken != payment.token) {
                    nextRefundToPay[msg.sender] = i;
                    require(doPayment(i-1, msg.sender, currentToken, acc));
                    currentToken = payment.token;
                    acc =0;
                }

                acc +=  payment.amount *
                        distToken.balanceOfAt(msg.sender, payment.block) /
                            distToken.totalSupplyAt(payment.block);
            }

            i++;
        }
        nextRefundToPay[msg.sender] = i;
        require(doPayment(i-1, msg.sender, currentToken, acc));
    }

    function skipPayment(uint _idPayment, bool _skip) public {
        require(_idPayment < payments.length);
        skipPayments[msg.sender][_idPayment] = _skip;
    }

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

    function hasFundsAvailable(address _holder) constant returns (bool) {
        return nextRefundToPay[_holder] < payments.length;
    }

    function nPayments() constant returns (uint) {
        return payments.length;
    }

    function doPayment(uint _idPayment,  address _dest, ERC20 _token, uint _amount) internal returns (bool) {
        if (_amount == 0) return true;
        if (address(_token) == 0) {
            if (!_dest.send(_amount)) return false;   // If we can not send, we continue...
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

    function isPaymentSkiped(address _holder, uint _idPayment) constant returns(bool) {
        return skipPayments[_holder][_idPayment];
    }

    event Withdraw(uint indexed lastIdPayment, address indexed tokenHolder, ERC20 indexed tokenContract, uint amount);
    event NewPayment(uint indexed idPayment, ERC20 indexed tokenContract, uint amount);
    event CancelPaymentGlobally(uint indexed idPayment);
}

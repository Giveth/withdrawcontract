
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

//File: ./contracts/WithdrawContract.sol
pragma solidity ^0.4.4;

contract MiniMeToken {
    function balanceOfAt(address _owner, uint _blockNumber) public constant returns (uint);
    function totalSupplyAt(uint _blockNumber) public constant returns(uint);
}

contract ERC20 {
    function transfer(address dest, uint amount) public returns(bool) ;
    function transferFrom(address from, address to, uint amount) public returns(bool);
    function balanceOf(address owner) public constant returns (uint);
}



contract WithdrawContract is Owned {
    struct Payment {
        uint block;
        ERC20 token;
        uint amount;
    }

    Payment[] public payments;
    MiniMeToken distToken;

    mapping (address => uint) public nextRefundToPay;

    function WithdrawContract(MiniMeToken _distToken) public {
        distToken = _distToken;
    }

    function () payable public {
        newEtherPayment(0);
    }

    function newEtherPayment(uint _block) public onlyOwner payable returns(bool) {
        if (msg.value == 0) return false;
        require(_block < block.number);
        Payment storage payment = payments[payments.length ++];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = ERC20(0);
        payment.amount = msg.value;
        return true;
    }

    function newTokenPayment(ERC20 token, uint amount, uint _block) public onlyOwner returns(bool) {
        if (amount == 0) return false;
        require(_block < block.number);
        require( token.transferFrom(msg.sender, address(this), amount) );
        Payment storage payment = payments[payments.length ++];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = token;
        payment.amount = amount;
        return true;
    }

    function withdraw() public {
        uint acc = 0;
        ERC20 currentToken = ERC20(0x0);
        uint i = nextRefundToPay[msg.sender];
        uint g;
        assembly {
            g:= gas
        }

        require(g>200000);
        while (( i< payments.length) && ( g > 150000)) { // TODO Adjust the miminum to a lowe value
            Payment storage payment = payments[i];

            if ( currentToken != payment.token) {
                nextRefundToPay[msg.sender] = i;
                if (!doPayment(currentToken, msg.sender, acc)) return;
                currentToken = payment.token;
                acc =0;
            }

            acc +=  payment.amount *
                    distToken.balanceOfAt(msg.sender, payment.block) /
                        distToken.totalSupplyAt(payment.block);
            i++;
            assembly {
                g:= gas
            }
        }
        nextRefundToPay[msg.sender] = i;
        if (!doPayment(currentToken, msg.sender, acc)) return;
    }

    function getPendingTokens() public constant returns(ERC20[] tokens) {
        uint tmpLen =0;
        ERC20[] memory tmpTokens = new ERC20[](payments.length - nextRefundToPay[msg.sender]);
        for (uint i=nextRefundToPay[msg.sender]; i<payments.length; i++) {
            Payment storage payment = payments[i];
            uint j;
            while ((j<tmpLen)&&(tmpTokens[j] != payment.token)) j++;
            if (j==tmpLen) {
                tmpTokens[tmpLen] = payment.token;
                tmpLen ++;
            }
        }
        tokens = new ERC20[](tmpLen);
        for (i=0; i<tmpLen; i++) tokens[i] = tmpTokens[i];
    }

    function getPendingReward(ERC20 token, address holder) public constant returns(uint) {
        uint acc =0;
        for (uint i=nextRefundToPay[msg.sender]; i<payments.length; i++) {
            Payment storage payment = payments[i];
            if (payment.token == token) {
                acc +=  payment.amount *
                    distToken.balanceOfAt(holder, payment.block) /
                        distToken.totalSupplyAt(payment.block);
            }
        }
        return acc;
    }

    function hasFundsAvailable(address holder) constant returns (bool) {
        nextRefundToPay[holder] == payments.length;
    }

    function nPayments() constant returns (uint) {
        return payments.length;
    }

    function doPayment(ERC20 token, address dest, uint amount) internal returns (bool) {
        if (amount == 0) return true;
        if (address(token) == 0) {
            if (!dest.send(amount)) return false;   // If we can not send, we continue...
        } else {
            if (!token.transfer(dest, amount)) return false;
        }
        return true;
    }

    function getBalance(ERC20 token, address holder) internal constant returns (uint) {
        if (address(token) == 0) {
            return holder.balance;
        } else {
            return token.balanceOf(holder);
        }
    }
}

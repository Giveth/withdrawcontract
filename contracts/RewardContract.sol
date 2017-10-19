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

contract Owned {
    /// Allows only the owner to call a function
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    address public owner;

    /// @return Returns the owner of this token
    function Owned() public {
        owner = msg.sender;
    }

    /// @notice Changes the owner of the contract
    /// @param _newOwner The new owner of the contract
    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }
}

contract RewardContract is Owned {
    struct Payment {
        uint block;
        ERC20 token;
        uint amount;
    }

    Payment[] public payments;
    MiniMeToken distToken;

    mapping (address => uint) public nextRefundToPay;

    function RewardContract(MiniMeToken _distToken) public {
        distToken = _distToken;
    }

    function newEtherPayment() public onlyOwner payable returns(bool) {
        if (msg.value == 0) return false;
        Payment storage payment = payments[payments.length ++];
        payment.block = block.number;
        payment.token = ERC20(0);
        payment.amount = msg.value;
        return true;
    }

    function newTokenPayment(ERC20 token, uint amount) public onlyOwner returns(bool) {
        if (amount == 0) return false;
        require( token.transferFrom(msg.sender, address(this), amount) );
        Payment storage payment = payments[payments.length ++];
        payment.block = block.number;
        payment.token = token;
        payment.amount = amount;
        return true;
    }

    function getRewards() public {
        uint acc = 0;
        ERC20 currentToken = ERC20(0x0);
        uint i = nextRefundToPay[msg.sender];
        uint g;
        assembly {
            g:= gas
        }
        while (( i< payments.length) && ( g > 50000)) { // TODO Adjust the miminum to a lowe value
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

    function getPendingReward(ERC20 token, address _holder) public constant returns(uint) {
        uint acc =0;
        for (uint i=nextRefundToPay[msg.sender]; i<payments.length; i++) {
            Payment storage payment = payments[i];
            if (payment.token == token) {
                acc +=  payment.amount *
                    distToken.balanceOfAt(_holder, payment.block) /
                        distToken.totalSupplyAt(payment.block);
            }
        }
        return acc;
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

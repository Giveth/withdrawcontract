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

import "../node_modules/giveth-common-contracts/contracts/Owned.sol";

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

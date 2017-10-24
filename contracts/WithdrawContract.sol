pragma solidity ^0.4.18;

contract MiniMeToken {
    function balanceOfAt(address _owner, uint _blockNumber) public constant returns (uint);
    function totalSupplyAt(uint _blockNumber) public constant returns(uint);
}

import "../node_modules/giveth-common-contracts/contracts/ERC20.sol";
import "../node_modules/giveth-common-contracts/contracts/Escapable.sol";

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

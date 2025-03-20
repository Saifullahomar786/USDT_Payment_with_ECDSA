// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuardTransient} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract EcomPayment is ReentrancyGuardTransient, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable baseToken;
    address private _treasuryWallet;
    address private _authorityAddress;
    uint256 constant PPM = 1_000_000;
    uint256 public platformFee = 0;

    mapping(bytes => bool) public signatureUsed;

    mapping(uint256 => bool) public orderIDPlaced;

    mapping(uint256 => bool) public fundsClaimedByOrderID;

    mapping(address => bool) public fundsClaimedByMerchant;

    mapping(uint256 => address) public orderIDBuyer;

    mapping(uint256 => uint256) public orderIDTimestamp;

    event ConstructorSet(address, address, address, uint256);

    event TreasuryWalletIsUpdated(
        address indexed previousTreasuryWallet,
        address indexed newTreasuryWallet
    );

    event AuthorityAddressUpdated(
        address indexed previousAuthorityAddress,
        address indexed newAuthorityAddress
    );

    event OrderPaid(uint256 orderID, uint256 amount, address indexed buyer);

    event FundsClaimedByMerchant(uint256 amount, address indexed merchant);

    event RefundsClaimed(
        uint256 orderID,
        uint256 amount,
        address indexed buyer
    );

    event OrderCancled(uint256 orderID, uint256 amount, address indexed buyer);

    error InvalidSignature();

    error InvalidAddress();

    error SignatureUsed();

    error OrderDoesnotExist();

    error FundsAlreadyClaimed();

    error YouAreNotBuyer();

    error OrderIDAlreadyExist();

    error RefundTimePassed();

    constructor(
        address setTreasuryWallet,
        address setAuthorityAddress,
        address setBaseToken,
        address owner,
        uint256 platfromFeeinPPM
    ) Ownable(owner) {
        if (
            setTreasuryWallet == address(0) ||
            setAuthorityAddress == address(0) ||
            address(setBaseToken) == address(0)
        ) {
            revert InvalidAddress();
        }

        _treasuryWallet = setTreasuryWallet;
        _authorityAddress = setAuthorityAddress;
        baseToken = IERC20(setBaseToken);
        platformFee = platfromFeeinPPM;
        emit ConstructorSet(
            _treasuryWallet,
            _authorityAddress,
            address(baseToken),
            platformFee
        );
    }

    event checkNow(uint256);

    function pay(
        uint256 orderID,
        uint256 amount,
        bytes calldata signature
    ) external {
        address user = msg.sender;
        if (orderIDPlaced[orderID]) {
            revert OrderIDAlreadyExist();
        }
        if (signatureUsed[signature]) {
            revert SignatureUsed();
        }
        if (
            !_isValidSignature(
                _authorityAddress,
                _generateHash(orderID, amount, this.pay.selector),
                signature
            )
        ) {
            revert InvalidSignature();
        }

        orderIDPlaced[orderID] = true;
        orderIDBuyer[orderID] = user;
        orderIDTimestamp[orderID] = block.timestamp;
        signatureUsed[signature] = true;
        IERC20(baseToken).safeTransferFrom(user, address(this), amount);

        emit OrderPaid({orderID: orderID, amount: amount, buyer: user});
    }

    function claimFund(
        uint256[] memory orderID,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant {
        address user = msg.sender;
        if (
            !_isValidSignature(
                _authorityAddress,
                _generateHashForClaim(orderID, amount, this.claimFund.selector),
                signature
            )
        ) {
            revert InvalidSignature();
        }
        if (signatureUsed[signature]) {
            revert SignatureUsed();
        }
        signatureUsed[signature] = true;
        uint256 platformWalletFee = (amount * 30_000) / PPM; //3% of the amount as fee
        baseToken.safeTransfer(_treasuryWallet, platformWalletFee);
        uint256 amountToBePaid = amount - platformWalletFee;
        baseToken.safeTransfer(user, amountToBePaid);

        emit FundsClaimedByMerchant({amount: amount, merchant: user});
    }

    function refundOrder(
        uint256 orderID,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant {
        address user = msg.sender;
        if (!orderIDPlaced[orderID]) {
            revert OrderDoesnotExist();
        }
        if (signatureUsed[signature]) {
            revert SignatureUsed();
        }
        if (orderIDBuyer[orderID] != user) {
            revert YouAreNotBuyer();
        }
        if (
            !_isValidSignature(
                _authorityAddress,
                _generateHash(orderID, amount, this.refundOrder.selector),
                signature
            )
        ) {
            revert InvalidSignature();
        }
        signatureUsed[signature] = true;
        baseToken.safeTransfer(user, amount);

        emit RefundsClaimed({orderID: orderID, amount: amount, buyer: user});
    }

    function cancleOrder(
        uint256 orderID,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant {
        address user = msg.sender;
        if (!orderIDPlaced[orderID]) {
            revert OrderDoesnotExist();
        }
        if (signatureUsed[signature]) {
            revert SignatureUsed();
        }
        if (
            !_isValidSignature(
                _authorityAddress,
                _generateHash(orderID, amount, this.cancleOrder.selector),
                signature
            )
        ) {
            revert InvalidSignature();
        }
        signatureUsed[signature] = true;
        baseToken.safeTransfer(orderIDBuyer[orderID], amount);

        emit OrderCancled({orderID: orderID, amount: amount, buyer: user});
    }

    //private functions
    function _generateHash(
        uint256 orderID,
        uint256 amount,
        bytes4 funtionSelector
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    orderID,
                    msg.sender,
                    amount,
                    address(this),
                    funtionSelector
                )
            );
    }

    function _generateHashForClaim(
        uint256[] memory orderID,
        uint256 amount,
        bytes4 funtionSelector
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    orderID,
                    msg.sender,
                    amount,
                    address(this),
                    funtionSelector
                )
            );
    }

    function _isValidSignature(
        address authority,
        bytes32 generatedHash,
        bytes calldata signature
    ) private pure returns (bool) {
        bytes32 signedHash = MessageHashUtils.toEthSignedMessageHash(
            generatedHash
        );
        return ECDSA.recover(signedHash, signature) == authority;
    }

    //admin functions
    function updateAuthorityAddress(
        address newAuthorityAddress
    ) external onlyOwner {
        emit AuthorityAddressUpdated({
            previousAuthorityAddress: _authorityAddress,
            newAuthorityAddress: newAuthorityAddress
        });
        _authorityAddress = newAuthorityAddress;
    }

    function updateTreasuryWallet(
        address newTreasuryWallet
    ) external onlyOwner {
        emit TreasuryWalletIsUpdated({
            previousTreasuryWallet: _treasuryWallet,
            newTreasuryWallet: newTreasuryWallet
        });
        _treasuryWallet = newTreasuryWallet;
    }

    function updatePlatfromFeeInPPM(
        uint256 setPlatfromFeeInPPM
    ) external onlyOwner {
        platformFee = setPlatfromFeeInPPM;
    }
}

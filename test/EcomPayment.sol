// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Test, console} from "forge-std/Test.sol";
import {EcomPayment} from "../src/EcomPayment.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(
            allowance[sender][msg.sender] >= amount,
            "Insufficient allowance"
        );

        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] -= amount;
        return true;
    }
}

contract ecomPaymentTest is Test {
    EcomPayment public ecomPayment;
    MockERC20 public usdtToken;

    // Test accounts
    address public owner;
    address public customer1;
    uint256 platformFee = 30_000;

    address public authority;
    address public updatedAuthority;
    address public merchant1;
    address public participant2;
    address public participant3;
    address public participant4;
    address public participant5;
    address public participant6;
    address public participant7;

    address public platformWallet;
    address public updatedPlatformWallet;

    // Test setup variables
    uint256 authorityPrivateKey;

    function setUp() public {
        //setup accounts
        owner = makeAddr("owner");
        customer1 = makeAddr("customer1");
        merchant1 = makeAddr("merchant1");
        participant2 = makeAddr("participant2");
        participant3 = makeAddr("participant3");
        participant4 = makeAddr("participant4");
        participant5 = makeAddr("participant5");
        participant6 = makeAddr("participant6");
        participant7 = makeAddr("participant7");

        platformWallet = makeAddr("platformWallet");

        updatedPlatformWallet = makeAddr("updatedPlatformWallet");
        updatedAuthority = makeAddr("updatedAuthority");

        authorityPrivateKey = 0xc051fc0cdb117453ad67ccbb5526dc7b2704b041d23708d6f9e9d563623ab6f2;
        authority = vm.addr(authorityPrivateKey);

        vm.prank(owner);
        usdtToken = new MockERC20("Mock USDT", "MUSDT", 6);
        console.log("address of usdt: ", address(usdtToken));

        vm.prank(owner);
        ecomPayment = new EcomPayment(
            platformWallet,
            authority,
            address(usdtToken),
            owner,
            platformFee
        );

        // Mint tokens to participants
        uint256 mintAmount = 1_000_000 * 10 ** usdtToken.decimals();
        usdtToken.mint(owner, mintAmount);
        usdtToken.mint(customer1, mintAmount);
        usdtToken.mint(merchant1, mintAmount);
        usdtToken.mint(participant2, mintAmount);
        usdtToken.mint(participant3, mintAmount);
    }

    function test_CreateOrder() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);

        uint256 orderID = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digest = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digest
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.stopPrank();

        vm.prank(customer1);
        ecomPayment.pay(orderID, amountinUSDT, signature);

        assertEq(usdtToken.balanceOf(address(ecomPayment)), amountinUSDT);
    }

    function test_CreateOrderWithSameID() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);

        uint256 orderID = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digest = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digest
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.stopPrank();
        console.log(
            "Balance of creator in USD : ",
            usdtToken.balanceOf(customer1)
        );
        vm.prank(customer1);
        ecomPayment.pay(orderID, amountinUSDT, signature);

        vm.prank(customer1);
        vm.expectRevert();
        ecomPayment.pay(orderID, amountinUSDT, signature);
    }

    function test_ClaimFundForCreatedOrder() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);
        uint256 orderIDforPay = 1;
        uint256[] memory orderIDforClaim = new uint256[](1);
        orderIDforClaim[0] = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD
        uint256 amountToClaim = (amountinUSDT * 97) / 100; //97USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digestForCreation = keccak256(
            abi.encodePacked(
                orderIDforPay,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHashForCreation = MessageHashUtils
            .toEthSignedMessageHash(digestForCreation);
        (uint8 vCreate, bytes32 rCreate, bytes32 sCreate) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHashForCreation
        );
        bytes memory signatureForCreation = abi.encodePacked(
            rCreate,
            sCreate,
            vCreate
        );

        vm.stopPrank();

        vm.prank(customer1);
        ecomPayment.pay(orderIDforPay, amountinUSDT, signatureForCreation);

        vm.startPrank(authority);
        bytes32 digestForClaim = keccak256(
            abi.encodePacked(
                orderIDforClaim,
                address(merchant1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.claimFund.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digestForClaim
        );
        (uint8 vClaim, bytes32 rClaim, bytes32 sClaim) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signatureForClaim = abi.encodePacked(
            rClaim,
            sClaim,
            vClaim
        );

        vm.stopPrank();

        uint256 merchant1BalanceBefore = usdtToken.balanceOf(merchant1);
        vm.startPrank(merchant1);
        ecomPayment.claimFund(orderIDforClaim, amountinUSDT, signatureForClaim);

        assertEq(
            usdtToken.balanceOf(merchant1),
            merchant1BalanceBefore + amountToClaim
        );
    }

    function test_ClaimFundAgainForCreatedOrder() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);

        uint256 orderIDforPay = 1;
        uint256[] memory orderIDforClaim = new uint256[](1);
        orderIDforClaim[0] = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD
        uint256 amountToClaim = (amountinUSDT * 97) / 100; //97USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digestForCreation = keccak256(
            abi.encodePacked(
                orderIDforPay,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHashForCreation = MessageHashUtils
            .toEthSignedMessageHash(digestForCreation);
        (uint8 vCreate, bytes32 rCreate, bytes32 sCreate) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHashForCreation
        );
        bytes memory signatureForCreation = abi.encodePacked(
            rCreate,
            sCreate,
            vCreate
        );

        vm.stopPrank();

        vm.prank(customer1);
        ecomPayment.pay(orderIDforPay, amountinUSDT, signatureForCreation);

        vm.startPrank(authority);
        bytes32 digestForClaim = keccak256(
            abi.encodePacked(
                orderIDforClaim,
                address(merchant1),
                amountToClaim,
                address(ecomPayment),
                ecomPayment.claimFund.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digestForClaim
        );
        (uint8 vClaim, bytes32 rClaim, bytes32 sClaim) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signatureForClaim = abi.encodePacked(
            rClaim,
            sClaim,
            vClaim
        );

        vm.stopPrank();

        vm.prank(merchant1);
        ecomPayment.claimFund(
            orderIDforClaim,
            amountToClaim,
            signatureForClaim
        );

        vm.prank(merchant1);
        vm.expectRevert();
        ecomPayment.claimFund(
            orderIDforClaim,
            amountToClaim,
            signatureForClaim
        );
    }

    function test_ReFundForCreatedOrder() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);

        uint256 orderID = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD
        uint256 amountToRefund = (amountinUSDT * 97) / 100; //97USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digestForCreation = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHashForCreation = MessageHashUtils
            .toEthSignedMessageHash(digestForCreation);
        (uint8 vCreate, bytes32 rCreate, bytes32 sCreate) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHashForCreation
        );
        bytes memory signatureForCreation = abi.encodePacked(
            rCreate,
            sCreate,
            vCreate
        );

        vm.stopPrank();

        vm.prank(customer1);
        ecomPayment.pay(orderID, amountinUSDT, signatureForCreation);

        vm.startPrank(authority);
        bytes32 digestForClaim = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountToRefund,
                address(ecomPayment),
                ecomPayment.refundOrder.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digestForClaim
        );
        (uint8 vClaim, bytes32 rClaim, bytes32 sClaim) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signatureForRefundOrder = abi.encodePacked(
            rClaim,
            sClaim,
            vClaim
        );

        vm.stopPrank();

        uint256 customer1BalanceBefore = usdtToken.balanceOf(customer1);
        vm.startPrank(customer1);
        ecomPayment.refundOrder(
            orderID,
            amountToRefund,
            signatureForRefundOrder
        );

        assertEq(
            usdtToken.balanceOf(customer1),
            customer1BalanceBefore + amountToRefund
        );
    }

    function test_CancleForCreatedOrder() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);

        uint256 orderID = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD
        uint256 amountToCancle = (amountinUSDT * 97) / 100; //97USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digestForCreation = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHashForCreation = MessageHashUtils
            .toEthSignedMessageHash(digestForCreation);
        (uint8 vCreate, bytes32 rCreate, bytes32 sCreate) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHashForCreation
        );
        bytes memory signatureForCreation = abi.encodePacked(
            rCreate,
            sCreate,
            vCreate
        );

        vm.stopPrank();

        vm.prank(customer1);
        ecomPayment.pay(orderID, amountinUSDT, signatureForCreation);

        vm.startPrank(authority);
        bytes32 digestForClaim = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountToCancle,
                address(ecomPayment),
                ecomPayment.cancleOrder.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digestForClaim
        );
        (uint8 vClaim, bytes32 rClaim, bytes32 sClaim) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signatureForRefundOrder = abi.encodePacked(
            rClaim,
            sClaim,
            vClaim
        );

        vm.stopPrank();

        uint256 customer1BalanceBefore = usdtToken.balanceOf(customer1);
        vm.startPrank(customer1);
        ecomPayment.cancleOrder(
            orderID,
            amountToCancle,
            signatureForRefundOrder
        );

        assertEq(
            usdtToken.balanceOf(customer1),
            customer1BalanceBefore + amountToCancle
        );
    }

    function test_CancleForCreatedOrderByMerchant() external {
        vm.prank(customer1);
        usdtToken.approve(address(ecomPayment), 100_000_000);

        uint256 orderID = 1;
        uint256 amountinUSDT = 100_000_000; //100 USD
        uint256 amountToCancle = (amountinUSDT * 97) / 100; //97USD

        //signature creation
        vm.startPrank(authority);
        bytes32 digestForCreation = keccak256(
            abi.encodePacked(
                orderID,
                address(customer1),
                amountinUSDT,
                address(ecomPayment),
                ecomPayment.pay.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHashForCreation = MessageHashUtils
            .toEthSignedMessageHash(digestForCreation);
        (uint8 vCreate, bytes32 rCreate, bytes32 sCreate) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHashForCreation
        );
        bytes memory signatureForCreation = abi.encodePacked(
            rCreate,
            sCreate,
            vCreate
        );

        vm.stopPrank();

        vm.prank(customer1);
        ecomPayment.pay(orderID, amountinUSDT, signatureForCreation);

        vm.startPrank(authority);
        bytes32 digestForClaim = keccak256(
            abi.encodePacked(
                orderID,
                address(merchant1),
                amountToCancle,
                address(ecomPayment),
                ecomPayment.cancleOrder.selector
            )
        ); // Use the correct message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digestForClaim
        );
        (uint8 vClaim, bytes32 rClaim, bytes32 sClaim) = vm.sign(
            authorityPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signatureForRefundOrder = abi.encodePacked(
            rClaim,
            sClaim,
            vClaim
        );

        vm.stopPrank();

        uint256 customer1BalanceBefore = usdtToken.balanceOf(customer1);
        vm.startPrank(merchant1);
        ecomPayment.cancleOrder(
            orderID,
            amountToCancle,
            signatureForRefundOrder
        );

        assertEq(
            usdtToken.balanceOf(customer1),
            customer1BalanceBefore + amountToCancle
        );
    }
}
